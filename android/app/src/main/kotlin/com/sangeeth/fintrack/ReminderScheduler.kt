package com.sangeeth.fintrack

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import java.util.Calendar

object ReminderScheduler {
    private const val PREFS_NAME = "fintrack_reminder_prefs"
    private const val KEY_ENABLED = "reminders_enabled"
    private const val KEY_INTERVAL_HOURS = "interval_hours"
    private const val KEY_NIGHT_ENABLED = "night_enabled"

    fun schedule(context: Context, intervalHours: Int = 3, nightReminder: Boolean = true) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_ENABLED, true)
            .putInt(KEY_INTERVAL_HOURS, intervalHours)
            .putBoolean(KEY_NIGHT_ENABLED, nightReminder)
            .apply()

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // 1. Daytime 3-hour repeating reminder
        val dayIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_EXPENSE_REMINDER
        }
        val dayPendingIntent = PendingIntent.getBroadcast(
            context,
            3001,
            dayIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = Calendar.getInstance().apply {
            add(Calendar.HOUR_OF_DAY, intervalHours.coerceAtLeast(1))
        }.timeInMillis

        val intervalMillis = (intervalHours.coerceAtLeast(1) * 60 * 60 * 1000L)
        try {
            alarmManager.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                intervalMillis,
                dayPendingIntent
            )
        } catch (_: Exception) {}

        // 2. Night End-of-Day Summary Reminder at 10:15 PM (22:15)
        if (nightReminder) {
            val nightIntent = Intent(context, ReminderReceiver::class.java).apply {
                action = ReminderReceiver.ACTION_NIGHT_REMINDER
            }
            val nightPendingIntent = PendingIntent.getBroadcast(
                context,
                3002,
                nightIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val nightCalendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 22)
                set(Calendar.MINUTE, 15)
                set(Calendar.SECOND, 0)
                if (before(Calendar.getInstance())) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }

            try {
                alarmManager.setInexactRepeating(
                    AlarmManager.RTC_WAKEUP,
                    nightCalendar.timeInMillis,
                    AlarmManager.INTERVAL_DAY,
                    nightPendingIntent
                )
            } catch (_: Exception) {}
        }
    }

    fun cancel(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_ENABLED, false).apply()

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val dayIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_EXPENSE_REMINDER
        }
        val dayPendingIntent = PendingIntent.getBroadcast(
            context,
            3001,
            dayIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(dayPendingIntent)

        val nightIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_NIGHT_REMINDER
        }
        val nightPendingIntent = PendingIntent.getBroadcast(
            context,
            3002,
            nightIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(nightPendingIntent)
    }

    fun sendTestNotification(context: Context) {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_TEST_REMINDER
        }
        context.sendBroadcast(intent)
    }

    fun reschedule(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_ENABLED, true)) {
            val interval = prefs.getInt(KEY_INTERVAL_HOURS, 3)
            val night = prefs.getBoolean(KEY_NIGHT_ENABLED, true)
            schedule(context, interval, night)
        }
    }
}

