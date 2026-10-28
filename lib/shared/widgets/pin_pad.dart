import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/motion/motion.dart';
import '../../app/theme/luxe_tokens.dart';

class PinDots extends StatelessWidget {
  final int length;
  final int filledCount;
  final bool hasError;

  const PinDots({
    super.key,
    this.length = 6,
    required this.filledCount,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;

    return TweenAnimationBuilder<double>(
      key: ValueKey<bool>(hasError),
      tween: Tween<double>(begin: 0.0, end: hasError ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 420),
      builder: (context, shakeProgress, child) {
        final dx = hasError
            ? math.sin(shakeProgress * math.pi * 4) * 14 * (1 - shakeProgress)
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(length, (index) {
          final isFilled = index < filledCount;
          final dotColor = hasError
              ? luxe.crimson
              : (isFilled ? luxe.emerald : Colors.transparent);
          final borderColor = hasError
              ? luxe.crimson
              : (isFilled ? luxe.emerald : luxe.borderSubtle);

          return AnimatedContainer(
            duration: LuxeMotion.fast,
            curve: LuxeMotion.bounce,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: isFilled ? 18 : 14,
            height: isFilled ? 18 : 14,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1.8),
              boxShadow: [
                if (isFilled)
                  BoxShadow(
                    color: (hasError ? luxe.crimson : luxe.emerald).withValues(
                      alpha: 0.65,
                    ),
                    blurRadius: 14,
                    spreadRadius: 1.5,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class GlassNumPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onClear;
  final VoidCallback? onBiometric;
  final bool showBiometric;
  final bool showDecimal;
  final bool hasEnteredDigits;

  const GlassNumPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onClear,
    this.onBiometric,
    this.showBiometric = false,
    this.showDecimal = false,
    this.hasEnteredDigits = false,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [
        showDecimal
            ? '.'
            : (hasEnteredDigits && onClear != null
                  ? 'CLR'
                  : (showBiometric ? 'BIO' : 'CLR')),
        '0',
        'DEL',
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((keyLabel) {
                if (keyLabel.isEmpty) {
                  return const SizedBox(width: 78, height: 64);
                }
                if (keyLabel == 'BIO') {
                  return _NumKeyButton(
                    onTap: onBiometric,
                    glowColor: luxe.emerald,
                    child: Icon(
                      Icons.fingerprint_rounded,
                      size: 30,
                      color: luxe.emerald,
                    ),
                  );
                }
                if (keyLabel == 'CLR') {
                  return _NumKeyButton(
                    onTap: onClear ?? onBackspace,
                    child: Text(
                      'CLEAR',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: hasEnteredDigits ? luxe.crimson : luxe.textMuted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  );
                }
                if (keyLabel == 'DEL') {
                  return _NumKeyButton(
                    onTap: onBackspace,
                    onLongPress: onClear,
                    child: Icon(
                      Icons.backspace_outlined,
                      size: 22,
                      color: luxe.textSecondary,
                    ),
                  );
                }
                return _NumKeyButton(
                  onTap: () => onDigit(keyLabel),
                  child: Text(
                    keyLabel,
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
            ),
          );
        }),
        if (showBiometric && hasEnteredDigits) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onBiometric,
            icon: Icon(
              Icons.fingerprint_rounded,
              color: luxe.emerald,
              size: 22,
            ),
            label: Text(
              'Unlock with Biometrics',
              style: TextStyle(
                color: luxe.emerald,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NumKeyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? glowColor;

  const _NumKeyButton({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.glowColor,
  });

  @override
  State<_NumKeyButton> createState() => _NumKeyButtonState();
}

class _NumKeyButtonState extends State<_NumKeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final radius = BorderRadius.circular(24);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        LuxeHaptics.light();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              LuxeHaptics.medium();
              widget.onLongPress?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.89 : 1.0,
        duration: LuxeMotion.micro,
        child: AnimatedContainer(
          duration: LuxeMotion.micro,
          width: 78,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _pressed
                  ? [
                      luxe.emerald.withValues(alpha: 0.28),
                      luxe.cyan.withValues(alpha: 0.14),
                    ]
                  : [
                      Colors.white.withValues(
                        alpha: luxe.isDark ? 0.10 : 0.85,
                      ),
                      luxe.surfaceGlass,
                    ],
            ),
            borderRadius: radius,
            border: Border.all(
              color: _pressed
                  ? luxe.emerald
                  : (widget.glowColor?.withValues(alpha: 0.45) ??
                        Colors.white.withValues(
                          alpha: luxe.isDark ? 0.14 : 0.5,
                        )),
              width: 1.2,
            ),
            boxShadow: [
              if (_pressed || widget.glowColor != null)
                BoxShadow(
                  color: (widget.glowColor ?? luxe.emerald)
                      .withValues(alpha: 0.25),
                  blurRadius: 16,
                ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
