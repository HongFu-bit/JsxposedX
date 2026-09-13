import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/desktop/bridge/remote_binary_messenger.dart';
import 'package:JsxposedX/desktop/bridge/remote_bridge_client.dart';
import 'package:JsxposedX/desktop/ui/desktop_connect_gate.dart';
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
/// 与手机端是同一套页面和同一套 provider，区别只在于原生能力经 USB 由手机执行。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const port = int.fromEnvironment(
    'BRIDGE_PORT',
    defaultValue: BridgeProtocol.defaultPort,
  );
  const token = String.fromEnvironment('BRIDGE_TOKEN');

  runApp(
    ProviderScope(
      child: DesktopApp(
        initialPort: port,
        initialToken: token,
        autoConnect: token.isNotEmpty,
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
  });

  final int initialPort;
  final String initialToken;
  final bool autoConnect;

  @override
  State<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends State<DesktopApp> {
  late RemoteBridgeClient _client;
  late int _port;
  late String _token;
  bool _autoConnectPending = false;

  @override
  void initState() {
    super.initState();
    _port = widget.initialPort;
    _token = widget.initialToken;
    _autoConnectPending = widget.autoConnect && _token.isNotEmpty;
    _client = _createClient(_port, _token);
  }

  @override
  void dispose() {
    _client.dispose();
    NativeBridge.detachRemote();
    super.dispose();
  }

  /// 创建一个客户端，并把它的 messenger 注入到原生访问层。
  RemoteBridgeClient _createClient(int port, String token) {
    final client = RemoteBridgeClient(port: port, token: token);
    NativeBridge.attachRemote(RemoteBinaryMessenger(client: client));
    return client;
  }

  Future<void> _connect(int port, String token) async {
    _autoConnectPending = false;

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
        );
      },
    );
  }
}
