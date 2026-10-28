import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/motion/motion.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/security/lock_controller.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/luxe_scaffold.dart';
import '../../../shared/widgets/pin_pad.dart';

class VaultLockScreen extends ConsumerStatefulWidget {
  const VaultLockScreen({super.key});

  @override
  ConsumerState<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends ConsumerState<VaultLockScreen> {
  String _enteredPin = '';
  String? _firstOnboardingPin;
  bool _enableBiometricOnSetup = true;
  bool _hasError = false;
  String? _localMessage;
  Timer? _cooldownTimer;
  int _lastHandledPulse = -1;

  @override
  void initState() {
    super.initState();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final lockState = ref.read(lockControllerProvider);
      if (lockState.isCoolingDown(DateTime.now()) && mounted) {
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoBiometric();
    });
  }

  void _tryAutoBiometric() {
    if (!mounted) return;
    final lockState = ref.read(lockControllerProvider);
    if (lockState.status == VaultStatus.locked &&
        lockState.biometricAvailable &&
        !lockState.isCoolingDown(DateTime.now())) {
      ref.read(lockControllerProvider.notifier).unlockWithBiometrics();
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onDigitPressed(String digit) async {
    final lockState = ref.read(lockControllerProvider);
    if (lockState.isCoolingDown(DateTime.now())) {
      LuxeHaptics.heavy();
      return;
    }
    if (_enteredPin.length >= 6) return;

    setState(() {
      _hasError = false;
      _localMessage = null;
      _enteredPin += digit;
    });

    if (_enteredPin.length == 6) {
      await _handleSixDigitsComplete(lockState);
    }
  }

  Future<void> _handleSixDigitsComplete(VaultLockState lockState) async {
    if (lockState.status == VaultStatus.needsOnboarding) {
      if (_firstOnboardingPin == null) {
        LuxeHaptics.medium();
        setState(() {
          _firstOnboardingPin = _enteredPin;
          _enteredPin = '';
          _localMessage = 'Re-enter your 6-digit PIN to confirm';
        });
        return;
      }

      if (_enteredPin == _firstOnboardingPin) {
        LuxeHaptics.medium();
        await ref.read(lockControllerProvider.notifier).setupPinAndUnlock(
              pin: _enteredPin,
              enableBiometric: _enableBiometricOnSetup,
            );
      } else {
        LuxeHaptics.heavy();
        setState(() {
          _hasError = true;
          _enteredPin = '';
          _firstOnboardingPin = null;
          _localMessage = 'PINs did not match. Let\'s try again.';
        });
      }
      return;
    }

    // Unlocking existing vault
    final ok = await ref
        .read(lockControllerProvider.notifier)
        .unlockWithPin(_enteredPin);
    if (!ok && mounted) {
      LuxeHaptics.heavy();
      setState(() {
        _hasError = true;
        _enteredPin = '';
      });
    } else {
      LuxeHaptics.medium();
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _hasError = false;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  void _onClearAll() {
    if (_enteredPin.isEmpty) return;
    LuxeHaptics.medium();
    setState(() {
      _hasError = false;
      _enteredPin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final lockState = ref.watch(lockControllerProvider);

    // Whenever the app resumes from minimize/close, automatically prompt biometrics
    if (lockState.resumeBiometricPulse != _lastHandledPulse) {
      _lastHandledPulse = lockState.resumeBiometricPulse;
      if (_lastHandledPulse > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryAutoBiometric();
        });
      }
    }

    final isOnboarding = lockState.status == VaultStatus.needsOnboarding;
    final now = DateTime.now();
    final isCoolingDown = lockState.isCoolingDown(now);

    // Dedicated Access Denied / 5-Min Cooldown Lockout Screen
    if (!isOnboarding && (lockState.showDeniedScreen || isCoolingDown)) {
      return _VaultAccessDeniedScreen(
        lockState: lockState,
        isCoolingDown: isCoolingDown,
        formattedCooldown: lockState.formatRemainingCooldown(now),
        onTryAgain: () {
          LuxeHaptics.selection();
          ref.read(lockControllerProvider.notifier).dismissDeniedScreen();
        },
        onBiometric: lockState.biometricAvailable && !isCoolingDown
            ? () => ref
                .read(lockControllerProvider.notifier)
                .unlockWithBiometrics()
            : null,
      );
    }

    final String titleText;
    final String subtitleText;

    if (isOnboarding) {
      titleText = _firstOnboardingPin == null
          ? 'Create Your Vault PIN'
          : 'Confirm Your Vault PIN';
      subtitleText = _localMessage ??
          'All records are encrypted locally with SQLCipher & PBKDF2-SHA256.';
    } else {
      titleText = 'FinTrack AI Vault';
      final remTries = lockState.remainingAttemptsBeforeLockout;
      subtitleText = lockState.errorMessage ??
          'Enter 6-digit PIN or use Biometrics ($remTries/${lockState.maxAttempts} attempts left)';
    }

    return LuxeScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            children: [
              const Spacer(flex: 1),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: luxe.emerald.withValues(alpha: 0.42),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                  ),
                ),
              )
                  .animate()
                  .scale(duration: LuxeMotion.medium, curve: LuxeMotion.bounce)
                  .fadeIn(),
              const SizedBox(height: 18),
              Text(
                titleText,
                style: Theme.of(context).textTheme.displaySmall,
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.15, end: 0),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  subtitleText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _hasError ? luxe.crimson : luxe.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              PinDots(
                filledCount: _enteredPin.length,
                hasError: _hasError,
              ),
              if (_enteredPin.isNotEmpty) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _onClearAll,
                  icon: Icon(
                    Icons.restart_alt_rounded,
                    size: 16,
                    color: luxe.crimson,
                  ),
                  label: Text(
                    'Clear Entered Digits',
                    style: TextStyle(
                      color: luxe.crimson,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (isOnboarding && lockState.biometricAvailable) ...[
                const SizedBox(height: 16),
                GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  borderRadius: 18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fingerprint_rounded,
                        color: luxe.emerald,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Always Require Biometric Unlock',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: luxe.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: _enableBiometricOnSetup,
                        activeTrackColor: luxe.emerald,
                        onChanged: (v) =>
                            setState(() => _enableBiometricOnSetup = v),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(flex: 1),
              GlassNumPad(
                onDigit: _onDigitPressed,
                onBackspace: _onBackspace,
                onClear: _onClearAll,
                hasEnteredDigits: _enteredPin.isNotEmpty,
                showBiometric: !isOnboarding && lockState.biometricAvailable,
                onBiometric: () => ref
                    .read(lockControllerProvider.notifier)
                    .unlockWithBiometrics(),
              ).animate().fadeIn(delay: 140.ms).slideY(begin: 0.08, end: 0),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    size: 14,
                    color: luxe.emerald,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '3-STRIKE SHIELD • ${lockState.lockoutDurationMinutes}M AUTO-LOCKOUT • SQLCIPHER',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: luxe.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dedicated Access Denied & 5-Minute Cooldown Lockout Screen
class _VaultAccessDeniedScreen extends StatelessWidget {
  final VaultLockState lockState;
  final bool isCoolingDown;
  final String formattedCooldown;
  final VoidCallback onTryAgain;
  final VoidCallback? onBiometric;

  const _VaultAccessDeniedScreen({
    required this.lockState,
    required this.isCoolingDown,
    required this.formattedCooldown,
    required this.onTryAgain,
    this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final usedTries = lockState.failedAttempts % lockState.maxAttempts == 0
        ? lockState.maxAttempts
        : lockState.failedAttempts % lockState.maxAttempts;
    final leftTries = lockState.maxAttempts - usedTries;

    return LuxeScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: luxe.debitGradient,
                  boxShadow: [
                    BoxShadow(
                      color: luxe.crimson.withValues(alpha: 0.55),
                      blurRadius: 42,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  isCoolingDown
                      ? Icons.timer_off_rounded
                      : Icons.gpp_bad_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              )
                  .animate()
                  .scale(duration: 420.ms, curve: LuxeMotion.bounce)
                  .shake(hz: 5, duration: 450.ms),
              const SizedBox(height: 24),
              Text(
                isCoolingDown ? 'VAULT LOCKED OUT' : 'ACCESS DENIED',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: luxe.crimson,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.15, end: 0),
              const SizedBox(height: 10),
              Text(
                isCoolingDown
                    ? 'Maximum ${lockState.maxAttempts} failed login attempts reached.\nSecurity lockdown active for ${lockState.lockoutDurationMinutes} minutes.'
                    : 'Incorrect Vault PIN entered.\nSecurity Intrusion Shield has logged this attempt.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: luxe.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              GlassCard(
                padding: const EdgeInsets.all(22),
                borderColor: luxe.crimson.withValues(alpha: 0.55),
                glowColor: luxe.crimson,
                child: Column(
                  children: [
                    if (isCoolingDown) ...[
                      Text(
                        'UNLOCKING AVAILABLE IN',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: luxe.crimson,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        formattedCooldown,
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              color: luxe.crimson,
                              fontFamily: 'JetBrains Mono',
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Wait for the timer to expire (configurable in Settings)',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(lockState.maxAttempts, (index) {
                          final isFailed = index < usedTries;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isFailed
                                  ? luxe.crimson.withValues(alpha: 0.22)
                                  : luxe.surfaceGlass,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isFailed
                                    ? luxe.crimson
                                    : luxe.borderSubtle,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isFailed
                                      ? Icons.close_rounded
                                      : Icons.shield_outlined,
                                  size: 16,
                                  color: isFailed
                                      ? luxe.crimson
                                      : luxe.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Try ${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isFailed
                                        ? luxe.crimson
                                        : luxe.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '$leftTries ${leftTries == 1 ? "attempt" : "attempts"} remaining before ${lockState.lockoutDurationMinutes}-minute vault lockdown',
                        style: TextStyle(
                          color: luxe.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ).animate().fadeIn(delay: 140.ms).scale(begin: const Offset(0.95, 0.95)),
              const Spacer(),
              if (!isCoolingDown) ...[
                GradientButton(
                  label: 'Try PIN Again',
                  icon: Icons.lock_reset_rounded,
                  gradient: luxe.debitGradient,
                  onPressed: onTryAgain,
                ),
                if (onBiometric != null) ...[
                  const SizedBox(height: 12),
                  GradientButton(
                    label: 'Authenticate with Biometrics',
                    icon: Icons.fingerprint_rounded,
                    onPressed: onBiometric,
                  ),
                ],
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dedicated Animated Liquid-Glass Welcome Screen shown upon Vault Unlock
class VaultWelcomeScreen extends ConsumerStatefulWidget {
  const VaultWelcomeScreen({super.key});

  @override
  ConsumerState<VaultWelcomeScreen> createState() => _VaultWelcomeScreenState();
}

class _VaultWelcomeScreenState extends ConsumerState<VaultWelcomeScreen> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _autoDismissTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        ref.read(lockControllerProvider.notifier).dismissWelcomeScreen();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final finState = ref.watch(finTrackControllerProvider);
    final displayName = finState.upiName.trim().isEmpty ||
            finState.upiName.trim() == 'Me'
        ? 'Financial Command'
        : finState.upiName.trim();

    return LuxeScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: luxe.emerald.withValues(alpha: 0.50),
                      blurRadius: 44,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
              )
                  .animate()
                  .scale(duration: 480.ms, curve: LuxeMotion.bounce)
                  .fadeIn(),
              const SizedBox(height: 24),
              Text(
                'VAULT DECRYPTED',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: luxe.emerald,
                  letterSpacing: 2.2,
                ),
              ).animate().fadeIn(delay: 80.ms),
              const SizedBox(height: 8),
              Text(
                'Welcome Back,\n$displayName',
                style: Theme.of(context).textTheme.displayMedium,
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.15, end: 0),
              const SizedBox(height: 22),
              GlassCard(
                padding: const EdgeInsets.all(22),
                borderColor: luxe.borderHighlight,
                glowColor: luxe.emerald,
                child: Column(
                  children: [
                    Text(
                      'TOTAL AVAILABLE BALANCE',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    AnimatedAmount(
                      paise: finState.cashflow.totalBalancePaise,
                      tone: AmountTone.neutral,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: luxe.gold,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            finState.dailyOpeningTip,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: 180.ms)
                  .scale(begin: const Offset(0.94, 0.94)),
              const Spacer(),
              GradientButton(
                label: 'Enter FinTrack AI',
                icon: Icons.arrow_forward_rounded,
                onPressed: () {
                  LuxeHaptics.selection();
                  ref
                      .read(lockControllerProvider.notifier)
                      .dismissWelcomeScreen();
                },
              ).animate().fadeIn(delay: 240.ms),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
