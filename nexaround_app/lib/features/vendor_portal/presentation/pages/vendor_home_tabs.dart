import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import 'package_editor_page.dart';
import 'vendor_requests_tab.dart';

/// A dark band with whether the listing is live, how many requests need an
/// answer and three numbers that each open their tab; then what the vendor
/// has to do, and the packages to swipe through, ending in New package.
class VendorDashboardTab extends StatefulWidget {
  final VendorPortalApi api;
  final ValueNotifier<int> changed;
  final ValueNotifier<int> reviewsChanged;

  /// Bumped when a request comes in or is answered anywhere.
  final ValueNotifier<int> requestsChanged;

  /// Switches the portal to a tab: 1 Requests, 2 Packages, 3 Reviews, 4 Profile.
  final ValueChanged<int> onOpenTab;

  /// After a request is answered from Home.
  final VoidCallback onAnswered;

  const VendorDashboardTab({
    super.key,
    required this.api,
    required this.changed,
    required this.reviewsChanged,
    required this.requestsChanged,
    required this.onOpenTab,
    required this.onAnswered,
  });

  @override
  State<VendorDashboardTab> createState() => _VendorDashboardTabState();
}

class _VendorDashboardTabState extends State<VendorDashboardTab> {
  static const _sectionTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2);

  // What the device kept, until the server answers.
  late VendorStats? _stats = widget.api.cachedStats();
  late List<VendorPackage>? _packages = widget.api.cachedPackages();
  late VendorReviewPage? _reviews = widget.api.cachedReviews();
  late VendorRequestPage? _requests = widget.api.cachedRequests();
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.changed.addListener(_load);
    widget.reviewsChanged.addListener(_loadReviews);
    widget.requestsChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.changed.removeListener(_load);
    widget.reviewsChanged.removeListener(_loadReviews);
    widget.requestsChanged.removeListener(_load);
    super.dispose();
  }

  /// The open requests; a failure keeps what showed.
  Future<void> _loadRequests() async {
    try {
      final page = await widget.api.requests();
      if (mounted) setState(() => _requests = page);
    } catch (_) {}
  }

  Future<void> _load() async {
    _loadReviews();
    _loadRequests();
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

  /// One request, with Confirm and "Can't do this date", over Home.
  Future<void> _openRequest(VendorRequest request) =>
      showRequestSheet(context, request, widget.api, onAnswered: widget.onAnswered);

  List<VendorRequest> get _waiting =>
      (_requests?.requests ?? const <VendorRequest>[]).where((r) => r.waiting).toList();

  /// Requests not answered yet: the server's count, or the ones loaded if
  /// that is more.
  int get _waitingCount {
    final counted = _requests?.waiting ?? _stats?.requestsWaiting ?? 0;
    final loaded = _waiting.length;
    return counted > loaded ? counted : loaded;
  }

  String get _headline {
    if (_requests == null && _stats == null) return 'Welcome back';
    final count = _waitingCount;
    if (count == 0) return 'All caught up';
    return count == 1 ? '1 request needs you' : '$count requests need you';
  }

  /// The soonest date waiting: "Next one: Sat 7 Nov 2026, 3 guests".
  String _nextRequestLine(List<VendorRequest> waiting) {
    if (waiting.isEmpty) return 'Waiting for your answer';
    final dated = waiting.where((r) => !r.flexible).toList()
      ..sort((a, b) => a.preferredDate!.compareTo(b.preferredDate!));
    final next = dated.isEmpty ? waiting.first : dated.first;
    final when = next.flexible ? 'Flexible date' : requestDay(next.preferredDate!);
    final guests = next.partySize;
    return guests == null ? 'Next one: $when' : 'Next one: $when, $guests ${guests == 1 ? 'guest' : 'guests'}';
  }

  /// The package of the first review with no reply yet.
  String _replyLine() {
    for (final review in _reviews?.reviews ?? const <VendorReview>[]) {
      if (review.vendorReply == null && review.packageTitle != null) return review.packageTitle!;
    }
    return 'A traveller is waiting for your reply';
  }

  /// What the vendor has to do, each line opening the place to do it; a
  /// single request or package opens straight away.
  List<Widget> _toDo() {
    final waiting = _waiting;
    final requests = _waitingCount;
    final replies = _reviews?.unanswered ?? 0;
    final toFix = (_packages ?? const <VendorPackage>[]).where((p) => p.review.changesRequested).toList();
    final rows = <Widget>[
      if (requests > 0)
        _TodoRow(
          icon: Icons.inbox_rounded,
          color: AppColors.error,
          title: 'Answer $requests request${requests == 1 ? '' : 's'}',
          line: _nextRequestLine(waiting),
          onTap: () {
            if (requests == 1 && waiting.length == 1) {
              _openRequest(waiting.first);
            } else {
              widget.onOpenTab(1);
            }
          },
        ),
      if (replies > 0)
        _TodoRow(
          icon: Icons.rate_review_rounded,
          color: const Color(0xFFB7791F),
          title: 'Reply to $replies review${replies == 1 ? '' : 's'}',
          line: _replyLine(),
          onTap: () => widget.onOpenTab(3),
        ),
      if (toFix.isNotEmpty)
        _TodoRow(
          icon: Icons.edit_note_rounded,
          color: AppColors.brandGreen,
          title: 'Fix ${toFix.length} package${toFix.length == 1 ? '' : 's'}',
          line: 'NexAround asked for a change',
          onTap: () {
            if (toFix.length == 1) {
              _edit(toFix.first);
            } else {
              widget.onOpenTab(2);
            }
          },
        ),
    ];
    if (rows.isEmpty) return const [];
    return [
      _gutter(const Text('To do', style: _sectionTitle)),
      const SizedBox(height: 8),
      _gutter(
        VendorCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 62),
                rows[i],
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 4),
    ];
  }

  Widget _gutter(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: vendorGutter),
        child: child,
      );

  /// The packages, side by side, then a card to add one.
  Widget _packageCards(List<VendorPackage> packages) {
    return SizedBox(
      height: 158,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The cards' shadows reach past the row.
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: vendorGutter),
        itemCount: packages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => i < packages.length
            ? _PackageCard(pkg: packages[i], onTap: () => _edit(packages[i]))
            : _NewPackageCard(onTap: () => _edit()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.api.me?.vendorIsActive ?? true;
    final stats = _stats;
    final reviews = _reviews;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        // No bounce: it would pull the dark band away from the header.
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _HomeHero(
            live: live,
            headline: _headline,
            stats: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.brandGreen,
                    value: stats == null ? '–' : '${stats.packagesPublished}/${stats.packagesTotal}',
                    label: 'Packages live',
                    onTap: () => widget.onOpenTab(2),
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
                    onTap: () => widget.onOpenTab(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    icon: Icons.mark_chat_unread_rounded,
                    color: (reviews?.unanswered ?? 0) > 0 ? AppColors.error : AppColors.textTertiary,
                    value: '${reviews?.unanswered ?? '–'}',
                    label: 'To reply',
                    onTap: () => widget.onOpenTab(3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_error != null && _packages != null) _gutter(const VendorSavedNote()),
          ..._toDo(),
          _gutter(
            Row(
              children: [
                const Expanded(child: Text('Your packages', style: _sectionTitle)),
                if ((_packages?.length ?? 0) > 0)
                  TextButton(
                    onPressed: () => widget.onOpenTab(2),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: const Text('Manage'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null && _packages == null)
            _gutter(
              VendorEmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Couldn’t load your packages',
                message: userMessageFor(_error),
                action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
              ),
            )
          else if (_packages == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_packages!.isEmpty)
            _gutter(
              VendorEmptyState(
                icon: Icons.confirmation_number_outlined,
                title: 'List your first package',
                message: 'Each package appears in the app as its own experience travellers can request.',
                action: VendorPrimaryButton(
                  label: 'New package',
                  icon: Icons.add_rounded,
                  compact: true,
                  onPressed: () => _edit(),
                ),
              ),
            )
          else
            _packageCards(_packages!),
        ],
      ),
    );
  }
}

/// The dark top of Home, carrying on from the shell's header: whether the
/// listing is live, the headline, and the three numbers half over its edge.
class _HomeHero extends StatelessWidget {
  final bool live;
  final String headline;
  final Widget stats;

  const _HomeHero({required this.live, required this.headline, required this.stats});

  @override
  Widget build(BuildContext context) {
    final statusColor = live ? const Color(0xFFA7F3D0) : const Color(0xFFFCA5A5);
    return Stack(
      children: [
        const Positioned.fill(
          bottom: 44,
          child: DecoratedBox(decoration: BoxDecoration(gradient: vendorHeaderGradient)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(vendorGutter, 8, vendorGutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 8, color: statusColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      live ? 'Your listing is live' : 'Your listing is hidden. Contact NexAround.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Colors.white),
              ),
              const SizedBox(height: 14),
              stats,
            ],
          ),
        ),
      ],
    );
  }
}

/// One number on Home. Solid white, not a GlassCard: that one is see-through
/// enough to show the dark band behind its top half.
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
    return DecoratedBox(
      decoration: const BoxDecoration(borderRadius: AppRadii.brMd, boxShadow: AppShadows.sm),
      child: Material(
        color: Colors.white,
        borderRadius: AppRadii.brMd,
        child: InkWell(
          borderRadius: AppRadii.brMd,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800, height: 1.15, color: AppColors.textPrimary)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing the vendor has to do.
class _TodoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String line;
  final VoidCallback onTap;

  const _TodoRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.line,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadii.brSm),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// A package on Home: photo, title and main price. A tap opens it to edit.
class _PackageCard extends StatelessWidget {
  static const _width = 168.0;

  final VendorPackage pkg;
  final VoidCallback onTap;

  const _PackageCard({required this.pkg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderRadius: AppRadii.brMd,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The photo takes what the text leaves, at any text size.
            Expanded(
              child: PackageThumb(
                pkg.photoUrls,
                previews: pkg.imagePreviews,
                size: _width,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pkg.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(packagePriceLine(pkg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last card in the row: adds a package.
class _NewPackageCard extends StatelessWidget {
  final VoidCallback onTap;

  const _NewPackageCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderRadius: AppRadii.brMd,
      child: const SizedBox(
        width: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_rounded, size: 30, color: AppColors.brandGreen),
            SizedBox(height: 6),
            Text('New package',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandGreen)),
          ],
        ),
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
              PackageThumb(pkg.photoUrls, previews: pkg.imagePreviews),
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
