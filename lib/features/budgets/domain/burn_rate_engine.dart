import '../../../core/db/models.dart';

class CashflowAndBurnSummary {
  final int totalBalancePaise;
  final int monthlyCreditedPaise;
  final int monthlyDebitedPaise;
  final int netMonthlyCashflowPaise;
  final double savingsRatePercent;
  final int monthlyBudgetPaise;
  final int safeDailyAllowancePaise;
  final int dailySpendLimitPaise;
  final int spentTodayPaise;
  final int remainingTodayPaise;
  final int remainingDailyLimitPaise;
  final int daysRemainingInMonth;
  final double monthlyBudgetProgress;
  final double todayAllowanceProgress;
  final double dailyLimitProgress;
  final bool isOverDailyLimit;
  final Map<String, int> spendByCategoryPaise;

  const CashflowAndBurnSummary({
    required this.totalBalancePaise,
    required this.monthlyCreditedPaise,
    required this.monthlyDebitedPaise,
    required this.netMonthlyCashflowPaise,
    required this.savingsRatePercent,
    required this.monthlyBudgetPaise,
    required this.safeDailyAllowancePaise,
    required this.dailySpendLimitPaise,
    required this.spentTodayPaise,
    required this.remainingTodayPaise,
    required this.remainingDailyLimitPaise,
    required this.daysRemainingInMonth,
    required this.monthlyBudgetProgress,
    required this.todayAllowanceProgress,
    required this.dailyLimitProgress,
    required this.isOverDailyLimit,
    required this.spendByCategoryPaise,
  });
}

class BurnRateEngine {
  static CashflowAndBurnSummary compute({
    required List<AccountModel> accounts,
    required List<TransactionModel> transactions,
    required int monthlyBudgetPaise,
    int? dailySpendLimitPaise,
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysRemaining = (daysInMonth - now.day + 1).clamp(1, 31);

    var initialAccountSum = 0;
    for (final acc in accounts) {
      initialAccountSum += acc.initialBalancePaise;
    }

    var allTimeCredits = 0;
    var allTimeDebits = 0;
    var monthlyCredited = 0;
    var monthlyDebited = 0;
    var spentBeforeTodayInMonth = 0;
    var spentToday = 0;
    final categoryTotals = <String, int>{};

    for (final txn in transactions) {
      if (txn.type == TxnType.credit) {
        allTimeCredits += txn.amountPaise;
      } else {
        allTimeDebits += txn.amountPaise;
      }

      final isThisMonth = !txn.occurredAt.isBefore(monthStart) &&
          txn.occurredAt.year == now.year &&
          txn.occurredAt.month == now.month;

      if (!isThisMonth) continue;

      if (txn.type == TxnType.credit) {
        monthlyCredited += txn.amountPaise;
      } else {
        monthlyDebited += txn.amountPaise;
        categoryTotals[txn.categoryId] =
            (categoryTotals[txn.categoryId] ?? 0) + txn.amountPaise;

        if (txn.occurredAt.isBefore(todayStart)) {
          spentBeforeTodayInMonth += txn.amountPaise;
        } else {
          spentToday += txn.amountPaise;
        }
      }
    }

    final totalBalance = initialAccountSum + allTimeCredits - allTimeDebits;
    final netMonthly = monthlyCredited - monthlyDebited;
    final savingsRate = monthlyCredited > 0
        ? ((netMonthly / monthlyCredited) * 100.0).clamp(-100.0, 100.0)
        : 0.0;

    final remainingPoolBeforeToday =
        (monthlyBudgetPaise - spentBeforeTodayInMonth);
    final safeDailyAllowance = remainingPoolBeforeToday > 0
        ? (remainingPoolBeforeToday ~/ daysRemaining)
        : 0;
    final remainingToday = safeDailyAllowance - spentToday;

    final resolvedDailyLimit = (dailySpendLimitPaise != null && dailySpendLimitPaise > 0)
        ? dailySpendLimitPaise
        : (safeDailyAllowance > 0 ? safeDailyAllowance : 150000); // Default ₹1,500 if unbudgeted

    final remainingDailyLimit = resolvedDailyLimit - spentToday;
    final isOverLimit = spentToday > resolvedDailyLimit;
    final dailyProgress = resolvedDailyLimit > 0
        ? (spentToday / resolvedDailyLimit)
        : (spentToday > 0 ? 1.0 : 0.0);

    final monthlyProgress = monthlyBudgetPaise > 0
        ? (monthlyDebited / monthlyBudgetPaise)
        : 0.0;
    final todayProgress = safeDailyAllowance > 0
        ? (spentToday / safeDailyAllowance)
        : (spentToday > 0 ? 1.0 : 0.0);

    return CashflowAndBurnSummary(
      totalBalancePaise: totalBalance,
      monthlyCreditedPaise: monthlyCredited,
      monthlyDebitedPaise: monthlyDebited,
      netMonthlyCashflowPaise: netMonthly,
      savingsRatePercent: savingsRate,
      monthlyBudgetPaise: monthlyBudgetPaise,
      safeDailyAllowancePaise: safeDailyAllowance,
      dailySpendLimitPaise: resolvedDailyLimit,
      spentTodayPaise: spentToday,
      remainingTodayPaise: remainingToday,
      remainingDailyLimitPaise: remainingDailyLimit,
      daysRemainingInMonth: daysRemaining,
      monthlyBudgetProgress: monthlyProgress,
      todayAllowanceProgress: todayProgress,
      dailyLimitProgress: dailyProgress,
      isOverDailyLimit: isOverLimit,
      spendByCategoryPaise: categoryTotals,
    );
  }
}

