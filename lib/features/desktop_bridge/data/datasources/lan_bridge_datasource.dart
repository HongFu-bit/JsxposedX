import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/lan_bridge.g.dart';

/// 手机端「局域网直连」页的数据来源。
///
/// 薄薄一层，只做两件事：
/// 1. 把 [NativeBridge] 的访问方式收口（与仓库里其它 feature 的 datasource 一致）；
/// 2. 把"粘贴一整行连接文本"的解析放在 Dart 侧，而不是让原生再去解析一遍。
///
/// 解析用的是与电脑端同一份 [BridgeLinkText]（`lib/core/utils/bridge_link_text.dart`），
/// 避免两端的格式理解出现偏差。
class LanBridgeDatasource {
  const LanBridgeDatasource();

  LanBridgeNative get _native => NativeBridge.lanBridge;

  Future<LanBridgeStatus> status() async => _native.getStatus();

  Future<List<LanPairedPc>> pairedPcs() async => _native.listPairedPcs();

  /// 用地址 + 6 位码发起配对。
  Future<void> connectWithCode({
    required String host,
    required int port,
    required String code,
  }) async {
    _native.connectWithCode(host, port, code);
  }

  /// 用已保存的令牌重连一台已配对的电脑。
  Future<void> reconnectTo({required String host, required int port}) async {
    _native.reconnectTo(host, port);
  }

  Future<void> disconnect() async => _native.disconnect();

  Future<bool> forgetPc({required String host, required int port}) async =>
      _native.forgetPc(host, port);

  Future<void> forgetAllPcs() async => _native.forgetAllPcs();

  Future<void> setAutoReconnect(bool enabled) async =>
      _native.setAutoReconnect(enabled);
}
