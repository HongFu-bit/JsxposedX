import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryQueryDatasource {
  final _native = NativeBridge.memoryTool;

  Future<int> getPid({required String packageName}) async {
    return await _native.getPid(packageName: packageName);
  }

  Future<List<ProcessInfo>> getProcessInfo({
    required int offset,
    required int limit,
  }) async {
    return await _native.getProcessInfo(offset, limit);
  }

  Future<List<MemoryRegion>> getMemoryRegions({
    required MemoryRegionQuery query,
  }) async {
    return await _native.getMemoryRegions(query);
  }

  Future<SearchSessionState> getSearchSessionState() async {
    return await _native.getSearchSessionState();
  }

  Future<SearchTaskState> getSearchTaskState() async {
    return await _native.getSearchTaskState();
  }

  Future<List<SearchResult>> getSearchResults({
    required int offset,
    required int limit,
  }) async {
    return await _native.getSearchResults(offset, limit);
  }

  Future<List<MemoryValuePreview>> readMemoryValues({
    required List<MemoryReadRequest> requests,
  }) async {
    return await _native.readMemoryValues(requests);
  }

  Future<List<MemoryInstructionPreview>> disassembleMemory({
    required int pid,
    required List<int> addresses,
  }) async {
    return await _native.disassembleMemory(pid, addresses);
  }

  Future<List<MemoryBreakpoint>> listMemoryBreakpoints({required int pid}) async {
    return await _native.listMemoryBreakpoints(pid);
  }

  Future<MemoryBreakpointState> getMemoryBreakpointState({
    required int pid,
  }) async {
    return await _native.getMemoryBreakpointState(pid);
  }

  Future<List<MemoryBreakpointHit>> getMemoryBreakpointHits({
    required int pid,
    required int offset,
    required int limit,
  }) async {
    return await _native.getMemoryBreakpointHits(pid, offset, limit);
  }
}
