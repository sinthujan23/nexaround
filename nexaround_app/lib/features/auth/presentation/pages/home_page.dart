import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/living_map_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';
import 'package:nexaround_app/features/ai_companion/presentation/pages/ai_chat_page.dart';
import 'package:nexaround_app/features/food_radar/presentation/pages/discover_page.dart';
import 'package:nexaround_app/features/profile/presentation/pages/profile_page.dart';
import 'package:nexaround_app/features/planning/presentation/pages/my_odysseys_page.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/core/services/permission_service.dart';
import 'package:nexaround_app/core/services/notification_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_event.dart';
import 'package:nexaround_app/features/budget/data/repositories/budget_repository_impl.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/onboarding/presentation/pages/splash_screen.dart';

class HomePage extends StatefulWidget {
  static final GlobalKey<HomePageState> homeKey = GlobalKey<HomePageState>();
  HomePage() : super(key: homeKey);

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  String? _pendingPrompt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Direct check and redirect on launch
    _checkLocationService();

    // Now that we're in the authenticated shell, register the device for push
    // and route notification taps to the right tab.
    NotificationService.instance.onOpen = (data) {
      if (data['type'] == 'odyssey_ready') switchToPlans();
    };
    NotificationService.instance.syncToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationService();
      // Surface any notifications saved while the app was backgrounded.
      CacheService.reload();
    }
  }

  /// Check if location service (GPS) is on; if off, redirect to system settings immediately
  /// This follows the direct redirect method used by popular apps to avoid UI-related crashes
  Future<void> _checkLocationService() async {
    final enabled = await PermissionService.isLocationServiceEnabled();
    if (!enabled && mounted) {
      debugPrint('📍 Location disabled. Redirecting to system settings...');
      await PermissionService.openLocationSettings();
    }
  }


  void switchToNeva(String? prompt) {
    setState(() {
      _selectedIndex = 2; // AI Chat Tab
      _pendingPrompt = prompt;
    });
  }

  void switchToAr() {
    setState(() {
      _selectedIndex = 1; // AR Camera Tab
    });
  }

  void switchToExplore() {
    setState(() {
      _selectedIndex = 0; // Explore/Map Tab
    });
  }

  void switchToPlans() {
    setState(() {
      _selectedIndex = 4; // Blueprints / Odysseys Tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const LivingMapPage(),
      ArCameraPage(isActive: _selectedIndex == 1),
      AiChatPage(initialPrompt: _pendingPrompt),
      const DiscoverPage(),
      const MyOdysseysPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError && (state.message.contains('401') || state.message.contains('token'))) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AnimatedSplashScreen()),
              (route) => false,
            );
            return;
          }
        },
        child: IndexedStack(
          index: _selectedIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: _selectedIndex == 1 ? null : _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppShadows.lg,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.glassBorder, width: 0.6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.explore_rounded, 'Home'),
                  _buildNavItem(1, Icons.view_in_ar_rounded, 'AR'),
                  _buildNavItem(2, Icons.auto_awesome_rounded, 'NEVA'),
                  _buildNavItem(3, Icons.restaurant_rounded, 'Food'),
                  _buildNavItem(4, Icons.auto_mode_rounded, 'Plans'),
                  _buildNavItem(5, Icons.person_rounded, 'Me'),
                ],
              ),
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
        duration: AppDurations.normal,
        curve: AppCurves.standard,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isActive ? AppColors.primaryGradient : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            label == 'NEVA'
                ? Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive ? Colors.white : Colors.transparent,
                        width: 1.5,
                      ),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/neva_avatar.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
                    color: isActive ? Colors.white : AppColors.textTertiary,
                  ),
            AnimatedSize(
              duration: AppDurations.normal,
              curve: AppCurves.standard,
              child: isActive
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
