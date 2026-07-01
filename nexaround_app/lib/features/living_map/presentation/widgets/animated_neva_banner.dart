import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

class AnimatedNevaBanner extends StatefulWidget {
  final VoidCallback onTap;

  const AnimatedNevaBanner({super.key, required this.onTap});

  @override
  State<AnimatedNevaBanner> createState() => _AnimatedNevaBannerState();
}

class _AnimatedNevaBannerState extends State<AnimatedNevaBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isExpanded = true;
  bool _showMood = true;
  Timer? _textTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _textTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      if (mounted && _isExpanded) {
        setState(() {
          _showMood = !_showMood;
        });
      }
    });

    // Auto-collapse the text banner after 5 seconds to save space
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isExpanded = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!_isExpanded) {
          setState(() => _isExpanded = true);
          // Re-collapse after a few seconds if they don't tap again
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _isExpanded = false);
          });
        } else {
          widget.onTap();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: 72,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomLeft: Radius.circular(24),
          ),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Neva Avatar (Sparkle icon with gentle pulse) + Red Badge
            ValueListenableBuilder<String?>(
              valueListenable: CacheService.discoveryResultNotifier,
              builder: (context, discoveryResult, _) {
                final hasResult = discoveryResult != null;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, sin(_controller.value * pi * 2) * 2),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.brandGreen.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/neva_peeking.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (hasResult)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withOpacity(0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ).animate(onPlay: (c) => c.repeat(reverse: true))
                         .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 800.ms),
                      ),
                  ],
                );
              },
            ),
            
            // Expanded text
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _isExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.5),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _showMood ? 'Mood?' : 'Weather?',
                          key: ValueKey<bool>(_showMood),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ).animate().fadeIn(duration: 200.ms),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ).animate().slideX(begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutBack),
    );
  }
}
