import 'package:flutter/material.dart';
import '../../app/motion/motion.dart';
import '../../app/theme/luxe_tokens.dart';

class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final bool isLoading;
  final bool expand;
  final EdgeInsetsGeometry padding;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.gradient,
    this.isLoading = false,
    this.expand = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final enabled = widget.onPressed != null && !widget.isLoading;
    final grad = widget.gradient ?? luxe.primaryGradient;

    final buttonContent = AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: LuxeMotion.micro,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: LuxeMotion.fast,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            gradient: grad,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: luxe.emerald.withValues(alpha: 0.32),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF061510)),
                  ),
                )
              else ...[
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 20,
                    color: const Color(0xFF061510),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF061510),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled
          ? () {
              LuxeHaptics.medium();
              widget.onPressed?.call();
            }
          : null,
      child: buttonContent,
    );
  }
}

