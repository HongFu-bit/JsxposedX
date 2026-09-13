import 'package:JsxposedX/core/utils/path_utils.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';

class FridaQueryDatasource {
  final _native = NativeBridge.project;
  final _piniaNative = NativeBridge.pinia;
  final _zygiskFridaNative = NativeBridge.zygiskFrida;

  Future<List<String>> getFridaScripts({required String packageName}) async {
    return await _native.getFridaScripts(packageName);
  }

  Future<String> readFridaScript({
    required String packageName,
    required String localPath,
  }) async {
    return await _native.readFridaScript(
      packageName,
      PathUtils.getName(path: localPath),
    );
  }

  Future<bool> getFridaScriptStatus({
    required String packageName,
    required String localPath,
  }) async {
    return await _piniaNative.getBool(
      key: "frida_check_status_${packageName}_$localPath",
      defaultValue: false,
    );
  }

  Future<bool> isZygiskModuleInstalled() async {
    return await _zygiskFridaNative.isModuleInstalled();
  }
}
