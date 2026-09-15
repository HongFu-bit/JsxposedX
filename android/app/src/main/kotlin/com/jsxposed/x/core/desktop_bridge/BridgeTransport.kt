package com.jsxposed.x.core.desktop_bridge

import java.io.InputStream
import java.io.OutputStream

/**
 * 一条已建立的 bridge 连接。
 *
 * 只暴露字节流与一个描述字符串——上层（[DesktopBridgeServer] 的握手、分帧、心跳）
 * 不关心这条连接是 USB 来的还是 Wi-Fi 来的。见 docs/desktop_bridge_lan_CN.md §6。
 *
 * **关于 [input] / [output] 为什么是 getter 而不是构造期字段**：
 * 两个平台实现（`LocalSocket` / `Socket`）的流对象都是首次访问时才创建、
 * 之后缓存复用的，而创建过程本身可能抛 IOException（例如 socket 已被关闭）。
 * 保持 getter 可以让"取流"这件事发生在调用方的 try 块里，与重构前的行为一致
 * （重构前 `handleClient` 就是在 try 里创建 Reader/Writer 的）。
 */
internal interface BridgeConnection {

    /** 对端描述，仅用于日志。USB 是 `usb`，LAN 是 `电脑IP:端口`。 */
    val remoteLabel: String

    val input: InputStream

    val output: OutputStream

    fun close()
}

/**
 * 连接来源的抽象。
 *
 * **注意 [accept] 的语义是"取得一条可用连接"，不承诺它是入站还是出站。**
 * 这一点是本方案能用很小的代价支持"手机主动拨号"的关键：
 * - [UsbLocalTransport] 的实现是阻塞等待 adb forward 过来的入站连接；
 * - `LanDialTransport` 的实现是主动向电脑发起 connect，成功就返回那条连接。
 *
 * 而 [DesktopBridgeServer] 拿到连接后做的事情（读 hello、回 welcome）在两种拓扑下
 * 都成立——反转后的拓扑里电脑恰好就是发 hello 的一方、手机恰好就是回 welcome 的一方。
 * 见 docs/desktop_bridge_lan_CN.md §6.2。
 */
internal interface BridgeTransport {

    /** 传输类型，取值见 [BridgeProtocol.TRANSPORT_USB] / [BridgeProtocol.TRANSPORT_LAN]。 */
    val kind: String

    /** 开始监听或准备拨号。失败时抛异常，由调用方决定是否致命。 */
    fun start()

    /**
     * 阻塞直到取得一条连接。
     *
     * @return `null` 表示该 transport 已关闭，调用方应结束 accept 循环。
     */
    fun accept(): BridgeConnection?

    /** 关闭并让阻塞中的 [accept] 尽快返回 null。可重复调用。 */
    fun close()
}
