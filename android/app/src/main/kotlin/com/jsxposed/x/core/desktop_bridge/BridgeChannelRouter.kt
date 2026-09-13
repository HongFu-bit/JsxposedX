package com.jsxposed.x.core.desktop_bridge

import android.os.Handler
import android.os.Looper
import java.nio.ByteBuffer

/**
 * 把桌面端发来的 {channel, 原始字节} 交给本机已注册的 Pigeon handler。
 *
 * 真正的分发逻辑在 [DesktopBridgeMessenger]（Pigeon handler 注册在那里）。
 * 本类只负责两件事：
 *  1. 持有当前生效的 messenger（Activity 重建时 FlutterEngine 会换新实例，必须重新绑定）；
 *  2. 把调用切到**主线程**再执行。
 *
 * 为什么走主线程：
 *  - 与手机 App 自己的调用保持同一线程，天然串行，避免与手机 UI 并发访问 Impl 的共享状态
 *    （内存工具的搜索会话、APK 会话等都不是线程安全的）。
 *  - 代价与手机端原有行为一致：`ProjectNativeImpl` 里用 `runBlocking` 的同步方法会短暂卡住
 *    手机 UI，这一点已在 docs/desktop_bridge_CN.md §9.2 说明。
 */
internal class BridgeChannelRouter {

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var bridgeMessenger: DesktopBridgeMessenger? = null

    fun attachMessenger(messenger: DesktopBridgeMessenger) {
        this.bridgeMessenger = messenger
    }

    fun detachMessenger() {
        this.bridgeMessenger = null
    }

    /**
     * @param onResult 主线程回调；buffer 为 null 表示该通道没有 handler。
     */
    fun dispatch(channel: String, bytes: ByteArray?, onResult: (ByteBuffer?) -> Unit) {
        val target = bridgeMessenger
        if (target == null) {
            onResult(null)
            return
        }

        mainHandler.post {
            target.dispatch(channel, bytes, onResult)
        }
    }
}
