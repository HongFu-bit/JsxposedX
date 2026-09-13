import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 响应式布局断点与平台判定。
///
/// 断点沿用仓库既有约定（`lib/features/memory_tool_overlay/.../memory_tool_debug_tab.dart`
/// 里的 `LayoutBuilder` 用的 760 / 1280），避免同一仓库出现两套阈值。
///
/// 重要的兼容约束：**手机端（Android）的渲染路径必须与改造前完全一致**。
/// 因此所有宽屏分支都要求同时满足「宽」和「桌面平台」，
/// 手机即使横屏变宽也不会切到双栏布局。
abstract final class LayoutBreakpoints {
  /// 中等宽度：可以放宽内边距、把内容限制在舒适宽度内居中。
  static const double medium = 760;

  /// 宽屏：启用双栏（列表 + 详情）与侧边导航。
  static const double wide = 1280;

  /// 单列内容的最大宽度。超宽窗口下单列内容如果铺满整屏，
  /// 阅读行长会远超易读范围，因此超过这个宽度就居中留白。
  static const double maxSingleColumnWidth = 720;

  /// 双栏布局里左侧列表栏的推荐宽度。
  static const double listPaneWidth = 320;

  /// 是否运行在桌面端（Windows / Linux / macOS）。
  ///
  /// 用 `defaultTargetPlatform` 而不是 `dart:io` 的 `Platform`：
  /// 后者在 web 目标上会直接编译失败，而前者各平台都安全。
  static bool get isDesktopPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// 计算 ScreenUtil 的设计基准尺寸。
  ///
  /// - Android：保持 375×812（与改造前完全一致，手机端表现不变）。
  /// - 桌面端：取**实际窗口尺寸**作为基准，使缩放系数恒为 1。
  ///   否则 `375` 的基准会让 1920 宽的窗口把整个界面放大 5 倍，
  ///   所有 `24.w` / `14.sp` 都会失控。
  ///
  /// 注意：调用方必须把**真实可用的窗口尺寸**传进来。不要用 `MediaQuery` 取——
  /// `AppBootstrap` 位于 `MaterialApp` 之上，那里取不到 `MediaQuery`，
  /// 会静默退回 375 基准（见 app_bootstrap.dart 里的 LayoutBuilder）。
  static Size resolveScreenUtilDesignSize(Size windowSize) {
    if (!isDesktopPlatform) {
      return const Size(375, 812);
    }

    // 兜底：约束无界或异常时退回手机基准，避免算出 0 缩放导致整个界面不可见。
    if (!windowSize.isFinite ||
        windowSize.width <= 0 ||
        windowSize.height <= 0) {
      return const Size(375, 812);
    }

    return Size(windowSize.width, windowSize.height);
  }
}
