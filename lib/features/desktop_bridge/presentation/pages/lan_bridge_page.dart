import 'dart:async';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/utils/bridge_link_text.dart';
import 'package:JsxposedX/features/desktop_bridge/data/datasources/lan_bridge_datasource.dart';
import 'package:JsxposedX/generated/lan_bridge.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 手机端「局域网直连」页。
///
/// 分工与电脑端严格对应（docs/desktop_bridge_lan_CN.md §10.2）：
///
/// - **地址**：稳定、可以提前传。输入框接受电脑端复制出来的**一整行**
///   （`192.168.1.9:27183 校验码 123456`），解析出地址与码。
/// - **6 位码**：每 15 秒就过期，**只能现场看着电脑屏幕输入**。
///   行内带的那个码只有在"复制后几秒内就能粘贴"（有剪贴板同步）时才用得上。
///
/// 页面靠轮询刷新：被拒绝的原因（`code` / `code-stale` / `locked`）是电脑发来的
/// 原生帧，Dart 侧看不到，只能通过 [LanBridgeStatus] 读回（§8.4、§9.3）。
class LanBridgePage extends StatefulWidget {
  const LanBridgePage({super.key});

  @override
  State<LanBridgePage> createState() => _LanBridgePageState();
}

class _LanBridgePageState extends State<LanBridgePage> {
  static const LanBridgeDatasource _datasource = LanBridgeDatasource();

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  Timer? _ticker;
  LanBridgeStatus? _status;
  List<LanPairedPc> _paired = const <LanPairedPc>[];

