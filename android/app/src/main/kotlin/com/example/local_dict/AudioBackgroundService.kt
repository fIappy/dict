package com.example.local_dict

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app playing while it is not on screen.
 *
 * Android freezes a backgrounded app and treats its process as a kill
 * candidate; playback through the audio plugin lives in this process, so a word
 * being read out is cut off the moment the launcher comes up or the screen goes
 * off. A foreground service with the media-playback type is the supported way to
 * say "still playing", and the partial wake lock keeps the CPU from sleeping
 * mid-clip.
 *
 * Deliberately dumb: it starts when Dart reports sound started, stops when Dart
 * reports sound ended, and holds no playback state of its own — the audio itself
 * stays in the plugin's player.
 */
class AudioBackgroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            // A ceiling, not an expectation: playback is seconds, the lock is
            // released in onDestroy either way.
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "读音播放",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "播放单词或句子读音时保持后台运行"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("正在播放读音")
            .setContentText("切到后台或息屏后仍会继续")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .build()
    }

    private companion object {
        const val CHANNEL_ID = "local_dict_audio"
        const val NOTIFICATION_ID = 4211
        const val WAKE_LOCK_TAG = "local_dict:audio"
        const val WAKE_LOCK_TIMEOUT_MS = 30L * 60L * 1000L
    }
}
