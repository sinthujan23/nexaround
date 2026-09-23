import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_package_detail_page.dart';
import 'package:nexaround_app/features/food_radar/presentation/pages/discover_page.dart';

/// What a shared link (`https://nexaround.com/e/<package id>`) opens.
///
/// A link carries only the id, and the detail page needs a package to draw
/// its first frame, so this fetches it first and then shows the detail page
/// in place.
///
/// Opened at /home/e/:id (lib/app/routes.dart), over Home, so Back returns
/// there. A signed-out user is sent to sign in first and lands here after.
/// The standalone /e/:id route is a fallback the redirect never lets through;
/// there [standalone] makes Back go through the splash screen.
class ExperienceLinkPage extends StatefulWidget {
  final String packageId;
  final bool standalone;

  const ExperienceLinkPage({
    super.key,
    required this.packageId,
    this.standalone = false,
  });

  @override
  State<ExperienceLinkPage> createState() => _ExperienceLinkPageState();
}

class _ExperienceLinkPageState extends State<ExperienceLinkPage> {
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  ExperiencePackageEntity? _package;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // A mangled link never reaches the network.
    final package = _uuid.hasMatch(widget.packageId)
        ? await ExperiencesService.fetchPackage(widget.packageId)
        : null;
    if (!mounted) return;
    setState(() {
      _package = package;
      _loading = false;
    });
  }

  void _leave() {
    if (widget.standalone) {
      context.go('/');
    } else if (!Navigator.of(context).canPop()) {
      context.go('/home');
    } else {
      Navigator.of(context).pop();
    }
  }

  /// From the "no longer available" state: straight to the Experiences tab
  /// when Home is underneath, otherwise the normal launch path.
  void _explore() {
    if (widget.standalone || !Navigator.of(context).canPop()) {
      _leave();
      return;
    }
    Navigator.of(context).pop();
    HomePage.homeKey.currentState?.switchToDiscover(
      initialTab: DiscoverPage.tabs.indexOf('Experiences'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget page;
    if (_loading) {
      page = const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppColors.brandGreen)),
      );
    } else if (_package != null) {
      page = ExperiencePackageDetailPage(package: _package!);
    } else {
      page = _buildUnavailable();
    }

    if (!widget.standalone) return page;

    // Standalone, this is the only page on the stack, so a plain Back would
    // close the app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: page,
    );
  }

  Widget _buildUnavailable() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _leave,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandGreenLight,
                ),
                child: const Icon(Icons.explore_off_rounded,
                    size: 32, color: AppColors.brandGreen),
              ),
              const SizedBox(height: 16),
              const Text(
                'This experience is no longer available',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'It may have been removed by the operator. There are plenty more to discover.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _explore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Explore experiences',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
