import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/motion/motion.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/security/lock_controller.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../profile/ui/profile_qr_sheet.dart';

class SettingsSheet extends ConsumerStatefulWidget {
  const SettingsSheet({super.key});

  @override
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet> {
  final _apiKeyCtrl = TextEditingController();
  late final TextEditingController _dailyLimitCtrl;
  late final TextEditingController _budgetCtrl;
  late final TextEditingController _hourlyRateCtrl;
  late final TextEditingController _upiVpaCtrl;
  late final TextEditingController _upiNameCtrl;
  final _backupPassCtrl = TextEditingController();
  final _restoreJsonCtrl = TextEditingController();
  String? _feedbackMessage;

  @override
  void initState() {
    super.initState();
    final state = ref.read(finTrackControllerProvider);
    _dailyLimitCtrl = TextEditingController(
      text: (state.dailySpendLimitPaise / 100.0).toStringAsFixed(0),
    );
    _budgetCtrl = TextEditingController(
      text: (state.cashflow.monthlyBudgetPaise / 100.0).toStringAsFixed(0),
    );
    _hourlyRateCtrl = TextEditingController(
      text: (state.hourlyRatePaise / 100.0).toStringAsFixed(0),
    );
    _upiVpaCtrl = TextEditingController(text: state.upiVpa);
    _upiNameCtrl = TextEditingController(text: state.upiName);
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _dailyLimitCtrl.dispose();
    _budgetCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _upiVpaCtrl.dispose();
    _upiNameCtrl.dispose();
    _backupPassCtrl.dispose();
    _restoreJsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final notifier = ref.read(finTrackControllerProvider.notifier);

    if (_apiKeyCtrl.text.trim().isNotEmpty) {
      await notifier.saveGeminiApiKey(_apiKeyCtrl.text.trim());
      _apiKeyCtrl.clear();
    }

    final dailyRupees = double.tryParse(_dailyLimitCtrl.text.trim());
    if (dailyRupees != null && dailyRupees >= 100) {
      await notifier.updateDailySpendLimit((dailyRupees * 100).round());
    }

    final budgetRupees = double.tryParse(_budgetCtrl.text.trim());
    if (budgetRupees != null && budgetRupees > 0) {
      await notifier.updateMonthlyBudget((budgetRupees * 100).round());
    }

    final hourlyRupees = double.tryParse(_hourlyRateCtrl.text.trim());
    await notifier.updatePreferences(
      hourlyRatePaise: hourlyRupees != null && hourlyRupees > 0
          ? (hourlyRupees * 100).round()
          : null,
      upiVpa: _upiVpaCtrl.text.trim(),
      upiName: _upiNameCtrl.text.trim(),
    );

    if (mounted) {
      LuxeHaptics.medium();
      setState(() => _feedbackMessage = 'Preferences saved to secure storage!');
    }
  }

  Future<void> _exportEncryptedBackup() async {
    final pass = _backupPassCtrl.text.trim();
    if (pass.length < 4) {
      setState(
        () => _feedbackMessage =
            'Enter a backup passphrase (min 4 chars) to encrypt.',
      );
      return;
    }
    try {
      final encryptedJson = await ref
          .read(finTrackControllerProvider.notifier)
          .exportEncryptedBackup(pass);
      await Clipboard.setData(ClipboardData(text: encryptedJson));
      await SharePlus.instance.share(
        ShareParams(
          text: encryptedJson,
          subject: 'FinTrack_AI_Encrypted_Backup.ftbackup',
        ),
      );
      if (mounted) {
        setState(
          () => _feedbackMessage =
              'AES-256-GCM Encrypted Backup copied & ready to save!',
        );
      }
    } catch (e) {
      setState(() => _feedbackMessage = 'Backup error: $e');
    }
  }

  Future<void> _restoreEncryptedBackup() async {
    final pass = _backupPassCtrl.text.trim();
    final payload = _restoreJsonCtrl.text.trim();
    if (pass.isEmpty || payload.isEmpty) {
      setState(
        () => _feedbackMessage =
            'Provide both the passphrase and the encrypted backup JSON.',
      );
      return;
    }
    try {
      await ref
          .read(finTrackControllerProvider.notifier)
          .restoreEncryptedBackup(encryptedJson: payload, passphrase: pass);
      if (mounted) {
        setState(
          () => _feedbackMessage =
              'Encrypted backup decrypted & restored into vault!',
        );
      }
    } catch (e) {
      setState(
        () => _feedbackMessage = 'Restore failed (check passphrase): $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final lockState = ref.watch(lockControllerProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasQrImage = state.upiQrImagePath != null &&
        File(state.upiQrImagePath!).existsSync();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
      decoration: BoxDecoration(
        color: luxe.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: luxe.borderSubtle),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vault & AI Settings',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ref.read(lockControllerProvider.notifier).lockVault();
                  },
                  icon: Icon(Icons.shield_moon_rounded, color: luxe.crimson),
                  label: Text(
                    'Lock Now',
                    style: TextStyle(
                      color: luxe.crimson,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (_feedbackMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: luxe.emerald.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _feedbackMessage!,
                  style: TextStyle(color: luxe.emerald, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Profile & UPI QR Image Quick Card
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: luxe.borderHighlight,
              onTap: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ProfileQrSheet(),
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: luxe.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: Color(0xFF041510),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasQrImage
                              ? 'My Profile & UPI QR Image (Active)'
                              : 'Upload Your UPI QR Code Image',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Show your QR in Profile & Splits to receive money from friends',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: luxe.emerald,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Security & 3-Attempt / 5-Min Lockout Configuration
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'VAULT SECURITY & BIOMETRIC SHIELD',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Always Lock & Require Biometrics on Minimize / Close',
                    ),
                    subtitle: const Text(
                      'Immediately locks vault when app is minimized or closed',
                    ),
                    value: lockState.alwaysLockOnMinimize,
                    activeTrackColor: luxe.emerald,
                    onChanged: (v) => ref
                        .read(lockControllerProvider.notifier)
                        .setSecurityLockoutSettings(alwaysLockOnMinimize: v),
                  ),
                  if (lockState.biometricAvailable)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Biometric Fingerprint / Face Unlock'),
                      value: lockState.biometricEnabled,
                      activeTrackColor: luxe.emerald,
                      onChanged: (v) => ref
                          .read(lockControllerProvider.notifier)
                          .setBiometricPreference(v),
                    ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Lockout Duration After ${lockState.maxAttempts} Failed Logins',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: luxe.textPrimary),
                        ),
                      ),
                      Text(
                        '${lockState.lockoutDurationMinutes} min',
                        style: TextStyle(
                          color: luxe.emerald,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1, 3, 5, 10, 15, 30].map((mins) {
                      final isSel = lockState.lockoutDurationMinutes == mins;
                      return ChoiceChip(
                        label: Text('$mins min'),
                        selected: isSel,
                        onSelected: (_) {
                          LuxeHaptics.selection();
                          ref
                              .read(lockControllerProvider.notifier)
                              .setSecurityLockoutSettings(
                                lockoutDurationMinutes: mins,
                              );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Automatic SMS Spend Analyzer
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'AUTOMATIC SMS SPEND ANALYZER',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Auto-Analyze Bank SMS & Add Spend Details',
                    ),
                    subtitle: const Text(
                      'Detects bank & UPI SMS alerts and logs expenses automatically',
                    ),
                    value: state.autoSmsEnabled,
                    activeTrackColor: luxe.emerald,
                    onChanged: (v) => ref
                        .read(finTrackControllerProvider.notifier)
                        .setAutoSmsEnabled(v),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final count = await ref
                          .read(finTrackControllerProvider.notifier)
                          .syncBankSmsInbox(requestPermissionIfNeeded: true);
                      if (mounted) {
                        setState(() {
                          _feedbackMessage = count > 0
                              ? 'Synced $count new transaction(s) from SMS inbox!'
                              : 'SMS inbox scanned — all bank SMS transactions are up to date.';
                        });
                      }
                    },
                    icon: Icon(
                      Icons.sms_rounded,
                      size: 18,
                      color: luxe.emerald,
                    ),
                    label: const Text('Scan SMS Inbox Now'),
                  ),
                ],
              ),
            ),
            // Notification Reminders Card
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        color: luxe.gold,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'EXPENSE REMINDERS & NIGHT SUMMARY',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Frequent Day Reminders (Every 3 Hours)',
                    ),
                    subtitle: const Text(
                      'Reminds you during the day to log any missed cash, chai, or food expenses',
                    ),
                    value: state.expenseReminderEnabled,
                    activeTrackColor: luxe.emerald,
                    onChanged: (v) => ref
                        .read(finTrackControllerProvider.notifier)
                        .updateReminderSettings(enabled: v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Night End-of-Day Review (10:15 PM)',
                    ),
                    subtitle: const Text(
                      'Nightly check-in before sleeping to view your daily spend summary',
                    ),
                    value: state.nightReminderEnabled,
                    activeTrackColor: luxe.emerald,
                    onChanged: (v) => ref
                        .read(finTrackControllerProvider.notifier)
                        .updateReminderSettings(nightReminder: v),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: luxe.gold.withValues(alpha: 0.6)),
                    ),
                    onPressed: () async {
                      await ref
                          .read(finTrackControllerProvider.notifier)
                          .sendTestReminder();
                      if (mounted) {
                        LuxeHaptics.medium();
                        setState(() {
                          _feedbackMessage =
                              'Notification sent! Check your Android status bar.';
                        });
                      }
                    },
                    icon: Icon(
                      Icons.notifications_rounded,
                      size: 17,
                      color: luxe.gold,
                    ),
                    label: Text(
                      'Send Test Notification Now',
                      style: TextStyle(
                        color: luxe.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'APPEARANCE THEME',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.nights_stay_rounded, size: 16),
                  label: Text('Obsidian'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.wb_sunny_rounded, size: 16),
                  label: Text('Ivory'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.auto_awesome_mosaic_rounded, size: 16),
                  label: Text('System'),
                ),
              ],
              selected: {state.themeMode},
              onSelectionChanged: (s) => ref
                  .read(finTrackControllerProvider.notifier)
                  .setThemeMode(s.first),
            ),
            const SizedBox(height: 16),
            Text(
              'GEMINI 3.8 FLASH API KEY (STORED IN KEYSTORE)',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: state.hasGeminiKey
                    ? '•••••••••••••••• (Key Configured — enter new to replace)'
                    : 'Paste your Gemini API Key (AIza...)',
                suffixIcon: Icon(
                  state.hasGeminiKey
                      ? Icons.verified_rounded
                      : Icons.key_rounded,
                  color: state.hasGeminiKey ? luxe.emerald : luxe.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dailyLimitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      labelText: 'Daily Spend Limit',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _budgetCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      labelText: 'Monthly Budget',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hourlyRateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      labelText: 'Your Hourly Value (₹/hr)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _upiVpaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Your UPI ID (for Splits)',
                      hintText: 'name@okaxis',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _upiNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Save Settings',
              icon: Icons.save_outlined,
              onPressed: _saveSettings,
            ),
            const SizedBox(height: 22),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'AES-256-GCM ENCRYPTED LOCAL BACKUP',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _backupPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Backup Encryption Passphrase',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _restoreJsonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Paste Encrypted Backup JSON (for Restore)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportEncryptedBackup,
                          icon: const Icon(Icons.upload_outlined, size: 18),
                          label: const Text('Export Backup'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restoreEncryptedBackup,
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Restore Backup'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
