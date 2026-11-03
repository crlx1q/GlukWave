package tech.gluk.glukwave

import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.app.Service
import org.junit.Before
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowPowerManager

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34])
class ConnectBackgroundTest {
    @Before fun reopenAnIdleActivity() {
        val app = RuntimeEnvironment.getApplication()
        ConnectBackgroundService.channel = null
        ConnectBackgroundService.activityOpened()
        ConnectBackgroundService.playback(app,false)
        app.getSharedPreferences("glukwave-connect-background",Context.MODE_PRIVATE)
            .edit().clear().commit()
        ConnectBackgroundService.update(app,false,false)
        clearServiceIntents()
    }

    private fun clearServiceIntents() {
        val app = RuntimeEnvironment.getApplication()
        while (shadowOf(app).nextStartedService != null) { }
        while (shadowOf(app).nextStoppedService != null) { }
    }

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

    @Test fun removingPausedTaskStopsTheServiceAndReleasesItsWakeLockAndNotification() {
        val app = RuntimeEnvironment.getApplication()
        val controller = Robolectric.buildService(ConnectBackgroundService::class.java).create()
        val service = controller.get()
        controller.startCommand(0,1)
        val wakeLock = requireNotNull(ShadowPowerManager.getLatestWakeLock())
        val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        assertTrue(wakeLock.isHeld)
        assertEquals(1,shadowOf(manager).allNotifications.size)
        clearServiceIntents()
        try {
            service.onTaskRemoved(Intent())
            val stopped = shadowOf(app).nextStoppedService
            assertNotNull(stopped)
            assertEquals(ConnectBackgroundService::class.java.name,stopped?.component?.className)
            // Android delivers onDestroy after stopService. The controller
            // delivers that lifecycle callback rather than emulating cleanup.
        } finally { controller.destroy() }
        assertFalse(wakeLock.isHeld)
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
        assertFalse(app.getSharedPreferences("glukwave-connect-background",Context.MODE_PRIVATE)
            .getBoolean("disabled",false))
    }

    @Test fun removingPlayingTaskKeepsAudioAliveUntilPlaybackIsPaused() {
        val app = RuntimeEnvironment.getApplication()
        ConnectBackgroundService.playback(app,true)
        val controller = Robolectric.buildService(ConnectBackgroundService::class.java).create()
        val service = controller.get()
        controller.startCommand(0,1)
        val wakeLock = requireNotNull(ShadowPowerManager.getLatestWakeLock())
        val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        clearServiceIntents()
        try {
            service.onTaskRemoved(Intent())
            assertNull(shadowOf(app).nextStoppedService)
            assertTrue(wakeLock.isHeld)
            assertEquals(1,shadowOf(manager).allNotifications.size)
            ConnectBackgroundService.playback(app,false)
            val stopped = shadowOf(app).nextStoppedService
            assertNotNull(stopped)
            assertEquals(ConnectBackgroundService::class.java.name,stopped?.component?.className)
        } finally { controller.destroy() }
        assertFalse(wakeLock.isHeld)
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
    }

    @Test fun reopeningAnActivityResumesAllowedConnectWithoutChangingTheUserPreference() {
        val app = RuntimeEnvironment.getApplication()
        val prefs = app.getSharedPreferences("glukwave-connect-background",Context.MODE_PRIVATE)
        assertTrue(ConnectBackgroundService.update(app,true,true))
        assertNotNull(shadowOf(app).nextStartedService)
        clearServiceIntents()
        ConnectBackgroundService.taskClosed(app)
        assertNotNull(shadowOf(app).nextStoppedService)
        assertFalse(prefs.getBoolean("disabled",false))
        assertTrue(ConnectBackgroundService.update(app,true,false))
        assertNull(shadowOf(app).nextStartedService)
        ConnectBackgroundService.activityOpened()
        assertTrue(ConnectBackgroundService.update(app,true,false))
        assertNotNull(shadowOf(app).nextStartedService)
        assertFalse(prefs.getBoolean("disabled",false))
    }

    @Test fun queuedStartAfterAnIdleTaskCloseCannotReacquireForegroundWork() {
        val app = RuntimeEnvironment.getApplication()
        val initial = Robolectric.buildService(ConnectBackgroundService::class.java).create()
        initial.startCommand(0,1)
        val wakeLock = requireNotNull(ShadowPowerManager.getLatestWakeLock())
        initial.get().onTaskRemoved(Intent())
        initial.destroy()
        assertFalse(wakeLock.isHeld)
        val queued = Robolectric.buildService(ConnectBackgroundService::class.java).create()
        try {
            val result = queued.get().onStartCommand(Intent(app,ConnectBackgroundService::class.java),0,2)
            assertEquals(Service.START_NOT_STICKY,result)
            assertTrue(shadowOf(queued.get()).isStoppedBySelf)
            assertFalse(requireNotNull(ShadowPowerManager.getLatestWakeLock()).isHeld)
            val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            assertTrue(shadowOf(manager).allNotifications.isEmpty())
        } finally { queued.destroy() }
    }

    @Test fun explicitNotificationStopStillPersistsWhenTheTaskWasAlreadyRemoved() {
        val app = RuntimeEnvironment.getApplication()
        val controller = Robolectric.buildService(ConnectBackgroundService::class.java).create()
        val service = controller.get()
        controller.startCommand(0,1)
        try {
            service.onTaskRemoved(Intent())
            val result = service.onStartCommand(Intent(app,ConnectBackgroundService::class.java)
                .setAction(ConnectBackgroundService.DISABLE),0,2)
            assertEquals(Service.START_NOT_STICKY,result)
            assertTrue(shadowOf(service).isStoppedBySelf)
            ConnectBackgroundService.activityOpened()
            assertFalse(ConnectBackgroundService.update(app,true,false))
            assertTrue(app.getSharedPreferences("glukwave-connect-background",Context.MODE_PRIVATE)
                .getBoolean("disabled",false))
            assertTrue(ConnectBackgroundService.update(app,true,true))
        } finally { controller.destroy() }
    }
}
