import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/living_map_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';
import 'package:nexaround_app/features/ai_companion/presentation/pages/ai_chat_page.dart';
import 'package:nexaround_app/features/food_radar/presentation/pages/discover_page.dart';
import 'package:nexaround_app/features/profile/presentation/pages/profile_page.dart';
import 'package:nexaround_app/features/planning/presentation/pages/my_odysseys_page.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/core/services/permission_service.dart';
import 'package:nexaround_app/core/services/notification_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/discovery_history_service.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/onboarding/presentation/pages/splash_screen.dart';

import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_detail_page.dart';
import 'package:nexaround_app/features/living_map/presentation/widgets/discovery_engine_sheet.dart';

class HomePage extends StatefulWidget {
  static final GlobalKey<HomePageState> homeKey = GlobalKey<HomePageState>();
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String? _pendingPrompt;
  Map<String, dynamic>? _pendingPlaceContext;
  int _discoverInitialTab = 0;
  int _discoverRequestCount = 0;
  DateTime? _lastBackPressTime;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Direct check and redirect on launch
    _checkLocationService();

    // Now that we're in the authenticated shell, register the device for push
    // and route notification taps to the right tab / exact plan.
    NotificationService.instance.onOpen = (data) async {
      final type = (data['type'] ?? '').toString();
      final odysseyId = (data['odyssey_id'] ?? data['itinerary_id'] ?? data['id'] ?? data['odysseyId'])?.toString();

      if (type == 'odyssey_ready' || type == 'odyssey_generated' || type == 'plan_ready' || (odysseyId != null && odysseyId.isNotEmpty && type.contains('odyssey'))) {
        if (odysseyId != null && odysseyId.isNotEmpty) {
          await openOdysseyById(odysseyId);
        } else {
          try {
            final repo = OdysseyRepository();
            final list = await repo.getMyOdysseys();
            if (list.isNotEmpty && mounted) {
              openOdysseyDetail(list.first);
            } else {
              switchToPlans();
            }
          } catch (_) {
            switchToPlans();
          }
        }
      }
      if (data['type'] == 'story_comment') switchToExplore();
      if (type == 'discovery_ready' || data['type'] == 'discovery_ready') {
        final discoveryId = (data['discovery_id'] ?? data['id'])?.toString();
        switchToExplore();
        CacheService.isDiscoveringNotifier.value = false;
        try {
          final history = await DiscoveryHistoryService.fetchHistory();
          Map<String, dynamic>? target;
          if (discoveryId != null && discoveryId.isNotEmpty) {
            for (final item in history) {
              if (item['id']?.toString() == discoveryId) {
                target = item;
                break;
              }
            }
          }
          target ??= history.isNotEmpty ? history.first : null;
          if (target != null && mounted) {
            final res = target['result'] as String?;
            final loc = target['location'] as String?;
            if (res != null && res.isNotEmpty) {
              openDiscoveryPlan(res, location: loc);
            }
          }
        } catch (e) {
          debugPrint('Error opening discovery plan from push: $e');
        }
      }
    };
    NotificationService.instance.syncToken();
  }

  void openDiscoveryPlan(String result, {String? location}) {
    switchToExplore();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DiscoveryEngineSheet(
        locationName: location ?? '',
        initialResult: result,
      ),
    );
  }

  void openOdysseyDetail(Odyssey odyssey) {
    switchToPlans();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OdysseyDetailPage(odyssey: odyssey),
      ),
    );
  }

  Future<void> openOdysseyById(String? odysseyId) async {
    switchToPlans();
    if (odysseyId == null || odysseyId.isEmpty) return;

    try {
      final repo = OdysseyRepository();
      // Fetch fresh network first to ensure full plan with all days is loaded
      Odyssey? odyssey = await repo.getOdysseyById(odysseyId);
      odyssey ??= repo.getCachedOdysseys().where((o) => o.id == odysseyId).firstOrNull;
      if (odyssey != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OdysseyDetailPage(odyssey: odyssey!),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error opening odyssey by id: $e');
    }
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

      // If we were waiting for Neva, check if it finished while we were away
      if (CacheService.isDiscoveringNotifier.value == true) {
        DiscoveryHistoryService.fetchHistory().then((history) {
          if (history.isNotEmpty) {
            final latest = history.first;
            CacheService.discoveryResultNotifier.value = latest['result'] as String?;
            CacheService.isDiscoveringNotifier.value = false;
          }
        }).catchError((e) {
          debugPrint('Error checking discovery status on resume: $e');
        });
      }
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


  void switchToNeva(String? prompt, {Map<String, dynamic>? placeContext}) {
    setState(() {
      _selectedIndex = 2; // AI Chat Tab
      _pendingPrompt = prompt;
      _pendingPlaceContext = placeContext;
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

  void switchToDiscover({int initialTab = 0}) {
    setState(() {
      _discoverInitialTab = initialTab;
      _discoverRequestCount++;
      _selectedIndex = 3; // Discover Tab
    });
  }

  void switchToPlans() {
    setState(() {
      _selectedIndex = 4; // Blueprints / Odysseys Tab
    });
  }

  void switchToProfile() {
    setState(() {
      _selectedIndex = 5; // Profile Tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const LivingMapPage(),
      ArCameraPage(isActive: _selectedIndex == 1),
      AiChatPage(initialPrompt: _pendingPrompt, placeContext: _pendingPlaceContext),
      DiscoverPage(
        initialTab: _discoverInitialTab,
        isActive: _selectedIndex == 3,
        requestCount: _discoverRequestCount,
      ),
      const MyOdysseysPage(),
      const ProfilePage(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0; // Redirect back to Home tab
          });
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Press back again to exit NexAround'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
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
      ),
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
              color: Colors.white.withValues(alpha: 0.92),
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
                  _buildNavItem(3, Icons.travel_explore_rounded, 'Discover'),
                  _buildNavItem(4, Icons.auto_mode_rounded, 'Plans'),
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
                    color: AppColors.primary.withValues(alpha: 0.18),
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
