package com.jsxposed.x.core.desktop_bridge

/**
 * LAN 链路上**手机要出示的凭据**。
 *
 * 方向与 USB 链路相反：USB 的可信信道是 adb，由电脑出示令牌、手机校验；
 * Wi-Fi 的可信信道是电脑屏幕上的 6 位码，由**手机**出示、**电脑**校验。
 * 规则是"谁掌握可信信道，谁就出示凭据"，见 docs/desktop_bridge_lan_CN.md §7.1、§7.3。
 *
 * 手机侧只是把凭据**原样放进 `welcome` 帧**，自己不做任何校验——
 * 那样校验方就成了电脑，而 §7.2 说明了为什么必须由电脑校验：
 * 它是监听端，任何同网段设备都能连上来，不校验就会把数据发出去。
 */
internal sealed class BridgeCredential {

    /** 首次配对：用户在手机上输入的 6 位校验码。 */
    data class Code(val value: String) : BridgeCredential()

    /**
     * 自动重连：之前由电脑签发、手机保存下来的会话令牌。
     *
     * 注意这条路径**不受来源限速与全局节流影响**（§9.2）——否则攻击者触发一次
     * 全局暂停，就能让已经配对过的手机也连不上，与"无需再输码即可自动重连"冲突。
     */
    data class Session(val value: String) : BridgeCredential()
}
