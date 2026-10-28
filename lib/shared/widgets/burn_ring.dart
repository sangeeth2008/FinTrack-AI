import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/motion/motion.dart';
import '../../app/theme/luxe_tokens.dart';

class BurnRing extends StatelessWidget {
  final double progress; // 0.0 to 1.0+
  final double size;
  final double strokeWidth;
  final Widget? center;

  const BurnRing({
    super.key,
    required this.progress,
    this.size = 112,
    this.strokeWidth = 10,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final clamped = progress.clamp(0.0, 1.25);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: clamped),
      duration: LuxeMotion.slow,
      curve: LuxeMotion.decelerate,
      builder: (context, animatedValue, _) {
        final Color ringColor = animatedValue > 0.95
            ? luxe.crimson
            : (animatedValue > 0.72 ? luxe.gold : luxe.emerald);

        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _BurnRingPainter(
              progress: animatedValue.clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              trackColor: luxe.borderSubtle,
              activeColor: ringColor,
              secondaryColor: animatedValue > 0.85 ? luxe.crimson : luxe.cyan,
            ),
            child: Center(child: center),
          ),
        );
      },
    );
  }
}

class _BurnRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color activeColor;
  final Color secondaryColor;

  const _BurnRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.activeColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.005) return;

    final sweepAngle = 2 * math.pi * progress;
    const startAngle = -math.pi / 2;

    final glowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);

    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [secondaryColor, activeColor, activeColor],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, activePaint);

    // Leading bioluminescent tip dot
    final tipAngle = startAngle + sweepAngle;
    final tipOffset = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    canvas.drawCircle(
      tipOffset,
      strokeWidth * 0.34,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _BurnRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor;
  }
}

