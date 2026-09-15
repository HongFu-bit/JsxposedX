import 'package:JsxposedX/desktop/bridge/remote_binary_messenger.dart';
import 'package:JsxposedX/desktop/bridge/remote_bridge_client.dart';
import 'package:JsxposedX/generated/apk_analysis.g.dart';
import 'package:JsxposedX/generated/app.g.dart';
import 'package:JsxposedX/generated/lan_bridge.g.dart';
import 'package:JsxposedX/generated/lsposed.g.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:JsxposedX/generated/pinia.g.dart';
import 'package:JsxposedX/generated/project.g.dart';
import 'package:JsxposedX/generated/so_analysis.g.dart';
import 'package:JsxposedX/generated/status_management.g.dart';
import 'package:JsxposedX/generated/zygisk_frida.g.dart';
import 'package:flutter/services.dart';

/// 原生 bridge 的统一访问层。
///
/// 业务代码不再直接 `new` 生成出来的 Native 类，而是从这里取：
///
/// ```dart
/// // 之前
/// final _native = ProjectNative();
/// // 现在
/// final _native = NativeBridge.project;
/// ```
///
/// 为什么需要这层：
/// - **Android（手机）上**：`_remote` 恒为 null，`XxxNative(binaryMessenger: null)`
///   与原来的 `XxxNative()` 完全等价，行为、通道名、编解码全部不变。
/// - **桌面端**：启动时注入 [RemoteBinaryMessenger]，同样的调用就会经 USB 送到手机，
///   由手机上已经注册好的 Pigeon Handler 执行。
///
/// 返回类型仍然是 Pigeon 生成的类型本身，所以调用方代码（方法名、参数、返回值）
/// 一行都不用改，UI 与业务逻辑两端共用同一份代码。
///
/// 说明：getter 每次调用都会构造新实例（与改造前的写法开销一致）；
/// Pigeon 的生成类本身只是通道包装，构造开销极低。
abstract final class NativeBridge {
  static RemoteBinaryMessenger? _remote;

  /// 桌面端启动时注入；Android 上永远不会被调用。
  static void attachRemote(RemoteBinaryMessenger messenger) {
    _remote = messenger;
  }

  /// 断开与手机桥接（桌面端退出或切回本地模式时调用）。
  static void detachRemote() {
    _remote = null;
  }

  /// 当前是否处于"远程（USB）"模式。
  static bool get isRemote => _remote != null;

  /// 仅用于诊断：当前生效的 messenger。
  static BinaryMessenger? get remoteMessenger => _remote;

  /// 桌面端当前的远程连接客户端；Android 上恒为 null。
  /// 供侧边栏显示连接状态使用（见 HomeNavSidebar / DesktopBridgeStatus）。
  static RemoteBridgeClient? get remoteClient => _remote?.client;

  static ApkAnalysisNative get apkAnalysis =>
      ApkAnalysisNative(binaryMessenger: _remote);

  static AppNative get app => AppNative(binaryMessenger: _remote);

  static LSPosedNative get lsposed => LSPosedNative(binaryMessenger: _remote);

  /// 「局域网直连」的状态与操作。
  ///
  /// 它读的是**手机侧**的 DesktopBridgeManager：桌面端连上之后，走这条通道
  /// 能读到手机那份"已配对的电脑"列表，而不是电脑自己的（§11.1）。
  static LanBridgeNative get lanBridge =>
      LanBridgeNative(binaryMessenger: _remote);

  static MemoryToolNative get memoryTool =>
      MemoryToolNative(binaryMessenger: _remote);

  static PiniaNative get pinia => PiniaNative(binaryMessenger: _remote);

  static ProjectNative get project => ProjectNative(binaryMessenger: _remote);

  static SoAnalysisNative get soAnalysis =>
      SoAnalysisNative(binaryMessenger: _remote);

  static StatusManagementNative get statusManagement =>
      StatusManagementNative(binaryMessenger: _remote);

  static ZygiskFridaNative get zygiskFrida =>
      ZygiskFridaNative(binaryMessenger: _remote);
}
