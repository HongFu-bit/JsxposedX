import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/features/overlay_window/domain/models/overlay_window_payload.dart';
import 'package:JsxposedX/features/overlay_window/domain/models/overlay_window_presentation.dart';
import 'package:JsxposedX/features/overlay_window/presentation/models/overlay_window_host_runtime_state.dart';
import 'package:JsxposedX/features/overlay_window/presentation/providers/overlay_window_host_runtime_provider.dart';

/// 桌面端的「悬浮窗宿主运行时」替身。
///
/// 背景：内存工具的 UI 是以悬浮窗"面板"的形式实现的，它需要宿主运行时提供
/// 显示模式（panel / bubble）、视口尺寸和 Toast 提示。
/// 而桌面端没有悬浮窗（`flutter_overlay_window` 是 Android 专属），
/// 原本的 [OverlayWindowHostRuntimeNotifier] 在 `build()` 里就会去订阅插件事件流、
/// 读取视口尺寸 —— 这两步在 Windows 上必然抛 MissingPluginException，
/// 所以桌面端必须换成这个替身。
///
/// 覆写的三处，都是与插件直接耦合的地方：
/// 1. [build]：固定为 panel 模式，且不订阅插件事件、不读视口。
///    注意默认 payload 是 **bubble** 模式 —— 不改的话内存工具会渲染成那颗悬浮小球。
/// 2. [showToast]：改走 App 自己的提示（SmartDialog），
///    因为桌面端没有宿主页面去渲染 `activeToast`，否则提示会静默消失。
/// 3. [closeOverlay]：空实现。桌面端没有悬浮窗可关，真去关会调到插件。
class DesktopOverlayWindowHostRuntime extends OverlayWindowHostRuntimeNotifier {
  @override
  OverlayWindowHostRuntimeState build() {
    return const OverlayWindowHostRuntimeState(
      payload: OverlayWindowPayload(
        sceneId: 0,
        displayMode: OverlayWindowDisplayMode.panel,
        localeLanguageCode: 'zh',
        localeCountryCode: 'CN',
        isDarkTheme: false,
        primaryColorValue: 0xFF98D2D5,
      ),
    );
  }

  @override
  void showToast(String message, {int durationMs = 1800}) {
    ToastMessage.show(message);
  }

  @override
  Future<void> closeOverlay() async {
    // 桌面端没有悬浮窗，什么都不用做。
  }
}
