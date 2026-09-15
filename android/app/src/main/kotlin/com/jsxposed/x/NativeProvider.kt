package com.jsxposed.x

import com.jsxposed.x.core.bridge.apk_analysis_native.ApkAnalysisNative
import com.jsxposed.x.core.bridge.apk_analysis_native.ApkAnalysisNativeImpl
import com.jsxposed.x.core.bridge.app_native.AppNative
import com.jsxposed.x.core.bridge.pinia_native.PiniaNativeImpl
import com.jsxposed.x.core.bridge.file_picker_native.OverlayFilePickerNative
import com.jsxposed.x.core.bridge.zygisk_frida_native.ZygiskFridaNative
import com.jsxposed.x.core.bridge.zygisk_frida_native.ZygiskFridaNativeImpl
import com.jsxposed.x.core.bridge.status_management_native.StatusManagementNative
import com.jsxposed.x.core.bridge.status_management_native.StatusManagementNativeImpl
import com.jsxposed.x.core.bridge.app_native.AppNativeImpl
import com.jsxposed.x.core.bridge.lan_bridge_native.LanBridgeNative
import com.jsxposed.x.core.bridge.lan_bridge_native.LanBridgeNativeImpl
import com.jsxposed.x.core.bridge.memory_tool_native.MemoryToolNative
import com.jsxposed.x.core.bridge.memory_tool_native.MemoryToolNativeImpl
import com.jsxposed.x.core.bridge.pinia_native.PiniaNative
import com.jsxposed.x.core.bridge.project_native.ProjectNative
import com.jsxposed.x.core.bridge.project_native.ProjectNativeImpl
import com.jsxposed.x.core.bridge.url_helper_native.UrlHelperNative
import com.jsxposed.x.core.bridge.so_analysis_native.SoAnalysisNative
import com.jsxposed.x.core.bridge.so_analysis_native.SoAnalysisNativeImpl
import com.jsxposed.x.core.bridge.lsposed_native.LSPosedNative
import com.jsxposed.x.core.bridge.lsposed_native.LSPosedNativeImpl
import io.flutter.plugin.common.BinaryMessenger

object NativeProvider {
    fun registerAll(context: android.content.Context, messenger: BinaryMessenger) {
        PiniaNative.setUp(messenger, PiniaNativeImpl(context))
        StatusManagementNative.setUp(messenger, StatusManagementNativeImpl(context))
        AppNative.setUp(messenger, AppNativeImpl(context))
        ProjectNative.setUp(messenger, ProjectNativeImpl(context))
        val apkAnalysisImpl = ApkAnalysisNativeImpl(context)
        ApkAnalysisNative.setUp(messenger, apkAnalysisImpl)
        SoAnalysisNative.setUp(messenger, SoAnalysisNativeImpl(context, apkAnalysisImpl.sharedSession))
        MemoryToolNative.setUp(messenger, MemoryToolNativeImpl(context))
        LSPosedNative.setUp(messenger, LSPosedNativeImpl(context))
        ZygiskFridaNative.setUp(messenger, ZygiskFridaNativeImpl(context))
        // 「局域网直连」的原生接口。它读的是 DesktopBridgeManager 的状态，
        // 因此桌面端连上之后也能通过隧道读到同一份数据（docs/desktop_bridge_lan_CN.md §11.1）。
        LanBridgeNative.setUp(messenger, LanBridgeNativeImpl(context))
        OverlayFilePickerNative.register(context, messenger)
        UrlHelperNative.register(context, messenger)
    }
}
