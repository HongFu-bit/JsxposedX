import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/apk_analysis.g.dart';

class ApkAnalysisActionDatasource {
  final _native = NativeBridge.apkAnalysis;

  Future<String> openApkSession(String packageName) async =>
      await _native.openApkSession(packageName);

  Future<void> closeApkSession(String sessionId) async =>
      await _native.closeApkSession(sessionId);
}

