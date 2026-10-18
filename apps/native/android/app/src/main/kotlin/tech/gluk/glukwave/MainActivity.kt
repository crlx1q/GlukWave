package tech.gluk.glukwave
import com.ryanheise.audioservice.AudioServiceFragmentActivity
class MainActivity : AudioServiceFragmentActivity() {
    override fun configureFlutterEngine(engine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(engine)
        val app = applicationContext
        io.flutter.plugin.common.MethodChannel(engine.dartExecutor.binaryMessenger,"tech.gluk.glukwave/updates").setMethodCallHandler { call,result ->
            if (call.method == "version") {
                val info = app.packageManager.getPackageInfo(app.packageName,0)
                val build = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                result.success("${info.versionName}+$build"); return@setMethodCallHandler
            }
            if (call.method != "install") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val file = java.io.File(call.argument<String>("path") ?: "").canonicalFile
                val root = java.io.File(app.filesDir,"updates").canonicalFile
                require(file.parentFile == root && file.name.matches(Regex("glukwave-[a-f0-9]{64}\\.apk")) && file.isFile)
                if (android.os.Build.VERSION.SDK_INT >= 26 && !app.packageManager.canRequestPackageInstalls()) {
                    startActivity(android.content.Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        android.net.Uri.parse("package:"+app.packageName)))
                    result.error("INSTALL_PERMISSION","Allow updates from GlukWave, then press Install again.",null)
                } else {
                    val uri = androidx.core.content.FileProvider.getUriForFile(app,app.packageName+".updates",file)
                    startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                        setDataAndType(uri,"application/vnd.android.package-archive")
                        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    })
                    result.success(true)
                }
            } catch (error: Exception) { result.error("UPDATE_INSTALL",error.javaClass.simpleName,null) }
        }
        io.flutter.plugin.common.MethodChannel(engine.dartExecutor.binaryMessenger,"tech.gluk.glukwave/connect_background").setMethodCallHandler { call,result ->
            if (call.method != "update") { result.notImplemented(); return@setMethodCallHandler }
            try {
                result.success(ConnectBackgroundService.update(app,call.argument<Boolean>("enabled") == true,
                    call.argument<Boolean>("explicit") == true))
            } catch (error: Exception) {
                result.error("CONNECT_BACKGROUND",error.javaClass.simpleName,null)
            }
        }
        io.flutter.plugin.common.MethodChannel(engine.dartExecutor.binaryMessenger,"tech.gluk.glukwave/energy").setMethodCallHandler { call,result ->
            if (call.method != "snapshot") { result.notImplemented(); return@setMethodCallHandler }
            val power = app.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
            val state = app.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
            val level = state?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL,-1) ?: -1
            val scale = state?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE,-1) ?: -1
            val status = state?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS,-1) ?: -1
            result.success(mapOf("saving" to power.isPowerSaveMode,
                "battery" to if(level>=0&&scale>0)level*100/scale else -1,
                "charging" to (status==android.os.BatteryManager.BATTERY_STATUS_CHARGING||status==android.os.BatteryManager.BATTERY_STATUS_FULL)))
        }
        captureWidgetAction(intent,false)
        // The media engine survives a closed Activity. Capture only application
        // context and the static bridge, never retain MainActivity in a handler.
        HomeWidgets.channel = io.flutter.plugin.common.MethodChannel(engine.dartExecutor.binaryMessenger,HomeWidgets.CHANNEL).also { channel ->
            channel.setMethodCallHandler { call,result ->
                when (call.method) {
                    "initialize" -> { result.success(mapOf("action" to HomeWidgets.pendingAction,"grant" to HomeWidgets.epoch(app))); HomeWidgets.pendingAction = null }
                    "update" -> { HomeWidgets.update(app,call.arguments as? Map<*,*> ?: emptyMap<Any,Any>()); result.success(HomeWidgets.epoch(app)) }
                    "clear" -> { HomeWidgets.clear(app); result.success(HomeWidgets.epoch(app)) }
                    "pin" -> {
                        val kind = call.argument<String>("kind"); val manager = android.appwidget.AppWidgetManager.getInstance(app)
                        result.success(if (android.os.Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported && kind in listOf("player","wave"))
                            manager.requestPinAppWidget(android.content.ComponentName(app,if (kind == "wave") WaveLargeWidget::class.java else WavePlayerWidget::class.java),null,null) else false)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        if (HomeWidgets.sessionReady && HomeWidgets.pendingAction != null) {
            HomeWidgets.channel?.invokeMethod("action",HomeWidgets.pendingAction)
            HomeWidgets.pendingAction = null
        }
    }
    private fun captureWidgetAction(source: android.content.Intent?,deliver: Boolean) {
        if (source == null || !HomeWidgets.validAction(applicationContext,source)) return
        val action = HomeWidgets.actionData(source)
        source.action = null // one shot across Activity/engine recreation
        if (deliver && HomeWidgets.sessionReady && HomeWidgets.channel != null) HomeWidgets.channel?.invokeMethod("action",action)
        else HomeWidgets.pendingAction = action
    }
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent); setIntent(intent); captureWidgetAction(intent,true)
    }
}
