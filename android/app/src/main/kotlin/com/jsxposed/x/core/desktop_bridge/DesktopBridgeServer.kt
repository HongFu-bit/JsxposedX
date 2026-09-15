package com.jsxposed.x.core.desktop_bridge

import android.content.Context
import android.os.Build
import android.util.Base64
import com.jsxposed.x.core.utils.log.LogX
import io.flutter.plugin.common.StandardMessageCodec
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * 桌面端 bridge 服务端。
 *
 * 职责：从 [BridgeTransport] 取得连接 → 校验凭据 → 收发 NDJSON 帧 → 把调用交给 [BridgeChannelRouter]。
 * 只允许一个桌面客户端同时连接（第二个连接收到 reject(busy)）。
 *
 * 线程模型：
 * - 每个 transport 一条独立的 accept 线程（USB 是等待入站，LAN 是主动拨号，见 [BridgeTransport]）
 * - Pigeon 派发与回包：走 Flutter 主线程（[BridgeChannelRouter] 内部处理）
 * - 写帧：单线程 executor，避免大载荷回包阻塞 UI 线程
 *
 * 本类**不关心连接是 USB 来的还是 Wi-Fi 来的**——那是 transport 的职责。
 * 两条链路共用同一个实例，因此单客户端约束、心跳、空闲超时、Pigeon 派发线程模型
 * 全部只有一份实现。见 docs/desktop_bridge_lan_CN.md §5、§6。
 */
