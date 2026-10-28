package com.sangeeth.fintrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import java.util.Calendar

class ReminderReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID = "fintrack_reminders"
        const val CHANNEL_NAME = "FinTrack Expense Reminders"
        const val ACTION_EXPENSE_REMINDER = "com.sangeeth.fintrack.ACTION_EXPENSE_REMINDER"
        const val ACTION_NIGHT_REMINDER = "com.sangeeth.fintrack.ACTION_NIGHT_REMINDER"
        const val ACTION_TEST_REMINDER = "com.sangeeth.fintrack.ACTION_TEST_REMINDER"
        const val NOTIFICATION_ID_DAY = 1001
        const val NOTIFICATION_ID_NIGHT = 1002
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        if (Intent.ACTION_BOOT_COMPLETED == action) {
            // Re-schedule alarms after device reboot
            ReminderScheduler.reschedule(context)
            return
        }

        createNotificationChannel(context)

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("route", if (action == ACTION_NIGHT_REMINDER) "daily_summary" else "capture")
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            if (action == ACTION_NIGHT_REMINDER) 2002 else 2001,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val (title, body, notifId) = when (action) {
            ACTION_NIGHT_REMINDER -> Triple(
                "FinTrack AI • Daily Wrap-up 🌙",
                "Log any missed cash or UPI expenses before sleeping and view your End-of-Day Spend Summary!",
                NOTIFICATION_ID_NIGHT
            )
            ACTION_TEST_REMINDER -> Triple(
                "FinTrack AI • Reminders Active 🔔",
                "Periodic 3-hour check-ins and night wrap-up reminders are enabled! Tap anytime to log spends.",
                NOTIFICATION_ID_DAY
            )
            else -> {
                val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
                val msg = if (hour in 12..14) {
                    "Lunch or chai expenses? Tap to quickly log or scan your payment screenshot."
                } else if (hour in 18..20) {
                    "Evening commute, snacks or groceries? Keep your daily spend limit in check!"
                } else {
                    "Did you make any payments in the last 3 hours? Tap to log in 2 seconds."
                }
                Triple("FinTrack AI • Expense Check ⚡", msg, NOTIFICATION_ID_DAY)
            }
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(notifId, notification)
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Periodic reminders to log missed expenses and nightly spend summaries"
                enableVibration(true)
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}

