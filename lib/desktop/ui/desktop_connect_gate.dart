import 'dart:async';

import 'package:JsxposedX/common/widgets/app_bootstrap.dart';
import 'package:JsxposedX/core/themes/app_colors.dart';
import 'package:JsxposedX/core/themes/app_theme.dart';
import 'package:JsxposedX/desktop/bridge/adb_helper.dart';
import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';
import 'package:JsxposedX/desktop/bridge/lan_bridge_controller.dart';
import 'package:JsxposedX/desktop/bridge/remote_bridge_client.dart';
import 'package:JsxposedX/desktop/ui/desktop_code_panel.dart';
import 'package:flutter/material.dart';

/// 连接页上的两种模式。
enum _ConnectMode { usb, wifi }

/// 桌面端启动时的连接界面。
///
/// 主流程是"一键连接"：自动找 adb → 找设备 → 拉起手机上的 JsxposedX →
/// 建立端口转发 → 从 logcat 读令牌 → 连接。这样双击 exe 就能用，
/// 不需要仓库脚本，也不需要用户手抄令牌。
///
/// adb 找不到、或有多台设备时，可以展开"手动连接"自己填端口和令牌
/// （例如先用 `run_desktop_bridge.ps1 -SkipLaunch` 手工把转发和令牌准备好）。
///
/// 连接成功后由 DesktopApp 切换到与手机完全相同的 MainApp。
class DesktopConnectGate extends StatefulWidget {
  const DesktopConnectGate({
    super.key,
    required this.initialPort,
    required this.initialToken,
    required this.onConnect,
    this.autoConnect = false,
    this.lanController,
  });

  final int initialPort;

  final String initialToken;

  /// 由入口负责：必要时用新端口/令牌重建客户端，然后连接。
  final Future<void> Function(int port, String token) onConnect;

  /// 启动时自动尝试连接一次（脚本已注入端口与令牌时使用）。
  final bool autoConnect;

  /// Wi-Fi 直连的控制器。为 null 时只显示 USB 那一档
  /// （例如从 `-SkipLaunch` 之类只有 USB 参数的入口进来时）。
  final LanBridgeController? lanController;

  @override
  State<DesktopConnectGate> createState() => _DesktopConnectGateState();
}

class _DesktopConnectGateState extends State<DesktopConnectGate> {
  final AdbHelper _adb = AdbHelper();

  late final TextEditingController _portController;
  late final TextEditingController _tokenController;

  bool _busy = false;
  String? _step;
  String? _error;
  String? _errorHint;
  bool _showManual = false;

  /// 当前显示哪一档。默认 USB，保持改动前的行为不变。
  _ConnectMode _mode = _ConnectMode.usb;

  /// 用户是否手动切过档。切过之后就不再自动跳到 Wi-Fi 那一档。
  bool _modeTouched = false;

  LanSnapshot? _lanSnapshot;
  StreamSubscription<LanSnapshot>? _lanSubscription;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(
      text: widget.initialPort.toString(),
    );
    _tokenController = TextEditingController(text: widget.initialToken);
    _showManual = widget.initialToken.isNotEmpty;

