import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/core/services/permission_service.dart';

const String _splashAnimAsset = 'assets/animations/splash_animation.webp';
// Total playback time baked into the WebP's own frame durations (see the
// generation script that produced it) — kept in sync manually since the
// widget-level Image API exposes no "animation complete" callback.
const Duration _splashAnimDuration = Duration(milliseconds: 2857);
const Duration _completionBuffer = Duration(milliseconds: 200);
const Duration _loadTimeout = Duration(seconds: 4);
const Duration _minSplashFloor = Duration(milliseconds: 1200);

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> {
  final bool _isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  final DateTime _startTime = DateTime.now();

  Timer? _loadTimeoutTimer;
  Timer? _completionTimer;
  bool _animReady = false;
  bool _animFailed = false;
  bool _navigated = false;
  bool _permissionsKicked = false;

  @override
  void initState() {
    super.initState();
    if (_isTest) return;

    _loadTimeoutTimer = Timer(_loadTimeout, _onLoadTimeout);
  }

  void _onFirstFrame() {
    if (_animReady || _animFailed || !mounted) return;

    _loadTimeoutTimer?.cancel();
    setState(() => _animReady = true);
    _completionTimer = Timer(_splashAnimDuration + _completionBuffer, _finishSplash);
    _kickPermissionsOnce();
  }

  void _onLoadTimeout() {
    if (!_animReady) {
      _handleAnimFailure();
    }
  }

  void _handleAnimFailure() {
    _loadTimeoutTimer?.cancel();
    if (mounted) {
      setState(() => _animFailed = true);
    } else {
      _animFailed = true;
    }
    _kickPermissionsOnce();
    _finishSplash();
  }

  void _kickPermissionsOnce() {
    if (_permissionsKicked) return;
    _permissionsKicked = true;
    unawaited(PermissionService.requestAllPermissions());
  }

  Future<void> _finishSplash() async {
    if (_navigated || !mounted) return;

    final elapsed = DateTime.now().difference(_startTime);
    if (elapsed < _minSplashFloor) {
      await Future.delayed(_minSplashFloor - elapsed);
      if (!mounted || _navigated) return;
    }

    _navigated = true;
    _loadTimeoutTimer?.cancel();
    _completionTimer?.cancel();

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
    _loadTimeoutTimer?.cancel();
    _completionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isTest) {
      return const Scaffold(
        body: Center(
          child: Text('Splash Screen (Test)'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fallback only — shown if the animation asset fails to load.
          if (_animFailed)
            Center(
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 220,
                fit: BoxFit.contain,
              ),
            ),
          if (!_animFailed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Image.asset(
                _splashAnimAsset,
                fit: BoxFit.contain,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (frame != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFrame());
                  }
                  return child;
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _handleAnimFailure());
                  return const SizedBox.shrink();
                },
              ),
            ),
        ],
      ),
    );
  }
}
