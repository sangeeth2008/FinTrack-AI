import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/motion/motion.dart';
import '../../app/theme/luxe_tokens.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final Color? glowColor;
  final Gradient? backgroundGradient;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool useBlur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = 24,
    this.borderColor,
    this.glowColor,
    this.backgroundGradient,
    this.onTap,
    this.onLongPress,
    this.useBlur = false,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final radius = BorderRadius.circular(widget.borderRadius);

    // Liquid glass diagonal specular refraction gradient
    final liquidSheenGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: luxe.isDark
          ? [
              Colors.white.withValues(alpha: _pressed ? 0.14 : 0.09),
              luxe.surfaceGlass,
              luxe.emerald.withValues(alpha: 0.03),
            ]
          : [
              Colors.white.withValues(alpha: 0.92),
              luxe.surfaceGlass,
              luxe.emerald.withValues(alpha: 0.04),
            ],
      stops: const [0.0, 0.48, 1.0],
    );

    Widget content = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        gradient: widget.backgroundGradient ?? liquidSheenGradient,
        borderRadius: radius,
        border: Border.all(
          color: widget.borderColor ??
              (luxe.isDark
                  ? Colors.white.withValues(alpha: 0.13)
                  : luxe.borderSubtle),
          width: 1.15,
        ),
        boxShadow: [
          if (widget.glowColor != null)
            BoxShadow(
              color: widget.glowColor!
                  .withValues(alpha: luxe.isDark ? 0.22 : 0.14),
              blurRadius: 30,
              spreadRadius: -2,
              offset: const Offset(0, 10),
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: luxe.isDark ? 0.36 : 0.06),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: widget.child,
    );

    if (widget.useBlur) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 16,
            sigmaY: 16,
          ),
          child: content,
        ),
      );
    }

    if (widget.onTap != null || widget.onLongPress != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: () {
          LuxeHaptics.selection();
          widget.onTap?.call();
        },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                LuxeHaptics.medium();
                widget.onLongPress?.call();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.972 : 1.0,
          duration: LuxeMotion.micro,
          curve: LuxeMotion.decelerate,
          child: content,
        ),
      );
    }

    if (widget.margin != null) {
      return Padding(padding: widget.margin!, child: content);
    }
    return content;
  }
}
