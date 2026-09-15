import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一台已配对的手机（电脑侧保存）。
@immutable
class PairedPhone {
  const PairedPhone({
    required this.deviceId,
    required this.name,
    required this.token,
    required this.lastConnectedAtMs,
  });

  /// 手机上报的稳定标识（`welcome.deviceId`）。**不是凭据**，只用于去重。
  final String deviceId;

  final String name;

  /// 电脑签发、下发给了手机的会话令牌。手机凭它自动重连（§7.3）。
  final String token;

  final int lastConnectedAtMs;
}

/// 电脑侧的"已配对的手机"。
///
/// 两条设计约束值得记下来（文档 §10.6）：
///
/// - **按 `deviceId` 去重。** 同一台手机重新配对（例如电脑 IP 变了、必须重新配对，
///   §10.4）时替换原记录而不是新增一条。否则每换一次 IP 就会留下一台再也用不上的
///   "僵尸手机"，白占上限，而且用户在列表里分不出哪条是活的。
/// - **不保存手机地址。** 地址是手机自己知道的（它拨号），电脑不需要记。
class PairedPhoneStore {
  PairedPhoneStore();

  static const String _prefsKey = 'desktop_bridge.paired_phones';

  /// 上限。超出按"最久未连接"淘汰。
  static const int _maxPhones = 8;

  static const int _tokenBytes = 16;

  final Random _random = Random.secure();

  List<PairedPhone> _phones = const <PairedPhone>[];

  List<PairedPhone> get phones => List<PairedPhone>.unmodifiable(_phones);

  /// 最近连接过的那台，供界面默认选中。
  PairedPhone? get mostRecent =>
      _phones.isEmpty ? null : (_phones.toList()..sort((a, b) => b.lastConnectedAtMs.compareTo(a.lastConnectedAtMs))).first;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _phones = const <PairedPhone>[];
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _phones = const <PairedPhone>[];
        return;
      }
      _phones = decoded
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .whereType<PairedPhone>()
          .toList();
    } on Object catch (error) {
      debugPrint('[lan] 读取已配对手机失败，忽略这份记录：$error');
      _phones = const <PairedPhone>[];
    }
  }

  /// 校验通过、下发新令牌后写入。同一 [deviceId] 只保留一条。
  Future<void> save({
    required String deviceId,
    required String name,
    required String token,
  }) async {
    final updated = <PairedPhone>[
      for (final phone in _phones)
        if (phone.deviceId != deviceId) phone,
      PairedPhone(
        deviceId: deviceId,
        name: name,
        token: token,
        lastConnectedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ]..sort((a, b) => b.lastConnectedAtMs.compareTo(a.lastConnectedAtMs));

    _phones = updated.take(_maxPhones).toList();
    await _persist();
  }

  /// 移除一条 = 吊销该令牌，该手机下次必须重新配对。
  Future<void> remove(String deviceId) async {
    _phones = _phones.where((phone) => phone.deviceId != deviceId).toList();
    await _persist();
  }

  Future<void> clear() async {
    _phones = const <PairedPhone>[];
    await _persist();
  }

  /// 该手机是否持有有效令牌。
  PairedPhone? findByDeviceId(String deviceId) {
    for (final phone in _phones) {
      if (phone.deviceId == deviceId) {
        return phone;
      }
    }
    return null;
  }

  /// 刷新最近连接时间（令牌没变时不重写记录，只更新时间）。
  Future<void> touch(String deviceId) async {
    final existing = findByDeviceId(deviceId);
    if (existing == null) {
      return;
    }
    await save(
      deviceId: existing.deviceId,
      name: existing.name,
      token: existing.token,
    );
  }

  /// 签发一个新的会话令牌（32 位 hex / 16 字节，与既有令牌格式一致）。
  ///
  /// 用 [Random.secure]：它和手机侧的 `SecureRandom` 一样取自操作系统的
  /// 密码学随机源，128 bit 的取值空间对"长期有效的自动重连凭据"是够的。
  String issueSessionToken() {
    final bytes = List<int>.generate(_tokenBytes, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  PairedPhone? _fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    final name = json['name'];
    final token = json['token'];
    if (deviceId is! String || name is! String || token is! String) {
      return null;
    }
    if (deviceId.isEmpty || token.isEmpty) {
      return null;
    }
    final at = json['lastConnectedAtMs'];
    return PairedPhone(
      deviceId: deviceId,
      name: name,
      token: token,
      lastConnectedAtMs: at is int ? at : 0,
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(<Map<String, Object?>>[
        for (final phone in _phones)
          <String, Object?>{
            'deviceId': phone.deviceId,
            'name': phone.name,
            'token': phone.token,
            'lastConnectedAtMs': phone.lastConnectedAtMs,
          },
      ]),
    );
  }
}
