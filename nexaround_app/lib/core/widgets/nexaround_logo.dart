import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

class NexaroundLogo extends StatelessWidget {
  final double size;
  final bool showShimmer;

  const NexaroundLogo({
    super.key, 
    this.size = 100, 
    this.showShimmer = false
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _NexaroundLogoPainter(),
    );
  }
}

class _NexaroundLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    
    // 1. Outer glow ring  
    final glowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius, glowPaint);

    // 2. Orbital Ring
    final ringPaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.primary, AppColors.secondary],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, radius, ringPaint);

    // 3. Inner secondary ring
    final innerRingPaint = Paint()
      ..color = AppColors.secondary.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, radius * 0.7, innerRingPaint);

    // 4. Vertical pillars with gradient
    final pillarPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.textPrimary, AppColors.primary],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round;

    // Left Pillar
    canvas.drawLine(
      Offset(size.width * 0.33, size.height * 0.28),
      Offset(size.width * 0.33, size.height * 0.72),
      pillarPaint,
    );

    // Right Pillar
    canvas.drawLine(
      Offset(size.width * 0.67, size.height * 0.28),
      Offset(size.width * 0.67, size.height * 0.72),
      pillarPaint,
    );

    // 5. Floating Diagonal Bridge with neon glow
    final bridgeGlowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawLine(
      Offset(size.width * 0.36, size.height * 0.34),
      Offset(size.width * 0.64, size.height * 0.66),
      bridgeGlowPaint,
    );

    final bridgePaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.primary, AppColors.secondary],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.36, size.height * 0.34),
      Offset(size.width * 0.64, size.height * 0.66),
      bridgePaint,
    );

    // 6. Center precision point with glow
    canvas.drawCircle(
      center, 
      size.width * 0.06, 
      Paint()
        ..color = AppColors.primary.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawCircle(
      center, 
      size.width * 0.035, 
      Paint()
        ..shader = const RadialGradient(
          colors: [AppColors.primary, AppColors.secondary],
        ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.035))
        ..style = PaintingStyle.fill,
    );

    // 7. Small floating dots (data nodes)
    final dotPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    
    final dotPositions = [
      Offset(size.width * 0.18, size.height * 0.5),
      Offset(size.width * 0.82, size.height * 0.5),
      Offset(size.width * 0.5, size.height * 0.15),
      Offset(size.width * 0.5, size.height * 0.85),
    ];
    
    for (final pos in dotPositions) {
      canvas.drawCircle(pos, size.width * 0.015, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
