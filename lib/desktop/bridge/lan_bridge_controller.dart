import 'dart:async';

import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';
import 'package:JsxposedX/desktop/bridge/lan_listener.dart';
import 'package:JsxposedX/desktop/bridge/local_address.dart';
import 'package:JsxposedX/desktop/bridge/paired_phone_store.dart';
import 'package:JsxposedX/desktop/bridge/pairing_code.dart';
import 'package:JsxposedX/desktop/bridge/remote_bridge_client.dart';
import 'package:flutter/foundation.dart';

/// Wi-Fi 直连在界面上的粗粒度状态。
enum LanPhase {
  /// 还没开始等待（用户没点"开始等待手机连接"）。
  idle,

  /// 已绑定端口，正在等手机连上来。
  waiting,

  /// 已有一台手机通过校验。
  connected,

  /// 起不来（端口全被占、枚举网卡失败等）。
  failed,
}

/// 给界面看的一份只读快照。
@immutable
class LanSnapshot {
  const LanSnapshot({
    required this.phase,
    required this.addresses,
    required this.address,
    required this.listenPort,
    required this.code,
    required this.rotationRemaining,
    required this.paused,
    required this.pauseRemaining,
    required this.pairedCount,
    this.error,
    this.device,
  });

  final LanPhase phase;
  final List<LanAddress> addresses;
  final LanAddress? address;
  final int? listenPort;

  /// 当前 6 位码；暂停期间**不要显示它**（§9.2 边界行为）。
  final String code;

  final Duration rotationRemaining;
  final bool paused;
  final Duration pauseRemaining;
  final int pairedCount;
  final String? error;
  final BridgeDeviceInfo? device;

  bool get isConnected => phase == LanPhase.connected;
}

/// 「Wi-Fi 直连」的电脑端控制器。
///
/// 把散落的几件事收在一处，让界面只依赖一个对象：
///
/// - [LanListener]：端口绑定与回退（§5.3）
/// - [PairingCode]：6 位码轮换、来源限速、全局节流（§9）
/// - [PairedPhoneStore]：已配对手机与会话令牌（§10.6）
/// - 地址枚举与"记住用户选的网卡"（§10.4）
/// - 监听模式下的 [RemoteBridgeClient]：**校验对端凭据**（§7.2、§7.3）
class LanBridgeController {
  LanBridgeController();

  /// 端口回退范围，与 `BridgeProtocol.defaultPort` / `maxPortFallback` 保持一致。
  static const int _fallbackBase = BridgeProtocol.defaultPort;
  static const int _fallbackMax = BridgeProtocol.maxPortFallback;

  final LanListener _listener = LanListener(
    preferredPort: _fallbackBase,
    maxPort: _fallbackMax,
  );

  final PairingCode _pairingCode = PairingCode();

  final PairedPhoneStore _phoneStore = PairedPhoneStore();

  final StreamController<LanSnapshot> _controller =
      StreamController<LanSnapshot>.broadcast();

  Timer? _ticker;

  RemoteBridgeClient? _client;

  List<LanAddress> _addresses = const <LanAddress>[];

  /// 用户选过的那块网卡地址，跨会话记住（§10.4 第 4 点）。
  String? _rememberedAddress;

  LanPhase _phase = LanPhase.idle;

  String? _error;

  BridgeDeviceInfo? _device;

  bool _phoneStoreLoaded = false;

  Stream<LanSnapshot> get stream => _controller.stream;

  /// 当前的监听模式客户端；只有进入等待状态之后才非空。
  RemoteBridgeClient? get client => _client;

  PairedPhoneStore get phoneStore => _phoneStore;

  /// 6 位码校验器。界面直接读它来画倒计时、判断是否处于暂停。
  PairingCode get pairingCode => _pairingCode;

  LanSnapshot get snapshot => _buildSnapshot();

  /// 枚举网卡并刷新候选列表（不改变已选中的那块，除非它消失了）。
  Future<void> refreshAddresses() async {
    _addresses = await LocalAddress.candidates();
    if (LocalAddress.findByAddress(_addresses, _rememberedAddress) == null) {
      _rememberedAddress = LocalAddress.preferred(_addresses)?.address;
    }
    _emit();
  }

  Future<void> selectAddress(LanAddress address) async {
    _rememberedAddress = address.address;
    _emit();
  }

  /// 开始等待手机连接：绑定端口、开始轮换 6 位码、准备一个监听模式的客户端。
  ///
  /// 幂等——已经处于等待状态时什么都不做，避免把正在等的那次断掉。
  Future<void> startWaiting() async {
    if (_phase == LanPhase.waiting) {
      return;
    }

    if (!_phoneStoreLoaded) {
      await _phoneStore.load();
      _phoneStoreLoaded = true;
      await refreshAddresses();
    }

    try {
      await _listener.start();
    } on Object catch (error) {
      _phase = LanPhase.failed;
      _error = '$error';
      _emit();
      return;
    }

    _pairingCode.start();
    _error = null;
    _device = null;
    _phase = LanPhase.waiting;

    _client = RemoteBridgeClient(
      port: _listener.port ?? _fallbackBase,
      listener: _listener,
      pairingCode: _pairingCode,
      phoneStore: _phoneStore,
    );

    _startTicking();
    _emit();

    // 进入等待后就开始接客：connect() 会一直循环"接受 → 握手 → 校验"，
    // 直到有一条通过（或用户点了停止）。它是个长久挂起的 Future，不要 await。
    unawaited(_waitForPhone());
  }

  Future<void> _waitForPhone() async {
    final current = _client;
    if (current == null) {
      return;
    }
    try {
      final device = await current.connect();
      _device = device;
      _phase = LanPhase.connected;
      _stopTicking();
      _emit();
    } on Object catch (error) {
      // 停止等待、端口被占、客户端被关掉都会走到这里。
      if (_phase == LanPhase.waiting) {
        _phase = LanPhase.idle;
        _error = null;
        if (error is! BridgeException) {
          _error = '$error';
        }
      }
      _stopTicking();
      _emit();
    }
  }

  /// 停止等待（用户切走 Tab 或点了停止）。
  Future<void> stopWaiting() async {
    _stopTicking();
    _pairingCode.stop();
    final current = _client;
    _client = null;
    if (current != null) {
      await current.disconnect();
      current.dispose();
    }
    await _listener.close();
    _phase = LanPhase.idle;
    _device = null;
    _emit();
  }

  /// 断开已连接的手机，回到等待状态。
  ///
  /// 走的是"先停再起"：不保留旧监听（端口已经关了），重新 bind 一次。
  Future<void> disconnectPhone() async {
    await stopWaiting();
    await startWaiting();
  }

  Future<void> removePhone(String deviceId) async {
    await _phoneStore.remove(deviceId);
    _emit();
  }

  Future<void> clearPhones() async {
    await _phoneStore.clear();
    _emit();
  }

  Future<void> dispose() async {
    await stopWaiting();
    await _controller.close();
  }

  // -------------------------------------------------------------- 内部实现

  /// 一秒一次地推快照，给倒计时用。
  void _startTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _emit());
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_buildSnapshot());
    }
  }

  LanSnapshot _buildSnapshot() {
    return LanSnapshot(
      phase: _phase,
      addresses: _addresses,
      address: LocalAddress.findByAddress(_addresses, _rememberedAddress),
      listenPort: _listener.port,
      code: _pairingCode.current,
      rotationRemaining: _pairingCode.rotationRemaining,
      paused: _pairingCode.isPaused,
      pauseRemaining: _pairingCode.pauseRemaining,
      pairedCount: _phoneStore.phones.length,
      error: _error,
      device: _device,
    );
  }
}
