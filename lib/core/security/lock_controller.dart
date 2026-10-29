import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'biometric_service.dart';
import 'pin_hasher.dart';
import 'secure_store.dart';

enum VaultStatus { initializing, needsOnboarding, locked, unlocked }

class VaultLockState {
  final VaultStatus status;
  final bool biometricEnabled;
  final bool biometricAvailable;
  final int failedAttempts;
  final int maxAttempts;
  final int lockoutDurationMinutes;
  final bool alwaysLockOnMinimize;
  final DateTime? lockoutUntil;
  final String? errorMessage;
  final bool showDeniedScreen;
  final bool showWelcomeScreen;
  final int resumeBiometricPulse;

  const VaultLockState({
    required this.status,
    this.biometricEnabled = false,
    this.biometricAvailable = false,
    this.failedAttempts = 0,
    this.maxAttempts = 3,
    this.lockoutDurationMinutes = 5,
    this.alwaysLockOnMinimize = true,
    this.lockoutUntil,
    this.errorMessage,
    this.showDeniedScreen = false,
    this.showWelcomeScreen = false,
    this.resumeBiometricPulse = 0,
  });

  bool isCoolingDown(DateTime now) =>
      lockoutUntil != null && lockoutUntil!.isAfter(now);

  int remainingCooldownSeconds(DateTime now) {
    if (!isCoolingDown(now)) return 0;
    return lockoutUntil!.difference(now).inSeconds.clamp(1, 86400);
  }

  int get remainingAttemptsBeforeLockout {
    final rem = maxAttempts - (failedAttempts % maxAttempts);
    return rem.clamp(1, maxAttempts);
  }

