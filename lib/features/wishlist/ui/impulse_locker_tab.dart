import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';

class ImpulseLockerTab extends ConsumerWidget {
  const ImpulseLockerTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final now = DateTime.now();

    final skippedItems = state.impulseItems
        .where((i) => i.status == 'skipped')
        .toList();
    final activeItems = state.impulseItems
        .where((i) => i.status == 'locked')
        .toList();

    final savedBySkippingPaise = skippedItems.fold<int>(
      0,
      (sum, i) => sum + i.pricePaise,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(22),
          borderColor: luxe.gold.withValues(alpha: 0.45),
          glowColor: luxe.gold,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAVED BY SKIPPING IMPULSES',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    AnimatedAmount(
                      paise: savedBySkippingPaise,
                      tone: AmountTone.credit,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Lock non-essential wants for 24–48 hours before spending.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.hourglass_top_rounded, size: 36, color: luxe.gold),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GradientButton(
          label: 'Lock New Impulse Want (24h Cool-Off)',
          icon: Icons.lock_clock_outlined,
          onPressed: () => _showAddImpulseDialog(context, ref, state),
        ),
        const SizedBox(height: 20),
        Text(
          'Active Cooling-Off Locker (${activeItems.length})',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        if (activeItems.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.lock_clock_outlined,
                  size: 40,
                  color: luxe.textMuted,
                ),
                const SizedBox(height: 10),
                Text(
                  'Your Impulse Locker is empty',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Tempted to buy a gadget or late-night item? Lock it here for 24h first!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          )
        else
          ...activeItems.map((item) {
            final isCooling = item.isCoolingDown(now);
            final hoursLeft = item.unlockAt
                .difference(now)
                .inHours
                .clamp(0, 99);
            final workHours = state.hourlyRatePaise > 0
                ? (item.pricePaise / state.hourlyRatePaise).toStringAsFixed(1)
                : '0';

            return GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      AnimatedAmount(
                        paise: item.pricePaise,
                        tone: AmountTone.accent,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isCooling
                        ? 'Cooling off: ${hoursLeft}h remaining • Equals $workHours hrs of work'
                        : 'Timer complete! Do you still really need this?',
                    style: TextStyle(
                      color: isCooling ? luxe.gold : luxe.emerald,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: luxe.emerald,
                            foregroundColor: const Color(0xFF041510),
                          ),
                          onPressed: () => ref
                              .read(finTrackControllerProvider.notifier)
                              .resolveImpulseItem(item, purchase: false),
                          icon: const Icon(Icons.savings_outlined, size: 18),
                          label: const Text('Skip & Save ₹'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isCooling
                              ? null
                              : () => ref
                                    .read(finTrackControllerProvider.notifier)
                                    .resolveImpulseItem(item, purchase: true),
                          icon: const Icon(
                            Icons.shopping_bag_outlined,
                            size: 18,
                          ),
                          label: Text(
                            isCooling ? 'Locked (${hoursLeft}h)' : 'Buy Now',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  void _showAddImpulseDialog(
    BuildContext context,
    WidgetRef ref,
    FinTrackState state,
  ) {
    final titleCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    int hours = 24;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add to 24–48h Impulse Locker'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Item you want to buy',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Price (INR)',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 24, label: Text('24 Hours')),
                  ButtonSegment(value: 48, label: Text('48 Hours')),
                ],
                selected: {hours},
                onSelectionChanged: (s) =>
                    setDialogState(() => hours = s.first),
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
                final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
                if (titleCtrl.text.trim().isEmpty || price <= 0) return;
                ref.read(finTrackControllerProvider.notifier).addImpulseItem(
                      title: titleCtrl.text.trim(),
                      pricePaise: (price * 100).round(),
                      categoryId: 'cat_tech',
                      coolOffHours: hours,
                    );
                Navigator.of(ctx).pop();
              },
              child: const Text('Lock Item'),
            ),
          ],
        ),
      ),
    );
  }
}
