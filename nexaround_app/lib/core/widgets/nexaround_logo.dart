import 'package:flutter/material.dart';

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
    return Image.asset(
      'assets/images/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
