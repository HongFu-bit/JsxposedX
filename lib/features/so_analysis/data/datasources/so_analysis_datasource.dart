import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/so_analysis.g.dart';

class SoAnalysisDatasource {
  final _native = NativeBridge.soAnalysis;

  Future<SoElfHeader> parseSoHeader(String sessionId, String soPath) =>
      _native.parseSoHeader(sessionId, soPath);

  Future<List<SoSection>> getSoSections(String sessionId, String soPath) =>
      _native.getSoSections(sessionId, soPath);

  Future<List<SoSymbol>> getExportedSymbols(String sessionId, String soPath) =>
      _native.getExportedSymbols(sessionId, soPath);

  Future<List<SoSymbol>> getImportedSymbols(String sessionId, String soPath) =>
      _native.getImportedSymbols(sessionId, soPath);

  Future<List<SoDependency>> getDependencies(String sessionId, String soPath) =>
      _native.getDependencies(sessionId, soPath);

  Future<List<SoJniFunction>> getJniFunctions(String sessionId, String soPath) =>
      _native.getJniFunctions(sessionId, soPath);

  Future<List<SoString>> getSoStrings(String sessionId, String soPath) =>
      _native.getSoStrings(sessionId, soPath);

  Future<String> generateFridaHook(
          String sessionId, String soPath, String symbolName, int address) =>
      _native.generateFridaHook(sessionId, soPath, symbolName, address);
}
