import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/presentation/pages/login_page.dart';
import 'package:flutter_animate/flutter_animate.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingData> _pages = [
    _OnboardingData(
      imagePath: 'assets/images/neva_avatar.png',
      icon: Icons.auto_awesome_rounded,
      title: 'AI Companion',
      subtitle: 'YOUR PERSONAL TRAVEL INTELLIGENCE',
      description:
          'An AI that learns your preferences and crafts unique experiences tailored just for you.',
      gradient: AppColors.primaryGradient,
      glowColor: AppColors.actionTeal,
    ),
    _OnboardingData(
      imagePath: 'assets/images/lotus_temple.png',
      icon: Icons.view_in_ar_rounded,
      title: 'AR Exploration',
      subtitle: 'SEE THE WORLD THROUGH AI EYES',
      description:
          'Point your camera at any landmark and instantly discover its history, ratings, and hidden stories.',
      gradient: AppColors.primaryGradient,
      glowColor: AppColors.ratingGold,
    ),
    _OnboardingData(
      imagePath: 'assets/images/hero_luxury.png',
      icon: Icons.public_rounded,
      title: '3D Living Map',
      subtitle: 'NAVIGATE YOUR ADVENTURE',
      description:
          'An intelligent map that breathes — showing trending spots, hidden gems, and real-time activity around you.',
      gradient: AppColors.primaryGradient,
      glowColor: AppColors.secondary,
    ),
  ];

  void _next() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _navigateToLogin();
    }
  }

  void _navigateToLogin() async {
    await CacheService.setOnboardingComplete();
    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const LoginPage(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_currentPage + 1}/3',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _navigateToLogin,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                children: List.generate(
                  3,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: index <= _currentPage
                            ? AppColors.primaryGradient
                            : null,
                        color: index <= _currentPage
                            ? null
                            : AppColors.surfaceVariant,
                        boxShadow: index <= _currentPage
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.4),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemCount: 3,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index], index);
                },
              ),
            ),

            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: _buildButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingData data, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated icon container
          _buildIconContainer(data, index),
          const SizedBox(height: 56),

          // Title
          ShaderMask(
            shaderCallback: (bounds) => data.gradient.createShader(
              Rect.fromLTWH(0, 0, bounds.width, bounds.height),
            ),
            child: Text(
              data.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ).animate().fade(delay: 200.ms).slideY(begin: 0.2, end: 0),

          const SizedBox(height: 12),

          // Subtitle
          Text(
            data.subtitle,
            style: TextStyle(
              color: data.glowColor.withOpacity(0.7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
            textAlign: TextAlign.center,
          ).animate().fade(delay: 400.ms),

          const SizedBox(height: 24),

          // Description
          Text(
            data.description,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ).animate().fade(delay: 500.ms).slideY(begin: 0.1, end: 0),
        ],
      ),
    );
  }

  Widget _buildIconContainer(_OnboardingData data, int index) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: data.glowColor.withOpacity(0.15)),
        gradient: RadialGradient(
          colors: [
            data.glowColor.withOpacity(0.2),
            data.glowColor.withOpacity(0.02),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: data.glowColor.withOpacity(0.25),
            blurRadius: 50,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Orbiting ring
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: data.glowColor.withOpacity(0.25),
                width: 1.5,
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .rotate(duration: 8.seconds),

          // Cinematic Image
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Image.asset(
              data.imagePath,
              fit: BoxFit.cover,
              width: 120,
              height: 120,
            ),
          ),
        ],
      ),
    )
        .animate()
        .scale(
          begin: const Offset(0.6, 0.6),
          duration: 800.ms,
          curve: Curves.easeOutBack,
        )
        .fade();
  }

  Widget _buildButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: AppColors.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _next,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            _currentPage == 2 ? 'GET STARTED' : 'CONTINUE',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    ).animate().fade(delay: 600.ms).slideY(begin: 0.3, end: 0);
  }
}

class _OnboardingData {
  final String imagePath;
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Gradient gradient;
  final Color glowColor;

  _OnboardingData({
    required this.imagePath,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.gradient,
    required this.glowColor,
  });
}
