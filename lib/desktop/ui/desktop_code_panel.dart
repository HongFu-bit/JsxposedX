import 'package:JsxposedX/core/themes/app_colors.dart';
import 'package:JsxposedX/desktop/bridge/local_address.dart';
import 'package:JsxposedX/desktop/bridge/pairing_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 「Wi-Fi 直连」Tab 在等待状态下的主面板。
///
/// 界面上最关键的其实是**本机地址**那一行：不做自动发现，用户只能从这里把地址
/// 抄到手机上（文档 §10.2）。6 位码反而是次要的——它每 15 秒就换，只能现场看着输。
///
/// 三种非正常状态也在这个面板里表达（§9.2 / §9.3）：
/// 被来源限速、"有人尝试连接"的全局暂停、以及连不上时的排错提示。
class DesktopCodePanel extends StatelessWidget {
  const DesktopCodePanel({
    super.key,
    required this.lanAddress,
    required this.listenPort,
    required this.availableAddresses,
    required this.onSelectAddress,
    required this.pairingCode,
    required this.rotationRemaining,
    required this.pauseRemaining,
    required this.connectionLabel,
    required this.pairedPhoneCount,
    required this.onDisconnect,
    this.errorText,
  });

  /// 当前用于显示给用户的地址（可能是热点网卡那块）。
  final LanAddress? lanAddress;

  /// 实际监听的端口。**必须以它为准**，不要假定是 27183——
  /// 端口冲突时会顺序回退（§5.3），回退后的值才是手机要输的那个。
  final int? listenPort;

  final List<LanAddress> availableAddresses;

  final ValueChanged<LanAddress> onSelectAddress;

  final PairingCode pairingCode;

  final Duration rotationRemaining;

  final Duration pauseRemaining;

  /// 已连接时的文字，例如"已连接：Pixel 8 Pro · 已连接 3 分钟"。
  final String? connectionLabel;

  final int pairedPhoneCount;

  final VoidCallback onDisconnect;

  final String? errorText;

  bool get _isPaused => pairingCode.isPaused;

  @override
  Widget build(BuildContext context) {
    if (connectionLabel != null) {
      return _connected(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _addressBlock(context),
        const SizedBox(height: 22),
        if (errorText != null) ...<Widget>[
          _errorLine(context, errorText!),
          const SizedBox(height: 18),
        ],
        _isPaused ? _pausedBlock(context) : _codeBlock(context),
        const SizedBox(height: 18),
        _troubleshoot(context),
      ],
    );
  }

  // --------------------------------------------------------------- 地址

  Widget _addressBlock(BuildContext context) {
    final address = lanAddress;
    final port = listenPort;
    final text = (address == null || port == null)
        ? ''
        : '${address.address}:$port';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '把这个地址输入到手机上',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: text.isEmpty
                  ? const Text(
                      '未找到可用的本机地址',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    )
                  : SelectableText(
                      text,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
            ),
            IconButton(
              tooltip: '复制地址',
              onPressed: text.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('地址已复制')),
                        );
                      }
                    },
              icon: const Icon(Icons.copy_rounded, size: 20),
            ),
          ],
        ),
        if (availableAddresses.length > 1) ...<Widget>[
          const SizedBox(height: 4),
          _addressPicker(context),
        ],
      ],
    );
  }

  Widget _addressPicker(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.lan_outlined, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<LanAddress>(
              isDense: true,
              value: lanAddress,
              hint: const Text('选择网卡', style: TextStyle(fontSize: 12.5)),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              items: <DropdownMenuItem<LanAddress>>[
                for (final candidate in availableAddresses)
                  DropdownMenuItem<LanAddress>(
                    value: candidate,
                    child: Text(
                      candidate.toString(),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onSelectAddress(value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- 6 位码

  Widget _codeBlock(BuildContext context) {
    final seconds = rotationRemaining.inMilliseconds / 1000.0;
    final total = pairingCode.rotation.inMilliseconds / 1000.0;
    final progress = total <= 0 ? 0.0 : (seconds / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '在手机上输入这个校验码',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        SelectableText(
          PairingCode.format(pairingCode.current),
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: AppColors.textSecondary.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '每 15 秒换一次，抄下来或用别的方式搬走都是没用的——请对着屏幕输入。',
          style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 全局失败节流期间不显示码，改为暂停倒计时（§9.2 的边界行为）。
  Widget _pausedBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.pause_circle_filled_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                '已暂停 ${pauseRemaining.inSeconds} 秒',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '短时间内失败次数过多，可能是有人在尝试连接。暂停期间不接受校验码，'
            '到期会自动换一组新码。',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- 其他

  Widget _connected(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.link_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                connectionLabel!,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          // 连上之后端口就关了，这一条要讲明白，否则用户会以为还能再连一台。
          '连接期间电脑不再监听端口，6 位码也已失效。断开后才会重新开始等待。',
          style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: onDisconnect,
            child: const Text('断开'),
          ),
        ),
      ],
    );
  }

  Widget _errorLine(BuildContext context, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.error_outline,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _troubleshoot(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text(
        '手机连不上？',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      children: <Widget>[
        _hint(
          '① 地址选对了吗',
          '电脑有多块网卡时，选错网卡就是这个地址永远连不上。'
              '与你正在用的那块保持一致：说"和手机前三段相同"就是同一网段。',
        ),
        _hint(
          '② 电脑开热点时，要选热点那块网卡',
          '默认路由指向的是对外的网卡，不是热点那块。热点网卡的地址通常形如 192.168.137.1。',
        ),
        _hint(
          '③ Windows 防火墙要放行入站',
          '首次监听时系统会弹询问，必须点"允许访问"；'
              '并且要确认当前网络位置是"专用网络"——是"公用网络"的话入站会被默认拦掉。',
        ),
        _hint(
          '④ 路由器可能开了客户端隔离',
          '公司 / 酒店 Wi-Fi 常见。最省事的排查是改用热点组网（§14.1），'
              '它不经过第三方路由器，也没有同网段的陌生设备。',
        ),
        if (pairedPhoneCount > 0)
          _hint(
            '⑤ 已配对过的手机可以直接重连',
            '当前已经记住了 $pairedPhoneCount 台手机。'
                '它们会在 App 启动时自动重连，不需要再输入校验码——'
                '除非电脑的 IP 变了。',
          ),
      ],
    );
  }

  Widget _hint(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
