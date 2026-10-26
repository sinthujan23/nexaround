import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../data/models/travel_story.dart';
import '../widgets/explore_stories_card.dart';
import '../widgets/official_story_widgets.dart';
import '../widgets/story_photo_preview.dart';
import '../widgets/travel_story_card.dart' show storyDistanceLabel;

/// Every story of the home Travel Stories row as a photo grid, opened from
/// the "Explore all stories" card at the row's end. Chips narrow it to the
/// stories near the traveller or to one category.
///
/// The home page owns the stories, so this page and the row always show the
/// same feed: [stories] reads them, [changes] fires when they change (a
/// reload, another country), [onPickCountry] opens the row's country picker
/// and [onOpen] its story viewer.
class ExploreStoriesPage extends StatefulWidget {
  /// In feed order: TravelBytes first, then travellers' stories.
  final List<TravelStory> Function() stories;
  final String Function() filterLabel;
  final Listenable changes;
  final VoidCallback onPickCountry;
  final void Function(List<TravelStory> stories, int index) onOpen;

  const ExploreStoriesPage({
    super.key,
    required this.stories,
    required this.filterLabel,
    required this.changes,
    required this.onPickCountry,
    required this.onOpen,
  });

  @override
  State<ExploreStoriesPage> createState() => _ExploreStoriesPageState();
}

class _ExploreStoriesPageState extends State<ExploreStoriesPage> {
  static const String _all = 'All';
  static const String _nearYou = 'Near you';

  /// "Near you" keeps the stories this close, nearest first: the server's
  /// second "Near you" band (NEARBY_BANDS_M in travel_stories.py).
  static const double _nearM = 150000;

  final ScrollController _scroll = ScrollController();
  String _picked = _all;
  late String _label = widget.filterLabel();

