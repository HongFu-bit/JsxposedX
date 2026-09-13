import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryPointerActionDatasource {
  final _native = NativeBridge.memoryTool;

  Future<void> startPointerScan({required PointerScanRequest request}) async {
    await _native.startPointerScan(request);
  }

  Future<void> cancelPointerScan() async {
    await _native.cancelPointerScan();
  }

  Future<void> resetPointerScanSession() async {
    await _native.resetPointerScanSession();
  }
}
