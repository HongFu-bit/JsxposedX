import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:JsxposedX/desktop/bridge/bridge_cipher.dart';
import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';
import 'package:JsxposedX/desktop/bridge/lan_listener.dart';
import 'package:JsxposedX/desktop/bridge/paired_phone_store.dart';
import 'package:JsxposedX/desktop/bridge/pairing_code.dart';
import 'package:flutter/foundation.dart';

/// 与手机的连接状态。
enum BridgeConnectionPhase {
  /// 完全没有连接，也没有在等待。
  disconnected,

  /// 拨号模式：正在往手机连。
  connecting,

  /// 监听模式：已经 bind 在等手机连上来（界面在这期间显示 6 位码）。
  waiting,

  /// 已完成握手，正在校验凭据。
  authenticating,

  connected,

  rejected,
}

/// 握手时手机返回的设备信息。
@immutable
class BridgeDeviceInfo {
  const BridgeDeviceInfo({
    required this.model,
    required this.android,
    required this.sdk,
    required this.appVersion,
    this.deviceId,
    this.transport,
  });

  final String model;
  final String android;
  final int sdk;
  final String appVersion;

  /// 手机上报的稳定标识（LAN 链路；USB 没有这个字段）。
  final String? deviceId;

  /// `usb` 或 `lan`，用来在状态栏显示"已连接手机（Wi-Fi）"。
  final String? transport;

  bool get isLan => transport == BridgeProtocol.transportLan;

  /// [deviceId] 与 [transport] 单独传进来，是因为手机把这两个字段放在
  /// **welcome 帧的顶层**（与 `code` / `token` 并列），而不是放进嵌套的 `device`
  /// 对象里。见 docs/desktop_bridge_lan_CN.md §8.2——手机侧
  /// `DesktopBridgeServer.welcomeFrame()` 就是这么拼的。
  ///
  /// 早先这里只从嵌套的 `device` 里读，结果 `deviceId` 恒为空：首次用 6 位码
  /// 配对能成功（那条路径不查表），但落盘时 deviceId 是空的，之后用令牌重连
  /// 永远查不到记录，表现为"会话令牌已失效"并无限重试。
  static BridgeDeviceInfo fromJson(
    Map<String, dynamic> json, {
    String? deviceId,
    String? transport,
  }) {
    final resolvedDeviceId = deviceId ?? json['deviceId'] as String?;
    return BridgeDeviceInfo(
      model: json['model'] as String? ?? 'unknown',
      android: json['android'] as String? ?? 'unknown',
      sdk: json['sdk'] as int? ?? 0,
      appVersion: json['appVersion'] as String? ?? '',
      deviceId: (resolvedDeviceId == null || resolvedDeviceId.isEmpty)
          ? null
          : resolvedDeviceId,
      transport: transport ?? json['transport'] as String?,
    );
  }

  @override
  String toString() => '$model / Android $android (API $sdk) / App $appVersion';
}

/// bridge 层异常（仅用于连接与握手阶段；调用阶段的错误按 Pigeon 语义返回 null）。
class BridgeException implements Exception {
  const BridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BridgeException($code): $message';
}

/// 电脑端 → 手机的远程 bridge 客户端。
///
/// 只负责"把 channel 名 + 原始字节送过去、把回包拿回来"，
/// 不解析 Pigeon 载荷内容（那是生成代码的职责）。
///
/// 两种工作模式（文档 §10.3）：
///
/// - **拨号模式**（USB / 手动连接）：主动 `Socket.connect` 到 `host:port`。
///   凭据是**手机出示**、手机校验——本类只把令牌放进 `hello`。
/// - **监听模式**（Wi-Fi 直连）：自己不 bind，socket 由 [LanListener] 提供；
///   连上之后由**本类校验手机出示的凭据**（`welcome.code` / `welcome.token`），
///   校验通过才签发会话令牌、才进入 [BridgeConnectionPhase.connected]。
///
/// 第二条里那句"校验通过才进入 connected"是整套安全性的支点：`sendRaw` 在非
/// connected 阶段直接丢弃调用，所以**校验通过前电脑不可能把任何 Pigeon 调用
/// 发给对端**（§7.2）。这一条是现成的，不需要额外写防护。
class RemoteBridgeClient {
  RemoteBridgeClient({
    this.port = BridgeProtocol.defaultPort,
    this.token = '',
    this.host = '127.0.0.1',
    this.listener,
    this.pairingCode,
    this.phoneStore,
    this.secureTransport = true,
  }) : assert(
          listener == null || (pairingCode != null && phoneStore != null),
          '监听模式必须同时提供 pairingCode 与 phoneStore，否则无法校验对端',
        );

