package tech.gluk.glukwave
import com.ryanheise.audioservice.AudioServiceFragmentActivity
class MainActivity : AudioServiceFragmentActivity() {
    override fun configureFlutterEngine(engine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(engine)
        val app = applicationContext
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
