package com.jsxposed.x.core.desktop_bridge

import android.content.Context
import android.net.LocalServerSocket
import android.net.LocalSocket
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
 * 职责：监听抽象命名空间 socket → 校验令牌 → 收发 NDJSON 帧 → 把调用交给 [BridgeChannelRouter]。
 * 只允许一个桌面客户端同时连接（第二个连接收到 reject(busy)）。
 *
 * 线程模型：
 * - accept / 读帧：独立守护线程
 * - Pigeon 派发与回包：走 Flutter 主线程（[BridgeChannelRouter] 内部处理）
 * - 写帧：单线程 executor，避免大载荷回包阻塞 UI 线程
 */
internal class DesktopBridgeServer(
    context: Context,
    private val router: BridgeChannelRouter,
    private val tokenStore: DesktopBridgeTokenStore,
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

    @Volatile
    private var client: LocalSocket? = null

    @Volatile
    private var clientWriter: BufferedWriter? = null

    private var serverSocket: LocalServerSocket? = null
    private var acceptThread: Thread? = null
    private var scheduler: ScheduledExecutorService? = null
    private var writeExecutor: ExecutorService? = null

    fun isRunning(): Boolean = running

    fun start() {
        if (running) {
            return
        }
        try {
            serverSocket = LocalServerSocket(BridgeProtocol.SOCKET_NAME)
        } catch (t: Throwable) {
            LogX.e(TAG, "bind socket failed:", BridgeProtocol.SOCKET_NAME, t)
            return
        }

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
        acceptThread = thread(isDaemon = true, name = "jsxposed-bridge-accept") { acceptLoop() }

        LogX.i(TAG, "listening on abstract socket:", BridgeProtocol.SOCKET_NAME)
        // token 通过 logcat 暴露给 adb 侧，启动脚本会读取这一行。
        LogX.i(TAG, "token=${tokenStore.token()}")
    }

    fun stop() {
        if (!running) {
            return
        }
        running = false

        scheduler?.shutdownNow()
        scheduler = null
        writeExecutor?.shutdownNow()
        writeExecutor = null

        closeQuietly(serverSocket)
        serverSocket = null

        val current = client
        client = null
        clientWriter = null
        closeQuietly(current)

        acceptThread = null
        LogX.i(TAG, "stopped")
    }

    // ---------------------------------------------------------------- accept

    private fun acceptLoop() {
        while (running) {
            val accepted = try {
                serverSocket?.accept()
            } catch (t: Throwable) {
                if (running) {
                    LogX.e(TAG, "accept failed:", t)
                }
                null
            } ?: break

            if (client != null) {
                LogX.w(TAG, "reject extra client: busy")
                sendOneShotReject(accepted, BridgeProtocol.ERR_BUSY, "Another desktop client is connected.")
                continue
            }

            handleClient(accepted)
        }
    }

    private fun handleClient(socket: LocalSocket) {
        try {
            val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
            val writer = BufferedWriter(OutputStreamWriter(socket.outputStream, Charsets.UTF_8))

            synchronized(writeLock) {
                client = socket
                clientWriter = writer
            }
            lastFrameAt = System.currentTimeMillis()

            if (!performHandshake(reader)) {
                return
            }

            LogX.i(TAG, "desktop client connected")
            readLoop(reader)
        } catch (t: Throwable) {
            if (running) {
                LogX.w(TAG, "client loop ended:", "${t.message}")
            }
        } finally {
            synchronized(writeLock) {
                client = null
                clientWriter = null
            }
            closeQuietly(socket)
            LogX.i(TAG, "desktop client disconnected")
        }
    }

    /** @return 握手是否通过。 */
    private fun performHandshake(reader: BufferedReader): Boolean {
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
        if (requireToken) {
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

        writeFrame(welcomeFrame())
        return true
    }

    // ------------------------------------------------------------- 读帧循环

    private fun readLoop(reader: BufferedReader) {
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

            when (frame.optString(BridgeProtocol.K_TYPE)) {
                BridgeProtocol.T_CALL -> onCall(frame)
                BridgeProtocol.T_PING -> writeFrame(
                    JSONObject()
                        .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_PONG)
                        .put(BridgeProtocol.K_ID, frame.optLong(BridgeProtocol.K_ID))
                )
                else -> LogX.w(TAG, "unknown frame type:", frame.optString(BridgeProtocol.K_TYPE))
            }
        }
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

    private fun decodePayload(frame: JSONObject): ByteArray? {
        if (frame.isNull(BridgeProtocol.K_PAYLOAD)) {
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

    private fun welcomeFrame(): JSONObject {
        val device = JSONObject()
            .put("model", "${Build.MANUFACTURER} ${Build.MODEL}")
            .put("android", Build.VERSION.RELEASE)
            .put("sdk", Build.VERSION.SDK_INT)
            .put("appVersion", appVersionName())

        val caps = JSONObject()
            .put("prefixes", JSONArray().put(BridgeProtocol.CHANNEL_PREFIX))
            .put("maxFrameBytes", BridgeProtocol.MAX_FRAME_CHARS)

        return JSONObject()
            .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_WELCOME)
            .put(BridgeProtocol.K_VERSION, BridgeProtocol.VERSION)
            .put(BridgeProtocol.K_DEVICE, device)
            .put(BridgeProtocol.K_CAPS, caps)
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
        val line = frame.toString() + "\n"
        executor.execute {
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
    private fun sendOneShotReject(socket: LocalSocket, code: String, message: String) {
        try {
            val writer = BufferedWriter(OutputStreamWriter(socket.outputStream, Charsets.UTF_8))
            writer.write(rejectFrame(code, message).toString())
            writer.write("\n")
            writer.flush()
        } catch (t: Throwable) {
            LogX.w(TAG, "send reject failed:", "${t.message}")
        } finally {
            closeQuietly(socket)
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

    private fun closeQuietly(socket: LocalSocket?) {
        try {
            socket?.close()
        } catch (_: Throwable) {
            // 忽略关闭异常
        }
    }

    private fun closeQuietly(server: LocalServerSocket?) {
        try {
            server?.close()
        } catch (_: Throwable) {
            // 忽略关闭异常
        }
    }
}
