import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_bloc.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_event.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_view.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nexaround_app/core/services/permission_service.dart';

class ArEntryPage extends StatefulWidget {
  const ArEntryPage({super.key});

  @override
  State<ArEntryPage> createState() => _ArEntryPageState();
}

class _ArEntryPageState extends State<ArEntryPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _orbitController;
  late AnimationController _pulseController;
  late AnimationController _scanlineController;
  bool _locationReady = false;
  bool _cameraReady = false;
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orbitController = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scanlineController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _checkPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when user returns from Settings (iOS flow)
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    // Actually check current permission status
    final cameraOk = await PermissionService.isCameraGranted();
    final locationOk = await PermissionService.isLocationGranted();

    if (mounted) {
      setState(() {
        _cameraReady = cameraOk;
        _locationReady = locationOk;
        _checkingPermissions = false;
      });
    }

    // If permissions are not granted, request them
    if (!cameraOk || !locationOk) {
      if (!cameraOk) {
        final granted = await PermissionService.requestCameraPermission();
        if (mounted) setState(() => _cameraReady = granted);
      }
      if (!locationOk) {
        final granted = await PermissionService.requestLocationPermission();
        if (mounted) setState(() => _locationReady = granted);
      }
    }
  }

  bool get _allPermissionsReady => _locationReady && _cameraReady;

  void _enterAR() {
    context.read<ArBloc>().add(ArSessionStarted());
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ArView(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.1, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orbitController.dispose();
    _pulseController.dispose();
    _scanlineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Subtle Background Grid
          CustomPaint(painter: _GridPainter(), child: const SizedBox.expand()),

          // Animated Orbital Rings
          Center(child: _buildOrbitalSystem()),

          // Content Overlay
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                _buildHeader(),
                const Spacer(),
                _buildCenterReticle(),
                const Spacer(),
                _buildNearbyStats(),
                const SizedBox(height: 24),
                _buildEnterButton(),
                const SizedBox(height: 16),
                _buildPermissionStatus(),
                const SizedBox(height: 48),
              ],
            ),
          ),

          // Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 16),
              ),
            ),
          ).animate().fade(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'AR DISCOVERY',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ).animate().fade().slideY(begin: -0.3, end: 0),
        const SizedBox(height: 8),
        Text(
          'See the world\nthrough new eyes',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ).animate().fade(delay: 200.ms).slideY(begin: 0.2, end: 0),
      ],
    );
  }

  Widget _buildOrbitalSystem() {
    return AnimatedBuilder(
      animation: _orbitController,
      builder: (context, _) {
        return SizedBox(
          width: 340,
          height: 340,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Ring
              Transform.rotate(
                angle: _orbitController.value * 2 * pi,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withOpacity(0.08), width: 1),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.4), shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
              // Middle Ring
              Transform.rotate(
                angle: -_orbitController.value * 2 * pi * 0.7,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.secondary.withOpacity(0.15), width: 1),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.5), shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
              // Inner Ring
              Transform.rotate(
                angle: _orbitController.value * 2 * pi * 1.3,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withOpacity(0.06), width: 1),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCenterReticle() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final scale = 1.0 + 0.05 * _pulseController.value;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.06),
              border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 2),
            ),
            child: Center(
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.1),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5),
                ),
                child: const Icon(Icons.filter_center_focus_rounded, color: AppColors.primary, size: 22),
              ),
            ),
          ),
        );
      },
    ).animate().scale(duration: 800.ms, curve: Curves.easeOutBack);
  }

  Widget _buildNearbyStats() {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        final count = state.attractions.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.radar_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Text(
                count > 0 ? '$count PLACES DETECTED NEARBY' : 'SCANNING FOR PLACES...',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ).animate().fade(delay: 600.ms).slideY(begin: 0.2, end: 0);
      },
    );
  }

  Widget _buildEnterButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton(
          onPressed: _allPermissionsReady ? _enterAR : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            elevation: 20,
            shadowColor: AppColors.primary.withOpacity(0.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_allPermissionsReady ? Icons.explore_rounded : Icons.lock_open_rounded, size: 20),
              const SizedBox(width: 12),
              Text(
                _allPermissionsReady ? 'ENTER AR WORLD' : 'GRANT PERMISSIONS',
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade(delay: 800.ms).slideY(begin: 0.3, end: 0);
  }

  Widget _buildPermissionStatus() {
    if (_checkingPermissions) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPermissionDot('Camera', _cameraReady),
        const SizedBox(width: 20),
        _buildPermissionDot('Location', _locationReady),
        const SizedBox(width: 20),
        _buildPermissionDot('Compass', true),
      ],
    ).animate().fade(delay: 1.seconds);
  }

  Widget _buildPermissionDot(String label, bool granted) {
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: granted ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withOpacity(0.15)
      ..strokeWidth = 0.5;
    
    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