internal class DesktopBridgeServer(
    context: Context,
    private val router: BridgeChannelRouter,
    private val tokenStore: DesktopBridgeTokenStore,
    /**
     * LAN 链路上**手机要出示的凭据**（§7.3）。
     *
     * 与 USB 相反的方向：USB 由电脑出示令牌、手机校验；LAN 由手机出示码/令牌、电脑校验。
     * USB 链路上这个 lambda 的返回值不会被用到，返回 null 即可。
     */
    private val credentialProvider: () -> BridgeCredential? = { null },
    /** 本机稳定标识，写进 `welcome.deviceId`，供电脑端给配对记录去重（§10.6）。 */
    private val deviceIdProvider: () -> String = { "" },
    /**
     * 收到电脑下发的会话令牌时回调（§8.3）。
     *
     * 由 [DesktopBridgeManager] 负责落盘——服务器本身不碰存储，
     * 这样"哪台电脑、什么名字"这类信息由掌握拨号目标的那个组件补齐。
     */
    private val onSessionTokenReceived: (token: String, clientName: String?) -> Unit = { _, _ -> },
) {

    private companion object {
        const val TAG = BridgeProtocol.LOG_TAG
    }

    private val appContext = context.applicationContext

    /** 调试开关：置为 false 则跳过令牌校验，仅限本地联调使用。 */
    private val requireToken = true

    private val writeLock = Any()

    @Volatile
    private var running = false

    @Volatile
    private var lastFrameAt = 0L

    /** 当前客户端。USB 与 LAN 共用这一个槽位。 */
    @Volatile
    private var client: BridgeConnection? = null

    /** 当前客户端是从哪种 transport 来的，用于"换拨号目标时断开旧连接"。 */
    @Volatile
    private var clientKind: String? = null

    @Volatile
    private var clientWriter: BufferedWriter? = null

    /** 本次握手收到的电脑主机名，配对成功后写进 PairedPcStore。 */
    @Volatile
    private var lastClientName: String? = null

    /**
     * LAN 链路最近一次被电脑拒绝的原因（`code` / `code-stale` / `locked`）。
     *
     * 手机端页面通过 Pigeon 轮询读取，用来显示准确文案（§9.3）。
     * 用状态而不是回调，是为了避免给 [DesktopBridgeServer] 再加一个监听者接口。
     */
    @Volatile
    var lastRejectCode: String? = null
        private set

    @Volatile
    var lastRejectMessage: String? = null
        private set

    /**
     * 当前连接上要使用的会话令牌（§7.6）。帧加密的密钥就是由它派生的。
     *
     * 两个来源：LAN 握手时手机出示的那个（自动重连路径），
     * 或者电脑随后用 `token` 帧签发的新令牌（首次配对路径）。
     * 收到 `secured` 时用它派生密钥。
     */
    @Volatile
    private var sessionToken: String? = null

    /** 非 null 表示本连接已启用帧加密；**仅 LAN 链路会启用**（USB 是本地可信通道）。 */
    @Volatile
    private var cipher: BridgeCipher? = null

    fun clearLastReject() {
        lastRejectCode = null
        lastRejectMessage = null
    }

    private val transports = mutableListOf<BridgeTransport>()
    private val acceptThreads = mutableMapOf<String, Thread>()
    private var scheduler: ScheduledExecutorService? = null
    private var writeExecutor: ExecutorService? = null

    fun isRunning(): Boolean = running

    /**
     * 当前是否已有客户端连着。
     *
     * 给 [LanDialTransport] 的 `canDial` 谓词用：已有连接时不要拨号，
     * 否则会出现"手机主动连上去、又被自己的单客户端约束以 busy 拒掉"的怪状态
     * （docs/desktop_bridge_lan_CN.md §6.4 第二点）。
     */
    fun hasClient(): Boolean = client != null

    /** 当前客户端来自哪种 transport；没有客户端时返回 null。 */
    fun currentClientKind(): String? = clientKind

    /**
     * 校验是否已经通过——也就是电脑是否已经发来 `secured`、帧加密是否已启用。
     *
     * **判断"LAN 已连接"必须用它，不能用 [hasClient]**：`hasClient` 在 TCP 刚接上的
     * 那一刻就为真，而那时电脑还没校验。用它做界面状态，每被拒绝一次就会先亮一下
     * "已连接"再退回"正在连接"，用户看到的是一条一直在跳的状态，而不是"从来没连上"。
     */
    fun isSecured(): Boolean = cipher != null

    fun start() {
        if (running) {
            return
        }

        val started = mutableListOf<BridgeTransport>()
        for (transport in createTransports()) {
            try {
                transport.start()
                started += transport
            } catch (t: Throwable) {
                LogX.e(TAG, "start transport failed:", transport.kind, t)
            }
        }
        if (started.isEmpty()) {
            LogX.e(TAG, "no transport could be started, bridge stays disabled")
            return
        }

        transports.addAll(started)
        running = true
        writeExecutor = Executors.newSingleThreadExecutor()
        scheduler = Executors.newSingleThreadScheduledExecutor().also { executor ->
            executor.scheduleWithFixedDelay(
                { checkIdleTimeout() },
                BridgeProtocol.HEARTBEAT_INTERVAL_MS,
                BridgeProtocol.HEARTBEAT_INTERVAL_MS,
                TimeUnit.MILLISECONDS,
            )
        }
        for (transport in started) {
            acceptThreads[transport.kind] = thread(
                isDaemon = true,
                name = "jsxposed-bridge-accept-${transport.kind}",
            ) {
                acceptLoop(transport)
            }
        }

        // token 通过 logcat 暴露给 adb 侧，启动脚本会读取这一行。
        LogX.i(TAG, "token=${tokenStore.token()}")
    }

    /**
     * 本次要启用的 transport。
     *
     * P0-1 只有 USB——这一步是把传输层抽出来的等价重构，行为必须与重构前完全一致。
     * LAN 拨号 transport 在后续步骤里加到这里。
     */
    private fun createTransports(): List<BridgeTransport> = listOf(
        UsbLocalTransport(BridgeProtocol.SOCKET_NAME),
    )

    fun stop() {
        if (!running) {
            return
        }
        running = false

        scheduler?.shutdownNow()
        scheduler = null
        writeExecutor?.shutdownNow()
        writeExecutor = null

        // 先关 transport 让阻塞中的 accept 返回，再关客户端。
        for (transport in transports) {
            transport.close()
        }
        transports.clear()
        acceptThreads.clear()

        val current = client
        client = null
        clientKind = null
        clientWriter = null
        closeQuietly(current)

        LogX.i(TAG, "stopped")
    }

    // ------------------------------------------------- 运行期增删 transport

    /**
     * 运行期加一条 transport（LAN 拨号用）。
     *
     * 同一时刻只允许一个 LAN 拨号目标：换目标时调用方应先 [removeTransport] 掉旧那条，
     * 再调本方法。这里额外做一次同 kind 清理，是为了防止调用方漏掉那一步
     * 而留下两条同时在拨号的 transport（文档 §6.4 第一点）。
     */
    @Synchronized
    fun addTransport(transport: BridgeTransport) {
        if (!running) {
            LogX.w(TAG, "addTransport ignored, bridge is not running:", transport.kind)
            return
        }
        removeTransportLocked(transport.kind)
        try {
            transport.start()
        } catch (t: Throwable) {
            LogX.e(TAG, "start transport failed:", transport.kind, t)
            return
        }
        transports += transport
        acceptThreads[transport.kind] = thread(
            isDaemon = true,
            name = "jsxposed-bridge-accept-${transport.kind}",
        ) {
            acceptLoop(transport)
        }
    }

    /** 关掉并移除指定类型的 transport；若当前客户端来自它，一并断开。 */
    @Synchronized
    fun removeTransport(kind: String) {
        removeTransportLocked(kind)
    }

    private fun removeTransportLocked(kind: String) {
        val target = transports.firstOrNull { it.kind == kind } ?: return
        transports.remove(target)
        acceptThreads.remove(kind)
        // close() 会让阻塞在 accept() 里的那条线程尽快返回 null 并退出。
        target.close()

        if (clientKind == kind) {
            val current = client
            client = null
            clientKind = null
            clientWriter = null
            closeQuietly(current)
            LogX.i(TAG, "client dropped because its transport was removed:", kind)
        }
    }

    // ---------------------------------------------------------------- accept

    private fun acceptLoop(transport: BridgeTransport) {
        while (running) {
            // accept() 返回 null 即结束循环——这与重构前的行为一致
            // （重构前也是 accept 失败就 break）。
            //
            // 重试/退避**不属于本层的职责**：USB 侧一次失败就是失败；
            // LAN 拨号侧需要反复重试，由 LanDialTransport 在它自己的 accept()
            // 内部完成退避循环，只在"该 transport 已关闭"时才返回 null。
            // 这样两端都不会出现"在 Server 里空转重试"的忙等。
            val accepted = transport.accept() ?: break

            if (client != null) {
                LogX.w(TAG, "reject extra client: busy")
                sendOneShotReject(accepted, BridgeProtocol.ERR_BUSY, "Another desktop client is connected.")
                continue
            }

            handleClient(accepted, transport.kind)
        }
    }

    /**
     * @param transportKind [BridgeProtocol.TRANSPORT_USB] 或 [BridgeProtocol.TRANSPORT_LAN]。
     *   握手与欢迎帧都要按它分支——两条链路的**凭据方向是相反的**（§7.3）。
     */
    private fun handleClient(connection: BridgeConnection, transportKind: String) {
        try {
            val reader = BufferedReader(InputStreamReader(connection.input, Charsets.UTF_8))
            val writer = BufferedWriter(OutputStreamWriter(connection.output, Charsets.UTF_8))

            synchronized(writeLock) {
                client = connection
                clientKind = transportKind
                clientWriter = writer
            }
            lastFrameAt = System.currentTimeMillis()

            if (!performHandshake(transportKind, reader)) {
                return
            }

            LogX.i(TAG, "desktop client connected:", connection.remoteLabel, transportKind)
            readLoop(reader, transportKind)
        } catch (t: Throwable) {
            if (running) {
                LogX.w(TAG, "client loop ended:", "${t.message}")
            }
        } finally {
            synchronized(writeLock) {
                client = null
                clientKind = null
                clientWriter = null
            }
            // 加密是**每条连接独立**的：密钥由那条连接的会话令牌派生。
            // 不清掉的话，下一条连接会带着上一条的密钥，直接解密失败。
            cipher = null
            sessionToken = null
            connection.close()
            LogX.i(TAG, "desktop client disconnected")
        }
    }

    /** @return 握手是否通过。 */
    private fun performHandshake(transportKind: String, reader: BufferedReader): Boolean {
        val line = reader.readLine() ?: return false
        lastFrameAt = System.currentTimeMillis()

        val hello = try {
            JSONObject(line)
        } catch (t: Throwable) {
            writeFrame(rejectFrame(BridgeProtocol.ERR_PROTOCOL, "Malformed hello frame."))
            return false
        }

        if (hello.optString(BridgeProtocol.K_TYPE) != BridgeProtocol.T_HELLO) {
            writeFrame(rejectFrame(BridgeProtocol.ERR_PROTOCOL, "Expected hello frame."))
            return false
        }
        if (hello.optInt(BridgeProtocol.K_VERSION, 0) != BridgeProtocol.VERSION) {
            writeFrame(
                rejectFrame(
                    BridgeProtocol.ERR_PROTOCOL,
                    "Unsupported protocol version, expected ${BridgeProtocol.VERSION}.",
                )
            )
            return false
        }

        // 电脑主机名，配对成功后写进 PairedPcStore，手机端用来显示"已连接到谁"。
        lastClientName = hello.optString(BridgeProtocol.K_CLIENT_NAME).takeIf { it.isNotBlank() }

        // 两条链路的**校验方向相反**（§7.3）：
        //
        // - USB：可信信道是 adb，由电脑出示令牌、手机校验 —— 今天的行为，一字不改。
        // - LAN：可信信道是电脑屏幕上的 6 位码，由手机出示、**电脑校验**。
        //   所以这一侧刻意不做任何本地校验，只把凭据原样附进 welcome，让电脑去判。
        //   这样做的理由见 §7.2：电脑是监听端，必须自己校验对端，不能依赖对端自证。
        if (transportKind == BridgeProtocol.TRANSPORT_USB && requireToken) {
            val expected = tokenStore.token()
            val provided = hello.optString(BridgeProtocol.K_TOKEN)
            if (!expected.equals(provided, ignoreCase = true)) {
                LogX.w(TAG, "auth failed, token mismatch")
                writeFrame(
                    rejectFrame(
                        BridgeProtocol.ERR_AUTH,
                        "Invalid token. Run .buildScript/run_desktop_bridge.ps1 to read it from logcat.",
                    )
                )
                return false
            }
        }

        // LAN 链路：记住手机这次出示的令牌，它就是帧加密的密钥来源（§7.6）。
        // 首次配对时这里拿不到令牌（出示的是 6 位码），要等电脑用 token 帧签发。
        if (transportKind == BridgeProtocol.TRANSPORT_LAN) {
            sessionToken = (credentialProvider() as? BridgeCredential.Session)?.value
        }

        writeFrame(welcomeFrame(transportKind))
        return true
    }

    // ------------------------------------------------------------- 读帧循环

    private fun readLoop(reader: BufferedReader, transportKind: String) {
        while (running) {
            val line = try {
                reader.readLine()
            } catch (t: Throwable) {
                if (running) {
                    LogX.w(TAG, "read failed:", "${t.message}")
                }
                null
            } ?: break

            lastFrameAt = System.currentTimeMillis()
            if (line.isBlank()) {
                continue
            }
            if (line.length > BridgeProtocol.MAX_FRAME_CHARS) {
                LogX.w(TAG, "frame too large:", line.length)
                writeFrame(
                    JSONObject()
                        .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_ERR)
                        .put(BridgeProtocol.K_CODE, BridgeProtocol.ERR_PROTOCOL)
                        .put(BridgeProtocol.K_MESSAGE, "Frame too large.")
                )
                break
            }

            val frame = try {
                JSONObject(line)
            } catch (t: Throwable) {
                LogX.w(TAG, "skip malformed frame")
                continue
            }

            // 协议违规（例如解密失败）时 handleFrame 返回 false，直接断开。
            if (!handleFrame(frame, transportKind)) {
                break
            }
        }
    }

    /**
     * 分发一帧。
     *
     * 加密信封在这里拆开：外层永远是 NDJSON，`enc` 的载荷是内层明文帧，
     * 拆完再递归回来走同一套分派——**加密对上层逻辑完全透明**。
     *
     * @return false 表示协议违规，调用方应当断开连接。
     */
    private fun handleFrame(frame: JSONObject, transportKind: String): Boolean {
        when (frame.optString(BridgeProtocol.K_TYPE)) {
            BridgeProtocol.T_ENC -> {
                val active = cipher
                if (active == null) {
                    LogX.w(TAG, "收到加密帧但本端还没启用加密，断开")
                    return false
                }
                val inner = active.open(
                    frame.optLong(BridgeProtocol.K_SEQ),
                    frame.optString(BridgeProtocol.K_DATA),
                )
                if (inner == null) {
                    LogX.w(TAG, "解密失败（被篡改 / 密钥不一致 / 重放），断开")
                    return false
                }
                val innerFrame = try {
                    JSONObject(inner)
                } catch (t: Throwable) {
                    LogX.w(TAG, "解密后的内容不是 JSON，断开")
                    return false
                }
                return handleFrame(innerFrame, transportKind)
            }

            BridgeProtocol.T_CALL -> onCall(frame)
            BridgeProtocol.T_PING -> writeFrame(
                JSONObject()
                    .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_PONG)
                    .put(BridgeProtocol.K_ID, frame.optLong(BridgeProtocol.K_ID))
            )
            BridgeProtocol.T_TOKEN -> onSessionToken(frame, transportKind)
            BridgeProtocol.T_SECURED -> return onSecured(transportKind)
            BridgeProtocol.T_REJECT -> onPeerReject(frame)
            else -> LogX.w(TAG, "unknown frame type:", frame.optString(BridgeProtocol.K_TYPE))
        }
        return true
    }

    /**
     * 电脑通知"校验通过，从这里开始加密"（§7.6）。
     *
     * 它是**明文发送的最后一帧**：两端都在它之后启用帧加密，所以它自己不能是加密的。
     */
    private fun onSecured(transportKind: String): Boolean {
        if (transportKind != BridgeProtocol.TRANSPORT_LAN) {
            // USB 链路是 adb forward 过来的本地可信通道，从来不做帧加密。
            LogX.w(TAG, "usb 链路上不该出现 secured 帧，忽略")
            return true
        }
        val token = sessionToken
        if (token.isNullOrBlank()) {
            LogX.w(TAG, "收到 secured 但还没有会话令牌，断开")
            return false
        }
        val created = try {
            BridgeCipher.fromSessionToken(token)
        } catch (t: Throwable) {
            LogX.e(TAG, "派生加密密钥失败:", t)
            return false
        }
        cipher = created
        // 指纹是给排错用的：电脑端也会打一行它的**发送**密钥指纹（pc2phone），
        // 两个数字应当相同——那是同一把密钥的两个方向视角。
        // 不同就说明密钥派生有问题，问题在 HKDF / 输入，而不在 GCM 本身。
        LogX.i(TAG, "frame encryption enabled phone2pc=${created.sendKeyFingerprint}")
        return true
    }

    private fun onCall(frame: JSONObject) {
        val id = frame.optLong(BridgeProtocol.K_ID)
        val channel = frame.optString(BridgeProtocol.K_CHANNEL)
        if (channel.isEmpty()) {
            writeFrame(
                JSONObject()
                    .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_ERR)
                    .put(BridgeProtocol.K_ID, id)
                    .put(BridgeProtocol.K_CODE, BridgeProtocol.ERR_PROTOCOL)
                    .put(BridgeProtocol.K_MESSAGE, "Missing channel.")
            )
            return
        }

        val payloadBytes = decodePayload(frame)

        router.dispatch(channel, payloadBytes) { replyBuffer ->
            if (replyBuffer == null) {
                LogX.w(TAG, "no handler for channel:", channel)
                writeFrame(resultFrame(id, encodeChannelError(channel)))
            } else {
                writeFrame(resultFrame(id, BridgeBuffers.readBytes(replyBuffer)))
            }
        }
    }

    /**
     * 电脑在校验通过后下发的会话令牌（§8.3）。
     *
     * 收到即视为"配对成功"，交给 [onSessionTokenReceived] 落盘，
     * 之后的重连就走 [BridgeCredential.Session] 这条路径，不再需要用户输码。
     */
    private fun onSessionToken(frame: JSONObject, transportKind: String) {
        if (transportKind != BridgeProtocol.TRANSPORT_LAN) {
            // USB 链路的令牌方向相反（由电脑出示、手机校验），这里收到的 token 帧没有意义。
            LogX.w(TAG, "unexpected token frame on usb transport, ignored")
            return
        }
        val token = frame.optString(BridgeProtocol.K_TOKEN)
        if (token.isBlank()) {
            LogX.w(TAG, "empty session token, ignored")
            return
        }
        LogX.i(TAG, "session token issued by desktop, paired")
        // 记住它——紧接着的 secured 帧要用它派生加密密钥（§7.6）。
        sessionToken = token
        clearLastReject()
        onSessionTokenReceived(token, lastClientName)
    }

    /**
     * 电脑发来的 reject（LAN 链路上由它发出，见 §8.4 的方向规则）。
     *
     * 只记录原因供页面显示，**不在这里决定重试策略**——`code` 要停下来等用户重新输码，
     * 而 `code-stale` / `locked` / `busy` 应当继续退避重试，这个判断属于拨号那一侧。
     */
    private fun onPeerReject(frame: JSONObject) {
        val code = frame.optString(BridgeProtocol.K_CODE)
        val message = frame.optString(BridgeProtocol.K_MESSAGE)
        lastRejectCode = code.takeIf { it.isNotBlank() }
        lastRejectMessage = message.takeIf { it.isNotBlank() }
        LogX.w(TAG, "rejected by desktop:", code, message)
    }

    private fun decodePayload(frame: JSONObject): ByteArray? {        if (frame.isNull(BridgeProtocol.K_PAYLOAD)) {
            return null
        }
        val encoded = frame.optString(BridgeProtocol.K_PAYLOAD)
        if (encoded.isEmpty()) {
            return null
        }
        return try {
            Base64.decode(encoded, Base64.NO_WRAP)
        } catch (t: Throwable) {
            LogX.w(TAG, "decode payload failed:", "${t.message}")
            null
        }
    }

    // -------------------------------------------------------------- 帧构造

    private fun welcomeFrame(transportKind: String): JSONObject {
        val device = JSONObject()
            .put("model", "${Build.MANUFACTURER} ${Build.MODEL}")
            .put("android", Build.VERSION.RELEASE)
            .put("sdk", Build.VERSION.SDK_INT)
            .put("appVersion", appVersionName())

        val caps = JSONObject()
            .put("prefixes", JSONArray().put(BridgeProtocol.CHANNEL_PREFIX))
            .put("maxFrameBytes", BridgeProtocol.MAX_FRAME_CHARS)
            // 帧加密的套件名。电脑端在 LAN 链路上要求它存在（§7.6）：
            // 版本不匹配时它宁可明确拒绝，也不会静默退回明文——
            // 静默退回等于给攻击者留了一个降级开关。
            .put(BridgeProtocol.K_CIPHER, BridgeProtocol.CIPHER_A256GCM)

        val frame = JSONObject()
            .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_WELCOME)
            .put(BridgeProtocol.K_VERSION, BridgeProtocol.VERSION)
            .put(BridgeProtocol.K_DEVICE, device)
            .put(BridgeProtocol.K_CAPS, caps)
            .put(BridgeProtocol.K_TRANSPORT, transportKind)

        if (transportKind == BridgeProtocol.TRANSPORT_LAN) {
            frame.put(BridgeProtocol.K_DEVICE_ID, deviceIdProvider())

            // LAN 链路要由**手机**出示凭据（§7.3）；USB 链路不带这两个字段，
            // 因为那条链路上是电脑出示令牌、手机校验。
            when (val credential = credentialProvider()) {
                is BridgeCredential.Code -> frame.put(BridgeProtocol.K_CODE, credential.value)
                is BridgeCredential.Session -> frame.put(BridgeProtocol.K_TOKEN, credential.value)
                // 没有凭据时什么都不放：电脑会按 §7.4 回 reject(code)，
                // 这正是"手机还没拿到码就抢先拨号"时应有的结果。
                null -> Unit
            }
        }

        return frame
    }

    private fun rejectFrame(code: String, message: String): JSONObject =
        JSONObject()
            .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_REJECT)
            .put(BridgeProtocol.K_CODE, code)
            .put(BridgeProtocol.K_MESSAGE, message)

    private fun resultFrame(id: Long, bytes: ByteArray): JSONObject =
        JSONObject()
            .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_RET)
            .put(BridgeProtocol.K_ID, id)
            .put(BridgeProtocol.K_PAYLOAD, Base64.encodeToString(bytes, Base64.NO_WRAP))

    /**
     * 通道没有 Handler 时，按 Pigeon 的错误载荷格式构造 [code, message, details]，
     * 这样桌面端的生成代码会抛出与真机一致的 PlatformException，UI 的既有错误分支不用改。
     */
    private fun encodeChannelError(channel: String): ByteArray {
        val message = "Unable to establish connection on channel: \"$channel\"."
        val encoded: ByteBuffer? = try {
            StandardMessageCodec().encodeMessage(
                listOf(BridgeProtocol.PIGEON_CHANNEL_ERROR, message, null)
            )
        } catch (t: Throwable) {
            LogX.e(TAG, "encode channel error failed:", t)
            null
        }
        return encoded?.let { BridgeBuffers.readBytes(it) } ?: ByteArray(0)
    }

    private fun writeFrame(frame: JSONObject) {
        val executor = writeExecutor ?: return
        val writer = synchronized(writeLock) { clientWriter } ?: return

        val plaintext = frame.toString()
        // 加密状态在**调用线程**取一次快照：决定要不要加密要看这一帧产生时的状态。
        val active = cipher

        executor.execute {
            // 加密放进这个**单线程** executor 里做——加密序号必须与写入顺序严格一致。
            // writeFrame 有两个调用线程（主线程回 Pigeon 结果、读帧线程回 pong），
            // 若在调用线程加密，两边可能分别拿到序号 5 和 6，却按 6、5 的顺序落盘，
            // 对端会因为"计数器回退"把后到的那帧当成重放拒掉。
            val line = try {
                (if (active == null) plaintext else active.seal(plaintext)) + "\n"
            } catch (t: Throwable) {
                // 加密失败是**致命**的：不能退回明文发出去（那是静默降级），
                // 也不能只记一笔日志——那会表现为"帧根本没出去、对端等不到响应
                // 然后断开"，安静得查不出来。这里直接断开，让重连把问题暴露出来。
                LogX.e(TAG, "seal frame failed, closing connection:", t)
                closeQuietly(client)
                return@execute
            }
            synchronized(writeLock) {
                try {
                    writer.write(line)
                    writer.flush()
                } catch (t: Throwable) {
                    LogX.w(TAG, "write failed:", "${t.message}")
                }
            }
        }
    }

    /** 握手阶段拒绝额外连接时，客户端 writer 还没登记，只能单独写一次。 */
    private fun sendOneShotReject(connection: BridgeConnection, code: String, message: String) {
        try {
            val writer = BufferedWriter(OutputStreamWriter(connection.output, Charsets.UTF_8))
            writer.write(rejectFrame(code, message).toString())
            writer.write("\n")
            writer.flush()
        } catch (t: Throwable) {
            LogX.w(TAG, "send reject failed:", "${t.message}")
        } finally {
            connection.close()
        }
    }

    private fun checkIdleTimeout() {
        val current = client ?: return
        val elapsed = System.currentTimeMillis() - lastFrameAt
        if (elapsed > BridgeProtocol.IDLE_TIMEOUT_MS) {
            LogX.w(TAG, "idle timeout, closing client:", elapsed)
            closeQuietly(current)
        }
    }

    private fun appVersionName(): String {
        return try {
            appContext.packageManager
                .getPackageInfo(appContext.packageName, 0)
                .versionName ?: ""
        } catch (t: Throwable) {
            ""
        }
    }

    private fun closeQuietly(connection: BridgeConnection?) {
        try {
            connection?.close()
        } catch (_: Throwable) {
            // 忽略关闭异常
        }
    }
}
