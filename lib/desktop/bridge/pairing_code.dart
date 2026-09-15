import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// 一次校验码尝试的结果。
enum CodeAttemptOutcome {
  /// 码正确，放行，并签发会话令牌。
  accepted,

  /// 是刚刚被轮换掉的那一组——只用于给出精确提示，**不通过**（§9.3）。
  stale,

  /// 码不对 / 过期 / 已使用。
  wrong,

  /// 被来源限速或全局节流拦下，属于**临时**状态（§9.2）。
  locked,

  /// 手机没出示任何凭据。等同 [wrong]，但文案能更具体。
  empty,
}

/// 校验码校验器：轮换、限速、节流。
///
/// 安全性**不建立在码的强度上**：6 位十进制只有约 20 bit，靠三条限制兜底
/// （文档 §9.2 有完整推导）：
///
/// 1. **严格过期**——每 15 秒轮换、过期即拒、一次性。它压的是"看过屏幕"的时效，
///    **不是限速手段**：攻击者猜错一次就换一组新码，新旧码概率无关，他并不吃亏。
/// 2. **来源 IP 限速**——同一来源 60 秒内最多 [sourceLimit] 次失败；超出的尝试
///    **不进入校验、也不计入全局计数**。阈值必须低于全局阈值，否则这一层永远不会先触发。
/// 3. **全局失败节流**——滑动 60 秒窗口内累计 [globalLimit] 次失败 → 暂停校验
///    [pauseDuration]。这是对"多台机器协同"的硬上限，与攻击者用多少台机器无关。
///
/// 单机上限因此精确等于来源限速（3 次/60 秒 ≈ 0.43%/天），全局节流只对多来源生效。
///
/// **真正把风险压到可忽略的是暴露窗口本身很短**：电脑只在等待连接期间校验，
/// 一次配对通常几十秒到几分钟（§9.2）。
class PairingCode {
  PairingCode({
    this.rotation = const Duration(seconds: 15),
    this.sourceLimit = 3,
    this.sourceWindow = const Duration(seconds: 60),
    this.globalLimit = 5,
    this.globalWindow = const Duration(seconds: 60),
    this.pauseDuration = const Duration(seconds: 60),
  });

  /// 轮换周期。这是安全性与成功率的唯一取舍点——严格过期意味着
  /// "扫码/输码慢了一拍"是**预期会发生**的失败（§9.3），而不是异常。
  final Duration rotation;

  final int sourceLimit;
  final Duration sourceWindow;
  final int globalLimit;
  final Duration globalWindow;
  final Duration pauseDuration;

  final Random _random = Random.secure();

  Timer? _rotationTimer;
  Timer? _pauseTimer;

  /// 当前有效的码（6 位数字字符串）。
  String _current = '';

  /// 上一组码，**只用于识别 [CodeAttemptOutcome.stale]**，永远不用于放行。
  String? _previous;

  DateTime _rotatedAt = DateTime.now();

  DateTime? _pausedUntil;

  /// 每个来源 IP 的失败时间戳（滑动窗口）。
  final Map<String, List<DateTime>> _failuresBySource = <String, List<DateTime>>{};

  /// 全局失败时间戳（滑动窗口）。
  final List<DateTime> _failuresGlobal = <DateTime>[];

  /// 当前有效的码。暂停期间界面上不应该显示它（§9.2 边界行为）。
  String get current => _current;

  bool get isPaused => _pausedUntil != null;

