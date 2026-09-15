package com.jsxposed.x.core.desktop_bridge

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** 一台已配对的电脑。手机侧只需要记住"往哪连"和"用什么令牌连"。 */
internal data class PairedPc(
    val name: String,
    val host: String,
    val port: Int,
    val token: String,
    val lastConnectedAtMs: Long,
) {
    val address: String get() = "$host:$port"
}

/**
 * 手机侧保存的"已配对的电脑"，以及本机的稳定标识。
 *
 * 与电脑侧的 `PairedPhoneStore` 是一对：那边记住"哪些手机可以连我"，
 * 这边记住"我可以连哪些电脑"。两边都用长期令牌做自动重连，
 * 但**令牌的签发方是电脑**——手机只是保存它。
 *
 * 注意 [deviceId] 不是凭据：它是一个随安装持久化的随机 UUID，
 * 唯一用途是让电脑端认出"还是那台手机"，从而在重新配对时替换旧记录
 * 而不是堆积僵尸条目（docs/desktop_bridge_lan_CN.md §10.6）。它泄露了也无所谓。
 */
internal class PairedPcStore(context: Context) {

    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 本机稳定标识，首次调用时生成并持久化。 */
    fun deviceId(): String {
        val existing = prefs.getString(KEY_DEVICE_ID, null)
        if (!existing.isNullOrBlank()) {
            return existing
        }
        val generated = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_DEVICE_ID, generated).apply()
        return generated
    }

    fun listPcs(): List<PairedPc> {
        val raw = prefs.getString(KEY_PCS, null) ?: return emptyList()
        val array = try {
            JSONArray(raw)
        } catch (t: Throwable) {
            // 存储损坏时清掉，避免每次启动都抛异常。
            prefs.edit().remove(KEY_PCS).apply()
            return emptyList()
        }

        val result = ArrayList<PairedPc>(array.length())
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            val host = item.optString(KEY_HOST)
            val token = item.optString(KEY_TOKEN)
            if (host.isBlank() || token.isBlank()) {
                continue
            }
            result += PairedPc(
                name = item.optString(KEY_NAME),
                host = host,
                port = item.optInt(KEY_PORT, BridgeProtocol.DEFAULT_PORT),
                token = token,
                lastConnectedAtMs = item.optLong(KEY_LAST_CONNECTED_AT, 0L),
            )
        }
        return result
    }

    fun findPc(host: String, port: Int): PairedPc? =
        listPcs().firstOrNull { it.host == host && it.port == port }

    /** 最近连接过的那台电脑，用于 App 启动时的自动重连。 */
    fun lastPc(): PairedPc? =
        listPcs().maxByOrNull { it.lastConnectedAtMs }

    /** 新增或更新一台电脑（按 `host:port` 归并）。 */
    fun savePc(name: String, host: String, port: Int, token: String) {
        val updated = listPcs()
            .filterNot { it.host == host && it.port == port }
            .toMutableList()
        updated += PairedPc(
            name = name,
            host = host,
            port = port,
            token = token,
            lastConnectedAtMs = System.currentTimeMillis(),
        )
        persist(updated)
    }

    /** @return 是否确实删掉了一条。 */
    fun forgetPc(host: String, port: Int): Boolean {
        val all = listPcs()
        val remaining = all.filterNot { it.host == host && it.port == port }
        if (remaining.size == all.size) {
            return false
        }
        persist(remaining)
        return true
    }

    fun forgetAllPcs() {
        prefs.edit().remove(KEY_PCS).apply()
    }

    fun isAutoReconnect(): Boolean = prefs.getBoolean(KEY_AUTO_RECONNECT, true)

    fun setAutoReconnect(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_AUTO_RECONNECT, enabled).apply()
    }

    /**
     * 上限 8 条，超出按"最久未连接"淘汰。
     *
     * 正常情况下一条电脑只会有一条记录（[savePc] 按地址归并）；
     * 但如果电脑的地址变了，旧的地址会留下一条再也用不上的记录——
     * 这是 §10.4 说的"地址一变就要重新配对"的另一面，界面上允许用户手动删除。
     */
    private fun persist(pcs: List<PairedPc>) {
        val trimmed = pcs.sortedByDescending { it.lastConnectedAtMs }.take(MAX_PCS)
        val array = JSONArray()
        for (pc in trimmed) {
            array.put(
                JSONObject()
                    .put(KEY_NAME, pc.name)
                    .put(KEY_HOST, pc.host)
                    .put(KEY_PORT, pc.port)
                    .put(KEY_TOKEN, pc.token)
                    .put(KEY_LAST_CONNECTED_AT, pc.lastConnectedAtMs)
            )
        }
        prefs.edit().putString(KEY_PCS, array.toString()).apply()
    }

    private companion object {
        const val PREFS_NAME = "jsxposed_desktop_bridge"
        const val KEY_DEVICE_ID = "bridge_device_id"
        const val KEY_PCS = "paired_pcs"
        const val KEY_AUTO_RECONNECT = "lan_auto_reconnect"

        const val KEY_NAME = "name"
        const val KEY_HOST = "host"
        const val KEY_PORT = "port"
        const val KEY_TOKEN = "token"
        const val KEY_LAST_CONNECTED_AT = "lastConnectedAtMs"

        const val MAX_PCS = 8
    }
}
