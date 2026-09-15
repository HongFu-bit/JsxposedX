import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 电脑侧的 TCP 监听器。
///
/// **只管 socket，不懂协议**（文档 §10.3 的职责边界）：绑定、端口回退、接受连接。
/// 握手、校验、令牌下发全在 [RemoteBridgeClient] 里。
///
/// 关于"一次只交付一条连接"：这是刻意的简化，也是这里唯一的资源限制。
/// 校验通过之前服务端并不知道对端是谁，所以任何人都能连上来；如果同时交付多条，
/// 未认证的连接就会互相争抢资源。改成串行交付之后，任意时刻最多一条"尚未完成校验"
/// 的连接，攻击者能造成的最大影响是**每次占用一个握手指令超时的时长**——
/// 而且他不会因此获得任何数据，因为校验通过前上层不会发出任何 Pigeon 调用（§7.2）。
///
/// 文档 §10.3 原来写的是"pending 集合（上限 3 条）+ 校验通过后才占槽位"，
/// 实现时收敛成了这里的串行交付 + 队列上限 [maxQueued]：两者的资源上界同样是常数，
/// 但少了一整类并发状态，在这个规模下更不容易写错。
///
/// **实现注意**：`dart:io` 的 [ServerSocket] 是一个 `Stream<Socket>`，**没有 accept()**。
/// 而且它是单订阅流——`await server.first` 之后再听会抛 "Stream has already been
/// listened to"，所以这里必须持有一个常驻订阅，把到来的连接排进队列，
/// 由 [accept] 按需取用。
class LanListener {
  LanListener({
    this.preferredPort = 27183,
    this.maxPort = 27192,
    this.maxQueued = 3,
  });

  /// 首选的监听端口，与 `adb forward` 用的端口一致，便于用户记忆。
  final int preferredPort;

  /// 端口回退上限。被占用时顺序尝试 `preferredPort..maxPort`。
  final int maxPort;

  /// 队列上限。超出后新连接直接丢弃——防止有人在握手期间把连接堆满。
  final int maxQueued;

  ServerSocket? _server;

  StreamSubscription<Socket>? _subscription;

  final Queue<Socket> _queue = Queue<Socket>();

  /// 正在等连接的调用方；同一时刻至多一个（上层就是串行取用的）。
  Completer<Socket?>? _waiter;

  int? _boundPort;

  bool _closed = false;

  /// 实际绑上的端口；未启动时为 null。
  ///
  /// **必须以这个值为准**，不要假定是 [preferredPort]——回退发生时
  /// 界面显示、连接文本、以及手机要输入的端口都得用它。
  int? get port => _boundPort;

  bool get isListening => _server != null && !_closed;

  /// 绑定端口并开始接收。全部端口都被占用时抛 [SocketException]。
  Future<void> start() async {
    _closed = false;

    ServerSocket? bound;
    for (var candidate = preferredPort; candidate <= maxPort; candidate++) {
      try {
        bound = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          candidate,
          shared: false,
        );
        _boundPort = candidate;
        break;
      } on SocketException catch (error) {
        debugPrint('[lan] 端口 $candidate 绑定失败：${error.message}');
      }
    }
    if (bound == null) {
      throw SocketException('端口 $preferredPort-$maxPort 全部被占用，无法监听。');
    }

    _server = bound;
    debugPrint('[lan] listening on 0.0.0.0:$_boundPort');

    _subscription = bound.listen(
      _onSocket,
      onError: (Object error) {
        if (!_closed) {
          debugPrint('[lan] 监听流报错：$error');
        }
      },
      cancelOnError: false,
    );
  }

  /// 取一条连接；[close] 之后返回 null。
  ///
  /// 上层是串行使用的（处理完上一条才再调一次），所以这里的队列通常不会超过一条。
  Future<Socket?> accept() async {
    if (_closed) {
      return null;
    }
    if (_queue.isNotEmpty) {
      return _queue.removeFirst();
    }
    if (_waiter != null) {
      // 上层是串行取用的（处理完上一条才再调一次）。真出现并发调用说明有 bug，
      // 这里直接拒绝，而不是覆盖掉前一个 waiter 让它永远挂住。
      debugPrint('[lan] accept() 被并发调用，忽略这一次');
      return null;
    }

    final completer = Completer<Socket?>();
    _waiter = completer;
    return completer.future;
  }

  /// 停止监听，并让阻塞中的 [accept] 尽快返回 null。
  ///
  /// 校验通过之后必须调用它：这是"暴露窗口只有几分钟"这个安全论证的前提
  /// （§9.2、§10.3 第 4 点）。
  Future<void> close() async {
    _closed = true;

    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } on Object catch (error) {
        debugPrint('[lan] 取消监听订阅失败：$error');
      }
    }

    final server = _server;
    _server = null;
    _boundPort = null;
    if (server != null) {
      try {
        await server.close();
      } on Object catch (error) {
        debugPrint('[lan] 关闭监听失败：$error');
      }
    }

    // 队列里还没被取走的连接：直接丢掉，否则它们会一直占着 fd。
    while (_queue.isNotEmpty) {
      _destroy(_queue.removeFirst());
    }

    // 唤醒还在等的那一位，让它看到 null 并结束循环。
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(null);
    }
  }

  // -------------------------------------------------------------- 内部实现

  void _onSocket(Socket socket) {
    if (_closed) {
      _destroy(socket);
      return;
    }

    // 有人在等就直接交付，避免多绕一圈队列。
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } on Object catch (_) {
        // 非致命：部分平台可能不支持该选项
      }
      waiter.complete(socket);
      return;
    }

    // 队列满了就丢新的：宁可让攻击者连不上，也不要让连接堆积。
    if (_queue.length >= maxQueued) {
      debugPrint('[lan] 队列已满（$maxQueued），丢弃一条新连接');
      _destroy(socket);
      return;
    }

    _queue.add(socket);
  }

  static void _destroy(Socket socket) {
    try {
      socket.destroy();
    } on Object catch (_) {
      // 忽略关闭失败
    }
  }
}
