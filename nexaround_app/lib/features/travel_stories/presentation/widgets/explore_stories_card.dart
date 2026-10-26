import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../data/models/travel_story.dart';
import 'story_photo_preview.dart';

/// The last card of the home Travel Stories row: a fanned stack of photos of
/// stories further along, and the way into the Explore page, which shows
/// them all as a grid. Every few seconds the next photo comes to the front
/// and the one that was there swings round to the back.
class ExploreStoriesCard extends StatefulWidget {
  /// The stories whose first photos the stack deals, in order.
  final List<TravelStory> collage;
  final int storyCount;
  final int countryCount;

  /// Stories without a card in the row, shown as "+N" when there are any.
  final int moreCount;
  final VoidCallback onTap;

  const ExploreStoriesCard({
    super.key,
    required this.collage,
    required this.storyCount,
    required this.countryCount,
    this.moreCount = 0,
    required this.onTap,
  });

  /// White, with everything on it in the app's green.
  static const Color background = Colors.white;

  /// How long each photo stays at the front.
  static const Duration dealEvery = Duration(seconds: 3);

  static String firstPhoto(TravelStory story) =>
      story.imageUrls.isNotEmpty ? story.imageUrls.first : story.imageUrl;

  @override
  State<ExploreStoriesCard> createState() => _ExploreStoriesCardState();
}

class _ExploreStoriesCardState extends State<ExploreStoriesCard>
    with SingleTickerProviderStateMixin {
  static const Duration _move = Duration(milliseconds: 650);
  static const Curve _curve = Curves.easeOutCubic;

  // Runs once for each photo at the front. A ticker rather than a timer, so
  // it stops while Home is off screen (another tab, the app in the
  // background).
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: ExploreStoriesCard.dealEvery,
  )..addStatusListener(_onClock);

  int _front = 0;

  String get _counts {
    final count = widget.storyCount;
    final stories = count == 1 ? '1 story' : '$count stories';
    final countries = widget.countryCount;
    if (countries == 0) return stories;
    return '$stories · ${countries == 1 ? '1 country' : '$countries countries'}';
  }

  void _onClock(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final n = widget.collage.length;
    if (n < 2) return;
    setState(() => _front = (_front + 1) % n);
    _clock.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant ExploreStoriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  /// Deals only with two photos or more, and never for travellers who have
  /// turned animations off in their phone's settings.
  void _syncClock() {
    final deal = widget.collage.length > 1 &&
        !MediaQuery.disableAnimationsOf(context);
    if (!deal) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// The front photo upright and largest; the next one tilted behind it on
  /// the left; the one just shown tilted on the right; any others hidden
  /// behind the front, ready to come round.
  Widget _buildStack() {
    final photos = widget.collage;
    final n = photos.length;
    if (n == 0) return const SizedBox.expand();
    final front = _front % n;
    int place(int i) => (i - front) % n;
    // 3 the front, 2 next, 1 just shown, 0 hidden: also the paint order.
    int depth(int i) {
      final p = place(i);
      if (p == 0) return 3;
      if (p == 1) return 2;
      if (p == n - 1) return 1;
      return 0;
    }

    return LayoutBuilder(
      builder: (context, box) {
        // Laid out for the 268 dp the card leaves at the default text size,
        // and shrunk with it at larger ones.
        final s = math.min(1.0, box.maxHeight / 268);
        final cx = box.maxWidth / 2;
        final cy = box.maxHeight * 0.41;

        Widget card(int i) {
          final d = depth(i);
          final upright = d == 3 || d == 0;
          final w = (upright ? 116 : 104) * s * (d == 0 ? 0.8 : 1);
          final h = (upright ? 160 : 140) * s * (d == 0 ? 0.8 : 1);
          final dx = d == 2 ? -39 * s : (d == 1 ? 39 * s : 0.0);
          final dy = upright ? 0.0 : 8 * s;
          final turns = d == 2 ? -12 / 360 : (d == 1 ? 12 / 360 : 0.0);
          return AnimatedPositioned(
            key: ValueKey('${photos[i].id}#$i'),
            duration: _move,
            curve: _curve,
            left: cx + dx - w / 2,
            top: cy + dy - h / 2,
            width: w,
            height: h,
            child: AnimatedRotation(
              turns: turns,
              duration: _move,
              curve: _curve,
              child: AnimatedOpacity(
                opacity: d == 0 ? 0 : 1,
                duration: _move,
                curve: _curve,
                child: _PhotoCard(
                  story: photos[i],
                  showBadge: d == 3 && photos[i].isOfficial,
                ),
              ),
            ),
          );
        }

        final order = List.generate(n, (i) => i)
          ..sort((a, b) => depth(a).compareTo(depth(b)));
        return Stack(
          children: [
            for (final i in order) card(i),
            // On the front photo's bottom-right corner, overlapping its
            // edge; it stays there while the photos come round under it.
            if (widget.moreCount > 0)
              Positioned(
                right: box.maxWidth - (cx + 58 * s) - 10,
                top: cy + 80 * s - 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    '+${widget.moreCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Explore all stories, $_counts',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 210,
          margin: const EdgeInsets.only(right: 18, bottom: 8, top: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ExploreStoriesCard.background,
            borderRadius: BorderRadius.circular(24),
            // As the story cards beside it.
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The stack takes what the text leaves, so a large system
              // font size shrinks it instead of overflowing the card.
              Expanded(child: _buildStack()),
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
                        color: AppColors.brandGreen,
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
                        color: AppColors.brandGreen,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brandGreen,
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
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
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

/// One photo of the stack: a green-edged card with a soft shadow.
class _PhotoCard extends StatelessWidget {
  final TravelStory story;
  final bool showBadge;

  const _PhotoCard({required this.story, required this.showBadge});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandGreen,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              StoryPhoto(
                story: story,
                url: ExploreStoriesCard.firstPhoto(story),
                // A 116 dp card at 3x DPR.
                memCacheWidth: 360,
              ),
              if (showBadge)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TRAVELBYTE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
