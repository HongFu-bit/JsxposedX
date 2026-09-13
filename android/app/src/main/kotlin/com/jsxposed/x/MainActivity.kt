package com.jsxposed.x

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.jsxposed.x.core.bridge.lsposed_native.LSPosed
import com.jsxposed.x.core.desktop_bridge.DesktopBridgeManager
import com.jsxposed.x.core.utils.log.LogX
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingLsposedCheck: Runnable? = null

    companion object {
        private const val TAG = "FINDBUGS"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "========== MainActivity.configureFlutterEngine ==========")

        // 桌面端 USB 桥（docs/desktop_bridge_CN.md）：
        // install 会启动本地 socket 服务，并返回一个"扇出 messenger"——
        // Pigeon handler 必须注册到它上面，桌面端的调用才能命中同一批实现实例；
        // 它同时把 handler 转发给引擎 messenger，手机端 UI 的调用路径保持不变。
        val bridgeMessenger = DesktopBridgeManager.install(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        NativeProvider.registerAll(this, bridgeMessenger)
        Log.d(TAG, "NativeProvider registered")
        LogX.i(
            "DesktopBridge",
            "registered channels: ${DesktopBridgeManager.registeredChannelCount()}",
        )
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity.onCreate")
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "MainActivity.onResume")
        LSPosed.initService(applicationContext)
        scheduleOneTimeLsposedCheck()
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "MainActivity.onPause")
        pendingLsposedCheck?.let { mainHandler.removeCallbacks(it) }
    }

    override fun onDestroy() {
        // 引擎随 Activity 销毁后通道不再可用，桌面端应看到断线而不是拿到空数据。
        DesktopBridgeManager.detach()
        super.onDestroy()
    }

    private fun scheduleOneTimeLsposedCheck() {
        pendingLsposedCheck?.let { mainHandler.removeCallbacks(it) }
        val task = Runnable {
            if (LSPosed.isServiceConnected()) {
                LogX.d("FixHookError", "LSPosed connected, skip auto restart")
                return@Runnable
            }

            LogX.w(
                "FixHookError",
                "LSPosed not connected after cold start, skip auto relaunch to avoid interrupting Frida/HookJsXposed"
            )
        }
        pendingLsposedCheck = task
        mainHandler.postDelayed(task, 3500L)
    }
}

