import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
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
      // Offline: the businesses last seen still open, from what was kept.
      final kept = VendorPortalApi.cachedAccess();
      if (kept.isNotEmpty && statusCodeOf(e) == null) {
        list = kept;
      } else {
        if (context.mounted) {
          showVendorSnack(context, userMessageFor(e, action: 'open the vendor portal'), error: true);
        }
        return;
      }
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(vendorGutter, 0, vendorGutter, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Which business?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 12),
                  for (final a in list!)
                    VendorCard(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      onTap: () => Navigator.pop(ctx, a),
                      child: Row(
                        children: [
                          VendorAvatar(name: a.vendorName),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(a.vendorName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                ],
              ),
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

/// The business's initials on the brand gradient.
class VendorAvatar extends StatelessWidget {
  final String name;
  final double size;

  const VendorAvatar({super.key, required this.name, this.size = 40});

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final letters = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return letters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w700),
      ),
    );
  }
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
  // "I am authorised to accept for <business>", as on the web portal.
  bool _authorised = false;

  @override
  void initState() {
    super.initState();
    // Opened before and accepted then: the tabs show what was kept while
    // the session is traded. The fresh answer still decides.
    final kept = _api.cachedAgreement();
    if (kept != null && !kept.mustAccept) _agreement = kept;
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
      final status = statusCodeOf(e);
      if (status == 404) CacheService.removeCachedVendor(widget.access.vendorId);
      // Offline while the kept tabs show: each tab says it is offline.
      if (_agreement != null && status != 404 && status != 403) return;
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
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: vendorAppBar(context, widget.access.vendorName),
        body: const Center(child: CircularProgressIndicator()),
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
      appBar: vendorAppBar(context, widget.access.vendorName),
      body: Center(
        child: VendorEmptyState(
          icon: Icons.storefront_outlined,
          title: 'Can’t open the vendor portal',
          message: message,
          action: status == 404 || status == 403
              ? null
              : OutlinedButton(onPressed: _open, child: const Text('Try again')),
        ),
      ),
    );
  }

  String? _serverDetail(Object? e) {
    if (e is! DioException) return null;
    final data = e.response?.data;
    return data is Map && data['detail'] is String ? data['detail'] as String : null;
  }

  Widget _agreementGate(PartnerAgreement agreement) {
    final vendorName = _api.me?.vendorName ?? widget.access.vendorName;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: vendorAppBar(context, agreement.title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brandGreenLight,
              borderRadius: AppRadii.brMd,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.handshake_outlined, size: 20, color: AppColors.brandGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    agreement.acceptedVersion == null
                        ? 'Before you manage $vendorName here, please read and accept the Provider Agreement.'
                        : 'The Provider Agreement has changed. Please read and accept the new version.',
                    style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          LegalBody(body: agreement.body),
        ],
      ),
      bottomNavigationBar: VendorActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: AppRadii.brSm,
              onTap: () => setState(() => _authorised = !_authorised),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _authorised,
                        onChanged: (v) => setState(() => _authorised = v ?? false),
                        activeColor: AppColors.brandGreen,
                        checkColor: Colors.white,
                        side: const BorderSide(color: AppColors.textSecondary, width: 1.6),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'I have read and accept the ${agreement.title} on behalf of '),
                            TextSpan(
                              text: vendorName,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const TextSpan(text: ', and I confirm that I am authorised to do so.'),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            VendorPrimaryButton(
              label: _accepting ? 'Saving…' : 'I accept the Provider Agreement',
              onPressed: _accepting || !_authorised ? null : _accept,
            ),
          ],
        ),
      ),
    );
  }
}

/// The business name, the bell, the tabs and the app's floating tab bar.
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
  static const _tabs = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home'),
    (Icons.confirmation_number_outlined, Icons.confirmation_number_rounded, 'Packages'),
    (Icons.star_outline_rounded, Icons.star_rounded, 'Reviews'),
    (Icons.storefront_outlined, Icons.storefront_rounded, 'Profile'),
  ];

  int _tab = 0;
  late int _unread = widget.api.cachedUnread() ?? 0;
  late String _vendorName = widget.vendorName;
  // Profile edits not saved yet: leaving the portal asks first.
  bool _profileDirty = false;

  // Bumped to make the Home and Packages tabs reload after an edit.
  final ValueNotifier<int> _packagesChanged = ValueNotifier(0);
  // Bumped when a reply is posted, so Home's "To reply" count follows.
  final ValueNotifier<int> _reviewsChanged = ValueNotifier(0);

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
    _reviewsChanged.dispose();
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

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard your changes?'),
        content: const Text('Your profile has changes that are not saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _profileDirty = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      VendorDashboardTab(
        api: widget.api,
        changed: _packagesChanged,
        reviewsChanged: _reviewsChanged,
        onOpenTab: _goTo,
      ),
      VendorPackagesTab(api: widget.api, changed: _packagesChanged),
      VendorReviewsTab(api: widget.api, onReplied: () => _reviewsChanged.value++),
      VendorProfileTab(
        api: widget.api,
        onRenamed: (name) => setState(() => _vendorName = name),
        onDirtyChanged: (dirty) => setState(() => _profileDirty = dirty),
      ),
    ];
    return PopScope(
      canPop: !_profileDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _header(),
            Expanded(child: IndexedStack(index: _tab, children: tabs)),
          ],
        ),
        bottomNavigationBar: _tabBar(),
      ),
    );
  }

  Widget _header() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(vendorGutter, 8, vendorGutter, 10),
        child: Row(
          children: [
            if (Navigator.of(context).canPop()) ...[
              VendorCircleButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 12),
            ],
            VendorAvatar(name: _vendorName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Not AppTypography.eyebrow: it names a font family the app
                  // never registers, so the label would drop the app font.
                  const Text('VENDOR PORTAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: AppColors.brandGreen,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    _vendorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            VendorCircleButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              onPressed: _openNotifications,
              badge: _unread > 0
                  ? Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        _unread > 99 ? '99+' : '$_unread',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1.1),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// The app's floating tab bar (Home screen), with every label showing.
  Widget _tabBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 12),
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.glassBorder, width: 0.6),
          boxShadow: AppShadows.lg,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) Expanded(child: _tabItem(i)),
          ],
        ),
      ),
    );
  }

  Widget _tabItem(int index) {
    final (icon, activeIcon, label) = _tabs[index];
    final active = _tab == index;
    final color = active ? Colors.white : AppColors.textTertiary;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _goTo(index),
        child: AnimatedContainer(
          duration: AppDurations.normal,
          curve: AppCurves.standard,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: active ? AppColors.primaryGradient : null,
            boxShadow: active ? AppShadows.glow(AppColors.primary) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? activeIcon : icon, size: 21, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.1,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
