package com.jsxposed.x.core.bridge.lan_bridge_native

import android.content.Context
import com.jsxposed.x.core.desktop_bridge.DesktopBridgeManager

/**
 * [LanBridgeNative] 的实现：把 Dart 侧的调用转给 [DesktopBridgeManager]。
 *
 * 这里刻意不做任何业务判断——拨号、凭据、限速、落盘全在
 * `core/desktop_bridge/` 里，本类只是一层很薄的转接，
 * 这样"桌面端连上手机后也能读到这套状态"这件事自动成立（隧道只认通道名）。
 *
 * 注意 Pigeon 会把 Dart 的 `int` 映射成 Kotlin 的 `Long`，所以端口参数是 Long。
 */
class LanBridgeNativeImpl(private val context: Context) : LanBridgeNative {

    override fun getStatus(): LanBridgeStatus {
        val manager = DesktopBridgeManager
        return LanBridgeStatus(
            usbConnected = manager.isUsbConnected(),
            lanConnected = manager.isLanConnected(),
            hasTarget = manager.hasLanTarget(),
            targetHost = manager.lanTargetHost(),
            targetPort = manager.lanTargetPort().toLong(),
            peerName = manager.lanPeerName(),
            lastRejectCode = manager.lastRejectCode(),
            lastRejectMessage = manager.lastRejectMessage(),
            autoReconnect = manager.isAutoReconnect(),
        )
    }

    override fun connectWithCode(host: String, port: Long, code: String) {
        DesktopBridgeManager.connectWithCode(
            host = host.trim(),
            port = port.toInt(),
            code = code.trim(),
        )
    }

    override fun reconnectTo(host: String, port: Long) {
        val target = DesktopBridgeManager.pairedPcs()
            .firstOrNull { it.host == host && it.port == port.toInt() }
        if (target == null) {
            // 记录已经被删掉了（例如用户在另一端忘了这台电脑），什么都不做；
            // 页面下一次轮询就会看到 hasTarget 仍是 false。
            return
        }
        DesktopBridgeManager.connectWithSession(target)
    }

    override fun disconnect() {
        DesktopBridgeManager.disconnectLan()
    }

    override fun listPairedPcs(): List<LanPairedPc> =
        DesktopBridgeManager.pairedPcs().map { pc ->
            LanPairedPc(
                name = pc.name,
                host = pc.host,
                port = pc.port.toLong(),
                lastConnectedAtMs = pc.lastConnectedAtMs,
            )
        }

    override fun forgetPc(host: String, port: Long): Boolean =
        DesktopBridgeManager.forgetPc(host = host, port = port.toInt())

    override fun forgetAllPcs() {
        DesktopBridgeManager.forgetAllPcs()
    }

    override fun setAutoReconnect(enabled: Boolean) {
        DesktopBridgeManager.setAutoReconnect(enabled)
    }
}
