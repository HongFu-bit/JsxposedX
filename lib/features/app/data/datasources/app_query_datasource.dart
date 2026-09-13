import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/app.g.dart';

/// 应用查询数据源 (已迁移至 Pigeon)
class AppQueryDatasource {
  final _native = NativeBridge.app;

  /// 获取应用总数
  Future<int> getAppCount({required bool includeSystemApps, String query = ""}) async {
    return await _native.getAppCount(includeSystemApps, query);
  }

  /// 获取已安装应用列表 (使用异步 Pigeon 接口)
  Future<List<AppInfo>> getInstalledApps({
    required bool includeSystemApps,
    int offset = 0,
    int limit = 50,
    String query = "",
  }) async {
    return await _native.getInstalledApps(
      includeSystemApps,
      offset,
      limit,
      query,
    );
  }

  /// 根据包名获取单个应用详情
  Future<AppInfo?> getAppByPackageName(String packageName) async {
    return await _native.getAppByPackageName(packageName);
  }
}
