import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/beauty_button.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/app_info.dart';
import 'package:JsxposedX/core/providers/status_management_provider.dart';
import 'package:JsxposedX/core/routes/routes/home_route.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProjectMenuSheet extends HookConsumerWidget {
  final AppInfo app;

  const ProjectMenuSheet({super.key, required this.app});

  static void show(BuildContext context, {required AppInfo app}) {
    AppBottomSheet.show(
      context: context,
      title: context.l10n.project,
      child: ProjectMenuSheet(app: app),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHookAsync = ref.watch(isHookProvider);

    final isHooked = isHookAsync.value ?? false;

    final menuItems = [
      _MenuData(
        icon: Icons.electric_bolt_rounded,
        label: context.l10n.quickFunctions,
        color: Colors.amber,
        onTap: () {
          final isHook = ref.read(isHookProvider).value ?? false;
          if (!isHook) {
            ToastMessage.show(context.l10n.pleaseActivateXposed);
            return;
          }
          context.push(
            HomeRoute.toQuickFunctions(app: app),
            extra: app,
          );
        },
      ),
      _MenuData(
        icon: Icons.auto_awesome_rounded,
        label: context.l10n.aiReverse,
        color: Colors.deepPurpleAccent,
        onTap: () {
          final isHook = ref.read(isHookProvider).value ?? false;
          if (!isHook) {
            ToastMessage.show(context.l10n.pleaseActivateXposed);
            return;
          }
          // if (!hasAi) {
          //   ToastMessage.show(context.l10n.aiNotActivated);
          //   return;
          // }
          context.push(HomeRoute.toAiReverse(packageName: app.packageName));
        },
      ),
      _MenuData(
        icon: Icons.terminal_rounded,
        label: context.l10n.xposedProject,
        color: Colors.indigo,
        onTap: () {
          if (!isHooked) {
            ToastMessage.show(context.l10n.pleaseActivateXposed);
            return;
          }
          context.push(HomeRoute.toXposedProject(packageName: app.packageName));
        },
      ),
      _MenuData(
        icon: Icons.bug_report_rounded,
        label: context.l10n.fridaProject,
        color: Colors.blueGrey,
        onTap: () {
          Future.microtask(() async {
            final installed = await NativeBridge.zygiskFrida.isModuleInstalled();
            if (!context.mounted) return;
            if (!installed) {
              ToastMessage.show(context.l10n.zygiskFridaModuleNotInstalled);
              return;
            }
            context.push(HomeRoute.toFridaProject(packageName: app.packageName));
          });
        },
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10.h,
        crossAxisSpacing: 10.w,
        mainAxisExtent: 90.h,
      ),
      itemCount: menuItems.length,
      itemBuilder: (context, index) {
        final item = menuItems[index];
        return BeautyButton(
          icon: item.icon,
          label: item.label,
          color: item.color,
          onTap: item.onTap,
        );
      },
    );
  }
}

class _MenuData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  _MenuData({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}
