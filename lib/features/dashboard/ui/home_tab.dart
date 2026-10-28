import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/motion/motion.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/db/models.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../../shared/widgets/burn_ring.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../capture/ui/multimodal_capture_sheet.dart';
import '../../profile/ui/profile_qr_sheet.dart';
import 'daily_summary_sheet.dart';

class HomeTab extends ConsumerStatefulWidget {
  final ValueChanged<CaptureTab> onOpenCapture;

  const HomeTab({super.key, required this.onOpenCapture});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  String _selectedCategoryFilter = 'all';
  bool _isSyncingSms = false;

  Future<void> _triggerAutoSmsSync() async {
    if (_isSyncingSms) return;
    LuxeHaptics.medium();
    setState(() => _isSyncingSms = true);
    final count = await ref
        .read(finTrackControllerProvider.notifier)
        .syncBankSmsInbox(requestPermissionIfNeeded: true);
    if (!mounted) return;
    setState(() => _isSyncingSms = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Auto-analyzed SMS inbox & added $count transaction(s)!'
              : 'SMS inbox synced! All detected bank SMS transactions are up to date.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final cashflow = state.cashflow;

    final filteredTxns = _selectedCategoryFilter == 'all'
        ? state.transactions
        : state.transactions
              .where((t) => t.categoryId == _selectedCategoryFilter)
              .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: [
        // 1. Proactive AI Opening Tip Banner
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          borderRadius: 20,
          borderColor: luxe.cyan.withValues(alpha: 0.45),
          glowColor: luxe.cyan,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: luxe.copilotGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: Color(0xFF041512),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          state.isTipAiGenerated
                              ? 'GEMINI 3.8 FLASH BRIEFING'
                              : 'SMART DAILY BRIEFING',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: luxe.cyan),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.dailyOpeningTip,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: luxe.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 320.ms).slideY(begin: -0.08, end: 0),

        const SizedBox(height: 16),

        // 2. Total Net Balance & Monthly Credited vs Spent Hero Card
        GlassCard(
          padding: const EdgeInsets.all(22),
          borderColor: luxe.borderHighlight,
          glowColor: luxe.emerald,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL AVAILABLE BALANCE',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  GestureDetector(
                    onTap: () =>
                        _showEditStartingBalanceDialog(context, ref, state),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: luxe.emerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: luxe.emerald.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 13,
                            color: luxe.emerald,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Set Opening Balance',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: luxe.emerald,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedAmount(
                paise: cashflow.totalBalancePaise,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _CashflowMetricTile(
                      label: 'CREDITED (MONTH)',
                      paise: cashflow.monthlyCreditedPaise,
                      tone: AmountTone.credit,
                      icon: Icons.south_west_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CashflowMetricTile(
                      label: 'SPENT (MONTH)',
                      paise: cashflow.monthlyDebitedPaise,
                      tone: AmountTone.debit,
                      icon: Icons.north_east_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: luxe.bgElevated.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: luxe.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Net Monthly Cashflow',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Row(
                      children: [
                        AnimatedAmount(
                          paise: cashflow.netMonthlyCashflowPaise,
                          showSign: true,
                          tone: cashflow.netMonthlyCashflowPaise >= 0
                              ? AmountTone.credit
                              : AmountTone.debit,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (cashflow.monthlyCreditedPaise > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(${cashflow.savingsRatePercent.toStringAsFixed(0)}% saved)',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: luxe.emerald),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 60.ms).slideY(begin: 0.06, end: 0),

        const SizedBox(height: 16),

        // 3. Quick Multimodal Capture & Auto-SMS Bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _QuickCapturePill(
                icon: Icons.add_circle_outline_rounded,
                label: 'Manual Add',
                accent: luxe.emerald,
                onTap: () => widget.onOpenCapture(CaptureTab.manual),
              ),
              const SizedBox(width: 10),
              _QuickCapturePill(
                icon: _isSyncingSms
                    ? Icons.sync_rounded
                    : Icons.mark_chat_read_rounded,
                label: _isSyncingSms ? 'Scanning SMS…' : 'Auto-Scan SMS',
                accent: luxe.emerald,
                onTap: _triggerAutoSmsSync,
              ),
              const SizedBox(width: 10),
              _QuickCapturePill(
                icon: Icons.qr_code_2_rounded,
                label: 'My UPI QR',
                accent: luxe.cyan,
                onTap: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const ProfileQrSheet(),
                  );
                },
              ),
              const SizedBox(width: 10),
              _QuickCapturePill(
                icon: Icons.document_scanner_outlined,
                label: 'Screenshot AI',
                accent: luxe.cyan,
                onTap: () => widget.onOpenCapture(CaptureTab.screenshot),
              ),
              const SizedBox(width: 10),
              _QuickCapturePill(
                icon: Icons.mic_none_rounded,
                label: 'Voice Note',
                accent: luxe.gold,
                onTap: () => widget.onOpenCapture(CaptureTab.voice),
              ),
              const SizedBox(width: 10),
              _QuickCapturePill(
                icon: Icons.upload_file_rounded,
                label: 'Statement PDF/CSV',
                accent: luxe.cyan,
                onTap: () => widget.onOpenCapture(CaptureTab.statement),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 110.ms),

        const SizedBox(height: 16),

        // 4. Daily Burn-Rate Meter Card (Dynamic Rollover Allowance)
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              BurnRing(
                progress: cashflow.todayAllowanceProgress,
                size: 104,
                strokeWidth: 10,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TODAY',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(cashflow.todayAllowanceProgress * 100).clamp(0, 999).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAFE DAILY BURN ALLOWANCE',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    AnimatedAmount(
                      paise: cashflow.safeDailyAllowancePaise,
                      style: Theme.of(context).textTheme.displaySmall,
                      tone: AmountTone.credit,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Spent today: ${AnimatedAmount.formatPaise(cashflow.spentTodayPaise)} • ${cashflow.daysRemainingInMonth}d left in month',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cashflow.remainingTodayPaise >= 0
                          ? '${AnimatedAmount.formatPaise(cashflow.remainingTodayPaise)} left today (rolls over tomorrow)'
                          : 'Exceeded today\'s safe limit by ${AnimatedAmount.formatPaise(cashflow.remainingTodayPaise.abs())}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cashflow.remainingTodayPaise >= 0
                            ? luxe.emerald
                            : luxe.crimson,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.06, end: 0),

        const SizedBox(height: 16),

        // 4b. Daily Spend Limit & End-of-Day Summary Card
        GlassCard(
          padding: const EdgeInsets.all(18),
          borderColor: cashflow.isOverDailyLimit
              ? luxe.crimson.withValues(alpha: 0.5)
              : luxe.cyan.withValues(alpha: 0.45),
          glowColor: cashflow.isOverDailyLimit ? luxe.crimson : luxe.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        cashflow.isOverDailyLimit
                            ? Icons.warning_amber_rounded
                            : Icons.speed_rounded,
                        color: cashflow.isOverDailyLimit
                            ? luxe.crimson
                            : luxe.cyan,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'DAILY SPEND TARGET',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cashflow.isOverDailyLimit
                                  ? luxe.crimson
                                  : luxe.cyan,
                            ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _showEditDailyLimitDialog(context, ref, state),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: luxe.cyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: luxe.cyan.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 13, color: luxe.cyan),
                          const SizedBox(width: 4),
                          Text(
                            'Set Limit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: luxe.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
                        paise: cashflow.spentTodayPaise,
                        tone: cashflow.isOverDailyLimit
                            ? AmountTone.debit
                            : AmountTone.neutral,
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontSize: 24),
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
                        paise: state.dailySpendLimitPaise,
                        tone: AmountTone.neutral,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: luxe.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Stack(
                  children: [
                    Container(height: 7, color: luxe.surfaceGlass),
                    FractionallySizedBox(
                      widthFactor: cashflow.dailyLimitProgress.clamp(0.0, 1.0),
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          gradient: cashflow.isOverDailyLimit
                              ? luxe.debitGradient
                              : luxe.copilotGradient,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cashflow.isOverDailyLimit
                    ? '⚠️ Over daily limit by ${AnimatedAmount.formatPaise(cashflow.spentTodayPaise - state.dailySpendLimitPaise)}'
                    : '🛡️ ${AnimatedAmount.formatPaise(state.dailySpendLimitPaise - cashflow.spentTodayPaise)} remaining under today\'s limit',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cashflow.isOverDailyLimit
                      ? luxe.crimson
                      : luxe.emerald,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(
                          color: luxe.emerald.withValues(alpha: 0.6),
                        ),
                      ),
                      onPressed: () => DailySummarySheet.show(context),
                      icon: Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: luxe.emerald,
                      ),
                      label: Text(
                        'End-of-Day AI Summary',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: luxe.emerald,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Send Test 3-Hour / Night Notification',
                    style: IconButton.styleFrom(
                      backgroundColor: luxe.gold.withValues(alpha: 0.14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: luxe.gold.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    onPressed: () async {
                      await ref
                          .read(finTrackControllerProvider.notifier)
                          .sendTestReminder();
                      if (context.mounted) {
                        LuxeHaptics.medium();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Expense reminder notification triggered! Check your Android status bar.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      Icons.notifications_active_rounded,
                      size: 18,
                      color: luxe.gold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.06, end: 0),

        const SizedBox(height: 22),

        // 5. Recent Activity Header + Animated Liquid Glass Category Filter Box
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Transactions by Category',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              '${filteredTxns.length} entries',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _LiquidCategoryFilterChip(
                label: 'All Categories',
                color: luxe.emerald,
                isSelected: _selectedCategoryFilter == 'all',
                onTap: () => setState(() => _selectedCategoryFilter = 'all'),
              ),
              ...state.categories.map((cat) {
                final isSel = _selectedCategoryFilter == cat.id;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _LiquidCategoryFilterChip(
                    label: cat.name,
                    color: Color(cat.colorValue),
                    isSelected: isSel,
                    onTap: () =>
                        setState(() => _selectedCategoryFilter = cat.id),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        AnimatedSwitcher(
          duration: LuxeMotion.medium,
          switchInCurve: LuxeMotion.decelerate,
          child: filteredTxns.isEmpty
              ? GlassCard(
                  key: ValueKey('empty_$_selectedCategoryFilter'),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 42,
                        color: luxe.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No transactions in this category yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap + below to add manually, scan a payment screenshot, record a voice note, auto-scan SMS, or upload a bank statement.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : Column(
                  key: ValueKey('list_$_selectedCategoryFilter'),
                  children: filteredTxns.take(30).map((txn) {
                    final cat = state.categoryById(txn.categoryId);
                    final isCredit = txn.type == TxnType.credit;
                    final dateFormatted = DateFormat(
                      'dd MMM • hh:mm a',
                    ).format(txn.occurredAt);

                    return Dismissible(
                      key: ValueKey(txn.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: luxe.crimson.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: luxe.crimson,
                        ),
                      ),
                      onDismissed: (_) => ref
                          .read(finTrackControllerProvider.notifier)
                          .deleteTransaction(txn.id),
                      child: GlassCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        borderRadius: 20,
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Color(
                                  cat.colorValue,
                                ).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Color(
                                    cat.colorValue,
                                  ).withValues(alpha: 0.45),
                                ),
                              ),
                              child: Icon(
                                isCredit
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded,
                                color: isCredit
                                    ? luxe.emerald
                                    : Color(cat.colorValue),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    txn.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${cat.name} • ${txn.paymentMode.label} • $dateFormatted',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontSize: 12),
                                  ),
                                  if (txn.tags.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 6,
                                      children: txn.tags
                                          .map(
                                            (t) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: luxe.cyan.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                t,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: luxe.cyan,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                AnimatedAmount(
                                  paise: txn.amountPaise,
                                  showSign: true,
                                  tone: isCredit
                                      ? AmountTone.credit
                                      : AmountTone.debit,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  txn.source.name.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(fontSize: 9),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  void _showEditStartingBalanceDialog(
    BuildContext context,
    WidgetRef ref,
    FinTrackState state,
  ) {
    final primaryAcc = state.accounts.first;
    final ctrl = TextEditingController(
      text: (primaryAcc.initialBalancePaise / 100.0).toStringAsFixed(0),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Opening Bank Balance'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: '₹ ',
            labelText: 'Opening Balance (INR)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.trim()) ?? 0;
              ref
                  .read(finTrackControllerProvider.notifier)
                  .updateAccountInitialBalance(
                    primaryAcc.id,
                    (val * 100).round(),
                  );
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditDailyLimitDialog(
    BuildContext context,
    WidgetRef ref,
    FinTrackState state,
  ) {
    final ctrl = TextEditingController(
      text: (state.dailySpendLimitPaise / 100.0).toStringAsFixed(0),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Daily Spend Limit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FinTrack AI monitors this daily threshold and generates an automated end-of-day spend analysis.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                labelText: 'Daily Limit (INR)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.trim()) ?? 0;
              if (val >= 100) {
                ref
                    .read(finTrackControllerProvider.notifier)
                    .updateDailySpendLimit((val * 100).round());
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _LiquidCategoryFilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _LiquidCategoryFilterChip({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;

    return GestureDetector(
      onTap: () {
        LuxeHaptics.selection();
        onTap();
      },
      child: AnimatedContainer(
        duration: LuxeMotion.medium,
        curve: LuxeMotion.bounce,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: luxe.isDark ? 0.24 : 0.92),
                    color.withValues(alpha: 0.30),
                    color.withValues(alpha: 0.14),
                  ],
                )
              : null,
          color: isSelected ? null : luxe.surfaceGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? color : luxe.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: 0.5,
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.2 : 1.0,
              duration: LuxeMotion.fast,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? luxe.textPrimary : luxe.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashflowMetricTile extends StatelessWidget {
  final String label;
  final int paise;
  final AmountTone tone;
  final IconData icon;

  const _CashflowMetricTile({
    required this.label,
    required this.paise,
    required this.tone,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final accent = tone == AmountTone.credit ? luxe.emerald : luxe.crimson;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: accent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedAmount(
            paise: paise,
            tone: tone,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _QuickCapturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _QuickCapturePill({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      borderRadius: 99,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
