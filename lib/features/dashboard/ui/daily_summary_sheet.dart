import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/motion/motion.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';

class DailySummarySheet extends ConsumerStatefulWidget {
  const DailySummarySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DailySummarySheet(),
    );
  }

  @override
  ConsumerState<DailySummarySheet> createState() => _DailySummarySheetState();
}

class _DailySummarySheetState extends ConsumerState<DailySummarySheet> {
  final _limitCtrl = TextEditingController();
  bool _isEditingLimit = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(finTrackControllerProvider);
    _limitCtrl.text =
        (state.dailySpendLimitPaise / 100.0).toStringAsFixed(0);
    if (state.dailySummary == null) {
      ref.read(finTrackControllerProvider.notifier).refreshDailySummary();
    }
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLimit() async {
    final val = double.tryParse(_limitCtrl.text.replaceAll(',', '').trim());
    if (val != null && val >= 100) {
      await ref
          .read(finTrackControllerProvider.notifier)
          .updateDailySpendLimit((val * 100).round());
      setState(() => _isEditingLimit = false);
      LuxeHaptics.medium();
    }
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final summary = state.dailySummary;
    final isLoading = state.isDailySummaryLoading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final spentPaise = state.cashflow.spentTodayPaise;
    final limitPaise = state.dailySpendLimitPaise;
    final progress = (spentPaise / limitPaise).clamp(0.0, 1.0);
    final isOver = spentPaise > limitPaise;

    final statusColor = isOver
        ? luxe.crimson
        : (spentPaise == 0 ? luxe.cyan : luxe.emerald);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      decoration: BoxDecoration(
        color: luxe.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: luxe.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: luxe.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      isOver
                          ? Icons.warning_amber_rounded
                          : Icons.auto_awesome_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'End-of-Day Spend Summary',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        summary?.isAiGenerated == true
                            ? 'Gemini 3.8 Flash AI Daily Analysis'
                            : 'Automated On-Device Daily Review',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                              color: luxe.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Refresh summary',
                onPressed: isLoading
                    ? null
                    : () => ref
                        .read(finTrackControllerProvider.notifier)
                        .refreshDailySummary(forceAi: true),
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh_rounded, color: luxe.emerald),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Daily Limit Meter Card
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    borderColor: statusColor.withValues(alpha: 0.45),
                    glowColor: statusColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TODAY\'S SPEND VS LIMIT',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(
                                  () => _isEditingLimit = !_isEditingLimit,
                                );
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 13,
                                    color: luxe.cyan,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Change Limit',
                                    style: TextStyle(
                                      color: luxe.cyan,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_isEditingLimit) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _limitCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    prefixText: '₹ ',
                                    labelText: 'Daily Spend Limit (₹)',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _saveLimit,
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Spent Today',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                AnimatedAmount(
                                  paise: spentPaise,
                                  tone: isOver
                                      ? AmountTone.debit
                                      : AmountTone.neutral,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(fontSize: 26),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Daily Limit',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                AnimatedAmount(
                                  paise: limitPaise,
                                  tone: AmountTone.neutral,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: luxe.textSecondary,
                                        fontSize: 20,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: Stack(
                            children: [
                              Container(
                                height: 8,
                                color: luxe.surfaceGlass,
                              ),
                              FractionallySizedBox(
                                widthFactor: progress,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    gradient: isOver
                                        ? luxe.debitGradient
                                        : luxe.primaryGradient,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isOver
                              ? '⚠️ Exceeded daily target by ₹${((spentPaise - limitPaise) / 100).toStringAsFixed(0)}'
                              : '✅ ₹${((limitPaise - spentPaise) / 100).toStringAsFixed(0)} remaining under daily limit',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // AI Headline & Analysis
                  if (summary != null) ...[
                    const SizedBox(height: 14),
                    GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.insights_rounded,
                                color: luxe.cyan,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  summary.headline,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: luxe.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            summary.analysis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontSize: 13.5,
                                  height: 1.45,
                                ),
                          ),
                          if (summary.topSpendPaise > 0) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: luxe.surfaceGlass,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: luxe.borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.local_fire_department_rounded,
                                    color: luxe.crimson,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Largest spend: ${summary.topSpendTitle}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: luxe.textPrimary,
                                      ),
                                    ),
                                  ),
                                  AnimatedAmount(
                                    paise: summary.topSpendPaise,
                                    tone: AmountTone.debit,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: luxe.gold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: luxe.gold.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  color: luxe.gold,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'RULE FOR TOMORROW',
                                        style: TextStyle(
                                          color: luxe.gold,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        summary.takeawayForTomorrow,
                                        style: TextStyle(
                                          color: luxe.textPrimary,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn().moveY(begin: 10, end: 0),
                  ],

                  const SizedBox(height: 16),
                  GradientButton(
                    label: 'Done',
                    icon: Icons.check_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

