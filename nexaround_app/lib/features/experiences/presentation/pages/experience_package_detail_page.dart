import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/contact_launcher.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/core/widgets/full_screen_image_viewer.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_request_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_description.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_fitted_photo.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_reviews_section.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_stars.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_good_to_know.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_share_sheet.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_video_slide.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/vendor_social_bar.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';

/// Detail for one package.
///
/// Opens with the saved full record if there is one, else the card's data, so
/// there is no blank screen, then replaces it with the full record
/// (description, gallery, inclusions, vendor contact) once the detail request
/// returns. A failed request keeps whatever is on screen.
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
  final ScrollController _scroll = ScrollController();
  int _photoIndex = 0;

  /// The photos have scrolled away and the white bar is pinned on its own:
  /// it then shows the package title, so the reader keeps their bearings.
  bool _collapsed = false;
  bool _loading = true;
  bool _isNavigatingToMap = false;

  Future<void> _openDirectionsInSmartMap({
    required double targetLat,
    required double targetLng,
    required String destinationName,
    required String addressQuery,
  }) async {
    if (_isNavigatingToMap) return;
    _isNavigatingToMap = true;

    double finalLat = targetLat;
    double finalLng = targetLng;

    // If coordinates are missing (0,0), attempt to search/geocode using GooglePlacesService
    if (finalLat == 0.0 && finalLng == 0.0) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Locating $destinationName on Smart Map...'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }

      try {
        final query = addressQuery.isNotEmpty ? addressQuery : destinationName;
        final places = await GooglePlacesService.searchPlaces(
          query: query,
          latitude: widget.userLatitude ?? CacheService.getLastFetchLat(),
          longitude: widget.userLongitude ?? CacheService.getLastFetchLng(),
        );
        if (places.isNotEmpty) {
          finalLat = places.first.latitude;
          finalLng = places.first.longitude;
        }
      } catch (e) {
        debugPrint('Geocoding error for $addressQuery: $e');
      }
    }

    if (!mounted) {
      _isNavigatingToMap = false;
      return;
    }

    // Fallback to cached or user location if coordinates remain 0.0
    if (finalLat == 0.0 && finalLng == 0.0) {
      finalLat = widget.userLatitude ?? CacheService.getLastFetchLat() ?? 0.0;
      finalLng = widget.userLongitude ?? CacheService.getLastFetchLng() ?? 0.0;
    }

    if (finalLat == 0.0 && finalLng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('📍 Location coordinates could not be resolved'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _isNavigatingToMap = false;
      return;
    }

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SmartTourismMapPage(
            initialLat: finalLat,
            initialLng: finalLng,
            destinationName: destinationName,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isNavigatingToMap = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // A package opened before paints its full detail at once, keeping the
    // card's distance; the request below still runs and replaces it.
    final saved = ExperiencesService.cachedPackage(
      widget.package.id,
      distanceM: widget.package.distanceM,
    );
    _package = saved ?? widget.package;
    _loading = saved == null;
    _scroll.addListener(_onScroll);
    if (saved != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchPhotos());
    }
    _loadDetail();
  }

  /// Starts every gallery photo downloading now, into the same memory and disk
  /// cache the gallery reads, so swiping shows each photo at once instead of
  /// its loading preview, and the next visit needs no download at all.
  void _prefetchPhotos() {
    if (!mounted) return;
    for (final path in _package.galleryUrls.take(_prefetchLimit)) {
      final url = PlaceImageHelper.resolveUrl(path);
      if (url == null) continue;
      precacheImage(
        CachedNetworkImageProvider(
          url,
          headers: PlaceImageHelper.headersFor(url),
        ),
        context,
        // A photo that fails here just loads (or fails) again in the slider.
        onError: (_, __) {},
      );
    }
  }

  static const int _prefetchLimit = 12;

  @override
  void dispose() {
    _photoController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // A pinned SliverAppBar finishes collapsing after scrolling its expanded
    // height less the toolbar that stays; the title comes in just before.
    final collapseAt =
        _headerHeight(MediaQuery.of(context)) - kToolbarHeight - 24;
    final collapsed = _scroll.offset > collapseAt;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  // One 4:3 frame from the very top of the screen, the status bar included,
  // so a 4:3 photo fills it exactly with no bars. SliverAppBar adds the
  // status bar height to expandedHeight itself, hence the subtraction.
  static double _headerHeight(MediaQueryData media) => math.max(
        media.size.width * 3 / 4 - media.padding.top,
        kToolbarHeight,
      );

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
    if (full != null) _prefetchPhotos();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _package.galleryUrls;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          _buildGalleryAppBar(_package.videoUrls, photos),
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

  /// The header carousel: videos first (the first one plays by itself, like
  /// the video on a product page), then the photos. `_photoIndex` counts both.
  Widget _buildGalleryAppBar(List<String> videos, List<String> photos) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final slideCount = videos.length + photos.length;
    final headerHeight = _headerHeight(MediaQuery.of(context));

    return SliverAppBar(
      expandedHeight: headerHeight,
      pinned: true,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      centerTitle: false,
      titleSpacing: 4,
      title: AnimatedOpacity(
        opacity: _collapsed ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Text(
          _package.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
      ),
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
        background: slideCount == 0
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
                    itemCount: slideCount,
                    onPageChanged: (i) => setState(() => _photoIndex = i),
                    itemBuilder: (_, index) {
                      if (index < videos.length) {
                        final videoUrl =
                            PlaceImageHelper.resolveUrl(videos[index]);
                        return videoUrl == null
                            ? Container(color: AppColors.surfaceVariant)
                            : ExperienceVideoSlide(
                                key: ValueKey(videoUrl),
                                url: videoUrl,
                                active: index == _photoIndex,
                                posterUrl: photos.isEmpty
                                    ? null
                                    : PlaceImageHelper.resolveUrl(photos.first),
                                posterPreview: photos.isEmpty
                                    ? null
                                    : _package.imagePreviews[photos.first],
                              );
                      }
                      final photoIndex = index - videos.length;
                      final url =
                          PlaceImageHelper.resolveUrl(photos[photoIndex]);
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullScreenImageViewer(
                              imageUrls: photos,
                              initialIndex: photoIndex,
                            ),
                          ),
                        ),
                        child: url == null
                            ? Container(color: AppColors.surfaceVariant)
                            : ExperienceFittedPhoto(
                                url: url,
                                headers: PlaceImageHelper.headersFor(url),
                                // Keyed by the photo's path as the API sent it.
                                preview: _package.imagePreviews[photos[photoIndex]],
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
                  if (slideCount > 1)
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          slideCount,
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
          // The package's own average, once travellers have rated it; the
          // provider's combined rating is the review count's second line.
          if (_package.hasRating) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ExperienceStars(value: _package.ratingAvg!, size: 17),
                const SizedBox(width: 8),
                Text(
                  '${_package.ratingAvg!.toStringAsFixed(1)} '
                  '(${_package.ratingCount} '
                  '${_package.ratingCount == 1 ? 'review' : 'reviews'})',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (vendor != null && vendor.reviewCount > _package.ratingCount && vendor.rating != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Provider rating ${vendor.rating!.toStringAsFixed(1)} '
                  'from ${vendor.reviewCount} reviews across all their experiences',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
          ],
          // The admin's region text. Not tappable: no map, no directions.
          if (_package.hasRegion) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.location_on_rounded,
                      size: 16, color: AppColors.brandGreen),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _package.regionLabel!.trim(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // With several prices they are listed below instead.
              if (_package.priceLabel.isNotEmpty && _package.priceOptions.length < 2)
                _chip(Icons.sell_rounded, _package.priceLabel, highlight: true),
              if (_package.formattedDuration.isNotEmpty)
                _chip(Icons.schedule_rounded, _package.formattedDuration),
              if (_package.distanceM != null)
                _chip(Icons.near_me_rounded,
                    formatDistance(_package.distanceM)),
              if (_package.maxParticipants != null)
                _chip(Icons.group_rounded,
                    'Up to ${_package.maxParticipants}'),
            ],
          ),

          if (_package.priceOptions.length > 1) ...[
            const SizedBox(height: 20),
            _sectionTitle('Prices'),
            const SizedBox(height: 10),
            ..._package.priceOptions.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sell_rounded,
                        size: 16, color: AppColors.brandGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(option.label,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
            const Text(
              'Choose one when you ask to book.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],

          if ((_package.summary ?? '').isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              _package.summary!,
              style: const TextStyle(
                  fontSize: 15, height: 1.5, color: AppColors.textSecondary),
            ),
          ],

          if ((_package.descriptionMd ?? _package.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            ExperienceDescription(
              markdown: _package.descriptionMd,
              plain: _package.description,
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
            GestureDetector(
              onTap: () => _openDirectionsInSmartMap(
                targetLat: _package.latitude,
                targetLng: _package.longitude,
                destinationName: '${_package.title} (Meeting Point)',
                addressQuery: _package.meetingPointAddress!,
              ),
              behavior: HitTestBehavior.opaque,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.place_rounded,
                        size: 15, color: AppColors.brandGreen),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _package.meetingPointAddress!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.brandGreen,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Travellers' reviews and the provider's replies, and the way to
          // write one: open to every signed-in traveller.
          ExperienceReviewsSection(
            packageId: _package.id,
            packageTitle: _package.title,
            vendorName: _package.vendorName,
            ratingCount: _package.ratingCount,
          ),

          // Only when there is something under it: a vendor with no
          // description, address, website or socials left a bare
          // "About ..." heading at the bottom of the page.
          if (vendor != null &&
              ((vendor.description ?? '').trim().isNotEmpty ||
                  (vendor.address ?? '').trim().isNotEmpty ||
                  vendor.hasWebsite ||
                  vendor.hasSocials)) ...[
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
              GestureDetector(
                onTap: () => _openDirectionsInSmartMap(
                  targetLat: vendor.latitude != 0.0
                      ? vendor.latitude
                      : _package.latitude,
                  targetLng: vendor.longitude != 0.0
                      ? vendor.longitude
                      : _package.longitude,
                  destinationName: vendor.name.isNotEmpty
                      ? vendor.name
                      : _package.title,
                  addressQuery: '${vendor.name}, ${vendor.address}',
                ),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.place_rounded,
                          size: 15, color: AppColors.brandGreen),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        vendor.address!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.brandGreen,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
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

          // Last, so it sits just above the Request button.
          const SizedBox(height: 28),
          const ExperienceGoodToKnow(),
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
                    showExperienceRequestPage(context, _package),
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
