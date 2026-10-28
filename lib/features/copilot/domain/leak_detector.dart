import '../../../core/db/models.dart';
import '../../../core/gemini/gemini_service.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../budgets/domain/burn_rate_engine.dart';

class LeakMetrics {
  final int microSpendCount;
  final int microSpendTotalPaise;
  final int lateNightSpendCount;
  final int lateNightTotalPaise;
  final int subscriptionTotalPaise;
  final String peakSpendWeekday;
  final int peakWeekdayTotalPaise;
  final List<MapEntry<String, int>> topMerchantsBySpend;

  const LeakMetrics({
    required this.microSpendCount,
    required this.microSpendTotalPaise,
    required this.lateNightSpendCount,
    required this.lateNightTotalPaise,
    required this.subscriptionTotalPaise,
    required this.peakSpendWeekday,
    required this.peakWeekdayTotalPaise,
    required this.topMerchantsBySpend,
  });
}

class LeakDetector {
  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static LeakMetrics analyzeMonth(
    List<TransactionModel> transactions, {
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    var microCount = 0;
    var microTotal = 0;
    var lateCount = 0;
    var lateTotal = 0;
    var subTotal = 0;
    final weekdaySums = <int, int>{};
    final merchantSums = <String, int>{};

    for (final txn in transactions) {
      if (txn.type != TxnType.debit) continue;
      if (txn.occurredAt.year != now.year || txn.occurredAt.month != now.month) {
        continue;
      }

      // Micro-spends under ₹100 (10,000 paise)
      if (txn.amountPaise <= 10000) {
        microCount++;
        microTotal += txn.amountPaise;
      }

      // Late-night impulse spends (10 PM to 4 AM)
      final hr = txn.occurredAt.hour;
      if (hr >= 22 || hr < 4) {
        lateCount++;
        lateTotal += txn.amountPaise;
      }

      // Subscription creep
      if (txn.categoryId == 'cat_subscriptions') {
        subTotal += txn.amountPaise;
      }

      final wd = txn.occurredAt.weekday;
      weekdaySums[wd] = (weekdaySums[wd] ?? 0) + txn.amountPaise;

      final merchant = txn.counterparty.trim().isEmpty
          ? txn.title
          : txn.counterparty.trim();
      merchantSums[merchant] = (merchantSums[merchant] ?? 0) + txn.amountPaise;
    }

    var peakDay = 'Saturday';
    var peakDayPaise = 0;
    weekdaySums.forEach((wd, sum) {
      if (sum > peakDayPaise) {
        peakDayPaise = sum;
        peakDay = _weekdayNames[(wd - 1).clamp(0, 6)];
      }
    });

    final sortedMerchants = merchantSums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return LeakMetrics(
      microSpendCount: microCount,
      microSpendTotalPaise: microTotal,
      lateNightSpendCount: lateCount,
      lateNightTotalPaise: lateTotal,
      subscriptionTotalPaise: subTotal,
      peakSpendWeekday: peakDay,
      peakWeekdayTotalPaise: peakDayPaise,
      topMerchantsBySpend: sortedMerchants.take(5).toList(),
    );
  }

  /// Builds a privacy-preserving aggregate payload (no individual raw transactions,
  /// no reference IDs, no bank account numbers) for Gemini Copilot.
  static Map<String, dynamic> buildAnonymizedPayload({
    required CashflowAndBurnSummary cashflow,
    required LeakMetrics leaks,
    required Map<String, String> categoryNamesById,
  }) {
    final categoryBreakdownInr = <String, double>{};
    cashflow.spendByCategoryPaise.forEach((catId, paise) {
      final label = categoryNamesById[catId] ?? catId;
      categoryBreakdownInr[label] = paise / 100.0;
    });

    return {
      'currency': 'INR',
      'monthly_credited_inr': cashflow.monthlyCreditedPaise / 100.0,
      'monthly_debited_inr': cashflow.monthlyDebitedPaise / 100.0,
      'net_cashflow_inr': cashflow.netMonthlyCashflowPaise / 100.0,
      'savings_rate_percent':
          double.parse(cashflow.savingsRatePercent.toStringAsFixed(1)),
      'monthly_budget_inr': cashflow.monthlyBudgetPaise / 100.0,
      'safe_daily_allowance_inr': cashflow.safeDailyAllowancePaise / 100.0,
      'spent_today_inr': cashflow.spentTodayPaise / 100.0,
      'days_remaining_in_month': cashflow.daysRemainingInMonth,
      'category_spend_inr': categoryBreakdownInr,
      'leak_signals': {
        'upi_micro_spends_under_100_count': leaks.microSpendCount,
        'upi_micro_spends_total_inr': leaks.microSpendTotalPaise / 100.0,
        'late_night_spends_count': leaks.lateNightSpendCount,
        'late_night_spends_total_inr': leaks.lateNightTotalPaise / 100.0,
        'subscriptions_total_inr': leaks.subscriptionTotalPaise / 100.0,
        'peak_spending_weekday': leaks.peakSpendWeekday,
        'peak_weekday_total_inr': leaks.peakWeekdayTotalPaise / 100.0,
      },
    };
  }

  static String generateLocalOpeningTip({
    required CashflowAndBurnSummary cashflow,
    required LeakMetrics leaks,
  }) {
    if (cashflow.monthlyDebitedPaise == 0 &&
        cashflow.monthlyCreditedPaise == 0) {
      return 'Share any GPay/PhonePe screenshot, record a voice note, or paste an SMS to log your first transaction!';
    }
    if (cashflow.spentTodayPaise > cashflow.safeDailyAllowancePaise &&
        cashflow.safeDailyAllowancePaise > 0) {
      final over = AnimatedAmount.formatPaise(
        cashflow.spentTodayPaise - cashflow.safeDailyAllowancePaise,
      );
      return 'You are $over above today\'s safe burn rate—pause non-essential UPI spends tonight to rebalance tomorrow.';
    }
    if (leaks.microSpendCount >= 5) {
      final total = AnimatedAmount.formatPaise(leaks.microSpendTotalPaise);
      return '${leaks.microSpendCount} micro-UPI spends (< ₹100) quietly drained $total this month. Batch small snacks or chai!';
    }
    if (cashflow.savingsRatePercent >= 25) {
      return 'Strong cashflow! You\'re saving ${cashflow.savingsRatePercent.toStringAsFixed(0)}% of your monthly credits. Safe daily allowance: ${AnimatedAmount.formatPaise(cashflow.safeDailyAllowancePaise)}.';
    }
    return 'Safe spend today: ${AnimatedAmount.formatPaise(cashflow.safeDailyAllowancePaise)} (unspent money rolls over automatically to tomorrow!).';
  }

  static MonthlyAuditReport generateLocalAuditReport({
    required CashflowAndBurnSummary cashflow,
    required LeakMetrics leaks,
    required Map<String, String> categoryNamesById,
  }) {
    final insights = <String>[];
    if (leaks.microSpendCount > 0) {
      insights.add(
        'Micro-Spend Drain: ${leaks.microSpendCount} small UPI transactions (< ₹100) added up to ${AnimatedAmount.formatPaise(leaks.microSpendTotalPaise)}.',
      );
    }
    if (leaks.lateNightSpendCount > 0) {
      insights.add(
        'Late-Night Spends: ${leaks.lateNightSpendCount} orders between 10 PM and 4 AM cost ${AnimatedAmount.formatPaise(leaks.lateNightTotalPaise)}.',
      );
    }
    if (leaks.peakWeekdayTotalPaise > 0) {
      insights.add(
        'Peak Spend Day: ${leaks.peakSpendWeekday}s account for ${AnimatedAmount.formatPaise(leaks.peakWeekdayTotalPaise)} of your monthly outflow.',
      );
    }
    if (insights.isEmpty) {
      insights.add(
        'No major micro-spend or late-night leakage detected yet this month.',
      );
    }

    final microSave = (leaks.microSpendTotalPaise * 0.45).round();
    final lateSave = (leaks.lateNightTotalPaise * 0.60).round();
    final generalSave = (cashflow.monthlyDebitedPaise * 0.12).round();

    return MonthlyAuditReport(
      headline: cashflow.netMonthlyCashflowPaise >= 0
          ? 'Positive Net Cashflow (${AnimatedAmount.formatPaise(cashflow.netMonthlyCashflowPaise, showSign: true)})'
          : 'Monthly Outflow Exceeds Credits by ${AnimatedAmount.formatPaise(cashflow.netMonthlyCashflowPaise.abs())}',
      cashflowSummary:
          'Credited: ${AnimatedAmount.formatPaise(cashflow.monthlyCreditedPaise)} • Spent: ${AnimatedAmount.formatPaise(cashflow.monthlyDebitedPaise)} • Savings Rate: ${cashflow.savingsRatePercent.toStringAsFixed(1)}%.',
      leakInsights: insights,
      recommendations: [
        AuditRecommendation(
          title: 'Cap Daily Micro-UPI Impulses',
          action:
              'Keep snacks/chai under 1 transaction a day to reclaim 45% of micro-spend leakage.',
          estimatedMonthlySavingPaise: microSave > 0 ? microSave : 45000,
        ),
        AuditRecommendation(
          title: 'Use the 24h Impulse Locker After 10 PM',
          action:
              'Move late-night shopping & food cravings into the Cooling-Off tab before paying.',
          estimatedMonthlySavingPaise: lateSave > 0 ? lateSave : 60000,
        ),
        AuditRecommendation(
          title: 'Lock In Rollover Daily Allowance',
          action:
              'Stay under ${AnimatedAmount.formatPaise(cashflow.safeDailyAllowancePaise)}/day for the next ${cashflow.daysRemainingInMonth} days.',
          estimatedMonthlySavingPaise: generalSave > 0 ? generalSave : 120000,
        ),
      ],
      isAiGenerated: false,
    );
  }
}

