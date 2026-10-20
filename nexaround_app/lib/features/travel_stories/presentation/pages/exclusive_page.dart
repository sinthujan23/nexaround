import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/travel_stories_service.dart';
import '../../data/models/travel_story.dart';
import '../widgets/official_story_widgets.dart';
import '../widgets/travel_story_card.dart' show storyDistanceLabel;

/// Exclusive: every TravelByte in one place, in the order the TravelByte card
/// on the home row shows them (the traveller's own country first, then the
/// newest). The first is featured with its cover photo whole; the rest follow
/// as a list. Each opens its "Read the experience" page.
class ExclusivePage extends StatefulWidget {
  const ExclusivePage({super.key});

  @override
  State<ExclusivePage> createState() => _ExclusivePageState();
}

class _ExclusivePageState extends State<ExclusivePage> {
  static const double _headerHeight = 150;

  final ScrollController _scroll = ScrollController();
  late List<TravelStory> _stories;
  bool _loading = true;

  /// The header has scrolled away and the bar is pinned on its own: it then
  /// shows the page's name.
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    // The saved feed paints at once; the server's full list replaces it.
    _stories = TravelStoriesService().cachedTravelBytes();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stories = await TravelStoriesService().getTravelBytes();
    if (!mounted) return;
    setState(() {
      _stories = stories;
      _loading = false;
    });
  }

  void _onScroll() {
    final collapsed = _scroll.offset > _headerHeight - kToolbarHeight - 24;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  void _open(TravelStory story) =>
      openStoryExperience(context, story, fromExclusive: true);

  @override
  Widget build(BuildContext context) {
    final featured = _stories.isEmpty ? null : _stories.first;
    final rest = _stories.length > 1 ? _stories.sublist(1) : const <TravelStory>[];

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          _buildHeader(),
          if (featured == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator(color: AppColors.brandGreen)
                    : const Text(
                        'No travel guides yet',
                        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
              ),
            )
          else ...[
            SliverToBoxAdapter(child: _buildFeatured(featured)),
            if (rest.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(
                    'More from ${featured.userName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildRow(rest[i]),
                childCount: rest.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final count = _stories.length;
    final name = _stories.isEmpty ? 'TravelByte' : _stories.first.userName;
    const titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 19,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
    );

    return SliverAppBar(
      pinned: true,
      expandedHeight: _headerHeight,
      backgroundColor: AppColors.brandGreenDark,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 4,
      title: AnimatedOpacity(
        opacity: _collapsed ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: const Text(
          'Exclusive',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          alignment: Alignment.bottomLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EXCLUSIVE',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Travel guides by ', style: titleStyle),
                  Flexible(child: OfficialName(name: name, style: titleStyle)),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(height: 4),
                Text(
                  count == 1 ? '1 guide' : '$count guides',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _coverOf(TravelStory story) =>
      story.imageUrls.isNotEmpty ? story.imageUrls.first : story.imageUrl;

  /// The place label, and how many photos and how far away.
  Widget _meta(TravelStory story) {
    final photos = story.imageUrls.isNotEmpty ? story.imageUrls.length : 1;
    final details = [
      photos == 1 ? '1 photo' : '$photos photos',
      if (story.distanceM != null) storyDistanceLabel(story.distanceM!),
    ].join(' · ');
    return Row(
      children: [
        Flexible(child: _label(story)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            details,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(TravelStory story) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandGreenLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        story.category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.brandGreen,
        ),
      ),
    );
  }

  Widget _buildFeatured(TravelStory story) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(story),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The cover whole, in its own shape: as wide as the page and as
            // tall as the photo needs, so no part of it is cut off.
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: storyPhotoUrl(_coverOf(story)),
                width: double.infinity,
                fit: BoxFit.fitWidth,
                memCacheWidth: 1440,
                placeholder: (_, __) => const AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(color: AppColors.surface),
                ),
                errorWidget: (_, __, ___) => const AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(color: AppColors.surfaceVariant),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _meta(story),
            const SizedBox(height: 8),
            Text(
              (story.title ?? '').trim().isNotEmpty ? story.title!.trim() : story.locationName,
              style: const TextStyle(
                fontSize: 21,
                height: 1.25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              story.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            ReadExperienceTab(onTap: () => _open(story)),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.03, end: 0, duration: 300.ms);
  }

  Widget _buildRow(TravelStory story) {
    return InkWell(
      onTap: () => _open(story),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 96,
                height: 96,
                child: CachedNetworkImage(
                  imageUrl: storyPhotoUrl(_coverOf(story)),
                  fit: BoxFit.cover,
                  memCacheWidth: 300,
                  placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
                  errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(story),
                  const SizedBox(height: 6),
                  Text(
                    (story.title ?? '').trim().isNotEmpty ? story.title!.trim() : story.locationName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Read →',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
