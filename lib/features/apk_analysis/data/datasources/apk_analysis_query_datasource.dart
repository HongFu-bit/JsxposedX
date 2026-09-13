import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/apk_analysis.g.dart';

class ApkAnalysisQueryDatasource {
  final _native = NativeBridge.apkAnalysis;

  Future<List<ApkAsset>> getApkAssets(String sessionId) async =>
      await _native.getApkAssets(sessionId);

  Future<List<ApkAsset>> getApkAssetsAt(String sessionId, String path) async =>
      await _native.getApkAssetsAt(sessionId, path);

  Future<ApkManifest> parseManifest(String sessionId) async =>
      await _native.parseManifest(sessionId);

  Future<List<String>> getDexPackages(
          String sessionId, List<String> dexPaths, String packagePrefix) async =>
      await _native.getDexPackages(sessionId, dexPaths, packagePrefix);

  Future<List<DexClass>> getDexClasses(
          String sessionId, List<String> dexPaths, String packageName) async =>
      await _native.getDexClasses(sessionId, dexPaths, packageName);

  Future<String> getClassSmali(
          String sessionId, List<String> dexPaths, String className) async =>
      await _native.getClassSmali(sessionId, dexPaths, className);

  Future<String> decompileClass(
          String sessionId, List<String> dexPaths, String className) async =>
      await _native.decompileClass(sessionId, dexPaths, className);

  Future<List<String>> searchDexClasses(
          String sessionId, List<String> dexPaths, String keyword) async =>
      await _native.searchDexClasses(sessionId, dexPaths, keyword);
}
