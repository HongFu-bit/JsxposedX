import 'dart:async';
import 'dart:typed_data';

import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';
import 'package:JsxposedX/desktop/bridge/remote_bridge_client.dart';
import 'package:flutter/services.dart';

/// 把 Pigeon 通道改道到 USB 的 [BinaryMessenger] 适配器。
///
/// 工作方式：命中 [BridgeProtocol.channelPrefix] 前缀的通道原样送手机（不解析载荷，
/// 由 Pigeon 生成代码负责编解码），其余通道交给 PC 本地的 messenger，
/// 保证桌面端本地插件（文件选择、SharedPreferences 等）行为不变。
///
/// ─────────────────────────────────────────────────────────────────────────
/// ⚠️ 本文件是全仓库唯一依赖 Flutter 框架内部 API（`BinaryMessenger` 抽象类成员集合）
/// 的地方。若 `flutter analyze` 报"缺少实现 / 签名不兼容"，按提示增删下面标注的三处
/// 兼容成员即可，不影响其他任何代码。详见 docs/desktop_bridge_CN.md §9.4。
/// ─────────────────────────────────────────────────────────────────────────
class RemoteBinaryMessenger extends BinaryMessenger {
  RemoteBinaryMessenger({
    required this.client,
    BinaryMessenger? local,
    List<String>? channelPrefixes,
  }) : _local = local ?? ServicesBinding.instance.defaultBinaryMessenger,
       _prefixes = channelPrefixes ?? const <String>[BridgeProtocol.channelPrefix];

  final RemoteBridgeClient client;

  final BinaryMessenger _local;

  final List<String> _prefixes;

  /// 该通道是否应该走 USB。
  bool handles(String channel) {
    for (final prefix in _prefixes) {
      if (channel.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (!handles(channel)) {
      return _local.send(channel, message);
    }
    return client.sendRaw(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (!handles(channel)) {
      _local.setMessageHandler(channel, handler);
      return;
    }
    // 当前 9 个 bridge 全部是 @HostApi，手机不会反向调用 Dart，
    // 因此远程通道不需要注册 handler（协议里已预留 rcall 帧）。
  }

  // ── 以下三个成员是跨 Flutter 版本兼容用的占位实现 ──
  // 它们在部分版本里是抽象成员（必须实现），在另一些版本里并不存在（多出来无害），
  // 因此刻意不加 @override，也不转发给本地 messenger（避免依赖不确定的方法存在性）。
  // 若编译器提示签名冲突，直接删掉对应方法即可。

  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    dynamic callback,
  ) async {
    // 桌面端不处理引擎下发的平台消息。
  }

  void setMockMessageHandler(String channel, MessageHandler? handler) {
    // 生产环境不使用 mock handler。
  }

  bool checkMockMessageHandler(String channel, Object? handler) => false;
}
