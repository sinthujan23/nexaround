import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

class AnimatedNevaBanner extends StatefulWidget {
  final VoidCallback onTap;
  final bool isActive;

  const AnimatedNevaBanner({
    super.key,
    required this.onTap,
    this.isActive = true,
  });

  @override
  State<AnimatedNevaBanner> createState() => _AnimatedNevaBannerState();
}

class _AnimatedNevaBannerState extends State<AnimatedNevaBanner> {
  bool _isExpanded = true;
  int _textIndex = 0;
  Timer? _step1Timer;
  Timer? _collapseTimer;

  final List<String> _cycleTexts = [
    'Where to?',
    'Where should I go?',
    "Let's explore!",
    'Ask Neva ✨',
    'Any plans?',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _startCycle();
    } else {
      _isExpanded = false;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedNevaBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _startCycle();
    } else if (oldWidget.isActive && !widget.isActive) {
      _cancelTimers();
      if (_isExpanded && mounted) {
        setState(() => _isExpanded = false);
      }
    }
  }

  void _cancelTimers() {
    _step1Timer?.cancel();
    _step1Timer = null;
    _collapseTimer?.cancel();
    _collapseTimer = null;
  }

  void _startCycle() {
    _cancelTimers();
    setState(() {
      _isExpanded = true;
      _textIndex = 0;
    });

    // Step 1: After 2.5s transition smoothly to second text
    _step1Timer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() {
        _textIndex = 1;
      });

      // Step 2: After displaying second text for 2.5s, smoothly collapse
      _collapseTimer = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        setState(() {
          _isExpanded = false;
        });
      });
    });
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        height: 72,
        margin: const EdgeInsets.only(top: 8),
        padding: EdgeInsets.only(
          left: 10,
          right: _isExpanded ? 14 : 10,
        ),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomLeft: Radius.circular(24),
          ),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Neva Walking Avatar + Red Badge
            ValueListenableBuilder<String?>(
              valueListenable: CacheService.discoveryResultNotifier,
              builder: (context, discoveryResult, _) {
                final hasResult =
                    discoveryResult != null && discoveryResult.isNotEmpty;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: Image.asset(
                        'assets/images/neva_walking.webp',
                        fit: BoxFit.contain,
                      ),
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
                                color: AppColors.error.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scale(
                              begin: const Offset(0.8, 0.8),
                              end: const Offset(1.2, 1.2),
                              duration: 800.ms,
                            ),
                      ),
                  ],
                );
              },
            ),

            // Animated text section (smoothly collapses without blank space)
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: _isExpanded
                    ? Padding(
                        padding: const EdgeInsets.only(left: 10, right: 4),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.4),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            _cycleTexts[_textIndex],
                            key: ValueKey<int>(_textIndex),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      )
          .animate()
          .slideX(begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutBack),
    );
  }
}
