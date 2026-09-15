/// 桌面端 bridge 协议常量（Dart 侧）。
///
/// 与手机侧 `android/app/src/main/kotlin/com/jsxposed/x/core/desktop_bridge/BridgeProtocol.kt`
/// 一一对应，字段名必须保持一致。协议说明见 docs/desktop_bridge_CN.md 第 5 节。
abstract final class BridgeProtocol {
  /// 协议版本。
  static const int version = 1;

  /// 手机侧抽象命名空间 socket 名称（adb forward ... `localabstract:<name>`）。
  static const String socketName = 'jsxposed_desktop_bridge';

  /// 手机端包名与主 Activity。桌面端要靠它把 JsxposedX 拉到前台
  /// （bridge 服务随 Flutter 引擎创建，App 不在前台时通道就没有 handler）。
  static const String androidPackageName = 'com.jsxposed.x';
  static const String androidMainActivity = '.MainActivity';

  /// 默认端口。
  ///
  /// 在 USB 链路上它是 adb forward 的本地转发端口；在 Wi-Fi 链路上它是
  /// **电脑侧实际监听的端口**（手机侧不监听 TCP）。被占用时会顺序回退到
  /// [maxPortFallback]，所以真实端口以欢迎帧/界面显示为准，不要假定是它。
  static const int defaultPort = 27183;

  /// 端口回退上限，与手机侧 `BridgeProtocol` 及文档 §5.3 保持一致。
  static const int maxPortFallback = 27192;

  /// 发现端口（UDP）。**本版不做自动发现**，保留它只为将来可能的增强，
  /// 当前代码里没有任何地方使用。见 docs/desktop_bridge_lan_CN.md §2。
  static const int discoveryPort = 27184;

  /// transport 类型，取值与手机侧一致，用于欢迎帧的 `transport` 字段。
  static const String transportUsb = 'usb';
  static const String transportLan = 'lan';

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

  /// 新增帧：电脑在校验通过后用它把会话令牌下发给手机（§8.3）。
  ///
  /// **手机侧的 `readLoop` 必须显式处理它**——那边对未知帧类型只记日志并继续，
  /// 漏掉会表现为"配对成功了但下次还要重新配对"。
  static const String tToken = 'token';

  /// 校验通过后、**明文发送的最后一帧**：通知手机"从这里开始加密"（§7.6）。
  static const String tSecured = 'secured';

  /// 加密信封：载荷是被 AES-256-GCM 密封的一帧。
  static const String tEnc = 'enc';

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

  /// Wi-Fi 链路新增的字段名（§8.1、§8.2）。
  ///
  /// `kCode` / `kToken` 早已存在（见上），LAN 链路复用它们承载 6 位校验码
  /// 与会话令牌，不要重复定义。
  static const String kTransport = 'transport';
  static const String kClientName = 'clientName';
  static const String kDeviceId = 'deviceId';

  /// 加密信封的字段名（§7.6）。
  static const String kSeq = 'n';

  static const String kData = 'd';

  /// 能力协商里的字段名与套件名（§7.6）。
  static const String kCipher = 'cipher';

  static const String cipherA256Gcm = 'A256GCM';

  /// 错误码。
  static const String errAuth = 'auth';
  static const String errProtocol = 'protocol';
  static const String errBusy = 'busy';
  static const String errNotConnected = 'not-connected';
  static const String errTimeout = 'timeout';

  /// Wi-Fi 链路新增的错误码（§8.4）。
  ///
  /// 前两个只有电脑会发；`locked` 是「被来源限速或全局节流」的**临时**状态，
  /// 手机收到后应继续退避重试，而不是像 `code` 那样停下来等用户输入。
  static const String errCode = 'code';
  static const String errCodeStale = 'code-stale';
  static const String errLocked = 'locked';
}