  final String host;

  final int port;

  /// 拨号模式下放进 `hello` 的令牌（USB 链路用它；LAN 链路用不到）。
  final String token;

  /// 是否启用帧加密（§7.6）。
  ///
  /// **只在排查问题时才关**（`--dart-define=BRIDGE_NO_ENCRYPT=true`）。
  /// 关掉之后这条链路退化成明文，用途是把"加密引起的故障"和"别处的故障"
  /// 分开——加密的失败是静默的（GCM 校验不通过只返回 null），只靠日志
  /// 很难断定它是不是元凶，容易在两件事之间来回猜。
  ///
  /// 关掉时两端都会保持在明文：电脑不发 `secured`，手机也就不会启用加密。
  final bool secureTransport;

  /// 非 null 即进入**监听模式**：socket 从它来，校验由本类做。
  final LanListener? listener;

  /// 监听模式下用来的 6 位码校验器；同样持有轮换与限速状态，界面直接读它。
  final PairingCode? pairingCode;

  /// 监听模式下用来签发/核对会话令牌。
  final PairedPhoneStore? phoneStore;

  bool get isListening => listener != null;

  final StreamController<BridgeConnectionPhase> _phaseController =
      StreamController<BridgeConnectionPhase>.broadcast();
  final Map<int, Completer<ByteData?>> _pending = <int, Completer<ByteData?>>{};

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Completer<BridgeDeviceInfo>? _handshake;

  /// NDJSON 分帧用的字节缓冲：攒到换行符为止，再整行 UTF-8 解码。
  ///
  /// 不用 `utf8.decoder` + `LineSplitter` 有两个原因：
  /// 1. Socket 是 `Stream<Uint8List>`，与 `utf8.decoder` 的
  ///    `StreamTransformer<List<int>, String>` 泛型不匹配；
  /// 2. 大载荷（例如反编译结果的 base64）按字符串反复拼接会退化成 O(n²)。
  ///
  /// 按字节累积是安全的：换行符 `0x0A` 不会出现在 UTF-8 多字节序列的续字节里
  /// （续字节都 >= 0x80），所以"一行的字节"永远是完整的 UTF-8。
  final List<int> _pendingBytes = <int>[];

  BridgeConnectionPhase _phase = BridgeConnectionPhase.disconnected;
  BridgeDeviceInfo? _device;
  String? _lastError;
  int _nextId = 1;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  bool _manualClose = false;
  DateTime _lastFrameAt = DateTime.now();

  /// 非 null 表示本连接已启用帧加密（§7.6）。
  ///
  /// 只在监听模式下会启用——USB / 拨号那条链路是 adb forward 过来的本地可信通道，
  /// 而且没有"电脑签发的会话令牌"这个概念，不参与加密。
  BridgeCipher? _cipher;

  Stream<BridgeConnectionPhase> get phaseStream => _phaseController.stream;

  BridgeConnectionPhase get phase => _phase;

  BridgeDeviceInfo? get device => _device;

  String? get lastError => _lastError;

  /// 连接并完成握手（监听模式下还会完成凭据校验）。
  Future<BridgeDeviceInfo> connect() async {
    if (_disposed) {
      throw const BridgeException(BridgeProtocol.errNotConnected, 'Client disposed.');
    }
    _manualClose = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardownSocket();
    _failPending();

    _lastError = null;
    _setPhase(isListening ? BridgeConnectionPhase.waiting : BridgeConnectionPhase.connecting);

    try {
      final device = isListening ? await _connectByListening() : await _connectByDialing();
      if (isListening) {
        // **校验通过就立刻停监听**（文档 §10.3 第 4 点）。
        // 这是 §9.2 里"暴露窗口只有几分钟"这个安全论证能够成立的前提：
        // 手机真的连上之后，端口就不该再对外开着。
        await listener!.close();
      }
      _device = device;
      _reconnectAttempt = 0;
      _setPhase(BridgeConnectionPhase.connected);
      _startHeartbeat();
      return device;
    } on BridgeException catch (error) {
      _lastError = error.message;
      await _teardownSocket();
      _setPhase(BridgeConnectionPhase.disconnected);
      throw error;
    }
  }

