/// 桌面端 bridge 协议常量（Dart 侧）。
///
/// 与手机侧 `android/app/src/main/kotlin/com/jsxposed/x/core/desktop_bridge/BridgeProtocol.kt`
/// 一一对应，字段名必须保持一致。协议说明见 docs/desktop_bridge_CN.md 第 5 节。
abstract final class BridgeProtocol {
  /// 协议版本。
  static const int version = 1;

  /// 手机侧抽象命名空间 socket 名称（adb forward ... localabstract:<name>）。
  static const String socketName = 'jsxposed_desktop_bridge';

  /// 手机端包名与主 Activity。桌面端要靠它把 JsxposedX 拉到前台
  /// （bridge 服务随 Flutter 引擎创建，App 不在前台时通道就没有 handler）。
  static const String androidPackageName = 'com.jsxposed.x';
  static const String androidMainActivity = '.MainActivity';

  /// 默认本地转发端口。
  static const int defaultPort = 27183;

  /// 只把该前缀的通道送到手机；其余通道交给 PC 本地实现。
  static const String channelPrefix = 'dev.flutter.pigeon.JsxposedX.';

  /// 心跳间隔。
  static const Duration heartbeatInterval = Duration(seconds: 10);

  /// 超过该时长没收到任何帧即判定断线。
  static const Duration idleTimeout = Duration(seconds: 30);

  /// 建连与鉴权超时。
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration handshakeTimeout = Duration(seconds: 10);

  /// 单次调用默认超时。部分方法（反编译、内存扫描）在服务端耗时较长，
  /// 见 docs/desktop_bridge_CN.md §9。
  static const Duration defaultCallTimeout = Duration(seconds: 60);

  /// 重连退避上限。
  static const Duration maxReconnectDelay = Duration(seconds: 5);

  /// 帧类型。
  static const String tHello = 'hello';
  static const String tWelcome = 'welcome';
  static const String tReject = 'reject';
  static const String tCall = 'call';
  static const String tRet = 'ret';
  static const String tErr = 'err';
  static const String tPing = 'ping';
  static const String tPong = 'pong';

  /// 帧字段名。
  static const String kType = 't';
  static const String kVersion = 'v';
  static const String kToken = 'token';
  static const String kClient = 'client';
  static const String kAppVersion = 'appVersion';
  static const String kDevice = 'device';
  static const String kCaps = 'caps';
  static const String kCode = 'code';
  static const String kMessage = 'message';
  static const String kId = 'id';
  static const String kChannel = 'ch';
  static const String kPayload = 'p';

  /// 错误码。
  static const String errAuth = 'auth';
  static const String errProtocol = 'protocol';
  static const String errBusy = 'busy';
  static const String errNotConnected = 'not-connected';
  static const String errTimeout = 'timeout';
}