  // The TravelByte on the grid's first tile, and the ones its shuffle
  // button has still to show this round, as on the home row's card.
  String? _shownTravelByteId;
  List<String> _travelBytesToShuffle = [];
  final _shuffleRandom = math.Random();

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_onStoriesChanged);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_onStoriesChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onStoriesChanged() {
    if (!mounted) return;
    final label = widget.filterLabel();
    // Another country: its grid starts at the top.
    if (label != _label && _scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _label = label);
  }

  /// Distances come with the default feed only, not with a picked country.
  bool _hasNearby(List<TravelStory> all) => all.any((s) => s.distanceM != null);

  /// Travellers' categories, the most used first. TravelBytes carry a place
  /// label there instead ("GREECE · SANTORINI"), so they have none.
  List<String> _categories(List<TravelStory> all) {
    final counts = <String, int>{};
    for (final s in all) {
      final category = s.category.trim();
      if (s.isOfficial || category.isEmpty) continue;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final categories = counts.keys.toList();
    // Equal counts keep the order they first appear in.
    final first = {for (final (i, c) in categories.indexed) c: i};
    return categories
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : first[a]!.compareTo(first[b]!);
      });
  }

  /// [shown] with its TravelBytes on one tile, first: the one the shuffle
  /// button picked, else the first. So travellers' stories fill the grid;
  /// the other TravelBytes are a tap of that button away.
  List<TravelStory> _oneTravelByte(List<TravelStory> shown) {
    final travelBytes = shown.where((s) => s.isOfficial).toList();
    if (travelBytes.isEmpty) return shown;
    final front = travelBytes.firstWhere(
      (s) => s.id == _shownTravelByteId,
      orElse: () => travelBytes.first,
    );
    return [front, ...shown.where((s) => !s.isOfficial)];
  }

  /// Another TravelByte on the first tile, Spotify style: each of the
  /// others once, in random order, before any comes round again.
  void _shuffleTravelByte(List<TravelStory> travelBytes, String current) {
    final ids = travelBytes.map((s) => s.id).toList();
    _travelBytesToShuffle.removeWhere((id) => id == current || !ids.contains(id));
    if (_travelBytesToShuffle.isEmpty) {
      _travelBytesToShuffle = ids.where((id) => id != current).toList()
        ..shuffle(_shuffleRandom);
    }
    if (_travelBytesToShuffle.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _shownTravelByteId = _travelBytesToShuffle.removeAt(0));
  }

  List<TravelStory> _shown(List<TravelStory> all, String picked) {
    if (picked == _all) return all;
    if (picked == _nearYou) {
      return all.where((s) => s.distanceM != null && s.distanceM! <= _nearM).toList()
        ..sort((a, b) => a.distanceM!.compareTo(b.distanceM!));
    }
    return all.where((s) => !s.isOfficial && s.category.trim() == picked).toList();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.stories();
    final chips = [
      _all,
      if (_hasNearby(all)) _nearYou,
      ..._categories(all),
    ];
    // A chip can go when the stories change (another country has no
    // distances, or none of that category).
    final picked = chips.contains(_picked) ? _picked : _all;
    final filtered = _shown(all, picked);
    final travelBytes = filtered.where((s) => s.isOfficial).toList();
    final shown = _oneTravelByte(filtered);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildChips(chips, picked),
            Expanded(
              child: shown.isEmpty
                  ? _buildEmpty(picked)
                  : _buildGrid(
                      shown,
                      onShuffle: travelBytes.length > 1
                          ? () => _shuffleTravelByte(travelBytes, shown.first.id)
                          : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Text(
              'Explore stories',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: widget.onPickCountry,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, maxWidth: 150),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.brandGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: AppColors.brandGreen, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChips(List<String> chips, String picked) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final chip = chips[i];
          final on = chip == picked;
          return Semantics(
            button: true,
            selected: on,
            child: GestureDetector(
              onTap: () => setState(() => _picked = chip),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AppColors.brandGreen : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: on ? AppColors.brandGreen : AppColors.border),
                ),
                child: Text(
                  chip,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(String picked) {
    final text = picked == _nearYou
        ? 'No stories within ${(_nearM / 1000).round()} km yet'
        : 'No stories here yet';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 36, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const double _gap = 10;

  /// Two staggered columns, built four stories at a time so a long feed
  /// loads its photos as they scroll in. In each block the left column has a
  /// tall photo over a short one and the right a short over a tall, so the
  /// columns end level and the blocks stack seamlessly.
  /// [onShuffle]: the first tile holds several TravelBytes.
  Widget _buildGrid(List<TravelStory> shown, {VoidCallback? onShuffle}) {
    final blocks = (shown.length + 3) ~/ 4;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
      itemCount: blocks,
      itemBuilder: (context, block) {
        return LayoutBuilder(
          builder: (context, box) {
            final column = (box.maxWidth - _gap) / 2;
            final tall = column * 1.3;
            final short = column * 0.95;
            Widget? tile(int offset, double height) {
              final i = block * 4 + offset;
              if (i >= shown.length) return null;
              return _ExploreTile(
                story: shown[i],
                height: height,
                onTap: () => widget.onOpen(shown, i),
                onShuffle: i == 0 ? onShuffle : null,
              );
            }

            Widget stack(List<Widget?> tiles) => Expanded(
                  child: Column(
                    children: [
                      for (final (n, t) in tiles.nonNulls.indexed) ...[
                        if (n > 0) const SizedBox(height: _gap),
                        t,
                      ],
                    ],
                  ),
                );
            return Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  stack([tile(0, tall), tile(2, short)]),
                  const SizedBox(width: _gap),
                  stack([tile(1, short), tile(3, tall)]),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ExploreTile extends StatelessWidget {
  final TravelStory story;
  final double height;
  final VoidCallback onTap;

  /// On the TravelByte tile when there are others to show.
  final VoidCallback? onShuffle;

  const _ExploreTile({
    required this.story,
    required this.height,
    required this.onTap,
    this.onShuffle,
  });

  /// Under the place: how far it is when the feed says, else its country
  /// (unless that is the place's name, as on a TravelByte about a country).
  String? get _subtitle {
    final distance = story.distanceM;
    if (distance != null) return storyDistanceLabel(distance);
    final country = story.country?.trim() ?? '';
    if (country.isEmpty || country == story.locationName.trim()) return null;
    return country;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    final shuffle = onShuffle;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label: [
              if (story.isOfficial) 'TravelByte',
              story.locationName,
              ?subtitle,
            ].join(', '),
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The shuffle fades one TravelByte into the next.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      child: StoryPhoto(
                        key: ValueKey(story.id),
                        story: story,
                        url: ExploreStoriesCard.firstPhoto(story),
                        // Half the screen wide, at 3x DPR.
                        memCacheWidth: 600,
                      ),
                    ),
                    if (story.isOfficial)
                      // The account's name and blue tick, as on the home
                      // row's TravelByte card.
                      Positioned(
                        top: 8,
                        left: 8,
                        right: shuffle != null ? 52 : 8,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: OfficialName(
                              name: story.userName.trim().isEmpty ? 'TravelByte' : story.userName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 26, 10, 9),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xB8000000), Color(0x00000000)],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              story.locationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFE4ECEC),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (shuffle != null)
            Positioned(
              top: 2,
              right: 2,
              child: _ShuffleButton(onTap: shuffle),
            ),
        ],
      ),
    );
  }
}

/// The home row card's shuffle button: a green disc, a 44 dp target.
class _ShuffleButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ShuffleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Show another TravelByte',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.brandGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandGreenDark.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.shuffle_rounded, size: 17, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
