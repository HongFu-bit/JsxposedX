package com.jsxposed.x.core.desktop_bridge

import android.content.Context
import java.security.SecureRandom

/**
 * 桌面端连接令牌。
 *
 * 令牌只用于挡住"手机上的其他 App 误连/恶意连接"，它不是网络防护手段：
 * 手机侧只监听抽象命名空间 socket，外部网络本来就访问不到；
 * 令牌本身通过 logcat（tag: JsxposedX-DesktopBridge）输出，只有持有 adb 的人能读到，
 * 也就是说能拿到令牌的人本来就已经具备 adb 权限。
 */
internal class DesktopBridgeTokenStore(context: Context) {

    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 读取已有令牌，不存在则生成并持久化。 */
    fun token(): String {
        val existing = prefs.getString(KEY_TOKEN, null)
        if (!existing.isNullOrBlank()) {
            return existing
        }
        val generated = generate()
        prefs.edit().putString(KEY_TOKEN, generated).apply()
        return generated
    }

    /** 重新生成令牌（旧令牌立即失效）。 */
    fun regenerate(): String {
        val generated = generate()
        prefs.edit().putString(KEY_TOKEN, generated).apply()
        return generated
    }

    private fun generate(): String {
        val bytes = ByteArray(TOKEN_BYTES)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString(separator = "") { "%02x".format(it.toInt() and 0xFF) }
    }

    private companion object {
        const val PREFS_NAME = "jsxposed_desktop_bridge"
        const val KEY_TOKEN = "desktop_bridge_token"
        const val TOKEN_BYTES = 16
    }
}
