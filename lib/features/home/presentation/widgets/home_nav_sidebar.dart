import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/desktop/bridge/remote_bridge_client.dart';
import 'package:JsxposedX/features/home/presentation/widgets/home_bottom_bar.dart';
import 'package:flutter/material.dart';

/// 侧边栏底部的连接状态。
///
/// 只在"桌面端远程模式"下渲染（`NativeBridge.remoteClient` 为空时返回空 widget），
/// 因此手机端的界面上不会出现任何变化。
class DesktopBridgeStatus extends StatelessWidget {
  const DesktopBridgeStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final client = NativeBridge.remoteClient;
    if (client == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<BridgeConnectionPhase>(
      stream: client.phaseStream,
      initialData: client.phase,
      builder: (context, snapshot) {
        final phase = snapshot.data ?? BridgeConnectionPhase.disconnected;
        final colorScheme = context.colorScheme;

        late final IconData icon;
        late final Color color;
        late final String label;

        if (phase == BridgeConnectionPhase.connected) {
          icon = Icons.link_rounded;
          color = const Color(0xFF2E9E5B);
          label = client.device?.model ?? '已连接';
        } else if (phase == BridgeConnectionPhase.connecting ||
            phase == BridgeConnectionPhase.authenticating) {
          icon = Icons.sync_rounded;
          color = const Color(0xFFE08A00);
          label = '正在连接手机…';
        } else if (phase == BridgeConnectionPhase.rejected) {
          icon = Icons.link_off_rounded;
          color = colorScheme.error;
          label = '连接被拒绝';
        } else {
          icon = Icons.link_off_rounded;
          color = colorScheme.onSurface.withValues(alpha: 0.45);
          label = '未连接手机';
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (phase == BridgeConnectionPhase.connected &&
                        client.device != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        'Android ${client.device!.android} · App ${client.device!.appVersion}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 宽屏下的左侧导航栏，替换原来的底部导航栏 [HomeBottomBar]。
///
/// 与底部栏共用同一份 [HomeBottomNavItemData]，避免两处维护导航定义。
class HomeNavSidebar extends StatelessWidget {
  const HomeNavSidebar({
    super.key,
    required this.navItems,
    required this.currentIndex,
    required this.onTap,
    this.width = 208,
  });

  final List<HomeBottomNavItemData> navItems;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Container(
      width: width,
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
            child: Text(
              'JsxposedX',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: colorScheme.primary,
              ),
            ),
          ),
          for (int index = 0; index < navItems.length; index++)
            _SidebarItem(
              item: navItems[index],
              selected: currentIndex == index,
              onTap: () => onTap(index),
            ),
          const Spacer(),
          const DesktopBridgeStatus(),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final HomeBottomNavItemData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.62);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? colorScheme.primary.withValues(
                alpha: context.isDark ? 0.16 : 0.10,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? item.filledIcon : item.outlinedIcon,
                  size: 18,
                  color: foreground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
