import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/motion/motion.dart';
import '../../app/theme/luxe_tokens.dart';

enum AmountTone { neutral, credit, debit, accent }

class AnimatedAmount extends StatelessWidget {
  final int paise;
  final TextStyle? style;
  final AmountTone tone;
  final bool showSign;
  final bool compact;
  final String currencySymbol;

  const AnimatedAmount({
    super.key,
    required this.paise,
    this.style,
    this.tone = AmountTone.neutral,
    this.showSign = false,
    this.compact = false,
    this.currencySymbol = '₹',
  });

  static String formatPaise(
    int paise, {
    String symbol = '₹',
    bool showSign = false,
    bool compact = false,
  }) {
    final isNegative = paise < 0;
    final absRupees = paise.abs() / 100.0;

    String formatted;
    if (compact && absRupees >= 100000) {
      formatted = '$symbol${(absRupees / 100000).toStringAsFixed(2)}L';
    } else if (compact && absRupees >= 10000) {
      formatted = '$symbol${(absRupees / 1000).toStringAsFixed(1)}K';
    } else {
      final hasPaise = (paise.abs() % 100) != 0;
      final fmt = NumberFormat.currency(
        locale: 'en_IN',
        symbol: symbol,
        decimalDigits: hasPaise ? 2 : 0,
      );
      formatted = fmt.format(absRupees);
    }

    if (isNegative) return '-$formatted';
    if (showSign && paise > 0) return '+$formatted';
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final Color textColor = switch (tone) {
      AmountTone.credit => luxe.emerald,
      AmountTone.debit => luxe.crimson,
      AmountTone.accent => luxe.gold,
      AmountTone.neutral => style?.color ?? luxe.textPrimary,
    };

    final resolvedStyle = (style ?? Theme.of(context).textTheme.displayMedium!)
        .copyWith(
          color: textColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      return Text(
        formatPaise(
          paise,
          symbol: currencySymbol,
          showSign: showSign,
          compact: compact,
        ),
        style: resolvedStyle,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: paise.toDouble()),
      duration: LuxeMotion.counter,
      curve: LuxeMotion.decelerate,
      builder: (context, value, _) {
        return Text(
          formatPaise(
            value.round(),
            symbol: currencySymbol,
            showSign: showSign,
            compact: compact,
          ),
          style: resolvedStyle,
        );
      },
    );
  }
}

