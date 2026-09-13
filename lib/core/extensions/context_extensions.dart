import 'package:JsxposedX/core/layout/layout_breakpoints.dart';
import 'package:JsxposedX/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// BuildContext 扩展
/// 提供快捷访问国际化、主题等常用功能
extension BuildContextExtensions on BuildContext {
  /// 快捷访问国际化
  /// 用法: context.l10n.home
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  /// 快捷访问主题
  /// 用法: context.theme.primaryColor
  ThemeData get theme => Theme.of(this);

  /// 快捷访问文字主题
  /// 用法: context.textTheme.bodyLarge
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// 快捷访问颜色方案
  /// 用法: context.colorScheme.primary
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// 判断当前语言是否为英文
  /// 用法: if (context.isEnglish) { ... }
  bool get isEnglish => Localizations.localeOf(this).languageCode == 'en';

  /// 判断当前语言是否为中文
  /// 用法: if (context.isChinese) { ... }
  bool get isChinese => Localizations.localeOf(this).languageCode == 'zh';

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  double get screenWidth => MediaQuery.of(this).size.width;

  double get screenHeight => MediaQuery.of(this).size.height;

  String get location => GoRouterState.of(this).matchedLocation;

  /// 用法: context.languageCode  // 返回 'zh' 或 'en'
  String get languageCode => Localizations.localeOf(this).languageCode;

  bool get isZh => Localizations.localeOf(this).languageCode == 'zh';

  bool get isEn => Localizations.localeOf(this).languageCode == 'en';

  /// 是否宽屏（>= 1280）：启用双栏布局与侧边导航。
  /// 注意：宽屏分支通常还要叠加 [isDesktopPlatform] 判断，
  /// 以保证手机端（哪怕横屏）渲染路径与改造前完全一致。
  bool get isWideLayout => screenWidth >= LayoutBreakpoints.wide;

  /// 是否达到中等宽度（>= 760）：适合把单列内容限制宽度后居中。
  bool get isMediumLayout => screenWidth >= LayoutBreakpoints.medium;

  /// 是否运行在桌面端（Windows / Linux / macOS）。
  bool get isDesktopPlatform => LayoutBreakpoints.isDesktopPlatform;
}
