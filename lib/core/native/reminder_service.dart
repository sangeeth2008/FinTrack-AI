import 'package:flutter/services.dart';

class ReminderService {
  static const _channel = MethodChannel('com.sangeeth.fintrack/native_bridge');

  static Future<bool> scheduleExpenseReminders({
    int intervalHours = 3,
    bool nightReminder = true,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'scheduleExpenseReminders',
        {
          'intervalHours': intervalHours,
          'nightReminder': nightReminder,
        },
      );
      return res ?? true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> cancelExpenseReminders() async {
    try {
      final res = await _channel.invokeMethod<bool>('cancelExpenseReminders');
      return res ?? true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> showTestReminder() async {
    try {
      final res = await _channel.invokeMethod<bool>('showTestReminder');
      return res ?? true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestNotificationPermission');
    } catch (_) {}
  }

  static Future<String?> getPendingNotificationRoute() async {
    try {
      return await _channel.invokeMethod<String>('getPendingNotificationRoute');
    } catch (_) {
      return null;
    }
  }
}

