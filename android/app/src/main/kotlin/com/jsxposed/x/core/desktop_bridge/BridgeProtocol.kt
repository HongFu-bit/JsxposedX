package com.jsxposed.x.core.desktop_bridge

/**
 * 桌面端 bridge 协议常量。
 *
 * 手机侧与本文件对应的 Dart 版本是 lib/desktop/bridge/bridge_protocol.dart，
 * 两侧字段名必须保持一致。协议说明见 docs/desktop_bridge_CN.md 第 5 节。
 */
internal object BridgeProtocol {

    /** 协议版本，修改帧格式时递增。 */
    const val VERSION = 1

    /** 抽象命名空间 socket 名称（adb forward ... localabstract:<name>）。 */
    const val SOCKET_NAME = "jsxposed_desktop_bridge"

    /** 日志 TAG，LogX 会拼成 "JsxposedX-DesktopBridge"，启动脚本依赖它读取 token。 */
    const val LOG_TAG = "DesktopBridge"

    /**
     * 允许隧道的 Pigeon 通道前缀。
     *
     * 只放行本应用自己的 bridge，避免把桌面端本地插件（文件选择、SharedPreferences 等）
     * 的通道也送到手机上。见 docs/desktop_bridge_CN.md §6.1。
     */
    const val CHANNEL_PREFIX = "dev.flutter.pigeon.JsxposedX."

    /** 默认端口，仅用于 adb forward 与文档说明，手机侧不监听 TCP。 */
    const val DEFAULT_PORT = 27183

    /**
     * transport 类型。取值会出现在 welcome 帧的 `transport` 字段里，
     * 让电脑端能区分"已连接手机（USB）"与"（Wi-Fi）"。
     * 见 docs/desktop_bridge_lan_CN.md §8.2。
     */
    const val TRANSPORT_USB = "usb"
    const val TRANSPORT_LAN = "lan"

    /** 心跳检测间隔。 */
    const val HEARTBEAT_INTERVAL_MS = 10_000L

    /** 超过该时长没有收到任何帧则判定客户端失联并关闭连接。 */
    const val IDLE_TIMEOUT_MS = 30_000L

    /** 单帧上限（字符数，base64 编码后的近似值）。 */
    const val MAX_FRAME_CHARS = 48 * 1024 * 1024

    /** 帧类型。 */
    const val T_HELLO = "hello"
    const val T_WELCOME = "welcome"
    const val T_REJECT = "reject"
    const val T_CALL = "call"
    const val T_RET = "ret"
    const val T_ERR = "err"
    const val T_PING = "ping"
    const val T_PONG = "pong"

    /**
     * 新增帧：电脑在校验通过后用它把会话令牌下发给手机（文档 §8.3）。
     *
     * 手机侧的 [DesktopBridgeServer.readLoop] **必须显式处理它**——那边对未知帧类型
     * 只记日志并继续，漏掉会表现为"配对成功了但下次还要重新输入校验码"。
     */
    const val T_TOKEN = "token"

    /** 帧字段名。 */
    const val K_TYPE = "t"
    const val K_VERSION = "v"
    const val K_TOKEN = "token"
    const val K_CLIENT = "client"
    const val K_APP_VERSION = "appVersion"
    const val K_DEVICE = "device"
    const val K_CAPS = "caps"
    const val K_CODE = "code"
    const val K_MESSAGE = "message"
    const val K_ID = "id"
    const val K_CHANNEL = "ch"
    const val K_PAYLOAD = "p"

    /**
     * Wi-Fi 链路新增的字段名（文档 §8.1、§8.2）。
     *
     * [K_CODE] / [K_TOKEN] 两个常量**早就存在**，LAN 链路复用它们承载
     * 6 位校验码与会话令牌，不要重复定义。
     */
    const val K_TRANSPORT = "transport"
    const val K_CLIENT_NAME = "clientName"
    const val K_DEVICE_ID = "deviceId"

    /** 错误码。 */
    const val ERR_AUTH = "auth"
    const val ERR_PROTOCOL = "protocol"
    const val ERR_BUSY = "busy"
    const val ERR_INTERNAL = "internal"

    /**
     * Wi-Fi 链路新增的错误码（文档 §8.4）。
     *
     * 只有电脑会发这三个；[ERR_LOCKED] 表示"被来源限速或全局节流"，是**临时**状态，
     * 手机收到后应继续退避重试，而不是像 [ERR_CODE] 那样停下来等用户输入。
     */
    const val ERR_CODE = "code"
    const val ERR_CODE_STALE = "code-stale"
    const val ERR_LOCKED = "locked"

    /** Pigeon 的通道缺失错误码，与生成代码里的 _createConnectionError 保持一致。 */
    const val PIGEON_CHANNEL_ERROR = "channel-error"
}
