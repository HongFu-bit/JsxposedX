package com.jsxposed.x.core.desktop_bridge

import com.jsxposed.x.core.utils.log.LogX
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Wi-Fi 链路的 transport：**手机主动向电脑发起连接**。
 *
 * 这是"连接方向反转"的落点——电脑是监听端，手机是拨号端。参见
 * docs/desktop_bridge_lan_CN.md §6.2：把 [BridgeTransport.accept] 的语义定义成
 * "取得一条可用连接"之后，本类就只是"拨号成功就返回那条连接"，
 * 而 [DesktopBridgeServer] 拿到连接后做的事情（读 hello、回 welcome）
 * 在反转后的拓扑里恰好仍然成立——电脑发 hello、手机回 welcome。
 *
 * 三个要点（对应文档 §6.4）：
 *
 * 1. **目标不可变**：目标在构造时确定。换目标 = 关掉本 transport、用新目标建一个，
 *    由调用方（[DesktopBridgeManager]）负责，这样就不需要在阻塞拨号期间做热切换。
 * 2. **已有连接时不拨号**：通过 [canDial] 谓词询问服务端。若不这样做，会出现
 *    "手机主动连上去、又被自己的单客户端约束以 busy 拒掉"这种怪状态。
 * 3. **失败退避**：1s → 2s → 4s … 上限 [MAX_BACKOFF_MS]。退避循环在本类内部完成，
 *    因此 [accept] 只在 transport 被关闭时才返回 null，
 *    服务端的 accept 循环不会出现忙等重试。
 */
internal class LanDialTransport(
    private val host: String,
    private val port: Int,
    private val canDial: () -> Boolean,
) : BridgeTransport {

    private companion object {
        const val TAG = BridgeProtocol.LOG_TAG

        /** 单次 connect 的超时。同网段正常在毫秒级，5 秒已经很宽松。 */
        const val CONNECT_TIMEOUT_MS = 5_000

        /** 退避上限。 */
        const val MAX_BACKOFF_MS = 30_000L

        /** 等待"服务端空闲"时的轮询间隔。 */
        const val IDLE_POLL_MS = 500L
    }

    override val kind: String = BridgeProtocol.TRANSPORT_LAN

    @Volatile
    private var closed = false

    override fun start() {
        // 拨号型 transport 没有"绑定"这一步，目标在构造时就已经确定。
        // 保留这个方法是契约要求，也便于将来在此做目标可达性的预检。
        LogX.i(TAG, "[lan] target:", "$host:$port")
    }

    override fun accept(): BridgeConnection? {
        var backoffMs = 1_000L

        while (!closed) {
            // 服务端已有客户端（例如 USB 那条链路正连着）时不拨号，等一等。
            if (!canDial()) {
                if (!sleepInterruptibly(IDLE_POLL_MS)) {
                    break
                }
                continue
            }

            val socket = Socket()
            try {
                socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                socket.tcpNoDelay = true
                LogX.i(TAG, "[lan] connected:", "$host:$port")
                return TcpConnection(socket, "$host:$port")
            } catch (t: Throwable) {
                try {
                    socket.close()
                } catch (_: Throwable) {
                    // 忽略关闭异常
                }
                if (closed) {
                    break
                }
                LogX.w(TAG, "[lan] dial failed, retry in ${backoffMs}ms:", "${t.message}")
                if (!sleepInterruptibly(backoffMs)) {
                    break
                }
                backoffMs = (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
            }
        }

        return null
    }

    override fun close() {
        closed = true
    }

    /** @return false 表示 transport 已关闭、调用方应退出循环。 */
    private fun sleepInterruptibly(durationMs: Long): Boolean {
        var remaining = durationMs
        while (remaining > 0) {
            if (closed) {
                return false
            }
            val slice = remaining.coerceAtMost(200L)
            try {
                Thread.sleep(slice)
            } catch (t: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
            remaining -= slice
        }
        return !closed
    }

    /** [BridgeConnection] 的 TCP 实现。 */
    private class TcpConnection(
        private val socket: Socket,
        override val remoteLabel: String,
    ) : BridgeConnection {

        override val input: InputStream
            get() = socket.getInputStream()

        override val output: OutputStream
            get() = socket.getOutputStream()

        override fun close() {
            try {
                socket.close()
            } catch (_: Throwable) {
                // 忽略关闭异常
            }
        }
    }
}
