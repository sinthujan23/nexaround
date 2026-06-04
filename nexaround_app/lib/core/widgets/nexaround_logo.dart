import 'package:flutter/material.dart';

class NexaroundLogo extends StatelessWidget {
  /// Controls the rendered width. Height is determined by the image's own
  /// aspect ratio so the "nexARound" wordmark and tagline are never clipped.
  final double size;
  final BoxFit fit;

  const NexaroundLogo({
    super.key,
    this.size = 100,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/app_logo.png',
      width: size,
      // No forced height — let the image decide its own proportions.
      fit: fit,
    );
  }
}

