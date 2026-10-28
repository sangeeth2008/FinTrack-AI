import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _kDbKey = 'ft_db_encryption_key';
  static const _kPinHash = 'ft_pin_hash';
  static const _kPinSalt = 'ft_pin_salt';
  static const _kBiometricEnabled = 'ft_biometric_enabled';
  static const _kFailedAttempts = 'ft_failed_pin_attempts';
  static const _kLockoutUntilMs = 'ft_lockout_until_ms';
  static const _kGeminiApiKey = 'ft_gemini_api_key';
  static const _kThemeMode = 'ft_theme_mode';
  static const _kHourlyRatePaise = 'ft_hourly_rate_paise';
  static const _kUpiVpa = 'ft_upi_vpa';
  static const _kUpiName = 'ft_upi_name';
  static const _kUpiQrImagePath = 'ft_upi_qr_image_path';
  static const _kMonthlyBudgetPaise = 'ft_monthly_budget_paise';
  static const _kDailySpendLimitPaise = 'ft_daily_spend_limit_paise';
  static const _kExpenseReminderEnabled = 'ft_expense_reminder_enabled';
  static const _kExpenseReminderIntervalHours = 'ft_expense_reminder_interval_hours';
  static const _kNightReminderEnabled = 'ft_night_reminder_enabled';
  static const _kLastDailySummaryJson = 'ft_last_daily_summary_json';
  static const _kLockoutDurationMinutes = 'ft_lockout_duration_minutes';
  static const _kMaxLoginAttempts = 'ft_max_login_attempts';
  static const _kAlwaysLockOnMinimize = 'ft_always_lock_on_minimize';
  static const _kAutoSmsEnabled = 'ft_auto_sms_enabled';
  static const _kLastSmsSyncMs = 'ft_last_sms_sync_ms';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memoryStore;

  const SecureStore._(this._storage, this._memoryStore);

  factory SecureStore.platform() {
    return const SecureStore._(
      FlutterSecureStorage(),
      null,
    );
  }

  factory SecureStore.inMemory([Map<String, String>? initial]) {
    return SecureStore._(null, Map<String, String>.from(initial ?? {}));
  }

  Future<String?> _read(String key) async {
    if (_memoryStore != null) return _memoryStore[key];
    return _storage!.read(key: key);
  }

  Future<void> _write(String key, String? value) async {
    if (_memoryStore != null) {
      if (value == null) {
        _memoryStore.remove(key);
      } else {
        _memoryStore[key] = value;
      }
      return;
    }
    if (value == null) {
      await _storage!.delete(key: key);
    } else {
      await _storage!.write(key: key, value: value);
    }
  }

  Future<String> getOrCreateDatabaseKey() async {
    final existing = await _read(_kDbKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final key = base64UrlEncode(bytes);
    await _write(_kDbKey, key);
    return key;
  }

  Future<bool> hasPin() async {
    final hash = await _read(_kPinHash);
    final salt = await _read(_kPinSalt);
    return hash != null && hash.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  Future<({String? hash, String? salt})> getPinCredentials() async {
    final hash = await _read(_kPinHash);
    final salt = await _read(_kPinSalt);
    return (hash: hash, salt: salt);
  }

  Future<void> savePinCredentials({
    required String hashBase64,
    required String saltBase64,
  }) async {
    await _write(_kPinHash, hashBase64);
    await _write(_kPinSalt, saltBase64);
  }

  Future<bool> isBiometricEnabled() async {
    return (await _read(_kBiometricEnabled)) == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _write(_kBiometricEnabled, enabled ? 'true' : 'false');
  }

  Future<int> getFailedAttempts() async {
    final raw = await _read(_kFailedAttempts);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> setFailedAttempts(int count) async {
    await _write(_kFailedAttempts, count.toString());
  }

  Future<DateTime?> getLockoutUntil() async {
    final raw = await _read(_kLockoutUntilMs);
    final ms = int.tryParse(raw ?? '');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLockoutUntil(DateTime? until) async {
    await _write(
      _kLockoutUntilMs,
      until?.millisecondsSinceEpoch.toString(),
    );
  }

  Future<String?> getGeminiApiKey() async {
    final key = await _read(_kGeminiApiKey);
    if (key == null || key.trim().isEmpty) return null;
    return key.trim();
  }

  Future<void> setGeminiApiKey(String? apiKey) async {
    final trimmed = apiKey?.trim();
    await _write(
      _kGeminiApiKey,
      (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
  }

  Future<String> getThemeMode() async {
    return (await _read(_kThemeMode)) ?? 'dark';
  }

  Future<void> setThemeMode(String mode) async {
    await _write(_kThemeMode, mode);
  }

  Future<int> getHourlyRatePaise() async {
    final raw = await _read(_kHourlyRatePaise);
    return int.tryParse(raw ?? '') ?? 50000; // Default ₹500/hr
  }

  Future<void> setHourlyRatePaise(int paise) async {
    await _write(_kHourlyRatePaise, paise.toString());
  }

  Future<String> getUpiVpa() async {
    return (await _read(_kUpiVpa)) ?? '';
  }

  Future<void> setUpiVpa(String vpa) async {
    await _write(_kUpiVpa, vpa.trim());
  }

  Future<String> getUpiName() async {
    return (await _read(_kUpiName)) ?? 'Me';
  }

  Future<void> setUpiName(String name) async {
    await _write(_kUpiName, name.trim().isEmpty ? 'Me' : name.trim());
  }

  Future<int> getMonthlyBudgetPaise() async {
    final raw = await _read(_kMonthlyBudgetPaise);
    return int.tryParse(raw ?? '') ?? 2500000; // Default ₹25,000
  }

  Future<void> setMonthlyBudgetPaise(int paise) async {
    await _write(_kMonthlyBudgetPaise, paise.toString());
  }

  Future<int> getDailySpendLimitPaise() async {
    final raw = await _read(_kDailySpendLimitPaise);
    return int.tryParse(raw ?? '') ?? 150000; // Default ₹1,500 daily spend limit
  }

  Future<void> setDailySpendLimitPaise(int paise) async {
    await _write(_kDailySpendLimitPaise, paise.toString());
  }

  Future<bool> getExpenseReminderEnabled() async {
    final raw = await _read(_kExpenseReminderEnabled);
    if (raw == null) return true; // Enabled by default
    return raw == 'true';
  }

  Future<void> setExpenseReminderEnabled(bool enabled) async {
    await _write(_kExpenseReminderEnabled, enabled ? 'true' : 'false');
  }

  Future<int> getExpenseReminderIntervalHours() async {
    final raw = await _read(_kExpenseReminderIntervalHours);
    return (int.tryParse(raw ?? '') ?? 3).clamp(1, 12);
  }

  Future<void> setExpenseReminderIntervalHours(int hours) async {
    await _write(_kExpenseReminderIntervalHours, hours.clamp(1, 12).toString());
  }

  Future<bool> getNightReminderEnabled() async {
    final raw = await _read(_kNightReminderEnabled);
    if (raw == null) return true; // Enabled by default
    return raw == 'true';
  }

  Future<void> setNightReminderEnabled(bool enabled) async {
    await _write(_kNightReminderEnabled, enabled ? 'true' : 'false');
  }

  Future<String?> getLastDailySummaryJson() async {
    return await _read(_kLastDailySummaryJson);
  }

  Future<void> setLastDailySummaryJson(String json) async {
    await _write(_kLastDailySummaryJson, json);
  }

  Future<String?> getUpiQrImagePath() async {
    final path = await _read(_kUpiQrImagePath);
    if (path == null || path.trim().isEmpty) return null;
    return path.trim();
  }

  Future<void> setUpiQrImagePath(String? path) async {
    final trimmed = path?.trim();
    await _write(
      _kUpiQrImagePath,
      (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
  }

  Future<int> getLockoutDurationMinutes() async {
    final raw = await _read(_kLockoutDurationMinutes);
    return (int.tryParse(raw ?? '') ?? 5).clamp(1, 120);
  }

  Future<void> setLockoutDurationMinutes(int minutes) async {
    await _write(_kLockoutDurationMinutes, minutes.clamp(1, 120).toString());
  }

  Future<int> getMaxLoginAttempts() async {
    final raw = await _read(_kMaxLoginAttempts);
    return (int.tryParse(raw ?? '') ?? 3).clamp(1, 10);
  }

  Future<void> setMaxLoginAttempts(int attempts) async {
    await _write(_kMaxLoginAttempts, attempts.clamp(1, 10).toString());
  }

  Future<bool> getAlwaysLockOnMinimize() async {
    final raw = await _read(_kAlwaysLockOnMinimize);
    if (raw == null) return true; // Default true per user requirement
    return raw == 'true';
  }

  Future<void> setAlwaysLockOnMinimize(bool enabled) async {
    await _write(_kAlwaysLockOnMinimize, enabled ? 'true' : 'false');
  }

  Future<bool> getAutoSmsEnabled() async {
    final raw = await _read(_kAutoSmsEnabled);
    if (raw == null) return true;
    return raw == 'true';
  }

  Future<void> setAutoSmsEnabled(bool enabled) async {
    await _write(_kAutoSmsEnabled, enabled ? 'true' : 'false');
  }

  Future<int> getLastSmsSyncEpochMs() async {
    final raw = await _read(_kLastSmsSyncMs);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> setLastSmsSyncEpochMs(int epochMs) async {
    await _write(_kLastSmsSyncMs, epochMs.toString());
  }
}

