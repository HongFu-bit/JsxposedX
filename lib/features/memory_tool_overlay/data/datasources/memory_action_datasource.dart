import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryActionDatasource {
  final _native = NativeBridge.memoryTool;

  Future<void> firstScan({required FirstScanRequest request}) async {
    await _native.firstScan(request);
  }

  Future<void> nextScan({required NextScanRequest request}) async {
    await _native.nextScan(request);
  }

  Future<void> cancelSearch() async {
    await _native.cancelSearch();
  }

  Future<void> resetSearchSession() async {
    await _native.resetSearchSession();
  }

  Future<void> writeMemoryValue({required MemoryWriteRequest request}) async {
    await _native.writeMemoryValue(request);
  }

  Future<MemoryInstructionPatchResult> patchMemoryInstruction({
    required MemoryInstructionPatchRequest request,
  }) async {
    return await _native.patchMemoryInstruction(request);
  }

  Future<void> setMemoryFreeze({required MemoryFreezeRequest request}) async {
    await _native.setMemoryFreeze(request);
  }

  Future<List<FrozenMemoryValue>> getFrozenMemoryValues() async {
    return await _native.getFrozenMemoryValues();
  }

  Future<bool> isProcessPaused({required int pid}) async {
    return await _native.isProcessPaused(pid);
  }

  Future<void> setProcessPaused({
    required int pid,
    required bool paused,
  }) async {
    await _native.setProcessPaused(pid, paused);
  }

  Future<MemoryBreakpoint> addMemoryBreakpoint({
    required AddMemoryBreakpointRequest request,
  }) async {
    return await _native.addMemoryBreakpoint(request);
  }

  Future<void> removeMemoryBreakpoint({required String breakpointId}) async {
    await _native.removeMemoryBreakpoint(breakpointId);
  }

  Future<void> setMemoryBreakpointEnabled({
    required String breakpointId,
    required bool enabled,
  }) async {
    await _native.setMemoryBreakpointEnabled(breakpointId, enabled);
  }

  Future<void> clearMemoryBreakpointHits({required int pid}) async {
    await _native.clearMemoryBreakpointHits(pid);
  }

  Future<void> resumeAfterBreakpoint({required int pid}) async {
    await _native.resumeAfterBreakpoint(pid);
  }
}