  // ------------------------------------------------------------ 监听模式

  /// 反复接受连接、握手、校验，直到有一条通过。
  ///
  /// 未通过的连接不进入 `connected`，因此不会泄漏任何数据（§7.2）；
  /// 这里只是把它关掉、继续等下一条。被拒绝的原因已经通过 `reject` 帧回给了手机。
  Future<BridgeDeviceInfo> _connectByListening() async {
    final pendingListener = listener!;
    while (!_disposed && !_manualClose) {
      final socket = await pendingListener.accept();
      if (socket == null) {
        throw const BridgeException(
          BridgeProtocol.errNotConnected,
          '监听已停止。',
        );
      }

      try {
        return await _performHandshake(socket);
      } on BridgeException catch (error) {
        debugPrint('[desktop-bridge] 本次连接未通过校验：${error.message}');
        await _teardownSocket();
        _setPhase(BridgeConnectionPhase.waiting);
      }
    }
    throw const BridgeException(BridgeProtocol.errNotConnected, '客户端已关闭。');
  }

  // ------------------------------------------------------------ 拨号模式

  Future<BridgeDeviceInfo> _connectByDialing() async {
    Socket socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: BridgeProtocol.connectTimeout,
      );
    } catch (error) {
      _lastError = '无法连接 $host:$port（$error）。请确认已执行 adb forward 且手机 App 在前台。';
      throw BridgeException(BridgeProtocol.errNotConnected, _lastError!);
    }
    return _performHandshake(socket);
  }

  // ------------------------------------------------------------ 握手（两种模式共用）

  /// 方法名刻意不叫 `_handshake`——那个名字已经被上面那个
  /// `Completer<BridgeDeviceInfo>? _handshake` 字段占了，Dart 不允许同名字段与方法。
  Future<BridgeDeviceInfo> _performHandshake(Socket socket) async {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      // 非致命：部分平台可能不支持该选项
    }

    _socket = socket;
    _lastFrameAt = DateTime.now();
    _pendingBytes.clear();

    final handshake = Completer<BridgeDeviceInfo>();
    _handshake = handshake;

    _socketSubscription = socket.listen(
      _onBytes,
      onError: (Object error) {
        debugPrint('[desktop-bridge] socket error: $error');
        _handleDisconnected('连接出错：$error');
      },
      onDone: () => _handleDisconnected('手机端已关闭连接'),
      cancelOnError: false,
    );

    _send(<String, Object?>{
      BridgeProtocol.kType: BridgeProtocol.tHello,
      BridgeProtocol.kVersion: BridgeProtocol.version,
      // 拨号模式下这是给手机校验的令牌；监听模式下手机不需要它（凭据方向相反）。
      BridgeProtocol.kToken: isListening ? '' : token,
      BridgeProtocol.kClient: 'desktop',
      BridgeProtocol.kClientName: _clientName(),
    });
    _setPhase(BridgeConnectionPhase.authenticating);

    try {
      return await handshake.future.timeout(BridgeProtocol.handshakeTimeout);
    } on TimeoutException {
      throw const BridgeException(
        BridgeProtocol.errTimeout,
        '握手超时，手机端未响应 welcome 帧。',
      );
    }
  }

  /// 电脑主机名，手机上用来显示"已连接到谁"。取不到时留空。
  static String _clientName() {
    try {
      return Platform.localHostname;
    } on Object catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------ 公开操作

  /// 主动断开（不会自动重连）。
  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _teardownSocket();
    _failPending();
    _setPhase(BridgeConnectionPhase.disconnected);
  }

  /// 发送一次 Pigeon 调用。
  ///
  /// 失败时返回 null，使生成代码抛出 `PlatformException('channel-error')`，
  /// 与真机上"通道没有实现"的表现完全一致，UI 的既有错误分支无需改动。
  Future<ByteData?> sendRaw(String channel, ByteData? message) {
    if (_socket == null || _phase != BridgeConnectionPhase.connected) {
      debugPrint('[desktop-bridge] 丢弃调用（未连接）：$channel');
      return Future<ByteData?>.value(null);
    }

    final id = _nextId++;
    final completer = Completer<ByteData?>();
    _pending[id] = completer;

    _send(<String, Object?>{
      BridgeProtocol.kType: BridgeProtocol.tCall,
      BridgeProtocol.kId: id,
      BridgeProtocol.kChannel: channel,
      BridgeProtocol.kPayload: message == null
          ? null
          : base64Encode(_bytesOf(message)),
    });

    return completer.future.timeout(
      BridgeProtocol.defaultCallTimeout,
      onTimeout: () {
        _pending.remove(id);
        debugPrint('[desktop-bridge] 调用超时：$channel');
        return null;
      },
    );
  }

  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    unawaited(_phaseController.close());
  }

  // -------------------------------------------------------------- 内部实现

  void _onBytes(Uint8List chunk) {
    _pendingBytes.addAll(chunk);

    while (true) {
      final newlineIndex = _pendingBytes.indexOf(_lineFeed);
      if (newlineIndex < 0) {
        break;
      }

      final lineBytes = _pendingBytes.sublist(0, newlineIndex);
      _pendingBytes.removeRange(0, newlineIndex + 1);

      if (lineBytes.isEmpty) {
        continue;
      }
      _onLine(utf8.decode(lineBytes, allowMalformed: true));
    }
  }

  void _onLine(String line) {
    _lastFrameAt = DateTime.now();
    if (line.isEmpty) {
      return;
    }
    if (!_handleLine(line)) {
      // 协议违规：解密失败，或收到加密帧但本端还没启用加密。
      // 这种连接不能再用了——继续读下去只会把垃圾当成指令。
      debugPrint('[desktop-bridge] 加密协商失败，断开');
      _handleDisconnected('加密协商失败');
    }
  }

  /// 处理一行。@return false 表示协议违规，调用方应断开。
  bool _handleLine(String line) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      debugPrint('[desktop-bridge] 忽略无法解析的帧');
      return true;
    }
    if (decoded is! Map<String, dynamic>) {
      return true;
    }

    switch (decoded[BridgeProtocol.kType]) {
      case BridgeProtocol.tEnc:
        return _onEncrypted(decoded);
      case BridgeProtocol.tWelcome:
        _onWelcome(decoded);
      case BridgeProtocol.tReject:
        _onReject(decoded);
      case BridgeProtocol.tRet:
        _onReturn(decoded);
      case BridgeProtocol.tErr:
        _onErrorFrame(decoded);
      case BridgeProtocol.tPong:
        break;
      default:
        debugPrint('[desktop-bridge] 忽略未知帧：${decoded[BridgeProtocol.kType]}');
    }
    return true;
  }

  /// 拆开一个 `enc` 信封，把内层明文帧送回同一套分派。
  ///
  /// **加密对上层逻辑完全透明**：`_onWelcome` / `_onReturn` 那些方法看到的是
  /// 解出来的原始 JSON，跟不加密时一模一样。
  bool _onEncrypted(Map<String, dynamic> frame) {
    final active = _cipher;
    if (active == null) {
      debugPrint('[desktop-bridge] 收到加密帧但本端还没启用加密');
      return false;
    }
    final seq = frame[BridgeProtocol.kSeq];
    final data = frame[BridgeProtocol.kData];
    if (seq is! int || data is! String) {
      debugPrint('[desktop-bridge] 加密信封字段不完整');
      return false;
    }
    final inner = active.open(seq, data);
    if (inner == null) {
      debugPrint('[desktop-bridge] 解密失败（被篡改 / 密钥不一致 / 重放）');
      return false;
    }
    return _handleLine(inner);
  }

  void _onWelcome(Map<String, dynamic> frame) {
    final rawDevice = frame[BridgeProtocol.kDevice];
    final rawDeviceId = frame[BridgeProtocol.kDeviceId];
    final rawTransport = frame[BridgeProtocol.kTransport];
    final device = BridgeDeviceInfo.fromJson(
      rawDevice is Map<String, dynamic> ? rawDevice : const <String, dynamic>{},
      deviceId: rawDeviceId is String ? rawDeviceId : null,
      transport: rawTransport is String ? rawTransport : null,
    );

    // 监听模式下，welcome 是**手机出示凭据的地方**（§7.3）——校验不通过就在这里
    // 结束：回一个 reject，然后抛出异常让 _connectByListening 继续等下一条。
    if (isListening) {
      final validation = _validate(frame, device);
      final rejection = validation.reject;
      if (rejection != null) {
        unawaited(_rejectAndDrop(rejection));
        return;
      }

      // 校验通过。`secured` 是**明文发送的最后一帧**：两端都在它之后启用帧加密，
      // 所以它自己不能是加密的（§7.6）。
      final sessionToken = validation.sessionToken;
      if (!secureTransport) {
        debugPrint('[desktop-bridge] 帧加密已禁用（BRIDGE_NO_ENCRYPT），本连接为明文');
      } else if (sessionToken != null && sessionToken.isNotEmpty) {
        // **先派生 + 自检，再发 `secured`。**
        // 顺序反过来的话，手机已经收到 secured、启用了加密，而本端却因为自检失败
        // 什么都没发出去——对端只会看到一条沉默的连接，正是最难查的那种故障。
        final BridgeCipher cipher;
        try {
          cipher = BridgeCipher.fromSessionToken(sessionToken);
        } catch (error, stack) {
          debugPrint('[desktop-bridge] 加密初始化失败，拒绝本次连接：$error');
          debugPrintStack(stackTrace: stack);
          unawaited(
            _rejectAndDrop(
              _rejectFrame(
                BridgeProtocol.errInternal,
                '电脑端加密初始化失败：$error',
              ),
            ),
          );
          return;
        }

        _send(<String, Object?>{BridgeProtocol.kType: BridgeProtocol.tSecured});
        _cipher = cipher;
        // 指纹：电脑的 pc2phone 应当等于手机的 phone2pc——同一把密钥的两个方向视角。
        // 两端这两个数不同，就说明密钥派生（HKDF 输入 / info 标签）不一致。
        debugPrint('[desktop-bridge] 帧加密已启用 pc2phone=${cipher.sendKeyFingerprint}');
      }
    }

    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.complete(device);
    }
  }

  /// 把 [rejection] 回给手机（并确保真的发出去），然后结束本次握手。
  Future<void> _rejectAndDrop(Map<String, Object?> rejection) async {
    final socket = _socket;
    if (socket != null) {
      try {
        socket.write('${jsonEncode(rejection)}\n');
        await socket.flush();
      } on Object catch (error) {
        debugPrint('[desktop-bridge] 回写 reject 失败：$error');
      }
    }

    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(
        BridgeException(
          rejection[BridgeProtocol.kCode] as String? ?? BridgeProtocol.errCode,
          rejection[BridgeProtocol.kMessage] as String? ?? '校验未通过。',
        ),
      );
    }
    await _teardownSocket();
  }

  /// 校验手机出示的凭据。
  ///
  /// [reject] 非 null 表示要回给手机的 `reject` 帧；通过时 [sessionToken] 是
  /// 本连接之后用来派生加密密钥的会话令牌（§7.6）。
  ({Map<String, Object?>? reject, String? sessionToken}) _validate(
    Map<String, dynamic> frame,
    BridgeDeviceInfo device,
  ) {
    final codes = pairingCode!;
    final store = phoneStore!;
    final deviceId = device.deviceId ?? '';
    final sourceIp = _socket?.remoteAddress.address ?? 'unknown';

    // 版本协商：手机必须声明支持帧加密。缺了它就**明确拒绝**，而不是静默退回明文——
    // 静默退回等于给攻击者留了一个降级开关（把 welcome 里的 caps 抹掉即可）。
    // 实际后果也只是"新旧版本不能混用"，并且在界面上给出一句能看懂的话。
    //
    // 唯一例外是排查用的 BRIDGE_NO_ENCRYPT：那时本端本来就用明文，
    // 也就没有"降级"可言。
    if (secureTransport) {
      final caps = frame[BridgeProtocol.kCaps];
      final cipherName = caps is Map<String, dynamic>
          ? caps[BridgeProtocol.kCipher]
          : null;
      if (cipherName != BridgeProtocol.cipherA256Gcm) {
        return (
          reject: _rejectFrame(
            BridgeProtocol.errProtocol,
            '手机端版本过旧（不支持帧加密），请更新手机上的 JsxposedX。',
          ),
          sessionToken: null,
        );
      }
    }

    // 路径一：会话令牌。**不受限速与节流影响**（§9.2）——令牌是 128 bit 随机值，
    // 不存在被枚举的风险；而如果把它一起限速，攻击者触发一次全局暂停就能让
    // 已经配对过的手机也连不上，与"无需再输码即可自动重连"直接冲突。
    final submittedToken = frame[BridgeProtocol.kToken];
    if (submittedToken is String && submittedToken.isNotEmpty) {
      final paired = deviceId.isEmpty ? null : store.findByDeviceId(deviceId);
      if (paired != null && paired.token == submittedToken) {
        codes.resetAfterSuccess();
        unawaited(store.touch(paired.deviceId));
        debugPrint('[desktop-bridge] 会话令牌校验通过：${paired.name}');
        return (reject: null, sessionToken: submittedToken);
      }
      return (
        reject: _rejectFrame(
          BridgeProtocol.errCode,
          '会话令牌已失效，请在手机上重新配对。',
        ),
        sessionToken: null,
      );
    }

    // 路径二：6 位校验码。
    final submittedCode = frame[BridgeProtocol.kCode];
    final outcome = codes.check(
      submittedCode is String ? submittedCode : null,
      sourceIp: sourceIp,
    );

    switch (outcome) {
      case CodeAttemptOutcome.accepted:
        codes.resetAfterSuccess();
        // 校验通过 → 签发会话令牌并下发（§8.3）。手机收到后落盘，
        // 之后的重连就走上面那条令牌路径。
        final issued = store.issueSessionToken();
        unawaited(
          store.save(
            deviceId: deviceId,
            name: device.model,
            token: issued,
          ),
        );
        _send(<String, Object?>{
          BridgeProtocol.kType: BridgeProtocol.tToken,
          BridgeProtocol.kToken: issued,
        });
        debugPrint('[desktop-bridge] 校验码通过，已签发会话令牌');
        return (reject: null, sessionToken: issued);

      case CodeAttemptOutcome.stale:
        return (
          reject: _rejectFrame(
            BridgeProtocol.errCodeStale,
            '校验码刚刚刷新，请输入屏幕上新的 6 位数字。',
          ),
          sessionToken: null,
        );

      case CodeAttemptOutcome.locked:
        return (
          reject: _rejectFrame(
            BridgeProtocol.errLocked,
            codes.isPaused
                ? '电脑已暂停校验，请稍后再试。'
                : '尝试次数过多，请稍后再试。',
          ),
          sessionToken: null,
        );

      case CodeAttemptOutcome.wrong:
      case CodeAttemptOutcome.empty:
        return (
          reject: _rejectFrame(BridgeProtocol.errCode, '校验码不正确。'),
          sessionToken: null,
        );
    }
  }

  Map<String, Object?> _rejectFrame(String code, String message) {
    debugPrint('[desktop-bridge] 拒绝手机：$code / $message');
    return <String, Object?>{
      BridgeProtocol.kType: BridgeProtocol.tReject,
      BridgeProtocol.kCode: code,
      BridgeProtocol.kMessage: message,
    };
  }

  void _onReject(Map<String, dynamic> frame) {
    final code = frame[BridgeProtocol.kCode] as String? ?? 'unknown';
    final message = frame[BridgeProtocol.kMessage] as String? ?? '手机端拒绝了连接。';
    _lastError = message;
    _setPhase(BridgeConnectionPhase.rejected);

    // 令牌/协议错误属于配置问题，重试没有意义：停掉自动重连，等用户修正后手动连接。
    if (code == BridgeProtocol.errAuth || code == BridgeProtocol.errProtocol) {
      _manualClose = true;
    }

    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(BridgeException(code, message));
    }
    unawaited(_teardownSocket());
  }

  void _onReturn(Map<String, dynamic> frame) {
    final id = frame[BridgeProtocol.kId];
    if (id is! int) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final payload = frame[BridgeProtocol.kPayload];
    if (payload is String && payload.isNotEmpty) {
      completer.complete(_byteDataOf(base64Decode(payload)));
    } else {
      completer.complete(null);
    }
  }

  void _onErrorFrame(Map<String, dynamic> frame) {
    final message = frame[BridgeProtocol.kMessage] as String? ?? '';
    debugPrint('[desktop-bridge] 手机端返回错误帧：$message');
    final id = frame[BridgeProtocol.kId];
    if (id is! int) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  void _handleDisconnected(String reason) {
    if (_disposed) {
      return;
    }
    _lastError = reason;
    debugPrint('[desktop-bridge] $reason');

    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(
        BridgeException(BridgeProtocol.errNotConnected, reason),
      );
    }

    unawaited(_teardownSocket());
    _failPending();
    _setPhase(BridgeConnectionPhase.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _manualClose) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final attempt = _reconnectAttempt < 1
        ? 1
        : (_reconnectAttempt > BridgeProtocol.maxReconnectDelay.inSeconds
              ? BridgeProtocol.maxReconnectDelay.inSeconds
              : _reconnectAttempt);
    _reconnectTimer = Timer(Duration(seconds: attempt), () {
      if (_disposed || _manualClose) {
        return;
      }
      if (_phase == BridgeConnectionPhase.connecting ||
          _phase == BridgeConnectionPhase.waiting ||
          _phase == BridgeConnectionPhase.authenticating ||
          _phase == BridgeConnectionPhase.connected) {
        return;
      }
      connect().catchError((Object error) {
        debugPrint('[desktop-bridge] 重连失败：$error');
        return BridgeDeviceInfo.fromJson(const <String, dynamic>{});
      });
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(BridgeProtocol.heartbeatInterval, (_) {
      if (_phase == BridgeConnectionPhase.connected) {
        _send(<String, Object?>{
          BridgeProtocol.kType: BridgeProtocol.tPing,
          BridgeProtocol.kId: 0,
        });
      }
      if (DateTime.now().difference(_lastFrameAt) >
          BridgeProtocol.idleTimeout) {
        _handleDisconnected('心跳超时，判定手机端失联');
      }
    });
  }

  void _send(Map<String, Object?> frame) {
    final socket = _socket;
    if (socket == null) {
      return;
    }

    late final String line;
    try {
      // 加密**同步完成**：加密序号必须严格按发送顺序递增。
      final active = _cipher;
      final text = jsonEncode(frame);
      line = '${active == null ? text : active.seal(text)}\n';
    } catch (error, stack) {
      // 加密失败与发送失败必须分开处理：加密失败是**致命**的，
      // 不能退回明文发出去（那是静默降级），也不能像普通写失败那样只记一笔日志——
      // 那会表现为"帧根本没出去、对端等不到响应然后断开"，安静得查不出来。
      debugPrint('[desktop-bridge] 加密失败，本帧不发送：$error');
      debugPrintStack(stackTrace: stack);
      _handleDisconnected('加密失败：$error');
      return;
    }

    try {
      socket.write(line);
    } catch (error) {
      debugPrint('[desktop-bridge] 发送失败：$error');
    }
  }

  static const int _lineFeed = 0x0A;

  Future<void> _teardownSocket() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pendingBytes.clear();
    // 加密是**每条连接独立**的：密钥由那条连接的会话令牌派生。
    // 不清掉的话，下一条连接会带着上一条的密钥，握手一过就解密失败。
    _cipher = null;

    final subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {
        // 忽略取消失败
      }
    }

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        socket.destroy();
      } catch (_) {
        // 忽略关闭失败
      }
    }
  }

  void _failPending() {
    final pending = Map<int, Completer<ByteData?>>.from(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
  }

  void _setPhase(BridgeConnectionPhase value) {
    if (_phase == value) {
      return;
    }
    _phase = value;
    if (!_phaseController.isClosed) {
      _phaseController.add(value);
    }
  }

  static Uint8List _bytesOf(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  static ByteData _byteDataOf(Uint8List bytes) =>
      ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}
