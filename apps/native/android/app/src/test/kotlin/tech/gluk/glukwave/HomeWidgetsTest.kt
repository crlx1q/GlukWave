package tech.gluk.glukwave

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HomeWidgetsTest {
    private lateinit var context: Context
    private var compact = 0
    private var large = 0
    private fun snapshot(bg: String = "#181817",ink: String = "#f4ede3",accent: String = "#ff9966") = mapOf(
        "scope" to "account-a", "signedIn" to true, "title" to "A long favourite title that needs ellipsis", "artist" to "GlukWave test artist",
        "status" to "Playing on Living room PC", "background" to bg, "ink" to ink, "accent" to accent,
        "trackId" to "test-track", "playing" to true, "canToggle" to true, "canSkip" to true, "canWave" to true,
        "labels" to mapOf("wave" to "Моя волна", "pause" to "Пауза", "next" to "Следующий трек"),
        "token" to "must-never-persist", "audio_url" to "https://private.invalid/signed-stream"
    )
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        HomeWidgets.clear(context)
        val manager = shadowOf(AppWidgetManager.getInstance(context))
        compact = manager.createWidget(WavePlayerWidget::class.java,R.layout.glukwave_widget_player)
        large = manager.createWidget(WaveLargeWidget::class.java,R.layout.glukwave_widget_wave)
        HomeWidgets.update(context,snapshot())
    }
    @Test fun snapshotIsPrivateBoundedAndDoesNotContainCredentialsOrUrls() {
        val json = HomeWidgets.state(context).toString()
        assertFalse(json.contains("must-never-persist")); assertFalse(json.contains("signed-stream"))
        assertEquals("account-a",HomeWidgets.state(context).optString("scope"))
        HomeWidgets.update(context,snapshot() + mapOf("title" to "x".repeat(10000),"signedIn" to false,"artwork" to "/private/cover"))
        val state = HomeWidgets.state(context)
        assertEquals(400,state.optString("title").length)
        assertEquals("",state.optString("scope")); assertEquals("",state.optString("artwork"))
        assertFalse(state.optBoolean("playing")); assertFalse(state.optBoolean("canToggle"))
    }
    @Test fun controlsAreImmutableDistinctAndBoundToInstalledWidgetAndAccountEpoch() {
        val first = HomeWidgets.controlIntent(context,compact,"next")
        val second = HomeWidgets.controlIntent(context,compact,"previous")
        assertNotEquals(first,second)
        val action = shadowOf(first).savedIntent
        assertTrue(HomeWidgets.validAction(context,action))
        assertTrue(shadowOf(first).isImmutable)
        assertFalse(HomeWidgets.validAction(context,Intent(action).putExtra("widgetId",9999)))
        assertFalse(HomeWidgets.validAction(context,Intent(action).putExtra("command","deleteAccount")))
        assertFalse(HomeWidgets.validAction(context,Intent(action).putExtra("scope","account-b")))
        val originalGrant = HomeWidgets.epoch(context)
        HomeWidgets.update(context,snapshot() + mapOf("scope" to "account-b"))
        assertNotEquals(originalGrant,HomeWidgets.epoch(context))
        HomeWidgets.update(context,snapshot())
        assertFalse(HomeWidgets.validAction(context,action))
        HomeWidgets.clear(context)
        HomeWidgets.update(context,snapshot())
        assertFalse(HomeWidgets.validAction(context,action))
    }
    @Test fun coldControlsOpenActualAppAndRenderingDoesNotStartAPlayerEngine() {
        HomeWidgets.sessionReady = false
        val pending = HomeWidgets.controlIntent(context,compact,"toggle")
        assertEquals(MainActivity::class.java.name,shadowOf(pending).savedIntent.component?.className)
        HomeWidgets.render(context,compact,false)
        assertFalse(HomeWidgets.sessionReady)
    }
    @Test fun staleOrForeignBroadcastCannotLaunchOrControl() {
        WidgetCommandReceiver().onReceive(context,Intent(HomeWidgets.ACTION).putExtra("command","next"))
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity)
    }
    @Test fun outsideArtworkAndMalformedImagesAreRejected() {
        assertNull(HomeWidgets.artwork(context,"/etc/passwd"))
        val file = File(context.cacheDir,"bad-art.png").apply { writeText("invalid image") }
        assertNull(HomeWidgets.artwork(context,file.path))
    }
    @Test fun themesAndResizeInflateActualRemoteViewsWithReadableControlsAndNoLayoutOverflow() {
        val proofRoot = File(System.getProperty("widget.proof.dir",System.getProperty("java.io.tmpdir")),"widgets-${System.currentTimeMillis()}").apply { mkdirs() }
        for ((theme,bg,ink,accent) in listOf(
            listOf("light","#f5f1e9","#38342e","#a9502c"),
            listOf("dark","#181817","#f4ede3","#ff9966"),
            listOf("amoled","#000000","#f4ede3","#6299ff")
        )) {
            HomeWidgets.update(context,snapshot(bg,ink,accent))
            for (fontScale in listOf(1f,1.3f)) {
              val renderContext = context.createConfigurationContext(Configuration(context.resources.configuration).apply { this.fontScale = fontScale })
              for ((id,isLarge) in listOf(compact to false,large to true)) {
                for (width in listOf(160,220,360)) {
                    val height = if (isLarge) 190 else 80
                    val options = Bundle().apply {
                        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,width)
                        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,height)
                    }
                    val view = HomeWidgets.render(renderContext,id,isLarge,options).apply(renderContext,FrameLayout(renderContext))
                    val density = context.resources.displayMetrics.density
                    val w = (width*density).toInt(); val h = (height*density).toInt()
                    view.measure(View.MeasureSpec.makeMeasureSpec(w,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(h,View.MeasureSpec.EXACTLY))
                    view.layout(0,0,w,h)
                    assertEquals("A long favourite title that needs ellipsis",view.findViewById<TextView>(R.id.widget_title).text.toString())
                    val play = view.findViewById<View>(R.id.widget_play)
                    assertTrue("main play target too small",play.width/density >= 47 && play.height/density >= 47)
                    assertEquals(if(width<250) View.GONE else View.VISIBLE,view.findViewById<View>(R.id.widget_next).visibility)
                    assertEquals(View.GONE,view.findViewById<View>(R.id.widget_progress).visibility)
                    val status = view.findViewById<View>(R.id.widget_status)
                    assertEquals(if (!isLarge && fontScale > 1.1f) View.GONE else View.VISIBLE,status.visibility)
                    if(status.visibility == View.VISIBLE) {
                        val statusRect = android.graphics.Rect()
                        status.getDrawingRect(statusRect)
                        (view as android.view.ViewGroup).offsetDescendantRectToMyCoords(status,statusRect)
                        assertTrue("metadata must stay inside widget at fontScale $fontScale",statusRect.top >= 0 && statusRect.bottom <= h)
                    }
                    if(isLarge) {
                        val wave = view.findViewById<View>(R.id.widget_wave)
                        assertTrue("Wave CTA should fit inside widget",wave.bottom <= h)
                        assertTrue("Wave CTA touch target",wave.height/density >= 43)
                        assertEquals("Моя волна",view.findViewById<TextView>(R.id.widget_wave_title).text.toString())
                    }
                    val bitmap = Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888)
                    view.draw(Canvas(bitmap))
                    File(proofRoot,"$theme-${if(isLarge) "wave" else "player"}-$width-font$fontScale.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
                    bitmap.recycle()
                }
              }
            }
        }
        println("WIDGET_RENDER_PROOF=${proofRoot.absolutePath}")
    }
}
