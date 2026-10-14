package tech.gluk.glukwave

import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34])
class ConnectBackgroundTest {
    @Test fun visibleServiceCanBeStoppedWithoutEnablingItselfAgain() {
        val app = RuntimeEnvironment.getApplication()
        val controller = Robolectric.buildService(ConnectBackgroundService::class.java).create()
        val service = controller.get()
        controller.startCommand(0,1)
        val manager=app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification=shadowOf(manager).allNotifications.single()
        assertEquals("GlukWave Connect",notification.extras.getString("android.title"))
        assertEquals(1,notification.actions.size)
        service.onStartCommand(Intent(service,ConnectBackgroundService::class.java).setAction(ConnectBackgroundService.DISABLE),0,2)
        assertFalse(ConnectBackgroundService.update(app,true,false))
        assertTrue(ConnectBackgroundService.update(app,true,true))
        assertFalse(ConnectBackgroundService.update(app,false,false))
        controller.destroy()
    }
    @Test fun connectServiceIsPrivateAndHasNetworkForegroundType() {
        val app=RuntimeEnvironment.getApplication()
        val component=android.content.ComponentName(app,ConnectBackgroundService::class.java)
        val info=app.packageManager.getServiceInfo(component,0)
        assertFalse(info.exported)
        assertEquals(android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,info.foregroundServiceType)
    }
}
