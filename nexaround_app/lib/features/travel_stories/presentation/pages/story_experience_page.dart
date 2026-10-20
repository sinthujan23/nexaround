import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../experiences/presentation/widgets/experience_description.dart';
import '../../data/datasources/travel_stories_service.dart';
import '../../data/models/travel_story.dart';
import '../widgets/official_story_widgets.dart';

/// The long read behind an official story: its photos, the place, the intro
/// from the card, then the sections written in the admin panel (light
/// Markdown, rendered the same way as an experience package's description).
/// It ends with more TravelBytes and the way to all of them in Exclusive.
class StoryExperiencePage extends StatefulWidget {
  final TravelStory story;

  /// Opened from Exclusive: "See all in Exclusive" goes back to it.
  final bool fromExclusive;

  const StoryExperiencePage({super.key, required this.story, this.fromExclusive = false});

  @override
  State<StoryExperiencePage> createState() => _StoryExperiencePageState();
}

class _StoryExperiencePageState extends State<StoryExperiencePage> {
  // The photo header's height, as a share of the screen width.
  static const double _heroFraction = 0.9;

  final ScrollController _scroll = ScrollController();
  int _photo = 0;

  /// The photos have scrolled away and the white bar is pinned on its own:
  /// it then shows the article's title, so the reader keeps their bearings.
  bool _collapsed = false;

  /// Other TravelBytes for the end of the page, in Exclusive's order.
  List<TravelStory> _more = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  Future<void> _loadMore() async {
    final all = await TravelStoriesService().getTravelBytes();
    if (!mounted) return;
    setState(() {
      _more = all.where((s) => s.id != widget.story.id).take(3).toList();
    });
  }

  void _seeAll() {
    if (widget.fromExclusive) {
      Navigator.pop(context);
    } else {
      openExclusive(context);
    }
  }

  /// Another TravelByte's read takes this one's place, so going back from it
  /// returns to where this one was opened from.
  void _openOther(TravelStory other) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StoryExperiencePage(story: other, fromExclusive: widget.fromExclusive),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // A pinned SliverAppBar finishes collapsing after scrolling its expanded
    // height less the toolbar that stays; the title comes in just before.
    final collapseAt =
        MediaQuery.of(context).size.width * _heroFraction - kToolbarHeight - 24;
    final collapsed = _scroll.offset > collapseAt;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  List<String> get _photos {
    final story = widget.story;
    if (story.imageUrls.isNotEmpty) return story.imageUrls;
    return story.imageUrl.isNotEmpty ? [story.imageUrl] : const [];
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final photos = _photos;
    final width = MediaQuery.of(context).size.width;
    final place = [
      story.locationName,
      if ((story.country ?? '').isNotEmpty) story.country!,
    ].join(' · ');
    final heading = (story.title ?? '').trim().isNotEmpty
        ? story.title!.trim()
        : story.locationName;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: width * _heroFraction,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            centerTitle: false,
            titleSpacing: 4,
            title: AnimatedOpacity(
              opacity: _collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                heading,
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
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: photos.isEmpty
                  ? Container(color: AppColors.surfaceVariant)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // Each photo whole, as it was uploaded: a TravelByte
                        // photo can carry a caption printed near its edge,
                        // which filling the frame would cut off. Any space it
                        // leaves is the page's own white.
                        const ColoredBox(color: Colors.white),
                        PageView.builder(
                          itemCount: photos.length,
                          onPageChanged: (i) => setState(() => _photo = i),
                          itemBuilder: (_, i) => CachedNetworkImage(
                            imageUrl: storyPhotoUrl(photos[i]),
                            fit: BoxFit.contain,
                            memCacheWidth: 1440,
                            placeholder: (_, __) => Container(color: AppColors.surface),
                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                          ),
                        ),
                        if (photos.length > 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 10,
                            // Dark dots on a white pill: readable on the white
                            // space round a photo and on the photo itself.
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(photos.length, (i) {
                                    final active = i == _photo;
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      width: active ? 18 : 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: active ? AppColors.textPrimary : AppColors.textMuted,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...[
                  Row(
                    children: [
                      const OfficialAvatar(radius: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: OfficialName(
                          name: story.userName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.brandGreenLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          story.category,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if ((story.title ?? '').trim().isNotEmpty) ...[
                    Text(
                      story.title!.trim(),
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 15, color: AppColors.brandGreen),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    story.description,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ExperienceDescription(markdown: story.articleMd),
                  ]
                      .animate(interval: 50.ms)
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: 0.04, end: 0, duration: 300.ms),
                  if (_more.isNotEmpty) _buildMore(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The end of the read: more TravelBytes, then the way to all of them.
  Widget _buildMore() {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 22),
          Text(
            'More from ${widget.story.userName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (final other in _more) _moreRow(other),
          const SizedBox(height: 12),
          ReadExperienceTab(label: 'See all in Exclusive', onTap: _seeAll),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _moreRow(TravelStory other) {
    final cover = other.imageUrls.isNotEmpty ? other.imageUrls.first : other.imageUrl;
    final title = (other.title ?? '').trim().isNotEmpty ? other.title!.trim() : other.locationName;
    return InkWell(
      onTap: () => _openOther(other),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: CachedNetworkImage(
                  imageUrl: storyPhotoUrl(cover),
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
                  errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    other.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandGreen,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
