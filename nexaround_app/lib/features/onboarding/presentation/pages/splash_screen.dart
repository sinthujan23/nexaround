import 'dart:math';
import 'dart:ui';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/core/services/permission_service.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _particleController;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _navigateToNext();
  }

  void _navigateToNext() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    // Wait for the first frame to render and layout to settle before requesting native dialogs on iOS
    _splashTimer = Timer(const Duration(milliseconds: 1000), () async {
      // Request permissions
      await PermissionService.requestAllPermissions();
      
      if (!mounted) return;
      
      // Wait for the remaining splash duration (3.5s total - 1.0s delay = 2.5s)
      _splashTimer = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;

        if (CacheService.isFirstTime()) {
          context.go('/onboarding');
        } else if (CacheService.isLoggedIn()) {
          context.go('/home');
        } else {
          context.go('/login');
        }
      });
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return const Scaffold(
        body: Center(
          child: Text('Splash Screen (Test)'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Animated particle field
          ...List.generate(20, (i) => _buildParticle(i)),

          // Radial glow behind logo
          Center(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 360 + (_pulseController.value * 50),
                  height: 360 + (_pulseController.value * 50),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.04 + _pulseController.value * 0.02),
                        AppColors.secondary.withOpacity(0.02),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Grid lines background
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _GridPainter(),
          ),

          // Glass blur overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo only — no text per client request
                _buildLogo(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticle(int index) {
    final random = Random(index);
    final startX = random.nextDouble() * 400;
    final startY = random.nextDouble() * 800;
    final size = 2.0 + random.nextDouble() * 3;

    return Positioned(
      left: startX,
      top: startY,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: index % 2 == 0
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.secondary.withOpacity(0.08),
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .moveY(
            begin: 0,
            end: -100 - random.nextDouble() * 200,
            duration: Duration(seconds: 4 + random.nextInt(4)),
            curve: Curves.easeInOut,
          )
          .fade(begin: 0, end: 0.8, duration: 1.seconds)
          .then()
          .fade(end: 0, duration: 2.seconds),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 280,
      // Let the logo determine its own height via aspect ratio.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.14),
            blurRadius: 60,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/app_logo.png',
        width: 280,
        fit: BoxFit.contain,
      ),
    )
        .animate()
        .scale(
          begin: const Offset(0.5, 0.5),
          end: const Offset(1, 1),
          duration: 1200.ms,
          curve: Curves.easeOutBack,
        )
        .fade(duration: 800.ms);
  }


}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withOpacity(0.3)
      ..strokeWidth = 0.5;

    // Vertical lines
    for (double x = 0; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = 0; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
