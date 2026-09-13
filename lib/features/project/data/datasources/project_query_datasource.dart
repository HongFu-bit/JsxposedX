import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/features/project/data/models/audit_log_dto.dart';
import 'package:JsxposedX/generated/project.g.dart';

class ProjectQueryDatasource {
  final _native = NativeBridge.project;

  Future<bool> projectExists({required String packageName}) async {
    return await _native.projectExists(packageName);
  }




  Future<List<AppInfo>> getProjects() async {
    return await _native.getProjects();
  }

  /// 获取审计日志列表
  Future<List<AuditLogDto>> getAuditLogs({
    required String packageName,
    required int limit,
    required int offset,
    String? keyword,
  }) async {
    final result = await _native.getAuditLogs(
      packageName,
      limit,
      offset,
      keyword,
    );
    return result
        .whereType<AuditLog>() // 过滤 null
        .map(
          (e) => AuditLogDto(
            algorithm: e.algorithm,
            operation: e.operation,
            key: e.key,
            keyBase64: e.keyBase64,
            keyPlaintext: e.keyPlaintext,
            iv: e.iv ?? '',
            ivBase64: e.ivBase64 ?? '',
            ivPlaintext: e.ivPlaintext ?? '',
            input: e.input,
            inputBase64: e.inputBase64,
            output: e.output,
            outputBase64: e.outputBase64,
            inputHex: e.inputHex,
            outputHex: e.outputHex,
            stackTrace: e.stackTrace.map((s) => s ?? "").toList(),
            fingerprint: e.fingerprint,
            timestamp: e.timestamp,
          ),
        )
        .toList();
  }

  Future<String> getAuditLogJsCode({required String packageName}) async {
    return await NativeBridge.pinia.getString(
      key: "${packageName}_audit_log_js_code",
      defaultValue: "",
    );
  }
}
