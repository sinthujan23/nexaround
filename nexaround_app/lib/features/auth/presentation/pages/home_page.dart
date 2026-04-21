import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/living_map_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';
import 'package:nexaround_app/features/ai_companion/presentation/pages/ai_chat_page.dart';
import 'package:nexaround_app/features/food_radar/presentation/pages/discover_page.dart';
import 'package:nexaround_app/features/profile/presentation/pages/profile_page.dart';
import 'package:nexaround_app/features/planning/presentation/pages/my_odysseys_page.dart';
import 'package:flutter_animate/flutter_animate.dart';

class HomePage extends StatefulWidget {
  static final GlobalKey<HomePageState> homeKey = GlobalKey<HomePageState>();
  HomePage() : super(key: homeKey);

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  String? _pendingPrompt;

  void switchToNeva(String? prompt) {
    setState(() {
      _selectedIndex = 2; // AI Chat Tab
      _pendingPrompt = prompt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const LivingMapPage(),
      const ArCameraPage(),
      AiChatPage(initialPrompt: _pendingPrompt),
      const DiscoverPage(),
      const MyOdysseysPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      height: 76,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.explore_rounded, 'Home'),
                _buildNavItem(1, Icons.view_in_ar_rounded, 'AR'),
                _buildNavItem(2, Icons.auto_awesome_rounded, 'NEVA'),
                _buildNavItem(3, Icons.restaurant_rounded, 'Food'),
                _buildNavItem(4, Icons.auto_mode_rounded, 'Plans'),
                _buildNavItem(5, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 600.ms, delay: 200.ms, curve: Curves.easeOutBack);
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _selectedIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isActive ? AppColors.primaryGradient : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isActive ? Colors.white : AppColors.textTertiary,
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
