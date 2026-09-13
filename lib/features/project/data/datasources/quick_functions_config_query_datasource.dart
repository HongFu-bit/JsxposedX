import 'dart:convert';

import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/features/project/data/models/dialog_keyword_dto.dart';

class QuickFunctionsConfigQueryDataSource {
  final _native = NativeBridge.pinia;

  Future<bool> getQuickFunctionStatus({
    required String packageName,
    required String name,
  }) async {
    return await _native.getBool(
      key: "${packageName}_$name",
      defaultValue: false,
    );
  }

  Future<List<DialogKeywordDto>> getDialogKeywords({
    required String packageName,
    required String name,
  }) async {
    final raw = await _native.getString(
      key: "${packageName}_${name}_keywords",
      defaultValue: '[]',
    );
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => DialogKeywordDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
