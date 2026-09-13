import 'dart:convert';

import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/features/project/data/models/dialog_keyword_dto.dart';

class QuickFunctionsConfigActionDataSource {
  final _native = NativeBridge.pinia;

  Future<void> setQuickFunctionStatus({
    required String packageName,
    required String name,
    required bool status,
  }) async {
    await _native.setBool(key: "${packageName}_$name", value: status);
  }

  Future<void> setDialogKeywords({
    required String packageName,
    required String name,
    required List<DialogKeywordDto> keywords,
  }) async {
    await _native.setString(
      key: "${packageName}_${name}_keywords",
      value: jsonEncode(keywords.map((e) => e.toJson()).toList()),
    );
  }
}
