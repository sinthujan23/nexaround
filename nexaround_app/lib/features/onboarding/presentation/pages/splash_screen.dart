import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/widgets/nexaround_logo.dart';
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
    // Wait for the first frame to render and layout to settle before requesting native dialogs on iOS
    await Future.delayed(const Duration(milliseconds: 1000));

    // Request permissions
    await PermissionService.requestAllPermissions();
    
    // Wait for the remaining splash duration (3.5s total - 1.0s delay = 2.5s)
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    if (CacheService.isFirstTime()) {
      context.go('/onboarding');
    } else if (CacheService.isLoggedIn()) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  width: 300 + (_pulseController.value * 40),
                  height: 300 + (_pulseController.value * 40),
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
                // Logo with glow
                _buildLogo(),
                const SizedBox(height: 48),
                _buildBrandText(),
                const SizedBox(height: 64),
                _buildLoadingIndicator(),
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
      width: 144,
      height: 144,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder, width: 0.8),
        gradient: const RadialGradient(
          colors: [
            AppColors.surface,
            AppColors.surfaceVariant,
          ],
          stops: [0.4, 1.0],
        ),
        boxShadow: [
          ...AppShadows.md,
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Center(child: NexaroundLogo(size: 125)),
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

  Widget _buildBrandText() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => AppColors.primaryGradient.createShader(
            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          ),
          child: const Text(
            'NexAround',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w300,
              letterSpacing: 8,
              height: 1.0,
            ),
          ),
        )
            .animate()
            .fade(delay: 600.ms, duration: 800.ms)
            .slideY(begin: 0.3, end: 0),
        const SizedBox(height: 16),
        Container(
          width: 80,
          height: 2,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.5),
                blurRadius: 10,
              ),
            ],
          ),
        ).animate().scaleX(delay: 1000.ms, begin: 0, end: 1, duration: 600.ms),
        const SizedBox(height: 16),
        const Text(
          'AI TOURISM COMPANION',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 4.5,
          ),
        ).animate().fade(delay: 1400.ms).slideY(begin: 0.5, end: 0),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return SizedBox(
      width: 160,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              backgroundColor: AppColors.surfaceVariant,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 3,
            ),
          )
              .animate()
              .fade(delay: 1800.ms)
              .shimmer(
                delay: 2.seconds,
                duration: 1500.ms,
                color: AppColors.primary.withOpacity(0.3),
              ),
          const SizedBox(height: 12),
          const Text(
            'INITIALIZING AI',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              letterSpacing: 2.8,
              fontWeight: FontWeight.w600,
            ),
          ).animate().fade(delay: 2.seconds),
        ],
      ),
    );
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