  String formatRemainingCooldown(DateTime now) {
    final totalSec = remainingCooldownSeconds(now);
    final mins = totalSec ~/ 60;
    final secs = totalSec % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  VaultLockState copyWith({
    VaultStatus? status,
    bool? biometricEnabled,
    bool? biometricAvailable,
    int? failedAttempts,
    int? maxAttempts,
    int? lockoutDurationMinutes,
    bool? alwaysLockOnMinimize,
    DateTime? lockoutUntil,
    bool clearLockout = false,
    String? errorMessage,
    bool clearError = false,
    bool? showDeniedScreen,
    bool? showWelcomeScreen,
    int? resumeBiometricPulse,
  }) {
    return VaultLockState(
      status: status ?? this.status,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      lockoutDurationMinutes:
          lockoutDurationMinutes ?? this.lockoutDurationMinutes,
      alwaysLockOnMinimize: alwaysLockOnMinimize ?? this.alwaysLockOnMinimize,
      lockoutUntil: clearLockout ? null : (lockoutUntil ?? this.lockoutUntil),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      showDeniedScreen: showDeniedScreen ?? this.showDeniedScreen,
      showWelcomeScreen: showWelcomeScreen ?? this.showWelcomeScreen,
      resumeBiometricPulse: resumeBiometricPulse ?? this.resumeBiometricPulse,
    );
  }
}

final secureStoreProvider = Provider<SecureStore>((ref) {
  return SecureStore.platform();
});

final pinHasherProvider = Provider<PinHasher>((ref) {
  return const PinHasher();
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final lockControllerProvider =
    NotifierProvider<LockController, VaultLockState>(
  LockController.new,
);

class LockController extends Notifier<VaultLockState> {
  DateTime? _backgroundedAt;
  bool _isBiometricDialogActive = false;
  static const Duration autoLockTimeout = Duration(seconds: 30);

  bool get isBiometricDialogActive => _isBiometricDialogActive;

  @override
  VaultLockState build() {
    _initialize();
    return const VaultLockState(status: VaultStatus.initializing);
  }

  SecureStore get _store => ref.read(secureStoreProvider);
  PinHasher get _hasher => ref.read(pinHasherProvider);
  BiometricService get _biometric => ref.read(biometricServiceProvider);

  Future<void> _initialize() async {
    final hasPin = await _store.hasPin();
    final bioAvailable = await _biometric.isAvailable();
    final bioEnabled = await _store.isBiometricEnabled();
    final attempts = await _store.getFailedAttempts();
    final lockoutUntil = await _store.getLockoutUntil();
    final maxAttempts = await _store.getMaxLoginAttempts();
    final lockoutMinutes = await _store.getLockoutDurationMinutes();
    final alwaysLock = await _store.getAlwaysLockOnMinimize();

    if (!hasPin) {
      state = VaultLockState(
        status: VaultStatus.needsOnboarding,
        biometricAvailable: bioAvailable,
        biometricEnabled: false,
        maxAttempts: maxAttempts,
        lockoutDurationMinutes: lockoutMinutes,
        alwaysLockOnMinimize: alwaysLock,
      );
      return;
    }

    state = VaultLockState(
      status: VaultStatus.locked,
      biometricAvailable: bioAvailable,
      biometricEnabled: bioEnabled && bioAvailable,
      failedAttempts: attempts,
      maxAttempts: maxAttempts,
      lockoutDurationMinutes: lockoutMinutes,
      alwaysLockOnMinimize: alwaysLock,
      lockoutUntil: lockoutUntil,
    );
  }

  Future<void> setupPinAndUnlock({
    required String pin,
    required bool enableBiometric,
  }) async {
    final record = await _hasher.createPinRecord(pin);
    await _store.savePinCredentials(
      hashBase64: record.hashBase64,
      saltBase64: record.saltBase64,
    );
    await _store.setBiometricEnabled(enableBiometric);
    await _store.setFailedAttempts(0);
    await _store.setLockoutUntil(null);

    state = state.copyWith(
      status: VaultStatus.unlocked,
      biometricEnabled: enableBiometric && state.biometricAvailable,
      failedAttempts: 0,
      clearLockout: true,
      clearError: true,
      showDeniedScreen: false,
      showWelcomeScreen: true,
    );
  }

  Future<bool> unlockWithPin(String pin, {DateTime? nowOverride}) async {
    final now = nowOverride ?? DateTime.now();
    if (state.isCoolingDown(now)) {
      state = state.copyWith(
        showDeniedScreen: true,
        errorMessage:
            'Vault locked. Try again in ${state.formatRemainingCooldown(now)}.',
      );
      return false;
    }

    final creds = await _store.getPinCredentials();
    if (creds.hash == null || creds.salt == null) return false;

    final valid = await _hasher.verifyPin(
      pin,
      storedHashBase64: creds.hash!,
      storedSaltBase64: creds.salt!,
    );

    if (valid) {
      // Transition UI state immediately for 60fps / 120fps instant unlock
      state = state.copyWith(
        status: VaultStatus.unlocked,
        failedAttempts: 0,
        clearLockout: true,
        clearError: true,
        showDeniedScreen: false,
        showWelcomeScreen: true,
      );
      await _store.setFailedAttempts(0);
      await _store.setLockoutUntil(null);
      return true;
    }

    final newAttempts = state.failedAttempts + 1;
    await _store.setFailedAttempts(newAttempts);

    final maxTries = state.maxAttempts;
    final lockMins = state.lockoutDurationMinutes;

    DateTime? newLockout;
    if (newAttempts >= maxTries && newAttempts % maxTries == 0) {
      newLockout = now.add(Duration(minutes: lockMins));
      await _store.setLockoutUntil(newLockout);
    }

    final triesLeft = maxTries - (newAttempts % maxTries);
    state = state.copyWith(
      failedAttempts: newAttempts,
      lockoutUntil: newLockout,
      showDeniedScreen: true,
      errorMessage: newLockout != null
          ? '3 incorrect attempts! Vault locked for $lockMins min (${state.formatRemainingCooldown(now)})'
          : 'Access Denied • Incorrect PIN ($triesLeft ${triesLeft == 1 ? "attempt" : "attempts"} left before $lockMins min lockout)',
    );
    return false;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.biometricAvailable || _isBiometricDialogActive) return false;
    if (state.isCoolingDown(DateTime.now())) return false;

    _isBiometricDialogActive = true;
    try {
      final ok = await _biometric.authenticate();
      if (ok) {
        // Update state immediately before async storage writes for instant 120fps unlock
        state = state.copyWith(
          status: VaultStatus.unlocked,
          failedAttempts: 0,
          clearLockout: true,
          clearError: true,
          showDeniedScreen: false,
          showWelcomeScreen: true,
        );
        await _store.setFailedAttempts(0);
        await _store.setLockoutUntil(null);
        return true;
      }
      return false;
    } finally {
      _isBiometricDialogActive = false;
    }
  }

  void dismissDeniedScreen() {
    if (state.showDeniedScreen) {
      state = state.copyWith(showDeniedScreen: false);
    }
  }

  void dismissWelcomeScreen() {
    if (state.showWelcomeScreen) {
      state = state.copyWith(showWelcomeScreen: false);
    }
  }

  Future<void> setBiometricPreference(bool enabled) async {
    await _store.setBiometricEnabled(enabled);
    state = state.copyWith(
      biometricEnabled: enabled && state.biometricAvailable,
    );
  }

  Future<void> setSecurityLockoutSettings({
    int? lockoutDurationMinutes,
    int? maxAttempts,
    bool? alwaysLockOnMinimize,
  }) async {
    if (lockoutDurationMinutes != null) {
      await _store.setLockoutDurationMinutes(lockoutDurationMinutes);
    }
    if (maxAttempts != null) {
      await _store.setMaxLoginAttempts(maxAttempts);
    }
    if (alwaysLockOnMinimize != null) {
      await _store.setAlwaysLockOnMinimize(alwaysLockOnMinimize);
    }
    state = state.copyWith(
      lockoutDurationMinutes:
          lockoutDurationMinutes ?? state.lockoutDurationMinutes,
      maxAttempts: maxAttempts ?? state.maxAttempts,
      alwaysLockOnMinimize: alwaysLockOnMinimize ?? state.alwaysLockOnMinimize,
    );
  }

  void lockVault() {
    if (state.status == VaultStatus.unlocked) {
      state = state.copyWith(
        status: VaultStatus.locked,
        clearError: true,
        showDeniedScreen: false,
        showWelcomeScreen: false,
      );
    }
  }

  void onAppBackgrounded({DateTime? at}) {
    if (_isBiometricDialogActive) return;
    if (state.status == VaultStatus.unlocked) {
      _backgroundedAt = at ?? DateTime.now();
      // Immediately lock when minimized or closed if alwaysLockOnMinimize is enabled
      if (state.alwaysLockOnMinimize) {
        lockVault();
      }
    }
  }

  void onAppResumed({DateTime? at}) {
    if (_isBiometricDialogActive) return;
    final now = at ?? DateTime.now();
    if (_backgroundedAt != null) {
      if (state.alwaysLockOnMinimize ||
          now.difference(_backgroundedAt!) >= autoLockTimeout) {
        lockVault();
      }
      _backgroundedAt = null;
    }
    if (state.status == VaultStatus.locked) {
      state = state.copyWith(
        resumeBiometricPulse: state.resumeBiometricPulse + 1,
      );
    }
  }
}
