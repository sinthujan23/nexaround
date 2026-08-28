import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/core/services/permission_service.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> {
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  void _navigateToNext() async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return const Scaffold(
        body: Center(
          child: Text('Splash Screen (Test)'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Image.asset(
          'assets/images/app_logo.png',
          width: 220,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
