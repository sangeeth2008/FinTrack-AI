import 'package:flutter/material.dart';
import '../../app/theme/luxe_tokens.dart';

class LuxeScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool extendBody;

  const LuxeScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.extendBody = true,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;

    return Scaffold(
      backgroundColor: luxe.bg,
      extendBody: extendBody,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: false,
              painter: _AmbientMeshPainter(
                isDark: luxe.isDark,
                emerald: luxe.emerald,
                gold: luxe.gold,
                cyan: luxe.cyan,
              ),
            ),
          ),
          body,
        ],
      ),
    );
  }
}

class _AmbientMeshPainter extends CustomPainter {
  final bool isDark;
  final Color emerald;
  final Color gold;
  final Color cyan;

  const _AmbientMeshPainter({
    required this.isDark,
    required this.emerald,
    required this.gold,
    required this.cyan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final alphaPrimary = isDark ? 0.13 : 0.08;
    final alphaSecondary = isDark ? 0.09 : 0.06;

    final offset1 = Offset(size.width * 0.22, size.height * 0.14);
    final offset2 = Offset(size.width * 0.82, size.height * 0.38);
    final offset3 = Offset(size.width * 0.36, size.height * 0.82);

    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          emerald.withValues(alpha: alphaPrimary),
          emerald.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: offset1, radius: size.width * 0.65),
      );

    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          gold.withValues(alpha: alphaSecondary),
          gold.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: offset2, radius: size.width * 0.58),
      );

    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          cyan.withValues(alpha: alphaSecondary),
          cyan.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: offset3, radius: size.width * 0.60),
      );

    canvas.drawCircle(offset1, size.width * 0.65, paint1);
    canvas.drawCircle(offset2, size.width * 0.58, paint2);
    canvas.drawCircle(offset3, size.width * 0.60, paint3);
  }

  @override
  bool shouldRepaint(covariant _AmbientMeshPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
