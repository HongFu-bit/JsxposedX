import 'dart:convert';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/custom_dIalog.dart';
import 'package:JsxposedX/common/widgets/loading.dart';
import 'package:JsxposedX/common/widgets/ref_error.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/layout/two_pane_layout.dart';
import 'package:JsxposedX/core/routes/routes/home_route.dart';
import 'package:JsxposedX/core/utils/file_picker_util.dart';
import 'package:JsxposedX/core/utils/path_utils.dart';
import 'package:JsxposedX/features/app/presentation/providers/app_query_provider.dart';
import 'package:JsxposedX/features/xposed/presentation/pages/xposed_editor_page.dart';
import 'package:JsxposedX/features/xposed/presentation/pages/xposed_visual_editor_page.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/xposed_action_provider.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/xposed_query_provider.dart';
import 'package:JsxposedX/features/xposed/presentation/widgets/create_xposed_project_dialog.dart';
import 'package:JsxposedX/features/xposed/presentation/widgets/xposed_script_item.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class XposedProjectPage extends HookConsumerWidget {
  final String packageName;

  const XposedProjectPage({super.key, required this.packageName});

  void _handleImportScript(BuildContext context, WidgetRef ref) {
    FilePickerUtil.pickMultipleFiles(
      type: FileType.custom,
      allowedExtensions: ["js"],
    ).then((pickFileDatas) async {
      if (pickFileDatas.isNotEmpty) {
        for (final file in pickFileDatas) {
          final existingType = PathUtils.getType(file.fileName);
          String taggedName;
          if (existingType != null) {
            taggedName = file.fileName;
          } else {
            final scriptType = await CustomDialog.show<String>(
              title: Text(file.fileName),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.code,
                      color: Colors.blue,
                      size: 20.sp,
                    ),
                    title: Text(context.l10n.traditionalType),
                    subtitle: Text(context.l10n.traditionalScriptDesc),
                    onTap: () => SmartDialog.dismiss(result: 'traditional'),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.auto_awesome,
                      color: Colors.purple,
                      size: 20.sp,
                    ),
                    title: Text(context.l10n.visualType),
                    subtitle: Text(context.l10n.visualScriptDesc),
                    onTap: () => SmartDialog.dismiss(result: 'visual'),
                  ),
                ],
              ),
            );
            if (scriptType == null) continue;
            taggedName = '[$scriptType]${file.fileName}';
          }
          final content = utf8.decode(file.bytes);
          await ref.read(
            createJsScriptProvider(
              packageName: packageName,
              localPath: taggedName,
              content: content,
            ).future,
          );
        }
        ref.invalidate(jsScriptsProvider(packageName: packageName));
      }
    });
  }

  void _showCreateProjectSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: context.l10n.newProject,
      child: CreateXposedProjectDialog(packageName: packageName),
    );
  }

  /// 宽屏双栏右侧的编辑器。
  ///
  /// 生成类页面都是构造函数传参、不依赖路由状态，所以可以原样内嵌；
  /// key 必须跟随脚本路径变化，否则切换脚本时会复用上一个编辑器的内部状态。
  Widget _buildEditorPane(String scriptPath) {
    final name = PathUtils.getName(path: scriptPath);
    final isVisual = PathUtils.getType(name) == 'visual';
    return isVisual
        ? XposedVisualEditorPage(
            key: ValueKey<String>(scriptPath),
            packageName: packageName,
            path: scriptPath,
          )
        : XposedEditorPage(
            key: ValueKey<String>(scriptPath),
            packageName: packageName,
            path: scriptPath,
          );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scriptsAsync = ref.watch(jsScriptsProvider(packageName: packageName));

    // 宽屏（桌面端）列表 + 编辑器双栏；窄屏保持原来的"点脚本跳编辑器页面"。
    final useTwoPaneLayout = context.isWideLayout && context.isDesktopPlatform;
    final selectedScript = useState<String?>(null);

    // 宽屏：左栏是原来的整页（含自己的标题栏与新建按钮），右栏是编辑器。
    // 窄屏：enabled 为 false，直接返回原来的 Scaffold，渲染路径与改造前一致。
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
        title: Text(context.l10n.xposedScripts),
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
        onPressed: () => _showCreateProjectSheet(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(jsScriptsProvider(packageName: packageName));
        },
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 10.w),
          child: scriptsAsync.when(
            data: (scripts) {
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final statusAsync = ref.watch(
                    getJsScriptStatusProvider(
                      packageName: packageName,
                      localPath: scripts[index],
                    ),
                  );
                  return statusAsync.when(
                    data: (status) {
                      return XposedScriptItem(
                        onClick: () {
                          final scriptPath = scripts[index];
                          if (useTwoPaneLayout) {
                            // 宽屏：在右栏打开，不跳转整页路由
                            selectedScript.value = scriptPath;
                            return;
                          }
                          final name = PathUtils.getName(path: scriptPath);
                          final isVisual = PathUtils.getType(name) == 'visual';
                          final route = isVisual
                              ? HomeRoute.toXposedVisualEditor(
                                  packageName: packageName,
                                )
                              : HomeRoute.toXposedEditor(
                                  packageName: packageName,
                                );
                          context.push(route, extra: scriptPath);
                        },
                        onLongClick: () {
                          CustomDialog.show(
                            title: Text(context.l10n.confirmDelete),
                            child: const SizedBox(),
                            actionButtons: [
                              ElevatedButton(
                                onPressed: () async {
                                  await ref.read(
                                    deleteJsScriptProvider(
                                      packageName: packageName,
                                      localPath: scripts[index],
                                    ).future,
                                  );
                                  ref.invalidate(
                                    jsScriptsProvider(packageName: packageName),
                                  );
                                  // 宽屏下删掉的正好是右栏展开的脚本时，清掉选中，
                                  // 否则右栏会停留在已删除的脚本上。
                                  if (selectedScript.value == scripts[index]) {
                                    selectedScript.value = null;
                                  }
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
                        },
                        path: scripts[index],
                        enabled: status,
                        onToggle: (enabled) async {
                          await ref.read(
                            setJsScriptStatusProvider(
                              packageName: packageName,
                              localPath: scripts[index],
                              status: enabled,
                            ).future,
                          );
                          ref.invalidate(
                            getJsScriptStatusProvider(
                              packageName: packageName,
                              localPath: scripts[index],
                            ),
                          );
                        },
                      );
                    },
                    error: (error, stack) => Text(error.toString()),
                    loading: () => const Loading(),
                  );
                },
                separatorBuilder: (context, index) => SizedBox(height: 3.h),
                itemCount: scripts.length,
              );
            },
            error: (error, index) => Stack(
              children: [
                ListView(physics: const AlwaysScrollableScrollPhysics()),
                Center(
                  child: RefError(
                    error: error,
                    onRetry: () =>
                        ref.read(jsScriptsProvider(packageName: packageName)),
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
