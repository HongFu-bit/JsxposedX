package com.jsxposed.x.core.desktop_bridge

import android.util.Base64
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * 帧级加密：把每个 bridge 帧整体用 AES-256-GCM 封装。
 *
 * **本文件必须与电脑侧的 `lib/desktop/bridge/bridge_cipher.dart` 逐字对应**：
 * 相同的 salt / info 标签 / AAD、相同的 HKDF、相同的 nonce 构造、相同的
 * `密文||tag` 输出格式。任何一处不一致都表现为"连上就断"——因为 GCM 校验失败
 * 是静默的（解密返回 null），不会告诉你差在哪。
 *
 * ## 密钥从哪来
 *
 * 用**电脑签发的会话令牌**（32 字节）当共享密钥，两端各自 HKDF-SHA256
 * 派生两条方向独立的密钥。必须分方向：GCM 的 nonce 在同一把密钥下重复
 * 会直接摧毁安全性，而两个方向都从计数器 1 开始，不分密钥必然撞。
 *
 * ## 局限
 *
 * **首次配对那一次是明文的**（包括会话令牌本身的传输）。所以它挡的是
 * "长期同网段的旁观者"，挡不住"正好在你配对时蹲守的人"。见文档 §7.6。
 */
internal class BridgeCipher private constructor(
    private val sendKey: ByteArray,
    private val receiveKey: ByteArray,
) {

    /** 本端发出帧的计数器，从 1 开始。 */
    private var sendSeq = 0L

    /** 对端发来帧的最大计数器，用来挡重放。 */
    private var lastReceiveSeq = 0L

    /**
     * 派生出的**发送密钥**的指纹（SHA-256 前 8 个 hex 字符）。纯诊断用。
     *
     * 加密相关的故障大多是"两端密钥不一致"，而那种失败是静默的（GCM 校验
     * 不通过就返回 null），日志里只会看到"连上就断"。两端各打一行指纹即可判断。
     * 泄漏它无害——SHA-256 不可逆。
     */
    val sendKeyFingerprint: String
        get() = MessageDigest.getInstance("SHA-256")
            .digest(sendKey)
            .take(4)
            .joinToString("") { "%02x".format(it) }

    /** 把一帧明文 JSON 封装成外层 `enc` 帧的 JSON 文本。 */
    fun seal(plaintextJson: String): String {
        sendSeq++
        val seq = sendSeq
        val sealed = gcm(
            forEncryption = true,
            key = sendKey,
            nonce = nonceFor(seq),
            input = plaintextJson.toByteArray(Charsets.UTF_8),
        )
        return JSONObject()
            .put(BridgeProtocol.K_TYPE, BridgeProtocol.T_ENC)
            .put(BridgeProtocol.K_SEQ, seq)
            .put(BridgeProtocol.K_DATA, Base64.encodeToString(sealed, Base64.NO_WRAP))
            .toString()
    }

    /**
     * 解开一个外层 `enc` 帧，返回内层明文 JSON 文本。
     *
     * 解密失败（被篡改、密钥不一致、计数器回退）时返回 null——
     * 调用方应当把它当作协议违规直接断开，不要继续用这条连接。
     */
    fun open(seq: Long, base64Data: String): String? {
        if (seq <= lastReceiveSeq) {
            // 正常的 TCP 流不会乱序，收到回退的计数器意味着有人在重放旧帧。
            return null
        }
        val sealed = try {
            Base64.decode(base64Data, Base64.NO_WRAP)
        } catch (t: Throwable) {
            return null
        }
        val plain = try {
            gcm(
                forEncryption = false,
                key = receiveKey,
                nonce = nonceFor(seq),
                input = sealed,
            )
        } catch (t: Throwable) {
            return null
        }
        lastReceiveSeq = seq
        return String(plain, Charsets.UTF_8)
    }

    /**
     * 自检：用一把**一次性密钥**把一段探针加密再解回来，验证本端的 GCM 实现自洽。
     *
     * 不用真实密钥，是为了避免占用一个 nonce——GCM 下 nonce 复用是灾难性的。
     * 一次性密钥足以覆盖这里要验的东西：本端实现是否自洽。
     *
     * 它**验不出**跨语言差异（nonce 构造、AAD、HKDF 输入是否与 Dart 侧一致），
     * 那要靠两端各打一行的密钥指纹去比对。
     */
    private fun verifySelfTest() {
        val probeKey = ByteArray(KEY_BYTES) { 0x5A }
        val nonce = ByteArray(NONCE_BYTES) { 0x5A }
        val probe = "jsxposedx-bridge-selftest".toByteArray(Charsets.UTF_8)

        val sealed = gcm(
            forEncryption = true,
            key = probeKey,
            nonce = nonce,
            input = probe,
        )
        val expected = probe.size + TAG_BITS / 8
        require(sealed.size == expected) {
            "GCM 自检失败：密文 ${sealed.size} 字节，期望 $expected（密文应为「明文 + 16 字节 tag」）"
        }

        val opened = gcm(
            forEncryption = false,
            key = probeKey,
            nonce = nonce,
            input = sealed,
        )
        require(opened.contentEquals(probe)) {
            "GCM 自检失败：解密结果与明文不一致"
        }
    }

    /** 12 字节 nonce = 4 字节 0 前缀 + 8 字节大端计数器。 */
    private fun nonceFor(seq: Long): ByteArray {
        val nonce = ByteArray(NONCE_BYTES)
        val buffer = ByteBuffer.wrap(nonce)
        buffer.position(4)
        buffer.putLong(seq) // ByteBuffer 默认大端，与 Dart 的 Endian.big 一致
        return nonce
    }

    /** 加密时返回 `密文||tag`；解密时同样以 `密文||tag` 为输入（与 Dart 侧一致）。 */
    private fun gcm(
        forEncryption: Boolean,
        key: ByteArray,
        nonce: ByteArray,
        input: ByteArray,
    ): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            if (forEncryption) Cipher.ENCRYPT_MODE else Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(TAG_BITS, nonce),
        )
        cipher.updateAAD(AAD)
        return cipher.doFinal(input)
    }

    internal companion object {
        // ── 与 bridge_cipher.dart 必须逐字一致 ──
        private const val SALT = "jsxposedx-bridge-v1-salt"
        private const val INFO_PC2_PHONE = "jsxposedx-bridge-v1/pc2phone"
        private const val INFO_PHONE2_PC = "jsxposedx-bridge-v1/phone2pc"

        private const val NONCE_BYTES = 12
        private const val TAG_BITS = 128
        private const val KEY_BYTES = 32

        /** 认证但不加密的附加数据；它同时锁定了协议版本与算法套件。 */
        private val AAD = "JsxposedX-Bridge/v1/A256GCM".toByteArray(Charsets.UTF_8)

        /**
         * 从会话令牌派生密钥。
         *
         * 注意方向与电脑侧**相反**：手机发出的用 `phone2pc`，收的用 `pc2phone`。
         *
         * **派生完立刻做一次自检**（[verifySelfTest]），失败会抛异常。
         * 调用方应当把它当作致命错误：加密实现坏了的话，最好的结果是当场报错，
         * 最坏的结果是安静地连上又断开——而那正是最难查的一种故障。
         *
         * @throws IllegalArgumentException 令牌不是 64 个 hex 字符。
         */
        internal fun fromSessionToken(sessionToken: String): BridgeCipher {
            val ikm = decodeHex(sessionToken)
            val cipher = BridgeCipher(
                sendKey = hkdf(ikm, INFO_PHONE2_PC.toByteArray(Charsets.UTF_8)),
                receiveKey = hkdf(ikm, INFO_PC2_PHONE.toByteArray(Charsets.UTF_8)),
            )
            cipher.verifySelfTest()
            return cipher
        }

        /** HKDF-SHA256（RFC 5869）。输出固定 32 字节，因此 expand 只跑一轮。 */
        private fun hkdf(ikm: ByteArray, info: ByteArray): ByteArray {
            val mac = Mac.getInstance("HmacSHA256")

            // extract
            mac.init(SecretKeySpec(SALT.toByteArray(Charsets.UTF_8), "HmacSHA256"))
            val prk = mac.doFinal(ikm)

            // expand：T(1) = HMAC(PRK, info || 0x01)
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(info)
            mac.update(byteArrayOf(0x01))
            return mac.doFinal().copyOf(KEY_BYTES)
        }

        private fun decodeHex(hex: String): ByteArray {
            val clean = hex.trim()
            require(clean.length == 64) {
                "会话令牌应是 64 个 hex 字符，实际 ${clean.length} 个"
            }
            val out = ByteArray(32)
            for (i in 0 until 32) {
                out[i] = clean.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
            return out
        }
    }
}
