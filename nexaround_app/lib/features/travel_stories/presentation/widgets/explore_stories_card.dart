import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../data/models/travel_story.dart';
import 'story_photo_preview.dart';

/// The last card of the home Travel Stories row: a collage of stories further
/// along and the way into the Explore page, which shows them all as a grid.
class ExploreStoriesCard extends StatelessWidget {
  /// Up to four stories; the first photo of each makes the collage.
  final List<TravelStory> collage;
  final int storyCount;
  final int countryCount;
  final VoidCallback onTap;

  const ExploreStoriesCard({
    super.key,
    required this.collage,
    required this.storyCount,
    required this.countryCount,
    required this.onTap,
  });

  static const Color background = Color(0xFF0E2B2C);

  static String firstPhoto(TravelStory story) =>
      story.imageUrls.isNotEmpty ? story.imageUrls.first : story.imageUrl;

  String get _counts {
    final stories = storyCount == 1 ? '1 story' : '$storyCount stories';
    if (countryCount == 0) return stories;
    final countries = countryCount == 1 ? '1 country' : '$countryCount countries';
    return '$stories · $countries';
  }

  Widget _photo(TravelStory story) => StoryPhoto(
        story: story,
        url: firstPhoto(story),
        // A quarter of a 210 dp card, at 3x DPR.
        memCacheWidth: 360,
      );

  /// One photo fills it, two sit side by side, three put one large on the
  /// left, four make a 2x2 grid.
  Widget _buildCollage() {
    const gap = 3.0;
    final photos = collage.take(4).map(_photo).toList();
    Widget pair(List<Widget> two, {required bool across}) {
      final children = [
        Expanded(child: two[0]),
        across ? const SizedBox(width: gap) : const SizedBox(height: gap),
        Expanded(child: two[1]),
      ];
      return across
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    switch (photos.length) {
      case 0:
        return const SizedBox.expand();
      case 1:
        return photos[0];
      case 2:
        return pair(photos, across: true);
      case 3:
        return pair([photos[0], pair(photos.sublist(1), across: false)], across: true);
      default:
        return pair([
          pair(photos.sublist(0, 2), across: true),
          pair(photos.sublist(2, 4), across: true),
        ], across: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Explore all stories, $_counts',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 210,
          margin: const EdgeInsets.only(right: 18, bottom: 8, top: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The collage takes what the text leaves, so a large system
              // font size shrinks it instead of overflowing the card.
              Expanded(child: _buildCollage()),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Explore all stories',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _counts,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB9D6D6),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Explore',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.brandGreen,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.brandGreen),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
