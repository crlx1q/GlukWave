package tech.gluk.glukwave

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/** Holds only the process/network lifetime. The existing Dart account socket
 * and AudioService keep all commands, authentication and music ownership. */
class ConnectBackgroundService : Service() {
    companion object {
        const val DISABLE = "tech.gluk.glukwave.CONNECT_DISABLE"
        private const val ID = 52023
        private const val CHANNEL = "glukwave.connect"
        private const val PREFS = "glukwave-connect-background"
        fun update(context: Context, enabled: Boolean, explicit: Boolean): Boolean {
            val prefs = context.getSharedPreferences(PREFS,Context.MODE_PRIVATE)
            if (explicit) prefs.edit().putBoolean("disabled",!enabled).apply()
            val allowed = enabled && !prefs.getBoolean("disabled",false)
            val intent = Intent(context,ConnectBackgroundService::class.java)
            if (allowed) ContextCompat.startForegroundService(context,intent)
            else context.stopService(intent)
            return allowed
        }
    }
    private var lock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == DISABLE) {
            getSharedPreferences(PREFS,MODE_PRIVATE).edit().putBoolean("disabled",true).apply()
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(CHANNEL,"GlukWave Connect",NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this,ID,Intent(this,MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this,ID,Intent(this,ConnectBackgroundService::class.java).setAction(DISABLE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this,CHANNEL)
            .setSmallIcon(R.drawable.ic_notification).setContentTitle("GlukWave Connect")
            .setContentText(getString(R.string.connect_background_status))
            .setContentIntent(open).setOngoing(true).setSilent(true)
            .addAction(0,getString(R.string.connect_background_stop),stop).build()
        ServiceCompat.startForeground(this,ID,notification,
            if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0)
        if (lock?.isHeld != true) {
            lock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"GlukWave:Connect").apply { acquire() }
        }
        // No restart after force-stop, task manager stop or reboot. Opening the
        // signed-in app starts it again unless the user disabled Connect.
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        if (lock?.isHeld == true) lock?.release()
        lock = null
        ServiceCompat.stopForeground(this,ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
