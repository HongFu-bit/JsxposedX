import 'dart:convert';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/custom_dIalog.dart';
import 'package:JsxposedX/common/widgets/custom_text_field.dart';
import 'package:JsxposedX/common/widgets/loading.dart';
import 'package:JsxposedX/common/widgets/ref_error.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/layout/two_pane_layout.dart';
import 'package:JsxposedX/core/providers/status_management_provider.dart';
import 'package:JsxposedX/core/routes/routes/home_route.dart';
import 'package:JsxposedX/core/utils/file_picker_util.dart';
import 'package:JsxposedX/core/utils/path_utils.dart';
import 'package:JsxposedX/features/frida/presentation/pages/frida_editor_page.dart';
import 'package:JsxposedX/features/frida/presentation/providers/frida_action_provider.dart';
import 'package:JsxposedX/features/frida/presentation/providers/frida_query_provider.dart';
import 'package:JsxposedX/generated/status_management.g.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FridaProjectPage extends HookConsumerWidget {
  final String packageName;

  const FridaProjectPage({super.key, required this.packageName});

  void _handleImportScript(BuildContext context, WidgetRef ref) {
    FilePickerUtil.pickMultipleFiles(
      type: FileType.custom,
      allowedExtensions: ["js"],
    ).then((pickFileDatas) async {
      if (pickFileDatas.isNotEmpty) {
        for (final file in pickFileDatas) {
          final content = utf8.decode(file.bytes);
          await ref.read(
            createFridaScriptProvider(
              packageName: packageName,
              localPath: file.fileName,
              content: content,
            ).future,
          );
        }
        ref.invalidate(fridaScriptsProvider(packageName: packageName));
      }
    });
  }

  Future<void> _handleToggle(
    WidgetRef ref,
    String scriptPath,
    bool enabled,
  ) async {
    await ref.read(
      setFridaScriptStatusProvider(
        packageName: packageName,
        localPath: scriptPath,
        enabled: enabled,
      ).future,
    );
    await ref.read(bundleFridaHookJsProvider(packageName: packageName).future);
    ref.invalidate(
      getFridaScriptStatusProvider(
        packageName: packageName,
        localPath: scriptPath,
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    String scriptPath,
  ) {
    CustomDialog.show(
      title: Text(context.l10n.confirmDelete),
      child: const SizedBox(),
      actionButtons: [
        ElevatedButton(
          onPressed: () async {
            await ref.read(
              deleteFridaScriptProvider(
                packageName: packageName,
                localPath: scriptPath,
              ).future,
            );
            await ref.read(
              bundleFridaHookJsProvider(packageName: packageName).future,
            );
            ref.invalidate(fridaScriptsProvider(packageName: packageName));
            SmartDialog.dismiss();
          },
          child: Text(context.l10n.confirm),
        ),
        ElevatedButton(
          onPressed: () => SmartDialog.dismiss(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }

  void _showCreateScriptDialog(BuildContext context, WidgetRef ref) {
    AppBottomSheet.show(
      context: context,
      title: context.l10n.newProject,
      child: _CreateFridaScriptDialog(
        packageName: packageName,
        onCreated: () {
          ref.invalidate(fridaScriptsProvider(packageName: packageName));
        },
      ),
    );
  }

  bool _isFridaModuleReady(FridaStatusData fridaStatus) {
    return fridaStatus.status && fridaStatus.type == 1;
  }

  String _buildFridaTargetSubtitle({
    required BuildContext context,
    required FridaStatusData fridaStatus,
    required bool targetEnabled,
  }) {
    return switch (fridaStatus.type) {
      1 => targetEnabled
          ? context.l10n.fridaStatusEnabled
          : context.l10n.fridaStatusDisabled,
      0 => context.l10n.fridaInitAbnormal,
      -1 => context.l10n.fridaNotInstalledShort,
      _ => context.l10n.fridaUnknown,
    };
  }

  Widget _buildStatusChip({required String label, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.sp,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<Widget> _buildScriptStateChips({
    required BuildContext context,
    required bool enabled,
    required bool moduleReady,
    required bool targetEnabled,
  }) {
    final chips = <Widget>[
      _buildStatusChip(label: 'frida', color: Colors.orange),
    ];

    if (!enabled) {
      return chips;
    }

    if (!moduleReady) {
      chips.add(
        _buildStatusChip(
          label: context.l10n.fridaInitAbnormal,
          color: Colors.redAccent,
        ),
      );
      return chips;
    }

    if (!targetEnabled) {
      chips.add(
        _buildStatusChip(
          label: context.l10n.fridaTargetDisabled,
          color: Colors.amber,
        ),
      );
      return chips;
    }

    chips.add(
      _buildStatusChip(label: context.l10n.fridaEffective, color: Colors.green),
    );
    return chips;
  }

  Widget _buildTargetTile(
    BuildContext context, {
    required bool enabled,
    required String subtitle,
    required ValueChanged<bool>? onChanged,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 4.h),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.1),
          child: Icon(
            Icons.power_settings_new_rounded,
            color: Colors.orange,
            size: 20.r,
          ),
        ),
        title: Text(
          'Frida Target Switch',
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle, style: context.textTheme.bodySmall),
        trailing: Transform.scale(
          scale: 0.85,
          child: Switch(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: Colors.orange,
            activeTrackColor: Colors.orange.withValues(alpha: 0.2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  /// 宽屏双栏右侧的脚本编辑器。
  ///
  /// 编辑器页面是构造函数传参、不依赖路由状态，可以原样内嵌；
  /// key 跟随脚本路径变化，避免切换脚本时复用上一个编辑器的内部状态。
  Widget _buildEditorPane(String scriptPath) {
    return FridaEditorPage(
      key: ValueKey<String>(scriptPath),
      packageName: packageName,
      path: scriptPath,
    );
  }

  Widget _buildScriptTile(
    BuildContext context,
    WidgetRef ref, {
    required String scriptPath,
    required String name,
    required bool enabled,
    required bool moduleReady,
    required bool targetEnabled,
    VoidCallback? onOpenScript,
  }) {
    return ListTile(
      onTap:
          onOpenScript ??
          () {
            context.push(
              HomeRoute.toFridaEditor(packageName: packageName),
              extra: scriptPath,
            );
          },
      onLongPress: () => _showDeleteDialog(context, ref, scriptPath),
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 2.h),
      leading: CircleAvatar(
        backgroundColor: Colors.orange.withValues(alpha: 0.1),
        child: Icon(Icons.bug_report, color: Colors.orange, size: 20.r),
      ),
      title: Text(
        name,
        style: context.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Wrap(
        spacing: 6.w,
        runSpacing: 4.h,
        children: _buildScriptStateChips(
          context: context,
          enabled: enabled,
          moduleReady: moduleReady,
          targetEnabled: targetEnabled,
        ),
      ),
      trailing: Transform.scale(
        scale: 0.8,
        child: Switch(
          value: enabled,
          onChanged: moduleReady && targetEnabled
              ? (value) async {
                  await _handleToggle(ref, scriptPath, value);
                }
              : null,
          activeThumbColor: Colors.orange,
          activeTrackColor: Colors.orange.withValues(alpha: 0.2),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scriptsAsync = ref.watch(
      fridaScriptsProvider(packageName: packageName),
    );
    final fridaStatusAsync = ref.watch(isFridaProvider);
    final fridaTargetAsync = ref.watch(
      getFridaTargetStatusProvider(packageName: packageName),
    );

    // 宽屏（桌面端）：列表 + 编辑器双栏；窄屏保持原来的"点脚本跳编辑器页面"。
    final useTwoPaneLayout = context.isWideLayout && context.isDesktopPlatform;
    final selectedScript = useState<String?>(null);
    VoidCallback? openScriptHandler(String scriptPath) => useTwoPaneLayout
        ? () => selectedScript.value = scriptPath
        : null;

    return TwoPaneScaffold(
      enabled: useTwoPaneLayout,
      detail: selectedScript.value == null
          ? TwoPaneEmptyDetail(
              message: context.isChinese
                  ? '从左侧选择一个脚本，编辑器会在这里打开'
                  : 'Pick a script on the left — the editor opens here.',
            )
          : _buildEditorPane(selectedScript.value!),
      scaffold: Scaffold(
      appBar: AppBar(
        title: const Text("Frida Scripts"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (value == 'import') {
                _handleImportScript(context, ref);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download_outlined, size: 20.sp),
                    SizedBox(width: 12.w),
                    Text(
                      context.l10n.importScript,
                      style: TextStyle(fontSize: 14.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateScriptDialog(context, ref),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(fridaScriptsProvider(packageName: packageName));
        },
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 10.w),
          child: scriptsAsync.when(
            data: (scripts) {
              final filtered = scripts.where((s) => s != 'hook.js').toList();
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filtered.length + 1,
                separatorBuilder: (_, __) => SizedBox(height: 3.h),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return fridaStatusAsync.when(
                      data: (fridaStatus) {
                        final moduleReady = _isFridaModuleReady(fridaStatus);
                        if (!moduleReady) {
                          return _buildTargetTile(
                            context,
                            enabled: false,
                            subtitle: _buildFridaTargetSubtitle(
                              context: context,
                              fridaStatus: fridaStatus,
                              targetEnabled: false,
                            ),
                            onChanged: null,
                          );
                        }

                        return fridaTargetAsync.when(
                          data: (enabled) => _buildTargetTile(
                            context,
                            enabled: enabled,
                            subtitle: _buildFridaTargetSubtitle(
                              context: context,
                              fridaStatus: fridaStatus,
                              targetEnabled: enabled,
                            ),
                            onChanged: (value) async {
                              try {
                                await ref.read(
                                  setFridaTargetStatusProvider(
                                    packageName: packageName,
                                    enabled: value,
                                  ).future,
                                );
                                ref.invalidate(
                                  getFridaTargetStatusProvider(
                                    packageName: packageName,
                                  ),
                                );
                              } catch (error) {
                                ToastMessage.show(error.toString());
                              }
                            },
                          ),
                          error: (error, _) => _buildTargetTile(
                            context,
                            enabled: false,
                            subtitle: error.toString(),
                            onChanged: null,
                          ),
                          loading: () => const Loading(),
                        );
                      },
                      error: (error, _) => _buildTargetTile(
                        context,
                        enabled: false,
                        subtitle: error.toString(),
                        onChanged: null,
                      ),
                      loading: () => const Loading(),
                    );
                  }

                  final scriptPath = filtered[index - 1];
                  final statusAsync = ref.watch(
                    getFridaScriptStatusProvider(
                      packageName: packageName,
                      localPath: scriptPath,
                    ),
                  );
                  return statusAsync.when(
                    data: (enabled) {
                      final name = PathUtils.getName(path: scriptPath);
                      return fridaStatusAsync.when(
                        data: (fridaStatus) {
                          final moduleReady = _isFridaModuleReady(fridaStatus);
                          if (!moduleReady) {
                            return _buildScriptTile(
                              context,
                              ref,
                              scriptPath: scriptPath,
                              name: name,
                              enabled: enabled,
                              moduleReady: false,
                              targetEnabled: false,
                              onOpenScript: openScriptHandler(scriptPath),
                            );
                          }

                          return fridaTargetAsync.when(
                            data: (masterEnabled) => _buildScriptTile(
                              context,
                              ref,
                              scriptPath: scriptPath,
                              name: name,
                              enabled: enabled,
                              moduleReady: true,
                              targetEnabled: masterEnabled,
                              onOpenScript: openScriptHandler(scriptPath),
                            ),
                            error: (_, __) => _buildScriptTile(
                              context,
                              ref,
                              scriptPath: scriptPath,
                              name: name,
                              enabled: enabled,
                              moduleReady: true,
                              targetEnabled: false,
                              onOpenScript: openScriptHandler(scriptPath),
                            ),
                            loading: () => const Loading(),
                          );
                        },
                        error: (_, __) => _buildScriptTile(
                          context,
                          ref,
                          scriptPath: scriptPath,
                          name: name,
                          enabled: enabled,
                          moduleReady: false,
                          targetEnabled: false,
                          onOpenScript: openScriptHandler(scriptPath),
                        ),
                        loading: () => const Loading(),
                      );
                    },
                    error: (error, _) => Text(error.toString()),
                    loading: () => const Loading(),
                  );
                },
              );
            },
            error: (error, _) => Stack(
              children: [
                ListView(physics: const AlwaysScrollableScrollPhysics()),
                Center(
                  child: RefError(
                    error: error,
                    onRetry: () => ref.read(
                      fridaScriptsProvider(packageName: packageName),
                    ),
                  ),
                ),
              ],
            ),
            loading: () => const Loading(),
          ),
        ),
      ),
      ),
    );
  }
}

class _CreateFridaScriptDialog extends HookConsumerWidget {
  final String packageName;
  final VoidCallback onCreated;

  const _CreateFridaScriptDialog({
    required this.packageName,
    required this.onCreated,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.projectName,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        SizedBox(height: 8.h),
        CustomTextField(controller: nameController, hintText: "script_name.js"),
        SizedBox(height: 16.h),
        Row(
          spacing: 5,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: () {
                var name = nameController.text.trim();
                if (name.isEmpty) {
                  ToastMessage.show(context.l10n.projectNameEmpty);
                  return;
                }
                if (name == 'hook.js' || name == "hook") {
                  ToastMessage.show(context.l10n.reservedScriptFileName);
                  return;
                }
                if (!name.endsWith('.js')) {
                  name = '$name.js';
                }
                ref.read(
                  createFridaScriptProvider(
                    packageName: packageName,
                    localPath: name,
                    content: "",
                  ),
                );
                ToastMessage.show(context.l10n.projectCreated(name));
                onCreated();
                Navigator.pop(context);
              },
              child: Text(context.l10n.projectCreate),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
          ],
        ),
      ],
    );
  }
}
