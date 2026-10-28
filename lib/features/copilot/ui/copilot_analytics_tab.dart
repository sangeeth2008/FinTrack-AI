import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/db/models.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';

class CopilotAnalyticsTab extends ConsumerWidget {
  const CopilotAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final audit = state.auditReport;
    final leaks = state.leaks;
    final cashflow = state.cashflow;

    // Aggregate spend by project tag (#ProjectMARK, etc.)
    final tagTotals = <String, int>{};
    for (final t in state.transactions) {
      if (t.type == TxnType.debit) {
        for (final tag in t.tags) {
          tagTotals[tag] = (tagTotals[tag] ?? 0) + t.amountPaise;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        // 1. "Where Did My Money Go?" Monthly Deep Audit Card
        GlassCard(
          padding: const EdgeInsets.all(20),
          borderColor: luxe.cyan.withValues(alpha: 0.5),
          glowColor: luxe.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: luxe.cyan,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'WHERE DID MY MONEY GO?',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: luxe.cyan),
                      ),
                    ],
                  ),
                  if (audit?.isAiGenerated == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: luxe.emerald.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'GEMINI 3.8 FLASH',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: luxe.emerald,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (audit != null) ...[
                Text(
                  audit.headline,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  audit.cashflowSummary,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Text(
                  'DETECTED MONEY LEAKAGES',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                ...audit.leakInsights.map(
                  (leak) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: luxe.gold,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            leak,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: luxe.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '3 ACTIONABLE SAVINGS RECOMMENDATIONS',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                ...audit.recommendations.map(
                  (rec) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: luxe.bgElevated.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: luxe.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rec.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                rec.action,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'SAVE / MO',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            AnimatedAmount(
                              paise: rec.estimatedMonthlySavingPaise,
                              tone: AmountTone.credit,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              GradientButton(
                label: state.hasGeminiKey
                    ? 'Run Gemini 3.8 Flash Deep Audit'
                    : 'Refresh Local Leak Audit (Add API Key in Settings for AI)',
                icon: Icons.psychology_outlined,
                gradient: luxe.copilotGradient,
                isLoading: state.isAuditLoading,
                onPressed: () => ref
                    .read(finTrackControllerProvider.notifier)
                    .generateMonthlyAiAudit(),
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.05, end: 0),

        const SizedBox(height: 16),

        // 2. Micro-Spend & Peak Day Leak Metrics Row
        Row(
          children: [
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UPI MICRO-SPENDS (< ₹100)',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    AnimatedAmount(
                      paise: leaks.microSpendTotalPaise,
                      tone: AmountTone.accent,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${leaks.microSpendCount} small transactions',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PEAK SPEND DAY',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      leaks.peakSpendWeekday,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: luxe.crimson,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AnimatedAmount.formatPaise(leaks.peakWeekdayTotalPaise),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 3. Offline Category Breakdown Donut Chart (fl_chart)
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OFFLINE CATEGORY BREAKDOWN',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 16),
              if (cashflow.spendByCategoryPaise.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Add expenses to see your offline category donut chart.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: PieChart(
                        PieChartData(
                          centerSpaceRadius: 38,
                          sectionsSpace: 3,
                          sections: cashflow.spendByCategoryPaise.entries.map((
                            entry,
                          ) {
                            final cat = state.categoryById(entry.key);
                            final pct = cashflow.monthlyDebitedPaise > 0
                                ? (entry.value /
                                          cashflow.monthlyDebitedPaise *
                                          100)
                                      .toStringAsFixed(0)
                                : '0';
                            return PieChartSectionData(
                              value: entry.value.toDouble(),
                              color: Color(cat.colorValue),
                              radius: 26,
                              title: '$pct%',
                              titleStyle: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: cashflow.spendByCategoryPaise.entries.map((
                          entry,
                        ) {
                          final cat = state.categoryById(entry.key);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Color(cat.colorValue),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    cat.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: luxe.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  AnimatedAmount.formatPaise(
                                    entry.value,
                                    compact: true,
                                  ),
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 4. Offline Credited vs Spent Bar Comparison (fl_chart)
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MONTHLY CREDITED VS SPENT COMPARISON',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, _) {
                            final label = switch (val.toInt()) {
                              0 => 'Credited',
                              1 => 'Spent',
                              _ => 'Budget',
                            };
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                label,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: (cashflow.monthlyCreditedPaise / 100.0).clamp(
                              10,
                              double.infinity,
                            ),
                            color: luxe.emerald,
                            width: 32,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: (cashflow.monthlyDebitedPaise / 100.0).clamp(
                              10,
                              double.infinity,
                            ),
                            color: luxe.crimson,
                            width: 32,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 2,
                        barRods: [
                          BarChartRodData(
                            toY: (cashflow.monthlyBudgetPaise / 100.0).clamp(
                              10,
                              double.infinity,
                            ),
                            color: luxe.gold,
                            width: 32,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        if (tagTotals.isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROJECT & HARDWARE INVENTORY TAGS',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                ...tagTotals.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.key,
                          style: TextStyle(
                            color: luxe.cyan,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        AnimatedAmount(
                          paise: e.value,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

