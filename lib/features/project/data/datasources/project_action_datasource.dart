import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/features/project/data/models/audit_log_dto.dart';
import 'package:JsxposedX/generated/project.g.dart';

class ProjectActionDatasource {
  final _native = NativeBridge.project;

  Future<void> initProject() async {
    await _native.initProject();
  }

  Future<void> createProject({required String packageName}) async {
    await _native.createProject(packageName);
  }

  Future<void> deleteProject({required String packageName}) async {
    await _native.deleteProject(packageName);
  }

  /// 删除单条审计日志
  Future<void> deleteAuditLog({
    required String packageName,
    required int timestamp,
  }) async {
    await _native.deleteAuditLog(packageName, timestamp);
  }

  /// 更新单条审计日志
  Future<void> updateAuditLog({
    //TODO 改成hook的
    required String packageName,
    required AuditLogDto log,
  }) async {
    final pigeonLog = AuditLog(
      algorithm: log.algorithm,
      operation: log.operation,
      key: log.key,
      keyBase64: log.keyBase64,
      keyPlaintext: log.keyPlaintext,
      iv: log.iv,
      ivBase64: log.ivBase64,
      ivPlaintext: log.ivPlaintext,
      input: log.input,
      inputBase64: log.inputBase64,
      output: log.output,
      outputBase64: log.outputBase64,
      inputHex: log.inputHex,
      outputHex: log.outputHex,
      stackTrace: log.stackTrace,
      fingerprint: log.fingerprint,
      timestamp: log.timestamp,
    );
    await _native.updateAuditLog(packageName, pigeonLog);
  }

  /// 清空所有审计日志
  Future<void> clearAuditLogs({required String packageName}) async {
    await _native.clearAuditLogs(packageName);
  }

  Future<void> saveAuditLogJsCode({
    required String packageName,
    required String code,
  }) async {
    await NativeBridge.pinia.setString(
      key: "${packageName}_audit_log_js_code",
      value: code,
    );
  }
}
