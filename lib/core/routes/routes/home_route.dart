import 'package:JsxposedX/common/pages/splash_page.dart';
import 'package:JsxposedX/core/models/app_info.dart';
import 'package:JsxposedX/desktop/ui/desktop_memory_tool_page.dart';
import 'package:JsxposedX/features/desktop_bridge/presentation/pages/lan_bridge_page.dart';
import 'package:JsxposedX/features/ai/presentation/pages/ai_reverse_page.dart';
import 'package:JsxposedX/features/home/presentation/pages/tabs/repository_tab/pages/script_detail_page.dart';
import 'package:JsxposedX/features/so_analysis/presentation/pages/so_analysis_page.dart';
import 'package:JsxposedX/features/home/presentation/pages/home_page.dart';
import 'package:JsxposedX/features/project/presentation/pages/crypto/crypto_audit_js_editor_page.dart';
import 'package:JsxposedX/features/project/presentation/pages/crypto/crypto_audit_log_page.dart';
import 'package:JsxposedX/features/frida/presentation/pages/frida_api_manual_page.dart';
import 'package:JsxposedX/features/frida/presentation/pages/frida_editor_page.dart';
import 'package:JsxposedX/features/frida/presentation/pages/frida_project_page.dart';
import 'package:JsxposedX/features/project/presentation/pages/quick_functions_page.dart';
import 'package:JsxposedX/features/xposed/presentation/pages/ai_api_manual_page.dart';
import 'package:JsxposedX/features/xposed/presentation/pages/api_manual_page.dart';
import 'package:JsxposedX/features/xposed/presentation/pages/xposed_editor_page.dart';
import 'package:JsxposedX/features/xposed/presentation/pages/xposed_project_page.dart';
import 'package:JsxposedX/features/xposed/presentation/pages/xposed_visual_editor_page.dart';
import 'package:go_router/go_router.dart';

/// 主要功能路由
class HomeRoute {
  HomeRoute._();

  static const splash = '/';

  static const home = '/home';

  static const quickFunctions = '/quickFunctions';
  static const xposedProject = '/xposedProject/:packageName';
  static const xposedEditor = '/xposedEditor/:packageName';
  static const xposedVisualEditor = '/xposedVisualEditor/:packageName';
  static const fridaProject = '/fridaProject/:packageName';
  static const fridaEditor = '/fridaEditor/:packageName';
  static const aiReverse = '/aiReverse/:packageName';
  static const cryptoAuditLog = '/cryptoAuditLog/:packageName';
  static const cryptoAuditJsEditor = '/cryptoAuditJsEditor/:packageName';
  static const apiManual = '/apiManual';
  static const aiApiManual = '/aiApiManual/:apiType';
  static const fridaApiManual = '/fridaApiManual';
  static const soAnalysis = '/soAnalysis/:packageName';
  static const memoryTool = '/memoryTool';

  /// 手机端「局域网直连」页（电脑端不走这个路由，它有自己的连接页）。
  static const lanBridge = '/lanBridge';
  static const scriptDetail = '/scriptDetail/:id';
  static const login = 'login';

  static String toQuickFunctions({required AppInfo app}) => '/quickFunctions';

  static String toXposedProject({required String packageName}) =>
      '/xposedProject/$packageName';

  static String toXposedEditor({required String packageName}) =>
      '/xposedEditor/$packageName';

  static String toXposedVisualEditor({required String packageName}) =>
      '/xposedVisualEditor/$packageName';

  static String toFridaProject({required String packageName}) =>
      '/fridaProject/$packageName';

  static String toFridaEditor({required String packageName}) =>
      '/fridaEditor/$packageName';

  static String toAiReverse({required String packageName}) =>
      '/aiReverse/$packageName';

  static String toCryptoAuditLog({required String packageName}) =>
      '/cryptoAuditLog/$packageName';

  static String toCryptoAuditJsEditor({required String packageName}) =>
      '/cryptoAuditJsEditor/$packageName';

  static String toSoAnalysis({required String packageName}) =>
      '/soAnalysis/$packageName';

  static String toScriptDetail({required int id}) => '/scriptDetail/$id';

  /// 桌面端内存工具页（手机端是悬浮窗，不走这个路由）。
  static String toMemoryTool() => memoryTool;

  /// 手机端「局域网直连」页。
  static String toLanBridge() => lanBridge;
}

List<GoRoute> homeRoutes = [
  GoRoute(
    path: HomeRoute.splash,
    builder: (context, state) => const SplashPage(),
  ),
  GoRoute(path: HomeRoute.home, builder: (context, state) => const HomePage()),
  GoRoute(
    path: HomeRoute.quickFunctions,
    builder: (context, state) {
      final app = state.extra as AppInfo;
      return QuickFunctionsPage(app: app);
    },
  ),
  GoRoute(
    path: HomeRoute.xposedProject,
    builder: (context, state) {
      final packageName = state.pathParameters["packageName"]!;
      return XposedProjectPage(packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.xposedEditor,
    builder: (context, state) {
      final path = state.extra as String;
      final packageName = state.pathParameters["packageName"]!;
      return XposedEditorPage(path: path, packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.xposedVisualEditor,
    builder: (context, state) {
      final path = state.extra as String;
      final packageName = state.pathParameters["packageName"]!;
      return XposedVisualEditorPage(path: path, packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.fridaProject,
    builder: (context, state) {
      final packageName = state.pathParameters["packageName"]!;
      return FridaProjectPage(packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.fridaEditor,
    builder: (context, state) {
      final path = state.extra as String;
      final packageName = state.pathParameters["packageName"]!;
      return FridaEditorPage(path: path, packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.aiReverse,
    builder: (context, state) {
      final packageName = state.pathParameters["packageName"]!;
      return AiReversePage(packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.cryptoAuditLog,
    builder: (context, state) {
      final packageName = state.pathParameters["packageName"]!;
      return CryptoAuditLogPage(packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.cryptoAuditJsEditor,
    builder: (context, state) {
      final packageName = state.pathParameters["packageName"]!;
      return CryptoAuditJsEditorPage(packageName: packageName);
    },
  ),
  GoRoute(
    path: HomeRoute.apiManual,
    builder: (context, state) => const ApiManualPage(),
  ),
  GoRoute(
    path: HomeRoute.aiApiManual,
    builder: (context, state) {
      final apiType = state.pathParameters['apiType'] ?? 'xposed';
      return AiApiManualPage(initialApiType: apiType);
    },
  ),
  GoRoute(
    path: HomeRoute.fridaApiManual,
    builder: (context, state) => const FridaApiManualPage(),
  ),
  GoRoute(
    path: HomeRoute.soAnalysis,
    builder: (context, state) {
      final packageName = state.pathParameters['packageName']!;
      final extra = state.extra as Map<String, String>;
      return SoAnalysisPage(
        sessionId: extra['sessionId']!,
        soPath: extra['soPath']!,
        packageName: packageName,
      );
    },
  ),
  GoRoute(
    path: HomeRoute.scriptDetail,
    builder: (context, state) {
      final id = state.pathParameters["id"]!;
      return ScriptDetailPage(id: int.tryParse(id) ?? -1);
    },
  ),
  GoRoute(
    path: HomeRoute.memoryTool,
    builder: (context, state) => const DesktopMemoryToolPage(),
  ),
  GoRoute(
    path: HomeRoute.lanBridge,
    builder: (context, state) => const LanBridgePage(),
  ),
];
