import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import 'package_editor_page.dart';

/// Welcome, how many packages are live, and the first few packages.
class VendorDashboardTab extends StatefulWidget {
  final VendorPortalApi api;
  final String vendorName;
  final ValueNotifier<int> changed;
  final VoidCallback onOpenPackages;
  final VoidCallback onOpenProfile;

  const VendorDashboardTab({
    super.key,
    required this.api,
    required this.vendorName,
    required this.changed,
    required this.onOpenPackages,
    required this.onOpenProfile,
  });

  @override
  State<VendorDashboardTab> createState() => _VendorDashboardTabState();
}

class _VendorDashboardTabState extends State<VendorDashboardTab> {
  static const _preview = 5;
  VendorStats? _stats;
  List<VendorPackage>? _packages;
  Object? _error;

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

  Future<void> _edit({String? id}) async {
    final saved = await openPackageEditor(context, widget.api, packageId: id);
    if (saved == true) widget.changed.value++;
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.api.me?.vendorIsActive ?? true;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Welcome back, ${widget.vendorName}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: live ? AppColors.success : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  live ? 'Your listing is live on NexAround' : 'Your listing is hidden. Contact NexAround.',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brandGreen, AppColors.brandGreenDark],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: InkWell(
              onTap: widget.onOpenPackages,
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Packages live',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text('${_stats?.packagesPublished ?? '–'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        Text('${_stats?.packagesTotal ?? 0} in total',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onOpenProfile,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Profile'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New package'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Your packages',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: widget.onOpenPackages, child: const Text('Manage')),
            ],
          ),
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
            VendorEmptyState(
              icon: Icons.confirmation_number_outlined,
              title: 'List your first package',
              message: 'Each package appears in the app as its own experience travellers can request.',
              action: FilledButton(
                onPressed: () => _edit(),
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandGreen),
                child: const Text('Add package'),
              ),
            )
          else
            for (final pkg in _packages!.take(_preview))
              PackageRow(pkg: pkg, onTap: () => _edit(id: pkg.id)),
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
  List<VendorPackage>? _packages;
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
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit({String? id}) async {
    final saved = await openPackageEditor(context, widget.api, packageId: id);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: AppColors.brandGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New package'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(),
      ),
    );
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
    if (packages.isEmpty) {
      return ListView(children: const [
        VendorEmptyState(
          icon: Icons.confirmation_number_outlined,
          title: 'List your first package',
          message: 'Each package appears in the app as its own experience travellers can request.',
        ),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        for (final pkg in packages)
          PackageRow(
            pkg: pkg,
            onTap: () => _edit(id: pkg.id),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  value: pkg.isActive,
                  activeThumbColor: AppColors.brandGreen,
                  onChanged: _toggling.contains(pkg.id) ? null : (v) => _toggle(pkg, v),
                ),
                const Text('Show in app', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
              ],
            ),
          ),
      ],
    );
  }
}

class PackageRow extends StatelessWidget {
  final VendorPackage pkg;
  final VoidCallback onTap;
  final Widget? trailing;

  const PackageRow({super.key, required this.pkg, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
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
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '${formatPrice(pkg.priceAmount, pkg.priceCurrency)}'
                      '${pkg.priceOptions.length > 1 ? ' +${pkg.priceOptions.length - 1} more' : ''}'
                      ' · ${categoryLabel(pkg.category)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    VisibilityPill(pkg.visibility),
                  ],
                ),
              ),
              if (trailing != null) trailing! else const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
