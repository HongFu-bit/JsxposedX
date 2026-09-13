package com.jsxposed.x.core.desktop_bridge

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger

/**
 * 桌面端 bridge 的生命周期入口，由 MainActivity 调用。
 *
 * 用法（MainActivity.configureFlutterEngine）：
 * ```kotlin
 * val bridgeMessenger = DesktopBridgeManager.install(this, flutterEngine.dartExecutor.binaryMessenger)
 * NativeProvider.registerAll(this, bridgeMessenger)
 * ```
 * **注册顺序很重要**：Pigeon 的 handler 必须注册到 [install] 返回的 messenger 上，
 * 桌面端的调用才能命中它们。原因见 [DesktopBridgeMessenger] 的类注释。
 */
object DesktopBridgeManager {

    private val router = BridgeChannelRouter()

    @Volatile
    private var server: DesktopBridgeServer? = null

    @Volatile
    private var messenger: DesktopBridgeMessenger? = null

    /**
     * 装配 bridge，返回应当用于注册 Pigeon handler 的 messenger。
     *
     * Activity 重建时 FlutterEngine 会换成新实例，因此这里每次都重建 messenger，
     * 调用方拿到返回值后需要重新 `NativeProvider.registerAll(...)`；
     * 已启动的服务端与已建立的桌面连接不会被重复创建或中断。
     */
    @Synchronized
    fun install(context: Context, engineMessenger: BinaryMessenger): BinaryMessenger {
        val created = DesktopBridgeMessenger(engineMessenger)
        messenger = created
        router.attachMessenger(created)

        if (server == null) {
            val bridgeServer = DesktopBridgeServer(
                context = context,
                router = router,
                tokenStore = DesktopBridgeTokenStore(context),
            )
            server = bridgeServer
            bridgeServer.start()
        }

        return created
    }

    @Synchronized
    fun detach() {
        router.detachMessenger()
        server?.stop()
        server = null
        messenger = null
    }

    fun isRunning(): Boolean = server?.isRunning() == true

    /** 已注册的 Pigeon 通道数，用于确认注册是否成功（诊断用）。 */
    fun registeredChannelCount(): Int = messenger?.channelCount() ?: 0

    /** 读取当前令牌（首次调用会生成并持久化）。 */
    fun token(context: Context): String = DesktopBridgeTokenStore(context).token()
}
