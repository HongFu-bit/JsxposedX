import 'package:pigeon/pigeon.dart';

/// 一台已配对的电脑（手机侧保存）。
///
/// **不含会话令牌**：令牌只留在原生侧，Dart 层不需要也不应该拿到它。
/// 这里只暴露"给用户看和给用户删"所需的最小信息。
class LanPairedPc {
  /// 电脑名，来自握手时 `hello.clientName`。配对成功前是地址。
  final String name;

  final String host;

  final int port;

  /// 上次成功配对/连接的时间戳（毫秒）。
  final int lastConnectedAtMs;

  LanPairedPc({
    required this.name,
    required this.host,
    required this.port,
    required this.lastConnectedAtMs,
  });
}

/// 「局域网直连」页要展示的状态。
///
/// 页面靠轮询 [LanBridgeNative.getStatus] 刷新；被拒绝的原因也在这里回传，
/// 因为 `reject` 是电脑发给手机的原生帧，Dart 侧看不到（docs/desktop_bridge_lan_CN.md §8.4、§9.3）。
class LanBridgeStatus {
  /// USB 链路是否已连上（与 LAN 互斥，共用一个客户端槽位）。
  final bool usbConnected;

  /// LAN 链路是否已连上。
  final bool lanConnected;

  /// 是否已经设定了拨号目标（不代表已连上）。
  final bool hasTarget;

  final String? targetHost;

  final int targetPort;

  /// 已连接/正在连接的电脑名。
  final String? peerName;

  /// 最近一次被电脑拒绝的错误码：`code` / `code-stale` / `locked` / `busy`（§8.4）。
  final String? lastRejectCode;

  final String? lastRejectMessage;

  final bool autoReconnect;

  LanBridgeStatus({
    required this.usbConnected,
    required this.lanConnected,
    required this.hasTarget,
    this.targetHost,
    required this.targetPort,
    this.peerName,
    this.lastRejectCode,
    this.lastRejectMessage,
    required this.autoReconnect,
  });
}

/// 手机端「局域网直连」的原生接口。
///
/// 这些方法都很快（只读写内存状态与 SharedPreferences），因此不加 `@async`。
/// 真正的拨号在原生侧的独立线程里跑，不阻塞这里。
@HostApi()
abstract class LanBridgeNative {
  /// 页面轮询当前状态。
  LanBridgeStatus getStatus();

  /// 用**用户输入的 6 位校验码**连接指定电脑（首次配对）。
  ///
  /// 调用即返回；拨号在后台按 1s→2s→4s… 退避重试，直到连上或用户断开。
  void connectWithCode(String host, int port, String code);

  /// 用**已保存的会话令牌**重连一台已配对的电脑。
  ///
  /// 与 [connectWithCode] 的区别只在出示什么凭据；地址变了就不该走这里（§11.4）。
  void reconnectTo(String host, int port);

  /// 主动断开 LAN 并清除拨号目标（保留已配对记录）。
  void disconnect();

  /// 已配对的电脑列表。
  List<LanPairedPc> listPairedPcs();

  /// 忘掉一台电脑（连同它的令牌）。若它正连着，一并断开。
  /// @return 是否确实删掉了一条。
  bool forgetPc(String host, int port);

  /// 忘记全部。
  void forgetAllPcs();

  /// 是否在 App 启动与断线后自动重连。
  void setAutoReconnect(bool enabled);
}
