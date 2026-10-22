import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import 'package_editor_page.dart';

/// Whether the listing is live, three numbers that each open their tab, the
/// New package button and the first few packages.
class VendorDashboardTab extends StatefulWidget {
  final VendorPortalApi api;
  final ValueNotifier<int> changed;
  final ValueNotifier<int> reviewsChanged;

  /// Switches the portal to a tab: 1 Packages, 2 Reviews, 3 Profile.
  final ValueChanged<int> onOpenTab;

  const VendorDashboardTab({
    super.key,
    required this.api,
    required this.changed,
    required this.reviewsChanged,
    required this.onOpenTab,
  });

  @override
  State<VendorDashboardTab> createState() => _VendorDashboardTabState();
}

class _VendorDashboardTabState extends State<VendorDashboardTab> {
  static const _preview = 3;
  // What the device kept, until the server answers.
  late VendorStats? _stats = widget.api.cachedStats();
  late List<VendorPackage>? _packages = widget.api.cachedPackages();
  late VendorReviewPage? _reviews = widget.api.cachedReviews();
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.changed.addListener(_load);
    widget.reviewsChanged.addListener(_loadReviews);
    _load();
  }

  @override
  void dispose() {
    widget.changed.removeListener(_load);
    widget.reviewsChanged.removeListener(_loadReviews);
    super.dispose();
  }

  Future<void> _load() async {
    _loadReviews();
    try {
      final results = await Future.wait([widget.api.stats(), widget.api.packages()]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as VendorStats;
        _packages = results[1] as List<VendorPackage>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Only the totals are used; a failure leaves the tiles at "–".
  Future<void> _loadReviews() async {
    try {
      final page = await widget.api.reviews();
      if (mounted) setState(() => _reviews = page);
    } catch (_) {}
  }

  Future<void> _edit([VendorPackage? pkg]) async {
    final saved = await openPackageEditor(context, widget.api, packageId: pkg?.id, initial: pkg);
    if (saved == true) widget.changed.value++;
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.api.me?.vendorIsActive ?? true;
    final stats = _stats;
    final reviews = _reviews;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 24),
        children: [
          if (_error != null && _packages != null) const VendorSavedNote(),
          _ListingStatus(live: live),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.check_circle_rounded,
                  color: AppColors.brandGreen,
                  value: stats == null ? '–' : '${stats.packagesPublished}/${stats.packagesTotal}',
                  label: 'Packages live',
                  onTap: () => widget.onOpenTab(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.star_rounded,
                  color: AppColors.ratingGold,
                  value: reviews?.average?.toStringAsFixed(1) ?? '–',
                  label: reviews == null
                      ? 'Rating'
                      : '${reviews.reviewCount} review${reviews.reviewCount == 1 ? '' : 's'}',
                  onTap: () => widget.onOpenTab(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.mark_chat_unread_rounded,
                  color: (reviews?.unanswered ?? 0) > 0 ? AppColors.error : AppColors.textTertiary,
                  value: '${reviews?.unanswered ?? '–'}',
                  label: 'To reply',
                  onTap: () => widget.onOpenTab(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          VendorPrimaryButton(
            label: 'New package',
            icon: Icons.add_rounded,
            onPressed: () => _edit(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text('Your packages',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              ),
              if ((_packages?.length ?? 0) > 0)
                TextButton(
                  onPressed: () => widget.onOpenTab(1),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text((_packages!.length > _preview) ? 'See all ${_packages!.length}' : 'Manage'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null && _packages == null)
            VendorEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn’t load your packages',
              message: userMessageFor(_error),
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            )
          else if (_packages == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_packages!.isEmpty)
            const VendorEmptyState(
              icon: Icons.confirmation_number_outlined,
              title: 'List your first package',
              message: 'Each package appears in the app as its own experience travellers can request. '
                  'Tap New package to add one.',
            )
          else
            for (final pkg in _packages!.take(_preview))
              PackageRow(pkg: pkg, onTap: () => _edit(pkg)),
        ],
      ),
    );
  }
}

/// Green "live" or red "hidden" at the top of Home.
class _ListingStatus extends StatelessWidget {
  final bool live;

  const _ListingStatus({required this.live});

  @override
  Widget build(BuildContext context) {
    final color = live ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadii.brMd,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(live ? Icons.public_rounded : Icons.visibility_off_rounded, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live ? 'Your listing is live on NexAround' : 'Your listing is hidden',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 1),
                Text(
                  live
                      ? 'Travellers can find and request your live packages.'
                      : 'Travellers can’t see your packages. Contact NexAround.',
                  style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One number on Home, like the stats on the traveller's Profile.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback onTap;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      borderRadius: AppRadii.brMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Every package, with its "Show in app" switch.
class VendorPackagesTab extends StatefulWidget {
  final VendorPortalApi api;
  final ValueNotifier<int> changed;

  const VendorPackagesTab({super.key, required this.api, required this.changed});

  @override
  State<VendorPackagesTab> createState() => _VendorPackagesTabState();
}

class _VendorPackagesTabState extends State<VendorPackagesTab> {
  // What the device kept, until the server answers.
  late List<VendorPackage>? _packages = widget.api.cachedPackages();
  // The switch saves the whole package, so it waits for this load's list:
  // a kept one may be older than what is on the server.
  bool _fresh = false;
  Object? _error;
  final Set<String> _toggling = {};

  @override
  void initState() {
    super.initState();
    widget.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.packages();
      if (!mounted) return;
      setState(() {
        _packages = list;
        _fresh = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([VendorPackage? pkg]) async {
    final saved = await openPackageEditor(context, widget.api, packageId: pkg?.id, initial: pkg);
    if (saved == true) widget.changed.value++;
  }

  /// Saves the package as it is with only the switch changed: updates are
  /// full replacements, as on the web.
  Future<void> _toggle(VendorPackage pkg, bool show) async {
    setState(() => _toggling.add(pkg.id!));
    try {
      await widget.api.savePackage(pkg.copyWith(isActive: show));
      widget.changed.value++;
    } catch (e) {
      if (mounted) showVendorSnack(context, userMessageFor(e, action: 'change the package'), error: true);
    } finally {
      if (mounted) setState(() => _toggling.remove(pkg.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: _load, child: _body());
  }

  Widget _body() {
    if (_error != null && _packages == null) {
      return ListView(children: [
        VendorEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load your packages',
          message: userMessageFor(_error),
          action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ),
      ]);
    }
    final packages = _packages;
    if (packages == null) return const Center(child: CircularProgressIndicator());
    final live = packages.where((p) => p.isActive).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 24),
      children: [
        if (_error != null) const VendorSavedNote(),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Packages',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text(
                    packages.isEmpty
                        ? 'Nothing listed yet'
                        : '${packages.length} in total · $live shown in the app',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            VendorPrimaryButton(
              label: 'New package',
              icon: Icons.add_rounded,
              compact: true,
              onPressed: () => _edit(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (packages.isEmpty)
          const VendorEmptyState(
            icon: Icons.confirmation_number_outlined,
            title: 'List your first package',
            message: 'Each package appears in the app as its own experience travellers can request.',
          )
        else
          for (final pkg in packages)
            PackageRow(
              pkg: pkg,
              onTap: () => _edit(pkg),
              footer: VendorSwitchRow(
                title: 'Show in app',
                value: pkg.isActive,
                onChanged: !_fresh || _toggling.contains(pkg.id) ? null : (v) => _toggle(pkg, v),
              ),
            ),
      ],
    );
  }
}

/// A package card: photo, title, price, category and where it stands.
class PackageRow extends StatelessWidget {
  final VendorPackage pkg;
  final VoidCallback onTap;

  /// Under a line at the foot of the card (the Packages tab's switch).
  final Widget? footer;

  const PackageRow({super.key, required this.pkg, required this.onTap, this.footer});

  @override
  Widget build(BuildContext context) {
    final more = pkg.priceOptions.length - 1;
    return VendorCard(
      padding: EdgeInsets.fromLTRB(12, 12, 12, footer == null ? 12 : 2),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PackageThumb(pkg.photoUrls),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(
                      '${packagePriceLine(pkg)}${more > 0 ? ' · +$more more' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brandGreen),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        VisibilityPill(pkg.visibility),
                        ReviewPill(pkg.review, approved: pkg.isApproved),
                        Text(categoryLabel(pkg.category),
                            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
              ),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            footer!,
          ],
        ],
      ),
    );
  }
}
