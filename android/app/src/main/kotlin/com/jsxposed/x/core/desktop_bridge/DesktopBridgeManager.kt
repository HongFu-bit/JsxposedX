package com.jsxposed.x.core.desktop_bridge

import android.content.Context
import com.jsxposed.x.core.utils.log.LogX
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
 *
 * 除生命周期外，本对象还是**两条链路的公共状态持有者**：
 * USB 那条由 [DesktopBridgeServer.start] 自动挂上；Wi-Fi 那条由
 * [connectWithCode] / [connectWithSession] 在运行期挂上（[DesktopBridgeServer.addTransport]），
 * 并由这里保存"当前拨号目标 + 当前要出示的凭据"。
 * 见 docs/desktop_bridge_lan_CN.md §7.3、§11。
 */
object DesktopBridgeManager {

    private companion object {
        const val TAG = BridgeProtocol.LOG_TAG
    }

    private val router = BridgeChannelRouter()

    @Volatile
    private var server: DesktopBridgeServer? = null

    @Volatile
    private var messenger: DesktopBridgeMessenger? = null

    /** 手机侧保存的"已配对的电脑"与本机 deviceId。首次 [install] 时创建。 */
    @Volatile
    private var store: PairedPcStore? = null

    // ---------------------------------------------------------- 当前 LAN 目标

    @Volatile
    private var lanHost: String? = null

    @Volatile
    private var lanPort: Int = 0

    /** 电脑名。来自 `hello.clientName`，配对成功前为 null。 */
    @Volatile
    private var lanName: String? = null

    /** 当前要出示给电脑的凭据；LAN 链路上由**手机**出示（§7.3）。 */
    @Volatile
    private var lanCredential: BridgeCredential? = null

    /**
     * 装配 bridge，返回应当用于注册 Pigeon handler 的 messenger。
     *
     * Activity 重建时 FlutterEngine 会换成新实例，因此这里每次都重建 messenger，
     * 调用方拿到返回值后需要重新 `NativeProvider.registerAll(...)`；
     * 已启动的服务端与已建立的桌面连接不会被重复创建或中断。
     */
    @Synchronized
    fun install(context: Context, engineMessenger: BinaryMessenger): BinaryMessenger {
        val appContext = context.applicationContext

        val created = DesktopBridgeMessenger(engineMessenger)
        messenger = created
        router.attachMessenger(created)

        val pairedStore = store ?: PairedPcStore(appContext).also { store = it }

        if (server == null) {
            val bridgeServer = DesktopBridgeServer(
                context = appContext,
                router = router,
                tokenStore = DesktopBridgeTokenStore(appContext),
                credentialProvider = { lanCredential },
                deviceIdProvider = { pairedStore.deviceId() },
                onSessionTokenReceived = { token, clientName -> onSessionToken(token, clientName) },
            )
            server = bridgeServer
            bridgeServer.start()
        }

        autoReconnectIfEnabled()

        return created
    }

    @Synchronized
    fun detach() {
        router.detachMessenger()
        server?.stop()
        server = null
        messenger = null
        // 保留 store 与已配对记录：下次 install 还要用；
        // 拨号目标也保留，Activity 重建后自动重连能接上。
    }

    fun isRunning(): Boolean = server?.isRunning() == true

    /** 已注册的 Pigeon 通道数，用于确认注册是否成功（诊断用）。 */
    fun registeredChannelCount(): Int = messenger?.channelCount() ?: 0

    /** 读取当前令牌（首次调用会生成并持久化）。USB 链路仍按老方式使用它。 */
    fun token(context: Context): String = DesktopBridgeTokenStore(context).token()

    // ------------------------------------------------------------- LAN 连接

    /**
     * 用**用户输入的 6 位校验码**发起一次 LAN 连接。
     *
     * 幂等：重复调用会先摘掉旧的拨号 transport 再挂新的，
     * 因此"改地址重连"与"重新输码"都走这一个入口。
     */
    @Synchronized
    fun connectWithCode(host: String, port: Int, code: String) {
        startLanDial(host = host, port = port, credential = BridgeCredential.Code(code))
    }

    /**
     * 用**已保存的会话令牌**自动重连某台电脑。
     *
     * 注意令牌与地址是绑定的（§11.4）：只有目标 `host:port` 与配对记录完全一致时
     * 才会走到这里；地址被改动过就必须回到 [connectWithCode] 重新输码。
     *
     * 标 `internal` 是因为参数 [PairedPc] 是 internal 类型——Kotlin 不允许公开函数
     * 暴露 internal 类型。同一个 Gradle 模块内的 [LanBridgeNativeImpl] 仍可调用它。
     */
    @Synchronized
    internal fun connectWithSession(pc: PairedPc) {
        startLanDial(
            host = pc.host,
            port = pc.port,
            credential = BridgeCredential.Session(pc.token),
            name = pc.name,
        )
    }

