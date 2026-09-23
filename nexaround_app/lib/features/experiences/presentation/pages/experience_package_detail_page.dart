import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/contact_launcher.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/core/widgets/full_screen_image_viewer.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_enquiry_sheet.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_share_sheet.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/vendor_social_bar.dart';

/// Detail for one package.
///
/// Opens with the card's data so there is no blank screen, then replaces it
/// with the full record (description, gallery, inclusions, vendor contact)
/// once the detail request returns.
class ExperiencePackageDetailPage extends StatefulWidget {
  final ExperiencePackageEntity package;
  final double? userLatitude;
  final double? userLongitude;

  const ExperiencePackageDetailPage({
    super.key,
    required this.package,
    this.userLatitude,
    this.userLongitude,
  });

  @override
  State<ExperiencePackageDetailPage> createState() =>
      _ExperiencePackageDetailPageState();
}

class _ExperiencePackageDetailPageState
    extends State<ExperiencePackageDetailPage> {
  late ExperiencePackageEntity _package;
  final PageController _photoController = PageController();
  int _photoIndex = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _package = widget.package;
    _loadDetail();
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    final full = await ExperiencesService.fetchPackage(
      widget.package.id,
      latitude: widget.userLatitude,
      longitude: widget.userLongitude,
    );
    if (!mounted) return;
    setState(() {
      if (full != null) _package = full;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = _package.galleryUrls;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildGalleryAppBar(photos),
          SliverToBoxAdapter(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildActionBar(),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black38,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          icon: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildGalleryAppBar(List<String> photos) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      // White circles rather than bare icons: over the photo a plain dark
      // icon sits on the dark top gradient and all but disappears.
      leading: _headerButton(
        icon: isIOS ? Icons.arrow_back_ios_new_rounded : Icons.arrow_back_rounded,
        tooltip: 'Back',
        onPressed: () => Navigator.maybePop(context),
      ),
      // Share lives up here, not in the bottom bar: a fourth fixed-width
      // button there squeezes "Request booking" on small phones.
      actions: [
        _headerButton(
          icon: isIOS ? Icons.ios_share : Icons.share_rounded,
          tooltip: 'Share',
          onPressed: () => showExperienceShareSheet(context, _package),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: photos.isEmpty
            ? Container(
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.kayaking_rounded,
                    size: 64, color: AppColors.textMuted),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _photoController,
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _photoIndex = i),
                    itemBuilder: (_, index) {
                      final url = PlaceImageHelper.resolveUrl(photos[index]);
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullScreenImageViewer(
                              imageUrls: photos,
                              initialIndex: index,
                            ),
                          ),
                        ),
                        child: url == null
                            ? Container(color: AppColors.surfaceVariant)
                            : CachedNetworkImage(
                                imageUrl: url,
                                httpHeaders:
                                    PlaceImageHelper.headersFor(url),
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    Container(color: AppColors.surfaceVariant),
                                errorWidget: (_, __, ___) =>
                                    Container(color: AppColors.surfaceVariant),
                              ),
                      );
                    },
                  ),
                  // Gradient so the back button stays legible on a light photo.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 120,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.35),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          photos.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _photoIndex ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _photoIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildBody() {
    final vendor = _package.vendor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _package.title,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            _package.vendorName,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_package.priceLabel.isNotEmpty)
                _chip(Icons.sell_rounded, _package.priceLabel, highlight: true),
              if (_package.durationLabel.isNotEmpty)
                _chip(Icons.schedule_rounded, _package.durationLabel),
              if (_package.distanceM != null)
                _chip(Icons.near_me_rounded,
                    formatDistance(_package.distanceM)),
              if (_package.maxParticipants != null)
                _chip(Icons.group_rounded,
                    'Up to ${_package.maxParticipants}'),
            ],
          ),

          if ((_package.summary ?? '').isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              _package.summary!,
              style: const TextStyle(
                  fontSize: 15, height: 1.5, color: AppColors.textSecondary),
            ),
          ],

          if ((_package.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _package.description!,
              style: const TextStyle(
                  fontSize: 15, height: 1.6, color: AppColors.textPrimary),
            ),
          ],

          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],

          if (_package.inclusions.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle("What's included"),
            const SizedBox(height: 10),
            ..._package.inclusions.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: AppColors.brandGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_package.languages.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('Languages'),
            const SizedBox(height: 8),
            Text(
              _package.languages.join(', '),
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],

          if ((_package.meetingPointAddress ?? '').isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('Meeting point'),
            const SizedBox(height: 8),
            Text(
              _package.meetingPointAddress!,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],

          if (vendor != null) ...[
            const SizedBox(height: 24),
            _sectionTitle('About ${vendor.name}'),
            const SizedBox(height: 8),
            if ((vendor.description ?? '').isNotEmpty)
              Text(
                vendor.description!,
                style: const TextStyle(
                    fontSize: 14, height: 1.5, color: AppColors.textSecondary),
              ),
            if ((vendor.address ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_rounded,
                      size: 15, color: AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      vendor.address!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ],
            if (vendor.hasWebsite) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => ContactLauncher.website(vendor.website),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 15, color: AppColors.brandGreen),
                    const SizedBox(width: 6),
                    Text(
                      'Visit website',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.brandGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (vendor.hasSocials) ...[
              const SizedBox(height: 16),
              const Text(
                'Connect with vendor',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              VendorSocialBar(
                whatsapp: vendor.contactWhatsapp,
                instagram: vendor.contactInstagram,
                facebook: vendor.contactFacebook,
                x: vendor.contactX,
                packageTitle: _package.title,
                isCompact: false,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      );

  Widget _chip(IconData icon, String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.brandGreenLight
            : AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: highlight ? AppColors.brandGreen : AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color:
                  highlight ? AppColors.brandGreen : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final vendor = _package.vendor;

    // Only the direct channels sit beside the booking button. Instagram,
    // Facebook and X are already in "Connect with vendor" above; with all five
    // here the fixed-width icons squeezed "Request booking" down to "R".
    final actionButtons = <Widget>[];

    if (vendor != null && vendor.hasPhone) {
      actionButtons.add(_iconAction(
        Icons.call_rounded,
        () => ContactLauncher.call(vendor.contactPhone),
        tooltip: 'Call',
      ));
    }

    if (vendor != null && vendor.hasWhatsapp) {
      actionButtons.add(_imageIconAction(
        'assets/images/social_whatsapp.png',
        () => ContactLauncher.whatsApp(
          vendor.contactWhatsapp,
          message: 'Hi, I am interested in "${_package.title}" '
              'I found on NexAround.',
        ),
        tooltip: 'WhatsApp',
      ));
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () =>
                    showExperienceEnquirySheet(context, _package),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'Request booking',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          for (final button in actionButtons) ...[
            const SizedBox(width: 8),
            button,
          ],
        ],
      ),
    );
  }

  Widget _iconAction(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Tooltip(
        message: tooltip ?? '',
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: const BorderSide(color: AppColors.border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _imageIconAction(String assetPath, VoidCallback onTap,
      {String? tooltip}) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Tooltip(
        message: tooltip ?? '',
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(12),
            side: const BorderSide(color: AppColors.border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Image.asset(assetPath, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
