import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/db/models.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../profile/ui/profile_qr_sheet.dart';
import '../domain/split_calculator.dart';

class SplitsTab extends ConsumerWidget {
  const SplitsTab({super.key});

  void _openProfileQrSheet(
    BuildContext context, {
    int? amountPaise,
    String? friendName,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileQrSheet(
        initialRequestAmountPaise: amountPaise,
        friendName: friendName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final pendingShares = state.splitShares
        .where((s) => !s.isSettled)
        .toList();
    final settledShares = state.splitShares.where((s) => s.isSettled).toList();

    final totalPendingPaise = pendingShares.fold<int>(
      0,
      (sum, s) => sum + s.sharePaise,
    );
    final totalSettledPaise = settledShares.fold<int>(
      0,
      (sum, s) => sum + s.sharePaise,
    );
    final hasCustomQrImage = state.upiQrImagePath != null &&
        File(state.upiQrImagePath!).existsSync();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(22),
          borderColor: luxe.borderHighlight,
          glowColor: luxe.emerald,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OWED TO YOU (PENDING)',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    AnimatedAmount(
                      paise: totalPendingPaise,
                      tone: AmountTone.credit,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Settled so far: ${AnimatedAmount.formatPaise(totalSettledPaise)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _openProfileQrSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: luxe.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: luxe.emerald.withValues(alpha: 0.35),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    size: 32,
                    color: Color(0xFF041510),
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.08, end: 0),
        const SizedBox(height: 16),
        // Dedicated UPI QR Code Image & Receive Payment Card for Splitting Bills
        GlassCard(
          padding: const EdgeInsets.all(18),
          onTap: () => _openProfileQrSheet(context),
          child: Row(
            children: [
              if (hasCustomQrImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(state.upiQrImagePath!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: luxe.emerald.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: luxe.emerald.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_rounded,
                    color: luxe.emerald,
                    size: 28,
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCustomQrImage
                          ? 'My UPI QR Code • Ready to Scan'
                          : 'Add Your UPI QR Code Image',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasCustomQrImage
                          ? 'Tap to show your uploaded QR image or request split payments from friends'
                          : 'Upload your GPay / PhonePe / Paytm QR image to show friends & receive split payments',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: luxe.emerald,
              ),
            ],
          ),
        ).animate().fadeIn(delay: 60.ms).slideY(begin: 0.08, end: 0),
        const SizedBox(height: 20),
        Text(
          'Pending Friend Splits (${pendingShares.length})',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        if (pendingShares.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.group_outlined, size: 40, color: luxe.textMuted),
                const SizedBox(height: 10),
                Text(
                  'No pending split dues',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Toggle "Split with Friends" when adding an expense or say "Spent 300 on dinner with Rahul" in a Voice Note!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          )
        else
          ...pendingShares.map((share) {
            return GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: luxe.cyan.withValues(alpha: 0.2),
                        child: Text(
                          share.friendName.isNotEmpty
                              ? share.friendName[0].toUpperCase()
                              : 'F',
                          style: TextStyle(
                            color: luxe.cyan,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              share.friendName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              'Owes you for shared expense',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      AnimatedAmount(
                        paise: share.sharePaise,
                        tone: AmountTone.credit,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showUpiQrSheet(context, state, share),
                          icon: Icon(
                            Icons.qr_code_rounded,
                            size: 18,
                            color: luxe.cyan,
                          ),
                          label: const Text('Show UPI QR'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: luxe.emerald,
                            foregroundColor: const Color(0xFF041510),
                          ),
                          onPressed: () => ref
                              .read(finTrackControllerProvider.notifier)
                              .settleSplitShare(share),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Settle (+Credit)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        if (settledShares.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Settled Repayments',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          ...settledShares.take(10).map((share) {
            return GlassCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${share.friendName} • Paid back',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  AnimatedAmount(
                    paise: share.sharePaise,
                    showSign: true,
                    tone: AmountTone.credit,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  void _showUpiQrSheet(
    BuildContext context,
    FinTrackState state,
    SplitShareModel share,
  ) {
    final vpa = state.upiVpa.trim().isEmpty
        ? 'yourname@upi'
        : state.upiVpa.trim();
    final upiUri = SplitCalculator.buildUpiPaymentUri(
      payeeVpa: vpa,
      payeeName: state.upiName,
      amountPaise: share.sharePaise,
      note: 'Split share for ${share.friendName}',
    );
    final formattedAmt = AnimatedAmount.formatPaise(share.sharePaise);
    final hasCustomQrImage = state.upiQrImagePath != null &&
        File(state.upiQrImagePath!).existsSync();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool showUploaded = hasCustomQrImage;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final luxe = ctx.luxe;
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: luxe.bgElevated,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border.all(color: luxe.borderSubtle),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Request $formattedAmt from ${share.friendName}',
                    style: Theme.of(ctx).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Payee UPI ID: $vpa',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  if (hasCustomQrImage)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('My Uploaded QR'),
                          selected: showUploaded,
                          onSelected: (_) =>
                              setModalState(() => showUploaded = true),
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: Text('Auto $formattedAmt QR'),
                          selected: !showUploaded,
                          onSelected: (_) =>
                              setModalState(() => showUploaded = false),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  if (showUploaded && hasCustomQrImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.file(
                        File(state.upiQrImagePath!),
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: QrImageView(
                        data: upiUri.toString(),
                        size: 200,
                      ),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          label: 'Share UPI Link',
                          icon: Icons.share_outlined,
                          onPressed: () {
                            SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Hey ${share.friendName}, your split share is $formattedAmt. Pay via UPI: $upiUri',
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GradientButton(
                          label: 'Open UPI App',
                          icon: Icons.open_in_new_rounded,
                          gradient: luxe.copilotGradient,
                          onPressed: () => launchUrl(upiUri),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
