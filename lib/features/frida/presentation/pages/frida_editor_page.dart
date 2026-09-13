import 'dart:convert';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_code_editor/widgets/code_find_panel_view.dart';
import 'package:JsxposedX/common/widgets/app_code_editor/app_code_editor.dart';
import 'package:JsxposedX/common/widgets/run_app_button.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/routes/routes/home_route.dart';
import 'package:JsxposedX/core/utils/js_formatter.dart';
import 'package:JsxposedX/core/utils/path_utils.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/features/frida/presentation/providers/frida_action_provider.dart';
import 'package:JsxposedX/features/frida/presentation/providers/frida_query_provider.dart';
import 'package:JsxposedX/features/frida/presentation/constants/frida_prompts.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/logcat_provider.dart';
import 'package:JsxposedX/features/xposed/presentation/widgets/editor_tab_button.dart';
import 'package:JsxposedX/features/xposed/presentation/widgets/logcat_panel_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:re_editor/re_editor.dart';

class FridaEditorPage extends HookConsumerWidget {
  final String path;
  final String packageName;

  const FridaEditorPage({
    super.key,
    required this.path,
    required this.packageName,
  });

  Future<void> _saveScript(WidgetRef ref, String text) async {
    await ref.read(
      createFridaScriptProvider(
        packageName: packageName,
        content: text,
        localPath: PathUtils.getName(path: path),
      ).future,
    );
    // 移除自动注入，改为在 RunAppButton 里手动触发
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useAutomaticKeepAlive();
    final controller = useMemoized(
      () => CodeLineEditingController.fromText(''),
    );
    useEffect(() => controller.dispose, []);

    final findController = useMemoized(() => CodeFindController(controller));
    useEffect(() => findController.dispose, []);

    final showLogcat = useState(false);
    final isLogcatFullscreen = useState(false);
    final scriptName = useMemoized(() => PathUtils.getName(path: path));
    final scriptFileName = useMemoized(() => path.split('/').last);

    useListenable(findController);

    ref.listen(
      readFridaScriptProvider(packageName: packageName, localPath: path),
      (previous, next) {
        next.whenData((content) {
          if (controller.text.isEmpty && content.isNotEmpty) {
            controller.text = content;
          }
        });
      },
    );

    final tabButtons = [
      _TabButtonData(
        name: context.l10n.formatCode,
        icon: Icons.format_align_left_rounded,
        color: Colors.orange,
        onClick: (ctrl) {
          final formatted = JsFormatter.format(ctrl.text);
          if (formatted != ctrl.text) ctrl.text = formatted;
        },
      ),
      _TabButtonData(
        name: context.l10n.search,
        icon: Icons.search_rounded,
        color: Colors.purple,
        onClick: (ctrl) {
          findController.findInputController.clear();
          findController.replaceInputController.clear();
          if (findController.value == null) {
            findController.value = const CodeFindValue(
              option: CodeFindOption(
                caseSensitive: false,
                regex: false,
                pattern: '',
              ),
              replaceMode: false,
            );
          } else {
            findController.value = null;
          }
        },
      ),
      _TabButtonData(
        name: context.l10n.terminal,
        icon: Icons.terminal_rounded,
        color: showLogcat.value ? Colors.green : Colors.grey,
        onClick: (ctrl) {
          showLogcat.value = !showLogcat.value;
          if (showLogcat.value) {
            ref.read(logcatProvider.notifier).start(packageName);
          } else {
            ref.read(logcatProvider.notifier).stop();
            isLogcatFullscreen.value = false;
          }
        },
      ),
      _TabButtonData(
        name: context.l10n.apiManual,
        icon: Icons.menu_book_rounded,
        color: Colors.cyan,
        onClick: (CodeLineEditingController ctrl) {
          context.push(HomeRoute.fridaApiManual);
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(scriptName),
            Text(
              scriptFileName,
              style: TextStyle(fontSize: 10.sp, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: context.l10n.saveScript,
            onPressed: () async {
              await _saveScript(ref, controller.text);
              ToastMessage.show(context.l10n.scriptSaved);
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: context.l10n.exportScript,
            onPressed: () async {
              await FilePicker.platform.saveFile(
                dialogTitle: context.l10n.exportScript,
                fileName: scriptFileName,
                bytes: utf8.encode(controller.text),
              );
              ToastMessage.show(context.l10n.scriptExported);
            },
          ),
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.orange),
            tooltip: '热更新脚本',
            onPressed: () async {
              await _saveScript(ref, controller.text);
              // 启动 logcat 监听
              ref.read(logcatProvider.notifier).start(packageName);
              // 保存后重新注入，实现热更新（异步执行，不阻塞 UI）
              ref.read(
                bundleFridaHookJsProvider(packageName: packageName).future,
              );
              if (!context.mounted) return;
              ToastMessage.show(context.l10n.scriptSaved);
            },
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Colors.green),
            tooltip: '重启并注入',
            onPressed: () {
              Future.microtask(() async {
                await _saveScript(ref, controller.text);
                ref.read(logcatProvider.notifier).start(packageName);
                // 先启动 App
                NativeBridge.app.openAppX(packageName);
                // 等待一下让 App 启动
                await Future.delayed(const Duration(milliseconds: 500));
                // 再注入脚本
                ref.read(
                  bundleFridaHookJsProvider(packageName: packageName).future,
                );
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          CodeEditorTapRegion(
            child: Container(
              height: 50.h,
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: tabButtons.map((btn) {
                    return Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: EditorTabButton(
                        icon: btn.icon,
                        label: btn.name,
                        onTap: () => btn.onClick(controller),
                        color: btn.color,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          Divider(
            height: 1.h,
            thickness: 0.5,
            color: context.theme.dividerColor.withValues(alpha: 0.1),
          ),
          Expanded(
            child: Column(
              children: [
                if (!isLogcatFullscreen.value)
                  Expanded(
                    flex: showLogcat.value ? 2 : 1,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: AppCodeEditor(
                        controller: controller,
                        findController: findController,
                        findBuilder: (context, controller, readOnly) =>
                            CodeFindPanelView(
                              controller: controller,
                              readOnly: readOnly,
                            ),
                        promptsBuilder: buildFridaPromptsBuilder(),
                      ),
                    ),
                  ),
                if (showLogcat.value)
                  Expanded(
                    flex: 1,
                    child: LogcatPanelView(
                      isFullscreen: isLogcatFullscreen.value,
                      onToggleFullscreen: () =>
                          isLogcatFullscreen.value = !isLogcatFullscreen.value,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButtonData {
  final String name;
  final IconData icon;
  final void Function(CodeLineEditingController) onClick;
  final Color? color;

  const _TabButtonData({
    required this.name,
    required this.icon,
    required this.onClick,
    this.color,
  });
}
