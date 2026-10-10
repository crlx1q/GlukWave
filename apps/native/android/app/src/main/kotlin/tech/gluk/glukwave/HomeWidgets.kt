package tech.gluk.glukwave

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import com.ryanheise.audioservice.AudioService
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Presentation only; no credentials, audio URLs, second queue or timer. */
object HomeWidgets {
    const val ACTION = "tech.gluk.glukwave.WIDGET_COMMAND"
    const val CHANNEL = "tech.gluk.glukwave/home_widgets"
    val commands = setOf("toggle", "previous", "next", "like", "wave")
    @Volatile var sessionReady = false
    var channel: io.flutter.plugin.common.MethodChannel? = null
    var pendingAction: Map<String,String>? = null
    private fun prefs(c: Context) = c.getSharedPreferences("glukwave_home_widgets", Context.MODE_PRIVATE)
    fun state(c: Context): JSONObject = try { JSONObject(prefs(c).getString("snapshot", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
    fun epoch(c: Context): String = prefs(c).getString("epoch", null) ?: UUID.randomUUID().toString().also { prefs(c).edit().putString("epoch", it).apply() }
    fun update(c: Context, values: Map<*, *>) {
        val data = JSONObject()
        for (key in listOf("scope","title","artist","trackId","artwork","status","background","ink","accent"))
            data.put(key, (values[key] as? String ?: "").take(if (key == "artwork") 2048 else 400))
        for (key in listOf("signedIn","playing","loading","liked","canToggle","canSkip","canWave")) data.put(key,values[key] == true)
        val labels = values["labels"] as? Map<*, *>
        data.put("labels",JSONObject().also { out ->
            for (key in listOf("wave","play","pause","previous","next","like","unlike","open")) out.put(key,(labels?.get(key) as? String ?: "").take(120))
        })
        if (!data.optBoolean("signedIn")) {
            for (key in listOf("scope","trackId","artwork")) data.put(key, "")
            for (key in listOf("playing","canToggle","canSkip","canWave")) data.put(key,false)
        }
        if (state(c).optString("scope") != data.optString("scope")) {
            prefs(c).edit().putString("epoch",UUID.randomUUID().toString()).apply()
        }
        prefs(c).edit().putString("snapshot",data.toString()).apply()
        sessionReady = true
        renderAll(c)
    }
    fun clear(c: Context) {
        sessionReady = false
        pendingAction = null
        prefs(c).edit().remove("snapshot").putString("epoch",UUID.randomUUID().toString()).apply()
        renderAll(c)
    }
    fun widgetIds(c: Context): IntArray {
        val m = AppWidgetManager.getInstance(c)
        return m.getAppWidgetIds(ComponentName(c,WavePlayerWidget::class.java)) + m.getAppWidgetIds(ComponentName(c,WaveLargeWidget::class.java))
    }
    fun validAction(c: Context, i: Intent): Boolean = i.action == ACTION && commands.contains(i.getStringExtra("command")) &&
        i.getStringExtra("epoch") == epoch(c) && i.getStringExtra("scope") == state(c).optString("scope") &&
        state(c).optBoolean("signedIn") && widgetIds(c).contains(i.getIntExtra("widgetId",-1))
    fun actionData(i: Intent): Map<String,String> = mapOf("command" to (i.getStringExtra("command") ?: ""),"scope" to (i.getStringExtra("scope") ?: ""))
    private fun intent(c: Context, id: Int, command: String?, activity: Boolean): Intent = Intent(c,if (activity) MainActivity::class.java else WidgetCommandReceiver::class.java).apply {
        data = Uri.parse("glukwave-widget://$id/${command ?: "open"}/${epoch(c)}")
        if (activity) flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        if (command != null) {
            action = ACTION
            putExtra("command",command); putExtra("scope",state(c).optString("scope")); putExtra("epoch",epoch(c)); putExtra("widgetId",id)
        }
    }
    fun activityIntent(c: Context,id: Int,command: String? = null): PendingIntent {
        val options = if (Build.VERSION.SDK_INT >= 35) ActivityOptions.makeBasic().apply {
            setPendingIntentCreatorBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        }.toBundle() else null
        return PendingIntent.getActivity(c,id,intent(c,id,command,true),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,options)
    }
    fun controlIntent(c: Context,id: Int,command: String): PendingIntent = if (!sessionReady) activityIntent(c,id,command) else
        PendingIntent.getBroadcast(c,id,intent(c,id,command,false),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun openFromClick(c: Context,id: Int,command: String) {
        // Only an explicit, validated user tap can request a cold launch.
        val options = if (Build.VERSION.SDK_INT >= 34) ActivityOptions.makeBasic().apply {
            setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        }.toBundle() else null
        try { activityIntent(c,id,command).send(c,0,null,null,null,null,options) }
        catch (_: PendingIntent.CanceledException) { renderAll(c) }
    }
    private fun color(value: String,fallback: Int): Int = try { Color.parseColor(value) } catch (_: Exception) { fallback }
    private fun mix(a: Int,b: Int,t: Float): Int = Color.rgb((Color.red(a)*(1-t)+Color.red(b)*t).toInt(),(Color.green(a)*(1-t)+Color.green(b)*t).toInt(),(Color.blue(a)*(1-t)+Color.blue(b)*t).toInt())
    private fun icon(c: Context,resource: Int,tint: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(32,32,Bitmap.Config.ARGB_8888)
        ContextCompat.getDrawable(c,resource)?.mutate()?.apply { setTint(tint); setBounds(0,0,32,32); draw(Canvas(bitmap)) }
        return bitmap
    }
    private fun panel(width: Int,height: Int,bg: Int,accent: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888)
        val rect = RectF(1f,1f,width-1f,height-1f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = bg }
        Canvas(bitmap).apply {
            drawRoundRect(rect,22f,22f,paint)
            paint.color = mix(bg,accent,.23f); paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.2f
            drawRoundRect(rect,22f,22f,paint)
        }
        return bitmap
    }
    private fun playIcon(c: Context,resource: Int,ink: Int,bg: Int,allowed: Boolean): Bitmap {
        val bitmap = Bitmap.createBitmap(48,48,Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawCircle(24f,24f,24f,Paint(Paint.ANTI_ALIAS_FLAG).apply { color = if (allowed) ink else mix(bg,ink,.45f) })
        ContextCompat.getDrawable(c,resource)?.mutate()?.apply { setTint(bg); setBounds(12,12,36,36); draw(canvas) }
        return bitmap
    }
    fun artwork(c: Context,path: String): Bitmap? = try {
        val f = File(path).canonicalFile
        val permitted = listOf(c.cacheDir,c.filesDir).any { f.path.startsWith(it.canonicalPath + File.separator) }
        if (path.isBlank() || !permitted || !f.isFile || f.length() > 16*1024*1024) null else {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(f.path,o)
            if (o.outWidth <= 0 || o.outHeight <= 0) null else {
                o.inJustDecodeBounds = false; o.inSampleSize = 1
                while (maxOf(o.outWidth,o.outHeight)/o.inSampleSize > 320) o.inSampleSize *= 2
                val source = BitmapFactory.decodeFile(f.path,o)
                if (source == null) null else {
                    val output = Bitmap.createBitmap(160,160,Bitmap.Config.ARGB_8888)
                    val side = minOf(source.width,source.height); val left = (source.width-side)/2; val top = (source.height-side)/2
                    Canvas(output).apply {
                        clipPath(Path().apply { addRoundRect(RectF(0f,0f,160f,160f),16f,16f,Path.Direction.CW) })
                        drawBitmap(source,Rect(left,top,left+side,top+side),RectF(0f,0f,160f,160f),Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
                    }
                    source.recycle(); output
                }
            }
        }
    } catch (_: Exception) { null }
    fun render(c: Context,id: Int,large: Boolean,options: Bundle = AppWidgetManager.getInstance(c).getAppWidgetOptions(id)): RemoteViews {
        val s = state(c); val labels = s.optJSONObject("labels") ?: JSONObject()
        val ink = color(s.optString("ink"),Color.rgb(244,240,233)); val accent = color(s.optString("accent"),Color.rgb(255,143,97))
        val bg = color(s.optString("background"),Color.rgb(24,24,23))
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,if (large) 300 else 320).coerceIn(120,480)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,if (large) 168 else 84).coerceIn(68,280)
        val v = RemoteViews(c.packageName,if (large) R.layout.glukwave_widget_wave else R.layout.glukwave_widget_player)
        v.setImageViewBitmap(R.id.widget_panel,panel(width,height,bg,accent))
        v.setTextViewText(R.id.widget_title,s.optString("title",c.getString(R.string.widget_empty))); v.setTextViewText(R.id.widget_artist,s.optString("artist","GlukWave"))
        v.setTextViewText(R.id.widget_status,s.optString("status",c.getString(R.string.widget_sign_in)))
        // The compact widget has only 56dp of usable content at its minimum
        // height. Preserve title/artist and transport when system text grows.
        v.setViewVisibility(R.id.widget_status,if (!large && c.resources.configuration.fontScale > 1.1f) View.GONE else View.VISIBLE)
        for (view in listOf(R.id.widget_title,R.id.widget_artist,R.id.widget_status)) v.setTextColor(view,if (view == R.id.widget_title) ink else mix(bg,ink,.72f))
        v.setOnClickPendingIntent(R.id.widget_root,activityIntent(c,id)); v.setContentDescription(R.id.widget_root,labels.optString("open",c.getString(R.string.widget_open)))
        v.setImageViewBitmap(R.id.widget_cover,artwork(c,s.optString("artwork")) ?: icon(c,R.drawable.widget_logo,accent))
        for ((view,cmd,res) in listOf(Triple(R.id.widget_previous,"previous",R.drawable.widget_previous),Triple(R.id.widget_play,"toggle",if (s.optBoolean("playing")) R.drawable.widget_pause else R.drawable.widget_play),Triple(R.id.widget_next,"next",R.drawable.widget_next))) {
            val allowed = s.optBoolean(if (cmd == "toggle") "canToggle" else "canSkip")
            if (cmd == "toggle") {
                v.setInt(view,"setBackgroundColor",Color.TRANSPARENT)
                v.setViewPadding(view,0,0,0,0)
                v.setImageViewBitmap(view,playIcon(c,res,ink,bg,allowed))
            } else v.setImageViewBitmap(view,icon(c,res,if (allowed) ink else mix(bg,ink,.35f)))
            v.setOnClickPendingIntent(view,if (allowed) controlIntent(c,id,cmd) else activityIntent(c,id))
            val key = if (cmd == "toggle") if (s.optBoolean("playing")) "pause" else "play" else cmd
            v.setContentDescription(view,labels.optString(key,key))
        }
        for (view in listOf(R.id.widget_previous,R.id.widget_next)) v.setViewVisibility(view,if (width < 250) View.GONE else View.VISIBLE)
        if (!large) {
            v.setViewVisibility(R.id.widget_cover,if (width < 180) View.GONE else View.VISIBLE)
        } else {
            v.setViewVisibility(R.id.widget_header,if (height < 215) View.GONE else View.VISIBLE)
            v.setImageViewBitmap(R.id.widget_wave_panel,panel(width,44,mix(bg,accent,.13f),accent))
            v.setTextViewText(R.id.widget_wave_title,labels.optString("wave",c.getString(R.string.widget_wave_label))); v.setTextColor(R.id.widget_wave_title,accent); v.setTextColor(R.id.widget_header,mix(bg,ink,.72f))
            v.setContentDescription(R.id.widget_wave,labels.optString("wave",c.getString(R.string.widget_wave_label)))
            v.setImageViewBitmap(R.id.widget_wave_icon,icon(c,R.drawable.widget_wave,accent))
            v.setImageViewBitmap(R.id.widget_like,icon(c,if (s.optBoolean("liked")) R.drawable.widget_heart_filled else R.drawable.widget_heart,if (s.optBoolean("liked")) accent else ink))
            v.setContentDescription(R.id.widget_like,labels.optString(if (s.optBoolean("liked")) "unlike" else "like","Like track"))
            v.setOnClickPendingIntent(R.id.widget_like,if (s.optBoolean("signedIn") && s.optString("trackId").isNotEmpty()) controlIntent(c,id,"like") else activityIntent(c,id))
            val click = if (s.optBoolean("canWave")) controlIntent(c,id,"wave") else activityIntent(c,id)
            v.setOnClickPendingIntent(R.id.widget_wave,click); v.setOnClickPendingIntent(R.id.widget_wave_icon,click)
        }
        v.setViewVisibility(R.id.widget_progress,View.GONE)
        return v
    }
    fun renderAll(c: Context) {
        val m = AppWidgetManager.getInstance(c)
        for ((p,large) in listOf(WavePlayerWidget::class.java to false,WaveLargeWidget::class.java to true))
            for (id in m.getAppWidgetIds(ComponentName(c,p))) m.updateAppWidget(id,render(c,id,large))
    }
}

open class WavePlayerWidget : AppWidgetProvider() {
    protected open val large = false
    override fun onUpdate(c: Context,m: AppWidgetManager,ids: IntArray) { for (id in ids) m.updateAppWidget(id,HomeWidgets.render(c,id,large)) }
    override fun onAppWidgetOptionsChanged(c: Context,m: AppWidgetManager,id: Int,options: Bundle) { m.updateAppWidget(id,HomeWidgets.render(c,id,large,options)) }
}
class WaveLargeWidget : WavePlayerWidget() { override val large = true }

class WidgetCommandReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context,i: Intent) {
        if (!HomeWidgets.validAction(c,i)) return
        val id = i.getIntExtra("widgetId",-1); val command = i.getStringExtra("command") ?: return
        if (!HomeWidgets.sessionReady) { HomeWidgets.openFromClick(c,id,command); return }
        val result = goAsync(); val handler = Handler(Looper.getMainLooper()); var finished = false
        lateinit var browser: MediaBrowserCompat
        fun finish() { if (!finished) { finished = true; handler.removeCallbacksAndMessages(null); browser.disconnect(); result.finish() } }
        browser = MediaBrowserCompat(c.applicationContext,ComponentName(c,AudioService::class.java),object : MediaBrowserCompat.ConnectionCallback() {
            override fun onConnected() {
                if (finished) return
                try {
                    if (HomeWidgets.validAction(c,i)) MediaControllerCompat(c,browser.sessionToken).transportControls.sendCustomAction("glukwave.widget",Bundle().apply { putString("command",command); putString("scope",i.getStringExtra("scope")); putString("grant",i.getStringExtra("epoch")) })
                } catch (_: Exception) {
                    // A failed binder cannot crash the application. Avoid
                    // retrying a toggle that might already have been delivered.
                    HomeWidgets.sessionReady = false
                    HomeWidgets.renderAll(c)
                } finally { finish() }
            }
            override fun onConnectionFailed() { if (!finished) { finish(); if (HomeWidgets.validAction(c,i)) HomeWidgets.openFromClick(c,id,command) } }
            override fun onConnectionSuspended() { finish() }
        },null)
        handler.postDelayed({ if (!finished) { finish(); if (HomeWidgets.validAction(c,i)) HomeWidgets.openFromClick(c,id,command) } },2500)
        try { browser.connect() } catch (_: Exception) { finish(); if (HomeWidgets.validAction(c,i)) HomeWidgets.openFromClick(c,id,command) }
    }
}
