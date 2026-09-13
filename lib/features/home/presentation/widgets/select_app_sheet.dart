import 'dart:async';

import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/custom_text_field.dart';
import 'package:JsxposedX/common/widgets/loading.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/app_info.dart';
import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/features/app/data/models/app_info_dto.dart';
import 'package:JsxposedX/features/app/presentation/providers/app_query_provider.dart';
import 'package:JsxposedX/features/app/presentation/widgets/app_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SelectAppSheet extends HookConsumerWidget {
  final ValueChanged<AppInfo>? onSelected;
  final bool addToLSPosedScope;

  const SelectAppSheet({
    super.key,
    this.onSelected,
    this.addToLSPosedScope = false,
  });

  static void show(
    BuildContext context, {
    ValueChanged<AppInfo>? onSelected,
    bool addToLSPosedScope = false,
  }) {
    AppBottomSheet.show(
      context: context,
      title: context.l10n.selectApp,
      child: SelectAppSheet(
        onSelected: onSelected,
        addToLSPosedScope: addToLSPosedScope,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = useState("");
    final showSystemApps = useState(false);

    // 聚合显示的应用列表
    final displayedApps = useState<List<AppInfoDto>>([]);
    final totalCount = useState(0);
    final isLoading = useState(false);
    final currentOffset = useState(0);
    const pageSize = 15;

    // 定时器用于搜索防抖
    final searchDebounce = useRef<Timer?>(null);

    // 初始化加载与重置
    Future<void> loadNextPage({bool reset = false}) async {
      if (isLoading.value) return;
      if (!reset &&
          displayedApps.value.length >= totalCount.value &&
          totalCount.value > 0) {
        return;
      }

      isLoading.value = true;
      final repo = ref.read(appQueryRepositoryProvider);
      final currentQuery = searchQuery.value;

      if (reset) {
        displayedApps.value = [];
        currentOffset.value = 0;
        totalCount.value = await repo.getAppCount(
          includeSystemApps: showSystemApps.value,
          query: currentQuery,
        );
      }

      final newBatch = await repo.getInstalledApps(
        includeSystemApps: showSystemApps.value,
        offset: currentOffset.value,
        limit: pageSize,
        query: currentQuery,
      );

      // 如果请求还没回来搜索词就变了，则丢弃这批结果，防止竞态
      if (currentQuery != searchQuery.value) return;

      displayedApps.value = [...displayedApps.value, ...newBatch];
      currentOffset.value += pageSize;
      isLoading.value = false;
    }

    // 监控系统应用开关变化
    useEffect(() {
      loadNextPage(reset: true);
      return null;
    }, [showSystemApps.value]);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Column(
            children: [
              CustomTextField(
                name: "search",
                hintText: context.l10n.searchAppsPlaceholder,
                prefixIcon: const Icon(Icons.search),
                onChanged: (value) {
                  final val = value ?? "";
                  searchQuery.value = val;

                  // 防抖逻辑：停止输入 500ms 后才触发原生搜索
                  searchDebounce.value?.cancel();
                  searchDebounce.value = Timer(
                    const Duration(milliseconds: 500),
                    () {
                      loadNextPage(reset: true);
                    },
                  );
                },
              ),
              SizedBox(height: 8.h),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      context.l10n.loadedCount(
                        displayedApps.value.length,
                        totalCount.value,
                      ),
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: context.colorScheme.primary,
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Text(
                      context.l10n.showSystemApps,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: showSystemApps.value,
                        onChanged: (val) => showSystemApps.value = val,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: displayedApps.value.isEmpty && !isLoading.value
              ? _EmptyResult()
              : NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 100) {
                      loadNextPage();
                    }
                    return true;
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemCount:
                        displayedApps.value.length + (isLoading.value ? 1 : 0),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    cacheExtent: 100,
                    itemBuilder: (context, index) {
                      if (index < displayedApps.value.length) {
                        final appDto = displayedApps.value[index];
                        return AppItem(
                          app: appDto.toEntity(),
                          onSelected: addToLSPosedScope
                              ? (app) => _handleLSPosedScopeAdd(context, app)
                              : onSelected,
                        );
                      }
                      return const Loading();
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// 处理添加应用到 LSPosed scope
  Future<void> _handleLSPosedScopeAdd(BuildContext context, AppInfo app) async {
    print('[LSPosed] 开始处理添加 ${app.packageName} 到作用域');
    final lsposedApi = NativeBridge.lsposed;
    
    // 先检查 LSPosed 是否可用
    try {
      final isAvailable = lsposedApi.isLSPosedAvailable();
      print('[LSPosed] LSPosed 可用性: $isAvailable');
      
      if (isAvailable == false) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.lsposedNotAvailable),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    } catch (e) {
      print('[LSPosed] 检查可用性失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.lsposedNotAvailable),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.lsposedAddingScope(app.name))),
      );
    }
    
    try {
      print('[LSPosed] 调用 addModuleScope: ${app.packageName}');
      final result = await lsposedApi.addModuleScope(app.packageName, 0);
      print('[LSPosed] addModuleScope 返回结果: $result');
      
      if (context.mounted) {
        if (result) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.lsposedScopeRequestedCheckNotification(app.name)),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.lsposedAddFailed(app.name)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('[LSPosed] 添加失败: $e');
      print('[LSPosed] 堆栈: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.lsposedAddFailedService),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    
    onSelected?.call(app);
  }
}

class _EmptyResult extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 48.sp,
            color: context.colorScheme.outline,
          ),
          SizedBox(height: 16.h),
          Text(context.l10n.noRelatedApps),
        ],
      ),
    );
  }
}