  Duration get pauseRemaining {
    final until = _pausedUntil;
    if (until == null) {
      return Duration.zero;
    }
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// 距离下一次轮换还有多久，用来画倒计时。
  Duration get rotationRemaining {
    final elapsed = DateTime.now().difference(_rotatedAt);
    final left = rotation - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  void start() {
    _regenerate();
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(rotation, (_) => _regenerate());
  }

  void stop() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _pausedUntil = null;
    _failuresBySource.clear();
    _failuresGlobal.clear();
  }

  /// 配对成功：两个计数都清零（§9.2 的"计数清零只有两种情况"之一）。
  void resetAfterSuccess() {
    _failuresBySource.clear();
    _failuresGlobal.clear();
  }

  /// 校验一次尝试。**只处理 6 位码这条路径**——会话令牌路径不受限速影响，
  /// 由调用方（[RemoteBridgeClient]）直接判断，不要走到这里来。
  CodeAttemptOutcome check(String? submitted, {required String sourceIp}) {
    final now = DateTime.now();

    // 暂停中：一律拒绝，且不计入任何计数（§9.2 边界行为）。
    if (isPaused) {
      if (pauseRemaining == Duration.zero) {
        _endPause();
      }
      return CodeAttemptOutcome.locked;
    }

    final code = _normalize(submitted);
    if (code == null) {
      _recordFailure(sourceIp, now);
      return CodeAttemptOutcome.empty;
    }

    // 来源限速：超出后**不进入校验、也不计入全局计数**。
    _pruneFailures(now);
    final perSource = _failuresBySource[sourceIp] ?? const <DateTime>[];
    if (perSource.length >= sourceLimit) {
      debugPrint('[lan] 来源 $sourceIp 触发限速，本次拒绝且不计入全局');
      return CodeAttemptOutcome.locked;
    }

    if (code == _current) {
      // 一次性：用掉即作废，并立刻换一组新码。
      _regenerate();
      return CodeAttemptOutcome.accepted;
    }

    _recordFailure(sourceIp, now);
    if (code == _previous) {
      return CodeAttemptOutcome.stale;
    }
    return CodeAttemptOutcome.wrong;
  }

  // -------------------------------------------------------------- 内部实现

  /// 失败计数：先记来源，再记全局；全局到阈值就暂停。
  void _recordFailure(String sourceIp, DateTime now) {
    _pruneFailures(now);

    (_failuresBySource[sourceIp] ??= <DateTime>[]).add(now);
    _failuresGlobal.add(now);

    if (_failuresGlobal.length >= globalLimit) {
      _beginPause();
    }
  }

  void _beginPause() {
    _pausedUntil = DateTime.now().add(pauseDuration);
    debugPrint('[lan] 累计失败达阈值，暂停校验 ${pauseDuration.inSeconds} 秒');
    // 暂停期间**监听仍在**，只是握手阶段一律回 reject(locked)——
    // 不能真的停止 accept，否则手机侧只会看到"连不上"，拿不到任何原因。
    _pauseTimer?.cancel();
    _pauseTimer = Timer(pauseDuration, _endPause);
  }

  void _endPause() {
    _pausedUntil = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _failuresBySource.clear();
    _failuresGlobal.clear();
    // **暂停结束时不复用旧码**：换一组全新的，避免用户照着暂停前记下的数字输入。
    _regenerate();
    debugPrint('[lan] 暂停结束，已换新码');
  }

  void _pruneFailures(DateTime now) {
    final sourceCutoff = now.subtract(sourceWindow);
    for (final entry in _failuresBySource.entries.toList()) {
      entry.value.removeWhere((at) => at.isBefore(sourceCutoff));
      if (entry.value.isEmpty) {
        _failuresBySource.remove(entry.key);
      }
    }
    final globalCutoff = now.subtract(globalWindow);
    _failuresGlobal.removeWhere((at) => at.isBefore(globalCutoff));
  }

  void _regenerate() {
    _previous = _current.isEmpty ? null : _current;
    _current = _random.nextInt(1000000).toString().padLeft(6, '0');
    _rotatedAt = DateTime.now();
  }

  static String? _normalize(String? raw) {
    if (raw == null) {
      return null;
    }
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length == 6 ? digits : null;
  }

  /// 界面显示用：`123456` → `123 456`。输入时忽略空格。
  static String format(String code) {
    if (code.length != 6) {
      return code;
    }
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }
}