  @override
  void initState() {
    super.initState();
    _refresh();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await _datasource.status();
      final paired = await _datasource.pairedPcs();
      if (mounted) {
        setState(() {
          _status = status;
          _paired = paired;
          // 已配对且当前没有拨号目标时，把地址预填上，用户只需要输码。
          if (_addressController.text.isEmpty && paired.isNotEmpty) {
            _addressController.text = '${paired.first.host}:${paired.first.port}';
          }
        });
      }
    } on Object catch (error) {
      // 原生侧不可用时不要打断页面——例如桌面端连上后读的是手机那份状态。
      debugPrint('[lan] 读取状态失败：$error');
    }
  }

  // ------------------------------------------------------------ 输入与连接

  /// 地址输入框：支持直接粘贴电脑端复制出来的整行文本。
  void _applyAddressInput(String raw) {
    final result = BridgeLinkText.parse(raw);
    switch (result) {
      case BridgeLinkOk(:final host, :final port, :final code):
        _addressController.text = '$host:$port';
        if (code != null && _codeController.text.isEmpty) {
          // 行内带了码就填上；它可能已经过期，所以不做新鲜度判断——
          // 交给电脑按 §9.3 给出准确原因（`code` 还是 `code-stale`）。
          _codeController.text = code;
        }
      case BridgeLinkInvalid(:final message):
        ToastMessage.show(message);
    }
  }

  Future<void> _connect() async {
    final parsed = BridgeLinkText.parse(_addressController.text.trim());
    if (parsed is! BridgeLinkOk) {
      ToastMessage.show(
        parsed is BridgeLinkInvalid ? parsed.message : '地址格式不对。',
      );
      return;
    }

    final code = BridgeLinkText.normalizeCode(_codeController.text);
    if (code == null) {
      ToastMessage.show('请输入电脑屏幕上的 6 位校验码。');
      return;
    }

    final status = _status;
    if (status != null && status.usbConnected) {
      ToastMessage.show('USB 那条还连着，先断开再走 Wi-Fi。');
      return;
    }

    await _datasource.connectWithCode(
      host: parsed.host,
      port: parsed.port,
      code: code,
    );
    await _refresh();
  }

  Future<void> _reconnect(LanPairedPc pc) async {
    await _datasource.reconnectTo(host: pc.host, port: pc.port);
    await _refresh();
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.isZh ? '局域网直连' : 'Wi-Fi direct'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 32.h),
        children: <Widget>[
          _connectionCard(context, status),
          SizedBox(height: 16.h),
          if (status == null || !status.lanConnected) ...<Widget>[
            _connectCard(context),
            SizedBox(height: 16.h),
          ],
          if (_paired.isNotEmpty) ...<Widget>[
            _pairedCard(context),
            SizedBox(height: 16.h),
          ],
          _autoReconnectCard(context, status),
          SizedBox(height: 12.h),
          _riskNote(context),
        ],
      ),
    );
  }

  Widget _connectionCard(BuildContext context, LanBridgeStatus? status) {
    final peer = status?.peerName;
    final connected = status?.lanConnected ?? false;
    final busy = (status?.hasTarget ?? false) && !connected;

    final String title;
    if (connected) {
      title = '已连接到 ${peer ?? '电脑'}';
    } else if (busy) {
      title = context.isZh ? '正在连接…' : 'Connecting…';
    } else {
      title = context.isZh ? '未连接' : 'Not connected';
    }

    final subtitle = _rejectText(status) ??
        (connected
            ? (context.isZh
                ? '界面与操作会和电脑端保持一致。'
                : 'The desktop app drives this session.')
            : (context.isZh
                ? '在电脑上打开等待页，把地址和 6 位码填到下面。'
                : 'Open the waiting page on your computer first.'));

    return Card(
      child: ListTile(
        leading: Icon(
          connected ? Icons.link_rounded : Icons.link_off_rounded,
          color: connected ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: connected || busy
            ? TextButton(
                onPressed: () async {
                  await _datasource.disconnect();
                  await _refresh();
                },
                child: Text(context.isZh ? '断开' : 'Disconnect'),
              )
            : null,
      ),
    );
  }

  /// 把电脑发来的错误码翻译成人话（§9.3）。
  ///
  /// 优先用电脑给的 `message`：它比这里更清楚当前是哪种情形
  /// （例如同样一个 `locked`，来源限速和全局暂停的提示就不一样）。
  String? _rejectText(LanBridgeStatus? status) {
    final code = status?.lastRejectCode;
    if (code == null) {
      return null;
    }
    final message = status?.lastRejectMessage;
    if (message != null && message.isNotEmpty) {
      return message;
    }
    switch (code) {
      case 'code':
        return context.isZh ? '校验码不正确，请重新输入。' : 'Wrong code.';
      case 'code-stale':
        return context.isZh
            ? '校验码刚刚刷新，请输入屏幕上新的 6 位数字。'
            : 'The code just rotated — read the new one.';
      case 'locked':
        return context.isZh ? '尝试次数过多，请稍后再试。' : 'Too many attempts.';
      case 'busy':
        return context.isZh ? '电脑上已经有手机连着。' : 'A phone is already connected.';
      default:
        return null;
    }
  }

  Widget _connectCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.isZh ? '电脑地址' : 'Computer address',
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6.h),
            TextField(
              controller: _addressController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                isDense: true,
                hintText: '192.168.1.9:27183',
                suffixIcon: IconButton(
                  tooltip: context.isZh ? '粘贴' : 'Paste',
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text;
                    if (text != null && text.isNotEmpty) {
                      _applyAddressInput(text);
                    }
                  },
                ),
              ),
              onSubmitted: _applyAddressInput,
            ),
            SizedBox(height: 6.h),
            Text(
              context.isZh
                  ? '可以直接粘贴电脑上复制的那一整行，会自动拆出地址。'
                  : 'You can paste the whole copied line.',
              style: TextStyle(fontSize: 11.5.sp, color: Colors.grey),
            ),
            SizedBox(height: 14.h),
            Text(
              context.isZh ? '校验码' : 'Pairing code',
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6.h),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: TextStyle(fontSize: 20.sp, letterSpacing: 4),
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                hintText: '123456',
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              context.isZh
                  ? '每 15 秒换一次，请对着电脑屏幕输入，不要照抄下来的数字。'
                  : 'Rotates every 15s — type it while looking at the screen.',
              style: TextStyle(fontSize: 11.5.sp, color: Colors.grey),
            ),
            SizedBox(height: 14.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _connect,
                child: Text(context.isZh ? '连接' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pairedCard(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(14.w, 14.w, 14.w, 4.h),
            child: Text(
              context.isZh ? '已配对的电脑' : 'Paired computers',
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
            ),
          ),
          for (final pc in _paired)
            ListTile(
              dense: true,
              leading: const Icon(Icons.desktop_windows_rounded, size: 20),
              title: Text(pc.name.isEmpty ? '${pc.host}:${pc.port}' : pc.name),
              subtitle: Text('${pc.host}:${pc.port}'),
              onTap: () => _reconnect(pc),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: () async {
                  await _datasource.forgetPc(host: pc.host, port: pc.port);
                  await _refresh();
                },
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: 8.w, bottom: 6.h),
              child: TextButton(
                onPressed: () async {
                  await _datasource.forgetAllPcs();
                  await _refresh();
                },
                child: Text(context.isZh ? '全部忘记' : 'Forget all'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoReconnectCard(BuildContext context, LanBridgeStatus? status) {
    return Card(
      child: SwitchListTile(
        value: status?.autoReconnect ?? true,
        onChanged: (value) async {
          await _datasource.setAutoReconnect(value);
          await _refresh();
        },
        title: Text(context.isZh ? '自动重连' : 'Auto reconnect'),
        subtitle: Text(
          context.isZh
              ? '打开 App 时自动连回最近那台电脑，不需要再输校验码。'
              : 'Reconnect to the last computer on launch.',
        ),
      ),
    );
  }

  Widget _riskNote(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            context.isZh
                ? '隧道内容是明文传输的，同一 Wi-Fi 下的其他设备可能抓包看到。'
                    '建议只在可信任的家庭或办公网络使用，公共 Wi-Fi 请改用 USB。'
                : 'The tunnel is plaintext. Use it only on a network you trust.',
            style: TextStyle(fontSize: 11.5.sp, height: 1.5, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}
