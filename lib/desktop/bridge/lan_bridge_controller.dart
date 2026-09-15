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
  LanBridgeController({this.secureTransport = true});

  /// 是否启用帧加密（§7.6）。排查问题时可以用
  /// `--dart-define=BRIDGE_NO_ENCRYPT=true` 关掉，见 [RemoteBridgeClient.secureTransport]。
  final bool secureTransport;

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

  /// 用户是否主动停止了等待。用它把"用户点了停止"和"连接意外断开"区分开——
  /// 后者要自动回到等待状态，前者不要。
  bool _stopping = false;

  /// 防止 [startWaiting] 被并发进入（用户点击 + 掉线自动重开）。
  bool _starting = false;

  /// 监听客户端的阶段变化，用来发现"连接掉了"。
  StreamSubscription<BridgeConnectionPhase>? _clientPhaseSubscription;

  Stream<LanSnapshot> get stream => _controller.stream;

  /// 当前的监听模式客户端；只有进入等待状态之后才非空。
  RemoteBridgeClient? get client => _client;

  PairedPhoneStore get phoneStore => _phoneStore;

  /// 6 位码校验器。界面直接读它来画倒计时、判断是否处于暂停。
  PairingCode get pairingCode => _pairingCode;

  LanSnapshot get snapshot => _buildSnapshot();

  /// 桌面端启动时调用：**已经配对过手机就自动回到等待状态**。
  ///
  /// 这一步是"双击 exe 就能用"的关键。少了它会出现一种很难自己诊断的僵局——
  /// 手机那边在自动重连（退避到 30 秒一次），而电脑这边端口根本没开，
  /// 用户只能看到一个「开始等待手机连接」按钮，完全想不到要点它。
  ///
  /// 只在**已经有配对记录**时才自动开监听：首次使用仍然要用户明确点一次，
  /// 避免一台从没配对过的电脑一启动就把端口开着。
  ///
  /// 代价要说清楚：端口会在桌面端启动后就开着，直到手机连上为止
  /// （连上即停，见 §10.3 第 4 点）。配对仍然需要屏幕上的 6 位码，
  /// 限速与节流也照旧——但"暴露窗口只有几十秒"这个前提在这里放宽了，
  /// 所以界面必须**切到 Wi-Fi 那一档**把当前状态显示出来，而不是默默开着。
  ///
  /// @return 是否真的进入了等待状态。
  Future<bool> autoResumeIfPaired() async {
    if (!_phoneStoreLoaded) {
      await _phoneStore.load();
      _phoneStoreLoaded = true;
      await refreshAddresses();
    }
    if (_phoneStore.phones.isEmpty) {
      _emit();
      return false;
    }
    await startWaiting();
    return _phase == LanPhase.waiting;
  }

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
  /// 连接掉线后也会走这里（见 [_onClientPhase]），所以它还负责把上一个客户端收拾干净。
  Future<void> startWaiting() async {
    if (_starting) {
      return;
    }
    if (_phase == LanPhase.waiting) {
      return;
    }

    _starting = true;
    try {
      _stopping = false;
      await _disposeClient();

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

      final client = RemoteBridgeClient(
        port: _listener.port ?? _fallbackBase,
        listener: _listener,
        pairingCode: _pairingCode,
        phoneStore: _phoneStore,
        secureTransport: secureTransport,
      );
      _client = client;
      _clientPhaseSubscription = client.phaseStream.listen(_onClientPhase);

      _startTicking();
      _emit();

      // 进入等待后就开始接客：connect() 会一直循环"接受 → 握手 → 校验"，
      // 直到有一条通过（或用户点了停止）。它是个长久挂起的 Future，不要 await。
      unawaited(_waitForPhone(client));
    } finally {
      _starting = false;
    }
  }

  Future<void> _waitForPhone(RemoteBridgeClient client) async {
    try {
      final device = await client.connect();
      if (!identical(_client, client)) {
        // 期间被替换过（例如用户重开了），这次结果作废。
        return;
      }
      _device = device;
      _phase = LanPhase.connected;
      _stopTicking();
      _emit();
    } on Object catch (error) {
      if (!identical(_client, client)) {
        return;
      }
      // 停止等待、端口被占、客户端被关掉都会走到这里。
      if (_phase == LanPhase.waiting) {
        _phase = LanPhase.idle;
        _error = error is BridgeException ? null : '$error';
      }
      _stopTicking();
      _emit();
    }
  }

  /// 客户端掉线（手机息屏、切后台、网络抖动……）时自动回到等待状态。
  ///
  /// **这一步不能省**：`connect()` 在校验通过时会主动关掉监听（§10.3 第 4 点），
  /// 所以连接一旦断开，如果不重新 bind，手机那边的自动重连会一直撞在"没人监听"上。
  /// 文档 §10.3 第 1 点说的"重连 = 重新监听"就是这个意思。
  void _onClientPhase(BridgeConnectionPhase phase) {
    // 只关心"从已连接掉下来"这一种，其余状态变化本来就在别处处理。
    if (_phase != LanPhase.connected) {
      return;
    }
    if (phase != BridgeConnectionPhase.disconnected &&
        phase != BridgeConnectionPhase.rejected) {
      return;
    }
    if (_stopping) {
      return;
    }

    // 先落到 idle，这样同一批事件里后续的几次也不会重复触发。
    _device = null;
    _phase = LanPhase.idle;
    _stopTicking();
    _emit();

    unawaited(_restartAfterDrop());
  }

  Future<void> _restartAfterDrop() async {
    // 等一小会儿再重开：让客户端的重连退避先跑、也让刚关掉的端口来得及释放。
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (_stopping) {
      return;
    }
    await startWaiting();
  }

  /// 停止等待（用户切走 Tab 或点了停止）。
  Future<void> stopWaiting() async {
    _stopping = true;
    _stopTicking();
    _pairingCode.stop();
    await _disposeClient();
    await _listener.close();
    _phase = LanPhase.idle;
    _device = null;
    _emit();
  }

  /// 断开当前客户端并释放它的订阅。
  Future<void> _disposeClient() async {
    final subscription = _clientPhaseSubscription;
    _clientPhaseSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }

    final current = _client;
    _client = null;
    if (current != null) {
      await current.disconnect();
      current.dispose();
    }
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
