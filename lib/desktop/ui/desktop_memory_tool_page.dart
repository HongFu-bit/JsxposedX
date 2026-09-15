import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/pages/memory_tool_overlay.dart';
import 'package:flutter/material.dart';

/// 桌面端的内存工具页面。
///
/// 手机端这个工具以悬浮窗形式存在（`flutter_overlay_window` 是 Android 专属），
/// 桌面端没有悬浮窗，因此把**同一套面板 UI** 直接放进普通页面渲染 ——
/// 界面与手机端一致，而它的原生能力本来就是经 Pigeon 隧道由手机执行的，
/// 所以功能是完整的。
///
/// 页面只额外加一条细标题栏：面板自带的工具栏里没有关闭按钮
/// （`showCloseAction: false`），需要一个明确的返回入口。
///
/// 依赖前提：桌面端入口 `main_desktop.dart` 把 `overlayWindowHostRuntimeProvider`
/// 覆写成了 `DesktopOverlayWindowHostRuntime`，否则面板读不到显示模式、
/// 并且会在构建时撞上悬浮窗插件。
class DesktopMemoryToolPage extends StatelessWidget {
  const DesktopMemoryToolPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text(context.l10n.overlayMemoryToolTitle),
      ),
      body: const MemoryToolOverlay(),
    );
  }
}
