import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryPointerAutoChaseQueryDatasource {
  final _native = NativeBridge.memoryTool;

  Future<PointerAutoChaseState> getPointerAutoChaseState() async {
    return await _native.getPointerAutoChaseState();
  }

  Future<List<PointerScanResult>> getPointerAutoChaseLayerResults({
    required int layerIndex,
    required int offset,
    required int limit,
  }) async {
    return await _native.getPointerAutoChaseLayerResults(
      layerIndex,
      offset,
      limit,
    );
  }
}