    @Synchronized
    private fun startLanDial(
        host: String,
        port: Int,
        credential: BridgeCredential,
        name: String? = null,
    ) {
        val bridgeServer = server
        if (bridgeServer == null) {
            LogX.w(TAG, "[lan] connect ignored, bridge is not running")
            return
        }

        lanHost = host
        lanPort = port
        lanName = name
        lanCredential = credential
        bridgeServer.clearLastReject()

        LogX.i(TAG, "[lan] dialing:", "$host:$port")
        bridgeServer.addTransport(
            LanDialTransport(host = host, port = port) { !bridgeServer.hasClient() }
        )
    }

    /** 主动断开 LAN 并清除拨号目标（不影响已配对记录）。 */
    @Synchronized
    fun disconnectLan() {
        server?.removeTransport(BridgeProtocol.TRANSPORT_LAN)
        lanHost = null
        lanPort = 0
        lanName = null
        lanCredential = null
    }

    /** App 启动时按配置自动重连最近一台电脑。 */
    @Synchronized
    private fun autoReconnectIfEnabled() {
        val pairedStore = store ?: return
        if (!pairedStore.isAutoReconnect()) {
            return
        }
        if (lanHost != null) {
            // 已经有拨号目标了（例如 Activity 重建），不要重复拨。
            return
        }
        val last = pairedStore.lastPc() ?: return
        LogX.i(TAG, "[lan] auto reconnect:", last.address)
        startLanDial(
            host = last.host,
            port = last.port,
            credential = BridgeCredential.Session(last.token),
            name = last.name,
        )
    }

    /**
     * 电脑校验通过后下发了会话令牌（§8.3）——配对成功，落盘。
     *
     * 落盘之后把当前凭据换成 [BridgeCredential.Session]，
     * 这样即便本次连接随后断开，重连也会直接用令牌而不是再去要一次码。
     */
    @Synchronized
    private fun onSessionToken(token: String, clientName: String?) {
        val pairedStore = store ?: return
        val host = lanHost ?: return
        val port = lanPort
        if (host.isBlank() || port <= 0) {
            return
        }
        val name = clientName ?: lanName ?: "$host:$port"
        pairedStore.savePc(name = name, host = host, port = port, token = token)
        lanName = name
        lanCredential = BridgeCredential.Session(token)
        LogX.i(TAG, "[lan] paired with:", name, "$host:$port")
    }

    // ------------------------------------------------- 供 Pigeon 实现读取的状态

    fun isUsbConnected(): Boolean =
        server?.let { it.hasClient() && it.currentClientKind() == BridgeProtocol.TRANSPORT_USB } == true

    fun isLanConnected(): Boolean =
        server?.let { it.hasClient() && it.currentClientKind() == BridgeProtocol.TRANSPORT_LAN } == true

    /** 是否已有 LAN 拨号目标（不代表已连上）。 */
    fun hasLanTarget(): Boolean = lanHost != null

    fun lanTargetHost(): String? = lanHost

    fun lanTargetPort(): Int = lanPort

    /** 已连接电脑的名称；未连上时回退到拨号记录里的名字。 */
    fun lanPeerName(): String? = lanName

    /** LAN 链路最近一次被电脑拒绝的原因（§9.3），供页面显示准确文案。 */
    fun lastRejectCode(): String? = server?.lastRejectCode

    fun lastRejectMessage(): String? = server?.lastRejectMessage

    /** 同上，返回类型 [PairedPc] 是 internal，因此这里也标 internal。 */
    internal fun pairedPcs(): List<PairedPc> = store?.listPcs() ?: emptyList()

    fun deviceId(): String? = store?.deviceId()

    /** @return 是否确实忘掉了一条。 */
    fun forgetPc(host: String, port: Int): Boolean {
        val removed = store?.forgetPc(host, port) ?: false
        // 如果忘掉的正是当前目标，顺带断开，避免"明明忘了却还连着"。
        if (removed && lanHost == host && lanPort == port) {
            disconnectLan()
        }
        return removed
    }

    fun forgetAllPcs() {
        store?.forgetAllPcs()
        disconnectLan()
    }

    fun isAutoReconnect(): Boolean = store?.isAutoReconnect() ?: true

    fun setAutoReconnect(enabled: Boolean) {
        store?.setAutoReconnect(enabled)
        if (enabled) {
            autoReconnectIfEnabled()
        }
    }
}
