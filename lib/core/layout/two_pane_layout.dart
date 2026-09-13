import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/layout/layout_breakpoints.dart';
import 'package:flutter/material.dart';

/// 宽屏双栏容器：左侧固定宽度的列表栏 + 右侧自适应详情栏。
///
/// **使用约束（重要）**：只在宽屏下使用。调用方必须保留窄屏原有的单列 + 路由跳转路径，
/// 这样手机端（Android）的渲染路径与改造前完全一致。典型用法：
///
/// ```dart
/// final useTwoPane = context.isWideLayout && context.isDesktopPlatform;
/// body: useTwoPane
///     ? TwoPaneLayout(list: listArea, detail: detailArea)
///     : listArea,
/// ```
///
/// 详情栏里可以直接放原来的"详情页"（例如 `XposedEditorPage`），
/// 它们都通过构造函数接收参数、不依赖路由状态，因此可以原样内嵌，
/// 同时保留自己的 AppBar 作为详情栏的标题/操作栏。
class TwoPaneLayout extends StatelessWidget {
  const TwoPaneLayout({
    super.key,
    required this.list,
    required this.detail,
    this.listWidth = LayoutBreakpoints.listPaneWidth,
  });

  /// 左栏：通常是列表、树或脚本清单。
  final Widget list;

  /// 右栏：选中项的内容；未选中时用 [TwoPaneEmptyDetail]。
  final Widget detail;

  final double listWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: listWidth, child: list),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: context.colorScheme.outline.withValues(
            alpha: context.isDark ? 0.28 : 0.16,
          ),
        ),
        // 详情栏单独放一个 ScaffoldMessenger：否则 SnackBar 会同时弹在左右两栏。
        Expanded(child: ScaffoldMessenger(child: detail)),
      ],
    );
  }
}

/// [TwoPaneLayout] 的便捷包装：把**整页 Scaffold** 当作左栏，把详情当作右栏。
///
/// `enabled` 为 false 时原样返回 [scaffold]，所以窄屏渲染路径与改造前完全一致。
/// 用它可以只改两行就把"列表页 + 详情页"变成双栏：
///
/// ```dart
/// return TwoPaneScaffold(
///   enabled: useTwoPaneLayout,
///   detail: selected == null ? const TwoPaneEmptyDetail(...) : editor,
///   scaffold: Scaffold(   // ← 原来的整页，内部缩进与结构都不用动
///     ...
///   ),
/// );
/// ```
///
/// 左右两栏各自保留完整的 Scaffold（含 AppBar 与悬浮按钮），
/// 因此每一栏都有自己的标题栏与操作入口，更接近桌面软件的习惯。
class TwoPaneScaffold extends StatelessWidget {
  const TwoPaneScaffold({
    super.key,
    required this.enabled,
    required this.scaffold,
    required this.detail,
    this.listWidth = LayoutBreakpoints.listPaneWidth,
  });

  final bool enabled;
  final Widget scaffold;
  final Widget detail;
  final double listWidth;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return scaffold;
    }
    return TwoPaneLayout(
      list: scaffold,
      detail: detail,
      listWidth: listWidth,
    );
  }
}

/// 双栏详情栏"还没选中条目"时的占位。
///
/// 空状态应当给出下一步动作的提示，而不是只留一片空白。
class TwoPaneEmptyDetail extends StatelessWidget {
  const TwoPaneEmptyDetail({
    super.key,
    required this.message,
    this.icon = Icons.touch_app_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 26,
              color: context.colorScheme.onSurface.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: context.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
