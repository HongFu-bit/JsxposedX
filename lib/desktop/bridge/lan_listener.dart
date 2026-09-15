import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 电脑侧的 TCP 监听器。
///
/// **只管 socket，不懂协议**（文档 §10.3 的职责边界）：绑定、端口回退、接受连接。
/// 握手、校验、令牌下发全在 [RemoteBridgeClient] 里。
///
/// 关于"一次只接受一条连接"：这是刻意的简化，也是这里唯一的资源限制。
/// 校验通过之前，服务端并不知道对端是谁，所以任何人都能连上来；
/// 如果同时接受多条，未认证的连接就会互相争抢资源。改成串行的之后，
/// 任意时刻最多只有一条"尚未完成校验"的连接，攻击者能造成的最大影响是
/// **每次占用一个握手指令超时的时长**——而且他不会因此获得任何数据，
/// 因为校验通过前上层不会发出任何 Pigeon 调用（§7.2 的阶段机）。
///
/// 文档 §10.3 原来写的是"pending 集合（上限 3 条）+ 校验通过后才占槽位"，
/// 实现时收敛成了串行接受：两者的资源上界一样是常数，但串行版本少一整类并发状态，
/// 在这个规模下更不容易写错。
class LanListener {
  LanListener({
    this.preferredPort = 27183,
    this.maxPort = 27192,
  });

  /// 首选的监听端口，与 `adb forward` 用的端口一致，便于用户记忆。
  final int preferredPort;

  /// 端口回退上限。被占用时顺序尝试 `preferredPort..maxPort`。
  final int maxPort;

  ServerSocket? _server;

  int? _boundPort;

  bool _closed = false;

  /// 实际绑上的端口；未启动时为 null。
  ///
  /// **必须以这个值为准**，不要假定是 [preferredPort]——回退发生时
  /// 界面显示、连接文本、以及手机要输入的端口都得用它。
  int? get port => _boundPort;

  bool get isListening => _server != null && !_closed;

  /// 绑定端口。全部端口都被占用时抛 [SocketException]。
  Future<void> start() async {
    _closed = false;
    for (var candidate = preferredPort; candidate <= maxPort; candidate++) {
      try {
        _server = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          candidate,
          shared: false,
        );
        _boundPort = candidate;
        debugPrint('[lan] listening on 0.0.0.0:$candidate');
        return;
      } on SocketException catch (error) {
        debugPrint('[lan] 端口 $candidate 绑定失败：${error.message}');
      }
    }
    throw SocketException(
      '端口 $preferredPort-$maxPort 全部被占用，无法监听。',
    );
  }

  /// 接受一条连接；[close] 之后返回 null。
  ///
  /// 单次握手期间不会有第二条被接受——调用方只在处理完上一条之后才再次调用本方法。
  Future<Socket?> accept() async {
    final server = _server;
    if (server == null || _closed) {
      return null;
    }
    try {
      final socket = await server.accept();
      socket.setOption(SocketOption.tcpNoDelay, true);
      return socket;
    } on Object catch (error) {
      if (!_closed) {
        debugPrint('[lan] accept 失败：$error');
      }
      return null;
    }
  }

  /// 停止监听，并让阻塞中的 [accept] 尽快返回 null。
  ///
  /// 校验通过之后必须调用它：这是"暴露窗口只有几分钟"这个安全论证的前提
  /// （§9.2、§10.3 第 4 点）。
  Future<void> close() async {
    _closed = true;
    final server = _server;
    _server = null;
    _boundPort = null;
    if (server == null) {
      return;
    }
    try {
      await server.close();
    } on Object catch (error) {
      debugPrint('[lan] 关闭监听失败：$error');
    }
  }
}
