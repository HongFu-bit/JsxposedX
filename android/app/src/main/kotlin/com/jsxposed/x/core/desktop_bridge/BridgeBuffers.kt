package com.jsxposed.x.core.desktop_bridge

import java.nio.ByteBuffer

/**
 * Pigeon 载荷与 socket 字节之间的转换工具。
 *
 * 两个必须注意的约束（否则消息会变成空载荷）：
 * 1. 交给 Flutter 引擎的 ByteBuffer **必须是 direct buffer**，引擎通过 JNI 的
 *    GetDirectBufferAddress 取数据，非 direct buffer 会取不到内容。
 * 2. 引擎按 buffer 的 position 到 limit 读取，所以写入后必须把 position 归零。
 */
internal object BridgeBuffers {

    /** socket 收到的字节 → 交给引擎的 direct buffer。 */
    fun toDirectBuffer(bytes: ByteArray): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(bytes.size)
        buffer.put(bytes)
        buffer.position(0)
        return buffer
    }

    /**
     * 引擎回包 → 字节。
     *
     * 不同 Flutter 版本对回包 buffer 的 position 处理不完全一致（有的已 flip、有的停在末尾），
     * 因此这里对"position 已到 limit"的情况做一次归零兜底。
     */
    fun readBytes(buffer: ByteBuffer): ByteArray {
        val duplicate = buffer.duplicate()
        if (duplicate.limit() > 0 && duplicate.position() == duplicate.limit()) {
            duplicate.position(0)
        }
        val out = ByteArray(duplicate.remaining())
        duplicate.get(out)
        return out
    }
}
