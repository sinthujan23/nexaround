import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/connectivity_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. NetworkErrorView — full empty-state for when a data fetch fails
// ─────────────────────────────────────────────────────────────────────────────

/// A beautiful, industry-standard empty state shown when a screen cannot
/// load data because of a network error. Includes a clear message and a
/// prominent retry button.
///
/// Usage:
/// ```dart
/// if (hasError && items.isEmpty) NetworkErrorView(onRetry: _refetch);
/// ```
class NetworkErrorView extends StatelessWidget {
  /// Called when the user taps "Try Again".
  final VoidCallback? onRetry;

  /// Override the default message ("No Internet Connection").
  final String? message;

  /// Override the subtitle.
  final String? subtitle;

  /// Custom icon (defaults to wifi-off).
  final IconData? icon;

  /// If true, show a compact variant (no big icon, smaller text).
  final bool compact;

  const NetworkErrorView({
    super.key,
    this.onRetry,
    this.message,
    this.subtitle,
    this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOffline = !ConnectivityService.instance.isOnline.value;
    final displayMessage = message ??
        (isOffline ? 'No Internet Connection' : 'Something went wrong');
    final displaySubtitle = subtitle ??
        (isOffline
            ? 'Check your Wi-Fi or mobile data\nand try again.'
            : 'Please check your connection\nand try again.');

    if (compact) {
      return _buildCompact(displayMessage, displaySubtitle);
    }
    return _buildFull(displayMessage, displaySubtitle, isOffline);
  }

  Widget _buildFull(String msg, String sub, bool isOffline) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: (isOffline ? AppColors.warning : AppColors.error)
                    .withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? (isOffline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded),
                size: 40,
                color: isOffline ? AppColors.warning : AppColors.error,
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(1.0, 1.0),
                  end: const Offset(1.06, 1.06),
                  duration: 1200.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 24),

            // Title
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),

            // Retry button
            if (onRetry != null)
              SizedBox(
                width: 180,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildCompact(String msg, String sub) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.wifi_off_rounded, color: AppColors.warning, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: AppColors.primary,
              splashRadius: 20,
              tooltip: 'Retry',
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. OfflineBanner — slim top banner shown globally when offline
// ─────────────────────────────────────────────────────────────────────────────

/// A slim, animated banner that slides in from the top when the device goes
/// offline, and auto-dismisses with a brief "Back online" green flash when
/// connectivity is restored. Drop this into any `Stack` (typically in the
/// app shell / HomePage).
///
/// Listens to [ConnectivityService.instance.isOnline].
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _showBanner = false;
  bool _showBackOnline = false;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _showBanner = !ConnectivityService.instance.isOnline.value;
    _wasOffline = _showBanner;
    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    final online = ConnectivityService.instance.isOnline.value;
    if (!online) {
      // Went offline
      if (mounted) {
        setState(() {
          _showBanner = true;
          _showBackOnline = false;
          _wasOffline = true;
        });
      }
    } else if (_wasOffline) {
      // Came back online — flash "Back online" for 2s then dismiss
      if (mounted) {
        setState(() {
          _showBackOnline = true;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _showBanner = false;
              _showBackOnline = false;
              _wasOffline = false;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBanner) return const SizedBox.shrink();

    final isBackOnline = _showBackOnline;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        bottom: 10,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: isBackOnline
            ? AppColors.success.withValues(alpha: 0.95)
            : const Color(0xFF1A1A1A),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isBackOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            isBackOnline ? 'Back online' : 'No internet connection',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
