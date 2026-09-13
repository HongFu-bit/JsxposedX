import 'package:JsxposedX/core/layout/layout_breakpoints.dart';
import 'package:JsxposedX/core/providers/locale_provider.dart';
import 'package:JsxposedX/core/providers/theme_provider.dart';
import 'package:JsxposedX/core/themes/app_theme.dart';
import 'package:JsxposedX/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef AppBootstrapBuilder =
    Widget Function(
      BuildContext context,
      Locale locale,
      ThemeData lightTheme,
      ThemeData darkTheme,
      ThemeMode themeMode,
    );

class AppBootstrap extends ConsumerWidget {
  const AppBootstrap({super.key, required this.builder});

  final AppBootstrapBuilder builder;

  static const Iterable<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];

  static const Iterable<Locale> supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final theme = ref.watch(themeProvider);
    final lightTheme = theme.brightness == Brightness.light
        ? theme
        : AppTheme.lightTheme(theme.colorScheme.primary);
    final darkTheme = theme.brightness == Brightness.dark
        ? theme
        : AppTheme.darkTheme(theme.colorScheme.primary);
    final themeMode = theme.brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    // ScreenUtil 的设计基准要跟着窗口走，但 AppBootstrap 位于 MaterialApp **之上**，
    // 那里取不到 MediaQuery（MediaQuery 由 MaterialApp/WidgetsApp 内部插入），
    // 所以这里用 LayoutBuilder 的约束取真实窗口尺寸；顺带保证窗口缩放时会跟着更新。
    return LayoutBuilder(
      builder: (context, constraints) {
        return ScreenUtilInit(
          // Android 保持 375×812；桌面端取实际窗口尺寸（缩放系数为 1），
          // 否则宽窗口会把整个界面等比放大数倍。见 LayoutBreakpoints。
          designSize: LayoutBreakpoints.resolveScreenUtilDesignSize(
            constraints.biggest,
          ),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) {
            return builder(context, locale, lightTheme, darkTheme, themeMode);
          },
        );
      },
    );
  }
}
