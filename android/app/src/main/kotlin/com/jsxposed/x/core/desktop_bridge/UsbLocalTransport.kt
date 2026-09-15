package com.jsxposed.x.core.desktop_bridge

import android.net.LocalServerSocket
import android.net.LocalSocket
import com.jsxposed.x.core.utils.log.LogX
import java.io.InputStream
import java.io.OutputStream

/**
 * USB 链路的 transport：监听**抽象命名空间** socket，等待 `adb forward` 过来的连接。
 *
 * 本类是从重构前的 [DesktopBridgeServer] 里原样搬出来的，行为没有任何变化——
 * 尤其是：socket 只绑抽象命名空间，不出现在网络栈上，因此外部网络访问不到它
 * （这也是 USB 链路的令牌只需要防"手机上的其他 App"的原因，
 * 见 [DesktopBridgeTokenStore] 的类注释）。
 */
internal class UsbLocalTransport(
    private val socketName: String,
) : BridgeTransport {

    private companion object {
        const val TAG = BridgeProtocol.LOG_TAG
    }

    @Volatile
    private var closed = false

    private var serverSocket: LocalServerSocket? = null

    override val kind: String = BridgeProtocol.TRANSPORT_USB

    override fun start() {
        // 失败时抛出，由 DesktopBridgeServer.start() 决定是否致命（与重构前一致）。
        serverSocket = LocalServerSocket(socketName)
        // 这一行是既有排错契约：docs/desktop_bridge_CN.md §15 与
        // .buildScript/run_desktop_bridge.ps1 都按这个字符串判断 bridge 是否就绪。
        LogX.i(TAG, "listening on abstract socket:", socketName)
    }

    override fun accept(): BridgeConnection? {
        val server = serverSocket ?: return null

        val accepted = try {
            server.accept()
        } catch (t: Throwable) {
            if (!closed) {
                LogX.e(TAG, "[usb] accept failed:", t)
            }
            // 关闭导致的 accept 异常与真正的失败在这里无法区分，
            // 统一返回 null 让上层结束循环；running 标志会决定是否继续重试。
            return null
        }

        return LocalSocketConnection(accepted)
    }

    override fun close() {
        closed = true
        val server = serverSocket
        serverSocket = null
        try {
            server?.close()
        } catch (_: Throwable) {
            // 忽略关闭异常
        }
    }

    /** [BridgeConnection] 的抽象命名空间 socket 实现。 */
    private class LocalSocketConnection(
        private val socket: LocalSocket,
    ) : BridgeConnection {

        override val remoteLabel: String = BridgeProtocol.TRANSPORT_USB

        // getter 而非字段：与重构前一样，把"取流"留到调用方的 try 块里，
        // 这样 socket 已关闭时抛出的 IOException 能被 handleClient 捕获。
        override val input: InputStream
            get() = socket.inputStream

        override val output: OutputStream
            get() = socket.outputStream

        override fun close() {
            try {
                socket.close()
            } catch (_: Throwable) {
                // 忽略关闭异常
            }
        }
    }
}
