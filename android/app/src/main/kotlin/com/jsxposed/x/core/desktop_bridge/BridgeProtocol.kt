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

    /** 错误码。 */
    const val ERR_AUTH = "auth"
    const val ERR_PROTOCOL = "protocol"
    const val ERR_BUSY = "busy"
    const val ERR_INTERNAL = "internal"

    /** Pigeon 的通道缺失错误码，与生成代码里的 _createConnectionError 保持一致。 */
    const val PIGEON_CHANNEL_ERROR = "channel-error"
}
