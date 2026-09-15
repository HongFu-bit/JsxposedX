import 'dart:async';

import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';
import 'package:JsxposedX/desktop/bridge/lan_bridge_controller.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/desktop/bridge/remote_binary_messenger.dart';
import 'package:JsxposedX/desktop/bridge/remote_bridge_client.dart';
import 'package:JsxposedX/desktop/ui/desktop_connect_gate.dart';
import 'package:JsxposedX/desktop/ui/desktop_overlay_host_runtime.dart';
import 'package:JsxposedX/features/overlay_window/presentation/providers/overlay_window_host_runtime_provider.dart';
import 'package:JsxposedX/main.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 桌面端入口。
///
/// 运行方式（推荐）：
/// ```powershell
/// .\.buildScript\run_desktop_bridge.ps1
/// ```
/// 手动运行：
/// ```powershell
/// flutter run -d windows -t lib/desktop/main_desktop.dart `
///   --dart-define=BRIDGE_PORT=27183 --dart-define=BRIDGE_TOKEN=<手机 logcat 里的 token>
/// ```
///
/// 连接成功后进入的界面就是 lib/main.dart 里的 [MainApp]——
/// 与手机端是同一套页面和同一套 provider，区别只在于原生能力经隧道由手机执行。
///
/// 两条链路在这里汇合（docs/desktop_bridge_lan_CN.md §10.3）：
/// - **USB / 拨号**：[RemoteBridgeClient] 主动连 `127.0.0.1:port`，凭据由手机校验。
/// - **Wi-Fi 直连**：[LanBridgeController] 里的 [RemoteBridgeClient] 是**监听模式**，
///   socket 由它自己 bind，凭据（6 位码/会话令牌）由**电脑**校验。
///
/// 两者只能有一个生效，所以下面用一个 [_lanAttached] 标志决定当前把哪一条
/// 接到 [NativeBridge] 上。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const port = int.fromEnvironment(
    'BRIDGE_PORT',
    defaultValue: BridgeProtocol.defaultPort,
  );
  const token = String.fromEnvironment('BRIDGE_TOKEN');

  // 排查用：关掉 LAN 链路的帧加密，把"加密引起的故障"和"别处的故障"分开。
  // 只在诊断时使用——关掉之后这条链路是明文（见 RemoteBridgeClient.secureTransport）。
  const noEncrypt = bool.fromEnvironment('BRIDGE_NO_ENCRYPT');

  runApp(
    ProviderScope(
      // 桌面端没有悬浮窗：把宿主运行时换成替身，否则内存工具面板在构建时
      // 就会去碰 flutter_overlay_window 而抛异常。手机端不受影响。
      overrides: [
        overlayWindowHostRuntimeProvider.overrideWith(
          DesktopOverlayWindowHostRuntime.new,
        ),
      ],
      child: DesktopApp(
        initialPort: port,
        initialToken: token,
        autoConnect: token.isNotEmpty,
        secureTransport: !noEncrypt,
      ),
    ),
  );
}

class DesktopApp extends StatefulWidget {
  const DesktopApp({
    super.key,
    this.initialPort = BridgeProtocol.defaultPort,
    this.initialToken = '',
    this.autoConnect = false,
    this.secureTransport = true,
  });

  final int initialPort;
  final String initialToken;
  final bool autoConnect;

  /// 是否启用 LAN 链路的帧加密。排查问题时用 `BRIDGE_NO_ENCRYPT` 关掉。
  final bool secureTransport;

  @override
  State<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends State<DesktopApp> {
  late RemoteBridgeClient _client;
  late int _port;
  late String _token;
  late final LanBridgeController _lan;
  bool _autoConnectPending = false;

  /// LAN 那条是否已经接到 [NativeBridge] 上。
  bool _lanAttached = false;

  @override
  void initState() {
    super.initState();
    _port = widget.initialPort;
    _token = widget.initialToken;
    _autoConnectPending = widget.autoConnect && _token.isNotEmpty;
    _lan = LanBridgeController(secureTransport: widget.secureTransport);
    _client = _createClient(_port, _token);
    _lan.stream.listen(_onLanState);

    // 已经有配对过的手机就自动开监听——否则手机在自动重连、电脑却没在等，
    // 两边永远对不上（见 LanBridgeController.autoResumeIfPaired 的说明）。
    unawaited(_lan.autoResumeIfPaired());
  }

  @override
  void dispose() {
    _client.dispose();
    unawaited(_lan.dispose());
    NativeBridge.detachRemote();
    super.dispose();
  }

  /// LAN 连上/断开时，切换 [NativeBridge] 背后是哪条链路。
  void _onLanState(LanSnapshot snapshot) {
    if (snapshot.isConnected == _lanAttached) {
      return;
    }
    final lanClient = _lan.client;
    if (snapshot.isConnected && lanClient != null) {
      NativeBridge.attachRemote(RemoteBinaryMessenger(client: lanClient));
      _lanAttached = true;
    } else {
      NativeBridge.attachRemote(RemoteBinaryMessenger(client: _client));
      _lanAttached = false;
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// 创建一个客户端，并把它的 messenger 注入到原生访问层。
  RemoteBridgeClient _createClient(int port, String token) {
    final client = RemoteBridgeClient(port: port, token: token);
    NativeBridge.attachRemote(RemoteBinaryMessenger(client: client));
    return client;
  }

  Future<void> _connect(int port, String token) async {
    _autoConnectPending = false;

    // LAN 那条如果正连着，先让位——两条链路共用一个客户端槽位。
    if (_lanAttached) {
      await _lan.stopWaiting();
    }

    // 端口或令牌变了就必须换客户端实例（两者都是构造期注入的 final 字段）。
    if (port != _client.port || token != _client.token) {
      final previous = _client;
      final replacement = _createClient(port, token);
      setState(() {
        _client = replacement;
        _port = port;
        _token = token;
      });
      previous.dispose();
      await replacement.connect();
      return;
    }

    await _client.connect();
  }

  @override
  Widget build(BuildContext context) {
    if (_lanAttached) {
      return const MainApp();
    }

    return StreamBuilder<BridgeConnectionPhase>(
      stream: _client.phaseStream,
      initialData: _client.phase,
      builder: (context, snapshot) {
        if (snapshot.data == BridgeConnectionPhase.connected) {
          return const MainApp();
        }
        return DesktopConnectGate(
          initialPort: _port,
          initialToken: _token,
          onConnect: _connect,
          autoConnect: _autoConnectPending,
          lanController: _lan,
        );
      },
    );
  }
}
