import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/legal_body.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import 'vendor_home_tabs.dart';
import 'vendor_notifications_page.dart';
import 'vendor_profile_tab.dart';
import 'vendor_reviews_tab.dart';

/// Opens the vendor screens for one of the businesses the traveller was
/// given; with several, asks which first. [toNotifications] lands on the
/// notifications (a push about a request was tapped).
Future<void> openVendorPortal(
  BuildContext context, {
  List<VendorAccess>? access,
  String? vendorId,
  bool toNotifications = false,
}) async {
  var list = access;
  if (list == null) {
    try {
      list = await VendorPortalApi.access();
    } catch (e) {
      if (context.mounted) {
        showVendorSnack(context, userMessageFor(e, action: 'open the vendor portal'), error: true);
      }
      return;
    }
  }
  if (!context.mounted || list.isEmpty) return;
  VendorAccess? chosen;
  if (vendorId != null) {
    for (final a in list) {
      if (a.vendorId == vendorId) chosen = a;
    }
  }
  chosen ??= list.length == 1
      ? list.first
      : await showModalBottomSheet<VendorAccess>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Which business?',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                for (final a in list!)
                  ListTile(
                    leading: const Icon(Icons.storefront_rounded, color: AppColors.brandGreen),
                    title: Text(a.vendorName),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(ctx, a),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
  if (chosen == null || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => VendorPortalPage(access: chosen!, toNotifications: toNotifications),
    ),
  );
}

/// The partner portal in the app: sign in with the vendor's own session,
/// the Provider Agreement until it is accepted, then the tabs.
class VendorPortalPage extends StatefulWidget {
  final VendorAccess access;
  final bool toNotifications;

  /// For tests: an API whose answers they control.
  final VendorPortalApi? api;

  const VendorPortalPage({super.key, required this.access, this.toNotifications = false, this.api});

  @override
  State<VendorPortalPage> createState() => _VendorPortalPageState();
}

class _VendorPortalPageState extends State<VendorPortalPage> {
  late final VendorPortalApi _api = widget.api ?? VendorPortalApi(widget.access.vendorId);
  PartnerAgreement? _agreement;
  Object? _error;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _api.signOut();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      await _api.signIn();
      final agreement = await _api.agreement();
      if (mounted) setState(() => _agreement = agreement);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      final agreement = await _api.acceptAgreement(_agreement!.version);
      if (mounted) setState(() => _agreement = agreement);
    } catch (e) {
      if (!mounted) return;
      showVendorSnack(context, userMessageFor(e, action: 'accept the agreement'), error: true);
      // Published while they read: show the new text.
      if (statusCodeOf(e) == 409) _open();
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _failed();
    final agreement = _agreement;
    if (agreement == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (agreement.mustAccept) return _agreementGate(agreement);
    return VendorShell(
      api: _api,
      vendorName: _api.me?.vendorName ?? widget.access.vendorName,
      toNotifications: widget.toNotifications,
    );
  }

  Widget _failed() {
    final status = statusCodeOf(_error);
    final message = switch (status) {
      404 => 'You no longer have access to ${widget.access.vendorName}. Contact NexAround.',
      403 => _serverDetail(_error) ?? 'Your listing is currently suspended. Contact NexAround.',
      _ => userMessageFor(_error, action: 'open the vendor portal'),
    };
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(widget.access.vendorName)),
      body: VendorEmptyState(
        icon: Icons.storefront_outlined,
        title: 'Can’t open the vendor portal',
        message: message,
        action: status == 404 || status == 403
            ? null
            : OutlinedButton(onPressed: _open, child: const Text('Try again')),
      ),
    );
  }

  String? _serverDetail(Object? e) {
    if (e is! DioException) return null;
    final data = e.response?.data;
    return data is Map && data['detail'] is String ? data['detail'] as String : null;
  }

  Widget _agreementGate(PartnerAgreement agreement) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(agreement.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            agreement.acceptedVersion == null
                ? 'Before you manage ${widget.access.vendorName} here, please read and accept the Provider Agreement.'
                : 'The Provider Agreement has changed. Please read and accept the new version.',
            style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          LegalBody(body: agreement.body),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _accepting ? null : _accept,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandGreen,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(_accepting ? 'Saving…' : 'I accept the Provider Agreement'),
        ),
      ),
    );
  }
}

/// The tabs, the business name and the bell.
class VendorShell extends StatefulWidget {
  final VendorPortalApi api;
  final String vendorName;
  final bool toNotifications;

  const VendorShell({
    super.key,
    required this.api,
    required this.vendorName,
    this.toNotifications = false,
  });

  @override
  State<VendorShell> createState() => _VendorShellState();
}

class _VendorShellState extends State<VendorShell> {
  int _tab = 0;
  int _unread = 0;
  late String _vendorName = widget.vendorName;

  // Bumped to make the Home and Packages tabs reload after an edit.
  final ValueNotifier<int> _packagesChanged = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _refreshUnread();
    if (widget.toNotifications) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openNotifications());
    }
  }

  @override
  void dispose() {
    _packagesChanged.dispose();
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    try {
      final n = await widget.api.unread();
      if (mounted) setState(() => _unread = n);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorNotificationsPage(api: widget.api)),
    );
    _refreshUnread();
  }

  void _goTo(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      VendorDashboardTab(
        api: widget.api,
        vendorName: _vendorName,
        changed: _packagesChanged,
        onOpenPackages: () => _goTo(1),
        onOpenProfile: () => _goTo(3),
      ),
      VendorPackagesTab(api: widget.api, changed: _packagesChanged),
      VendorReviewsTab(api: widget.api),
      VendorProfileTab(
        api: widget.api,
        onRenamed: (name) => setState(() => _vendorName = name),
      ),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VENDOR PORTAL',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandGreen)),
            Text(_vendorName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text(_unread > 99 ? '99+' : '$_unread'),
              backgroundColor: AppColors.error,
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _goTo,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.brandGreen.withValues(alpha: 0.14),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.confirmation_number_outlined), selectedIcon: Icon(Icons.confirmation_number_rounded), label: 'Packages'),
          NavigationDestination(icon: Icon(Icons.star_outline_rounded), selectedIcon: Icon(Icons.star_rounded), label: 'Reviews'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}
