import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryPointerQueryDatasource {
  final _native = NativeBridge.memoryTool;

  Future<PointerScanSessionState> getPointerScanSessionState() async {
    return await _native.getPointerScanSessionState();
  }

  Future<PointerScanTaskState> getPointerScanTaskState() async {
    return await _native.getPointerScanTaskState();
  }

  Future<List<PointerScanResult>> getPointerScanResults({
    required int offset,
    required int limit,
  }) async {
    return await _native.getPointerScanResults(offset, limit);
  }

  Future<PointerScanChaseHint> getPointerScanChaseHint() async {
    return await _native.getPointerScanChaseHint();
  }
}
