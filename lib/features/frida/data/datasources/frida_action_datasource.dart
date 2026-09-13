import 'package:JsxposedX/core/utils/path_utils.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';

class FridaActionDatasource {
  final _native = NativeBridge.project;
  final _piniaNative = NativeBridge.pinia;
  final _zygiskFridaNative = NativeBridge.zygiskFrida;

  Future<void> createFridaScript({
    required String packageName,
    required String localPath,
    required String content,
    bool append = false,
  }) async {
    await _native.createFridaScript(packageName, content, localPath, append);
  }

  Future<void> deleteFridaScript({
    required String packageName,
    required String localPath,
  }) async {
    await _native.deleteFridaScript(
      packageName,
      PathUtils.getName(path: localPath),
    );
    await _piniaNative.remove(
      key: "frida_check_status_${packageName}_$localPath",
    );
  }

  Future<void> importFridaScripts({
    required String packageName,
    required List<String> localPaths,
  }) async {
    await _native.importFridaScripts(packageName, localPaths);
  }

  Future<void> setFridaScriptStatus({
    required String packageName,
    required String localPath,
    required bool enabled,
  }) async {
    await _piniaNative.setBool(
      key: "frida_check_status_${packageName}_$localPath",
      value: enabled,
    );
  }

  Future<void> bundleFridaHookJs({required String packageName}) async {
    await _native.bundleFridaHookJs(packageName);
  }

  Future<bool> isZygiskModuleInstalled() async {
    return await _zygiskFridaNative.isModuleInstalled();
  }

  Future<bool> isZygiskTargetEnabled({required String packageName}) async {
    return await _zygiskFridaNative.isTargetEnabled(packageName);
  }

  Future<int> setZygiskTargetEnabled({
    required String packageName,
    required bool enabled,
  }) async {
    return await _zygiskFridaNative.setTargetEnabled(packageName, enabled);
  }
}
