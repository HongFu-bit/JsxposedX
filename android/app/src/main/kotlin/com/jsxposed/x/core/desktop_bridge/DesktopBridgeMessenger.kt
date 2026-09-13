package com.jsxposed.x.core.desktop_bridge

import com.jsxposed.x.core.utils.log.LogX
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap

/**
 * 扇出 messenger：让 Pigeon 的 handler 同时服务于「手机 UI」和「桌面端 bridge」。
 *
 * ── 为什么需要这个类（关键实现细节）────────────────────────────────────────
 * Flutter 的 `BinaryMessenger.send()` 是「平台 → Dart」方向。而 Pigeon 生成代码注册的
 * handler 属于「Dart → 平台」方向（由引擎在收到 Dart 消息时调用 `handleMessageFromDart` 触发）。
 * 所以**不能**用引擎 messenger 的 `send()` 去调用 Pigeon handler——那条路径只会去找 Dart 侧
 * 的 handler（本仓库没有任何 FlutterApi，也就没有 Dart 侧 handler），结果是拿到 null。
 *
 * 正确做法：把 Pigeon 的 handler 注册到本类上。`NativeProvider.registerAll()` 收到本类实例后，
 * Pigeon 的 `setUp()` 会把每个通道的 handler 交给本类：
 *   - 存进本地注册表 → 桌面端 bridge 通过 [dispatch] 直接调用；
 *   - 同时转发给引擎 messenger → 手机 App 自己的 UI 调用照旧走原生链路，完全不受影响。
 *
 * 由于两边的调用最终落到**同一批 Impl 实例**上，桌面端与手机端看到的状态、会话、数据必然一致
 * （不会出现"两套业务对象"）。
 *
 * 注意：`send()` 这两个重载在本方案里不会真正被用到（没人从平台侧向 Dart 发消息），
 * 实现它们只是为了满足接口契约。
 */
internal class DesktopBridgeMessenger(
    private val engineMessenger: BinaryMessenger,
) : BinaryMessenger {

    private companion object {
        const val TAG = BridgeProtocol.LOG_TAG
    }

    /** channel → Pigeon 为该方法注册的 handler */
    private val handlers =
        ConcurrentHashMap<String, BinaryMessenger.BinaryMessageHandler>()

    // ------------------------------------------------------------ 接口实现

    override fun send(channel: String, message: ByteBuffer?) {
        send(channel, message, null)
    }

    override fun send(
        channel: String,
        message: ByteBuffer?,
        callback: BinaryMessenger.BinaryReply?,
    ) {
        val handler = handlers[channel]
        if (handler == null) {
            callback?.reply(null)
            return
        }

        try {
            handler.onMessage(
                message,
                BinaryMessenger.BinaryReply { reply -> callback?.reply(reply) },
            )
        } catch (t: Throwable) {
            LogX.e(TAG, "handler failed:", channel, t)
            callback?.reply(null)
        }
    }

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?,
    ) {
        if (handler == null) {
            handlers.remove(channel)
        } else {
            handlers[channel] = handler
        }

        // 手机端 UI 仍然通过引擎 messenger 调用原生能力，必须同步注册过去。
        engineMessenger.setMessageHandler(channel, handler)
    }

    // --------------------------------------------------------- 桌面端入口

    /**
     * 向本机已注册的 Pigeon handler 投递一次调用。
     *
     * @param bytes Pigeon 编码后的请求载荷，可为 null（Dart 侧无参方法就是发 null）
     * @param onReply 回调收到的字节即为 Pigeon 回包；**null 表示该通道没有 handler**，
     *                由调用方转换成 Pigeon 的 channel-error 载荷。
     */
    fun dispatch(channel: String, bytes: ByteArray?, onReply: (ByteBuffer?) -> Unit) {
        val handler = handlers[channel]
        if (handler == null) {
            LogX.w(TAG, "no handler registered for channel:", channel)
            onReply(null)
            return
        }

        try {
            val payload = bytes?.let { BridgeBuffers.toDirectBuffer(it) }
            handler.onMessage(
                payload,
                BinaryMessenger.BinaryReply { reply -> onReply(reply) },
            )
        } catch (t: Throwable) {
            LogX.e(TAG, "dispatch failed:", channel, t)
            onReply(null)
        }
    }

    /** 该通道是否已经有 Pigeon handler（用于诊断与文档说明）。 */
    fun hasChannel(channel: String): Boolean = handlers.containsKey(channel)

    /** 当前已注册的通道数量（用于诊断）。 */
    fun channelCount(): Int = handlers.size
}
