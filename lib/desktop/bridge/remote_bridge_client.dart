import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';
import 'package:flutter/foundation.dart';

/// 与手机的连接状态。
enum BridgeConnectionPhase {
  disconnected,
  connecting,
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
  });

  final String model;
  final String android;
  final int sdk;
  final String appVersion;

  static BridgeDeviceInfo fromJson(Map<String, dynamic> json) {
    return BridgeDeviceInfo(
      model: json['model'] as String? ?? 'unknown',
      android: json['android'] as String? ?? 'unknown',
      sdk: json['sdk'] as int? ?? 0,
      appVersion: json['appVersion'] as String? ?? '',
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

/// 桌面端 → 手机的远程 bridge 客户端。
///
/// 只负责"把 channel 名 + 原始字节送过去、把回包拿回来"，
/// 不解析 Pigeon 载荷内容（那是生成代码的职责）。
class RemoteBridgeClient {
  RemoteBridgeClient({
    required this.port,
    required this.token,
    this.host = '127.0.0.1',
  });

  final String host;
  final int port;
  final String token;

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

  Stream<BridgeConnectionPhase> get phaseStream => _phaseController.stream;

  BridgeConnectionPhase get phase => _phase;

  BridgeDeviceInfo? get device => _device;

  String? get lastError => _lastError;

  /// 连接并完成握手。
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
    _setPhase(BridgeConnectionPhase.connecting);

    Socket socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: BridgeProtocol.connectTimeout,
      );
    } catch (error) {
      _lastError = '无法连接 $host:$port（$error）。请确认已执行 adb forward 且手机 App 在前台。';
      _setPhase(BridgeConnectionPhase.disconnected);
      throw BridgeException(BridgeProtocol.errNotConnected, _lastError!);
    }

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      // 非致命：部分平台可能不支持该选项
    }

    _socket = socket;
    _lastFrameAt = DateTime.now();

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
      BridgeProtocol.kToken: token,
      BridgeProtocol.kClient: 'desktop',
    });
    _setPhase(BridgeConnectionPhase.authenticating);

    try {
      final device = await handshake.future.timeout(
        BridgeProtocol.handshakeTimeout,
      );
      _device = device;
      _reconnectAttempt = 0;
      _setPhase(BridgeConnectionPhase.connected);
      _startHeartbeat();
      return device;
    } on TimeoutException {
      _lastError = '握手超时，手机端未响应 welcome 帧。';
      await _teardownSocket();
      _setPhase(BridgeConnectionPhase.disconnected);
      throw BridgeException(BridgeProtocol.errTimeout, _lastError!);
    }
  }

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

    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      debugPrint('[desktop-bridge] 忽略无法解析的帧');
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    switch (decoded[BridgeProtocol.kType]) {
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
  }

  void _onWelcome(Map<String, dynamic> frame) {
    final rawDevice = frame[BridgeProtocol.kDevice];
    final device = rawDevice is Map<String, dynamic>
        ? BridgeDeviceInfo.fromJson(rawDevice)
        : const BridgeDeviceInfo(
            model: 'unknown',
            android: 'unknown',
            sdk: 0,
            appVersion: '',
          );
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.complete(device);
    }
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
    try {
      socket.write('${jsonEncode(frame)}\n');
    } catch (error) {
      debugPrint('[desktop-bridge] 发送失败：$error');
    }
  }

  static const int _lineFeed = 0x0A;

  Future<void> _teardownSocket() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pendingBytes.clear();

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