    final lan = widget.lanController;
    if (lan != null) {
      _lanSnapshot = lan.snapshot;
      // 控制器可能在我订阅之前就已经开始等待了（autoResumeIfPaired 是异步的），
      // 那种情况下面这个流监听收不到那一次事件，所以这里先按当前快照判一次。
      if (_mode == _ConnectMode.usb && lan.snapshot.phase != LanPhase.idle) {
        _mode = _ConnectMode.wifi;
      }
      _lanSubscription = lan.stream.listen((snapshot) {
        if (!mounted) {
          return;
        }
        setState(() {
          _lanSnapshot = snapshot;
          // 桌面端在有配对记录时会自动开始等待（LanBridgeController.autoResumeIfPaired）。
          // 那种情况下端口已经开着、6 位码正在轮换，界面必须跟着跳过去，
          // 否则用户对着 USB 页面完全不知道发生了什么。
          if (!_modeTouched &&
              _mode == _ConnectMode.usb &&
              snapshot.phase != LanPhase.idle) {
            _mode = _ConnectMode.wifi;
          }
        });
      });
    }

    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connectViaAdb());
    }
  }

  @override
  void dispose() {
    unawaited(_lanSubscription?.cancel());
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  int? get _port {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      return null;
    }
    return port;
  }

  void _start() {
    setState(() {
      _busy = true;
      _step = null;
      _error = null;
      _errorHint = null;
    });
  }

  void _setStep(String step) {
    if (mounted) {
      setState(() => _step = step);
    }
  }

  void _finish() {
    if (mounted) {
      setState(() {
        _busy = false;
        _step = null;
      });
    }
  }

  void _fail(String message, String? hint) {
    if (mounted) {
      setState(() {
        _error = message;
        _errorHint = hint;
      });
    }
  }

  /// adb 的原始报错是英文诊断信息，统一加一层双语说明再展示。
  void _failWith(Object error) {
    if (error is AdbException) {
      _fail(
        error.technical
            ? '${_t('adb 执行失败：', 'adb failed: ')}${error.message}'
            : error.message,
        error.hint,
      );
      return;
    }
    if (error is BridgeException) {
      _fail(error.message, null);
      return;
    }
    _fail(error.toString(), null);
  }

  // ------------------------------------------------------------ 一键连接

  Future<void> _connectViaAdb() async {
    if (_busy) {
      return;
    }
    final port = _port;
    if (port == null) {
      _fail(_t('端口必须是数字（1-65535）。', 'Port must be a number (1-65535).'), null);
      return;
    }

    _start();
    try {
      _setStep(_t('正在查找 adb…', 'Looking for adb…'));
      if (!await _adb.resolveAdb()) {
        throw AdbException(
          _t('未找到 adb。', 'adb not found.'),
          hint: _t(
            '把 Android SDK 的 platform-tools 目录放到 exe 同级的 platform-tools 下，'
                '或把 adb 加入系统 PATH。',
            'Put the Android SDK platform-tools folder next to the exe as "platform-tools", '
                'or add adb to PATH.',
          ),
        );
      }

      _setStep(_t('正在查找手机…', 'Looking for the phone…'));
      final serial = await _requireSingleDevice();

      _setStep(_t('正在启动手机上的 JsxposedX…', 'Opening JsxposedX on the phone…'));
      try {
        await _adb.startPhoneApp(serial: serial);
      } on AdbException catch (error) {
        throw AdbException(
          _t(
            '无法启动手机上的 JsxposedX，请确认手机已安装该应用。',
            'Could not start JsxposedX on the phone — is it installed?',
          ),
          hint: error.message,
        );
      }

      _setStep(_t('正在建立 USB 端口转发…', 'Setting up the USB port forward…'));
      await _adb.forward(port: port, serial: serial);

      _setStep(_t('正在读取连接令牌…', 'Reading the connection token…'));
      var token = await _adb.waitForToken(serial: serial, attempts: 6);
      if (token == null) {
        // 令牌是 bridge 服务启动时打印的。App 早就在运行、logcat 又已经翻过页时读不到，
        // 这时冷启动一次手机上的 App，让它重新生成并打印令牌。
        _setStep(
          _t(
            '正在重启手机上的 JsxposedX 以重新生成令牌…',
            'Restarting JsxposedX on the phone to get a fresh token…',
          ),
        );
        await _adb.forceStopPhoneApp(serial: serial);
        await _adb.startPhoneApp(serial: serial);
        token = await _adb.waitForToken(serial: serial);
      }
      if (token == null) {
        throw AdbException(
          _t('没有读到连接令牌。', 'Could not read the connection token.'),
          hint: _t(
            '确认手机上的 JsxposedX 能正常启动；也可以展开下面"手动连接"，'
                '用 adb logcat -d -s JsxposedX-DesktopBridge 自己读令牌。',
            'Make sure JsxposedX starts on the phone; you can also read the token yourself with '
                'adb logcat -d -s JsxposedX-DesktopBridge and use manual connect.',
          ),
        );
      }
      _tokenController.text = token;

      _setStep(_t('正在连接…', 'Connecting…'));
      await widget.onConnect(port, token);
    } catch (error) {
      _failWith(error);
    } finally {
      _finish();
    }
  }

  /// 返回唯一一台就绪设备的序列号。
  Future<String> _requireSingleDevice() async {
    final devices = await _adb.listDevices();
    if (devices.isEmpty) {
      throw AdbException(
        _t('没有检测到设备。', 'No device detected.'),
        hint: _t(
          '用 USB 连接手机、在开发者选项里打开 USB 调试，并在手机弹出的授权框里点"允许"。',
          'Connect the phone over USB, enable USB debugging, and accept the authorization '
              'prompt on the phone.',
        ),
      );
    }

    final ready = devices.where((device) => device.isReady).toList();
    if (ready.isEmpty) {
      final first = devices.first;
      if (first.state == 'unauthorized') {
        throw AdbException(
          _t('手机还没有授权本机调试。', 'The phone has not authorized this computer.'),
          hint: _t(
            '在手机上确认"允许 USB 调试"弹窗；如果没看到弹窗，拔插一次数据线。',
            'Accept the "Allow USB debugging" prompt on the phone; if it does not appear, '
                're-plug the cable.',
          ),
        );
      }
      if (first.state == 'offline') {
        throw AdbException(
          _t('设备处于 offline 状态。', 'The device is offline.'),
          hint: _t(
            '拔插一次数据线，或在命令行执行 adb kill-server 后重试。',
            'Re-plug the cable, or run "adb kill-server" and retry.',
          ),
        );
      }
      throw AdbException(
        _t('设备状态异常：${first.state}', 'Device state: ${first.state}'),
        hint: _t('拔插一次数据线后重试。', 'Re-plug the cable and retry.'),
      );
    }

    if (ready.length > 1) {
      throw AdbException(
        _t(
          '检测到多台设备：${ready.map((d) => d.serial).join('、')}',
          'Multiple devices: ${ready.map((d) => d.serial).join(', ')}',
        ),
        hint: _t(
          '只保留一台设备再重试，或展开下面的"手动连接"。',
          'Leave a single device connected and retry, or use manual connect below.',
        ),
      );
    }

    return ready.first.serial;
  }

  // ------------------------------------------------------------ 手动连接

  Future<void> _connectManually() async {
    if (_busy) {
      return;
    }
    final port = _port;
    if (port == null) {
      _fail(_t('端口必须是数字（1-65535）。', 'Port must be a number (1-65535).'), null);
      return;
    }

    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _fail(
        _t('需要填写连接令牌。', 'A connection token is required.'),
        _t(
          '运行 .buildScript/run_desktop_bridge.ps1 会自动填好，'
              '或执行 adb logcat -d -s ${_logTagForHint} 自己读。',
          'Running .buildScript/run_desktop_bridge.ps1 fills this in, or read it yourself '
              'with adb logcat -d -s ${_logTagForHint}.',
        ),
      );
      return;
    }

    _start();
    try {
      _setStep(_t('正在连接…', 'Connecting…'));
      await widget.onConnect(port, token);
    } catch (error) {
      _failWith(error);
    } finally {
      _finish();
    }
  }

  static const String _logTagForHint = 'JsxposedX-DesktopBridge';

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final lan = widget.lanController;
    return MaterialApp(
      title: 'JsxposedX Desktop',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppBootstrap.localizationsDelegates,
      supportedLocales: AppBootstrap.supportedLocales,
      locale: _resolvedLocale,
      theme: AppTheme.lightTheme(AppColors.primary),
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _wordmark(context),
                  const SizedBox(height: 20),
                  if (lan != null) ...<Widget>[
                    _modeSwitcher(),
                    const SizedBox(height: 20),
                  ],
                  if (lan == null || _mode == _ConnectMode.usb)
                    ..._usbPane(context)
                  else
                    ..._lanPane(context, lan),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// USB 那一档的内容——与改造前逐字一致，一行没动。
  List<Widget> _usbPane(BuildContext context) => <Widget>[
        _connectButton(),
        const SizedBox(height: 18),
        _statusArea(context),
        const SizedBox(height: 22),
        _manualSection(context),
      ];

  Widget _modeSwitcher() {
    return SegmentedButton<_ConnectMode>(
      segments: const <ButtonSegment<_ConnectMode>>[
        ButtonSegment<_ConnectMode>(
          value: _ConnectMode.usb,
          icon: Icon(Icons.usb_rounded, size: 16),
          label: Text('USB 连接'),
        ),
        ButtonSegment<_ConnectMode>(
          value: _ConnectMode.wifi,
          icon: Icon(Icons.wifi_tethering_rounded, size: 16),
          label: Text('Wi-Fi 直连'),
        ),
      ],
      selected: <_ConnectMode>{_mode},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll<TextStyle>(TextStyle(fontSize: 12.5)),
      ),
      onSelectionChanged: (selection) {
        final next = selection.first;
        if (next == _mode) {
          return;
        }
        setState(() {
          _mode = next;
          // 用户既然手动切过，就别再自动跳档了。
          _modeTouched = true;
        });
        // 切走时把等待停掉：电脑只在"等待连接"期间监听，
        // 让用户在别的页面上还开着端口是不必要的暴露（§7.5）。
        if (next == _ConnectMode.usb) {
          unawaited(widget.lanController?.stopWaiting());
        }
      },
    );
  }

  // ------------------------------------------------------------ Wi-Fi 直连

  List<Widget> _lanPane(BuildContext context, LanBridgeController lan) {
    final snapshot = _lanSnapshot ?? lan.snapshot;

    if (snapshot.phase == LanPhase.idle || snapshot.phase == LanPhase.failed) {
      return <Widget>[
        _lanIntro(context, snapshot),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => unawaited(lan.startWaiting()),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(_t('开始等待手机连接', 'Start waiting for the phone')),
        ),
        const SizedBox(height: 22),
        _pairedPhones(context, lan, snapshot),
      ];
    }

    return <Widget>[
      DesktopCodePanel(
        lanAddress: snapshot.address,
        listenPort: snapshot.listenPort,
        availableAddresses: snapshot.addresses,
        onSelectAddress: (address) => unawaited(lan.selectAddress(address)),
        pairingCode: lan.pairingCode,
        rotationRemaining: snapshot.rotationRemaining,
        pauseRemaining: snapshot.pauseRemaining,
        connectionLabel: snapshot.isConnected
            ? '已连接：${snapshot.device?.model ?? '手机'}'
            : null,
        pairedPhoneCount: snapshot.pairedCount,
        // 用 disconnectPhone 而不是 stopWaiting：面板上写着"断开后才会重新开始等待"，
        // 所以断开之后要立刻重新 bind、换一组新码，等下一次配对。
        onDisconnect: () => unawaited(lan.disconnectPhone()),
        errorText: snapshot.error,
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => unawaited(lan.stopWaiting()),
          child: Text(_t('停止等待', 'Stop waiting')),
        ),
      ),
      const SizedBox(height: 10),
      _pairedPhones(context, lan, snapshot),
    ];
  }

  Widget _lanIntro(BuildContext context, LanSnapshot snapshot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '电脑只在这段时间里监听端口，并把地址显示出来供你抄到手机上。'
          '手机需要在同一 Wi-Fi（或同一热点）下。',
          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
        ),
        if (snapshot.phase == LanPhase.failed && snapshot.error != null) ...<Widget>[
          const SizedBox(height: 12),
          _statusLine(
            icon: Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            text: snapshot.error!,
          ),
        ],
      ],
    );
  }

  Widget _pairedPhones(
    BuildContext context,
    LanBridgeController lan,
    LanSnapshot snapshot,
  ) {
    final phones = lan.phoneStore.phones;
    if (phones.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          '已配对的手机',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          '这些手机会用保存的会话令牌自动重连，不再需要输入校验码；'
          '移除某一条就等于吊销它的令牌。',
          style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final phone in phones)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    phone.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(lan.removePhone(phone.deviceId)),
                  child: Text(_t('移除', 'Remove')),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => unawaited(lan.clearPhones()),
            child: Text(_t('全部移除', 'Remove all')),
          ),
        ),
      ],
    );
  }

  Widget _wordmark(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'JsxposedX',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.lanController == null
              ? _t(
                  '通过 USB 连接手机，界面与功能与手机端保持一致。',
                  'Connect to your phone over USB. Same features as the phone app.',
                )
              : _t(
                  '两条路可选：USB（需要 adb）或 Wi-Fi 直连（同一局域网，不需要 adb）。',
                  'Two ways in: USB (needs adb) or Wi-Fi direct (same LAN, no adb).',
                ),
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _connectButton() {
    return FilledButton(
      onPressed: _busy ? null : _connectViaAdb,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(_t('连接手机', 'Connect to phone')),
    );
  }

  Widget _statusArea(BuildContext context) {
    if (_busy) {
      return _statusLine(
        icon: Icons.sync,
        color: AppColors.textSecondary,
        text: _step ?? _t('正在处理…', 'Working…'),
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _statusLine(
            icon: Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            text: _error!,
          ),
          if (_errorHint != null) ...<Widget>[
            const SizedBox(height: 10),
            _statusLine(
              icon: Icons.help_outline,
              color: AppColors.textSecondary,
              text: _errorHint!,
            ),
          ],
        ],
      );
    }

    return _statusLine(
      icon: Icons.usb,
      color: AppColors.textSecondary,
      text: _t(
        '点上面的按钮即可：自动查找 adb、拉起手机上的 JsxposedX、建立端口转发并读取令牌。',
        'Press the button above: it finds adb, opens JsxposedX on the phone, sets up the '
            'port forward, and reads the token.',
      ),
    );
  }

  Widget _manualSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() => _showManual = !_showManual),
            icon: Icon(
              _showManual ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              _t('手动连接', 'Manual connect'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        if (_showManual) ...<Widget>[
          const SizedBox(height: 4),
          _field(
            controller: _portController,
            label: _t('转发端口', 'Forwarded port'),
            hint: '${BridgeProtocol.defaultPort}',
          ),
          const SizedBox(height: 14),
          _field(
            controller: _tokenController,
            label: _t('连接令牌', 'Connection token'),
            hint: _t('由手机生成', 'Generated on the phone'),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _busy ? null : _connectManually,
              child: Text(_t('用这组参数连接', 'Connect with these values')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !_busy,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusLine({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: color),
          ),
        ),
      ],
    );
  }

  /// 连接页位于 MaterialApp 的 Localizations 树**之上**，不能用 `Localizations.localeOf`
  /// （那个 context 里找不到 Localizations 祖先，会直接抛错），因此直接读平台语言。
  bool get _isChinese =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';

  Locale get _resolvedLocale =>
      _isChinese ? const Locale('zh', 'CN') : const Locale('en', 'US');

  String _t(String zh, String en) => _isChinese ? zh : en;
}
