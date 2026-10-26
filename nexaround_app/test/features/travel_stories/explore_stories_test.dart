import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/travel_stories/data/models/travel_story.dart';
import 'package:nexaround_app/features/travel_stories/presentation/pages/explore_stories_page.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/explore_stories_card.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/story_photo_preview.dart';

// A 32 x 24 WebP, the size the server sends (app/services/image_preview.py).
const _preview =
    'UklGRmIAAABXRUJQVlA4IFYAAAAQBACdASogABgAPu1sqk+tNiOqMBgIAsAdiWgAnTKEdJCwsxgUCUyhAAD9rrwsYK/Tnap3fkhsTcLIsXovNGyzHSs58WH46BfwfXfmCdwSAGBqAphgAA==';

TravelStory _story(
  String id, {
  String place = 'Somewhere',
  String category = '💎 Hidden Gem',
  String? country = 'Sri Lanka',
  double? km,
  bool official = false,
}) {
  final photo = '/static/uploads/stories/$id.jpg';
  return TravelStory(
    id: id,
    userId: official ? 'official' : 'u-$id',
    userName: official ? 'TravelByte' : 'Traveller',
    userAvatar: '',
    locationName: place,
    category: category,
    description: '',
    imageUrl: photo,
    imageUrls: [photo],
    comments: [],
    createdAt: DateTime(2026, 10, 1),
    country: country,
    distanceM: km == null ? null : km * 1000,
    isOfficial: official,
    imagePreviews: {photo: _preview},
  );
}

/// The default feed, as the server orders it: TravelBytes first.
List<TravelStory> _feed() => [
      _story('tb-santorini',
          place: 'Santorini', category: 'GREECE · SANTORINI', country: 'Greece', km: 6900, official: true),
      _story('tb-lanka',
          place: 'Sri Lanka', category: 'SRI LANKA', country: 'Sri Lanka', km: 120, official: true),
      _story('sigiriya', place: 'Sigiriya Rock', category: '🌅 Scenic Viewpoint', km: 34),
      _story('gregory', place: 'Lake Gregory', km: 118),
      _story('dambulla', place: 'Dambulla Caves', km: 48),
      _story('pinnawala', place: 'Pinnawala', category: '🧭 Offbeat Place', km: 160),
      _story('oia', place: 'Oia', category: '🌅 Scenic Viewpoint', country: 'Greece', km: 6905),
    ];

void _phone(WidgetTester tester, {double width = 412}) {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

class _Explore {
  List<TravelStory> stories;
  String label;
  final ValueNotifier<int> changes = ValueNotifier(0);
  final List<(List<TravelStory>, int)> opened = [];
  int countryPicks = 0;

  _Explore(this.stories, {this.label = '🌐 Global'});

  void change(List<TravelStory> to, {String? label}) {
    stories = to;
    if (label != null) this.label = label;
    changes.value++;
  }

  /// [width]: the chip row builds only the chips on screen.
  Future<void> pump(WidgetTester tester, {double textScale = 1.0, double width = 412}) async {
    _phone(tester, width: width);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: ExploreStoriesPage(
          stories: () => stories,
          filterLabel: () => label,
          changes: changes,
          onPickCountry: () => countryPicks++,
          onOpen: (shown, index) => opened.add((shown, index)),
        ),
      ),
    ));
  }
}

List<String> _chips(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Text),
    ))
    .map((t) => t.data!)
    .toList();

final _tile = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ExploreTile');

/// The places on the grid, in story order: the list the viewer opens on
/// (the grid draws its blocks column by column, so not the widget order),
/// checked against the tiles drawn.
Future<List<String>> _tiles(WidgetTester tester, _Explore explore) async {
  final drawn = tester
      .widgetList(_tile)
      .map((w) => (w as dynamic).story.locationName as String)
      .toSet();
  await tester.tap(_tile.first);
  final shown = explore.opened.removeLast().$1.map((s) => s.locationName).toList();
  expect(drawn, shown.toSet());
  return shown;
}

void main() {
  group('the Explore card at the end of the row', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      int photos = 0,
      List<TravelStory>? collage,
      int more = 0,
      int stories = 16,
      int countries = 10,
      double textScale = 1.0,
      bool animationsOff = false,
      VoidCallback? onTap,
    }) async {
      _phone(tester);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(412, 900),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: animationsOff,
          ),
          // The home row: 425 high with 12 on top.
          child: Scaffold(
            body: SizedBox(
              height: 425,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 6, 0),
                scrollDirection: Axis.horizontal,
                children: [
                  ExploreStoriesCard(
                    collage: collage ?? _feed().take(photos).toList(),
                    moreCount: more,
                    storyCount: stories,
                    countryCount: countries,
                    onTap: onTap ?? () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    for (final scale in [1.0, 1.3, 2.0]) {
      for (final photos in [0, 1, 2, 3, 4]) {
        testWidgets('fits its row with $photos photos at text size x$scale', (tester) async {
          await pumpCard(tester, photos: photos, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(find.byType(StoryPhoto), findsNWidgets(photos));
        });
      }
    }

    testWidgets('counts the stories and countries, and opens Explore', (tester) async {
      var taps = 0;
      await pumpCard(tester, photos: 4, onTap: () => taps++);
      expect(find.text('16 stories · 10 countries'), findsOneWidget);
      await tester.tap(find.text('Explore'));
      expect(taps, 1);

      await pumpCard(tester, photos: 2, stories: 2, countries: 1);
      expect(find.text('2 stories · 1 country'), findsOneWidget);
      await pumpCard(tester, photos: 2, stories: 2, countries: 0);
      expect(find.text('2 stories'), findsOneWidget);
    });

    testWidgets('photos show their blurred preview while they load', (tester) async {
      await pumpCard(tester, photos: 4);
      expect(find.byType(StoryPhotoPreview), findsNWidgets(4));
    });

    testWidgets('"+N" for the stories without a card in the row', (tester) async {
      await pumpCard(tester, photos: 3, more: 11);
      expect(find.text('+11'), findsOneWidget);
      await pumpCard(tester, photos: 3);
      expect(find.textContaining('+'), findsNothing);
    });

    // A TravelByte first, then two travellers' stories: the badge shows
    // only while the TravelByte is at the front.
    List<TravelStory> oneTravelByte() {
      final feed = _feed();
      return [feed[0], feed[2], feed[3]];
    }

    testWidgets('deals the next photo to the front every few seconds, round and round',
        (tester) async {
      await pumpCard(tester, collage: oneTravelByte());
      await tester.pump(); // the clock's first tick
      expect(find.text('TRAVELBYTE'), findsOneWidget);

      // Each pump passes one deal (the clock restarts on the frame it ends).
      const pastADeal = Duration(milliseconds: 3800);
      await tester.pump(pastADeal);
      expect(find.text('TRAVELBYTE'), findsNothing);
      await tester.pump(pastADeal);
      expect(find.text('TRAVELBYTE'), findsNothing);
      await tester.pump(pastADeal);
      expect(find.text('TRAVELBYTE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps still for travellers who turned animations off', (tester) async {
      await pumpCard(tester, collage: oneTravelByte(), animationsOff: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('TRAVELBYTE'), findsOneWidget);
    });
  });

  group('the Explore page', () {
    testWidgets('chips: All, Near you, then the categories most used first', (tester) async {
      final explore = _Explore(_feed());
      await explore.pump(tester, width: 1400);
      expect(_chips(tester), [
        'All',
        'Near you',
        // Two each: the one seen first in the feed first.
        '🌅 Scenic Viewpoint',
        '💎 Hidden Gem',
        '🧭 Offbeat Place',
      ]);
    });

    testWidgets('All: the TravelBytes share the first tile, then travellers\' stories',
        (tester) async {
      final explore = _Explore(_feed());
      await explore.pump(tester);
      expect(await _tiles(tester, explore), [
        'Santorini', 'Sigiriya Rock', 'Lake Gregory',
        'Dambulla Caves', 'Pinnawala', 'Oia',
      ]);
      // The account's name with the blue tick, on that tile only.
      expect(find.text('TravelByte'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('34 km away'), findsOneWidget);
    });

    testWidgets('its shuffle button shows the other TravelBytes in turn', (tester) async {
      final explore = _Explore(_feed());
      await explore.pump(tester);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pump(const Duration(milliseconds: 400));
      expect((await _tiles(tester, explore)).first, 'Sri Lanka');

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pump(const Duration(milliseconds: 400));
      expect((await _tiles(tester, explore)).first, 'Santorini');
    });

    testWidgets('no shuffle button with one TravelByte', (tester) async {
      await _Explore(_feed().skip(1).toList()).pump(tester);
      expect(find.text('TravelByte'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
    });

    testWidgets('"Near you" keeps the stories within 150 km: TravelBytes first, then nearest first',
        (tester) async {
      final explore = _Explore(_feed());
      await explore.pump(tester);
      await tester.tap(find.text('Near you'));
      await tester.pump();
      expect(await _tiles(tester, explore), ['Sri Lanka', 'Sigiriya Rock', 'Dambulla Caves', 'Lake Gregory']);
    });

    testWidgets('a category keeps only travellers\' stories of it', (tester) async {
      final explore = _Explore(_feed());
      await explore.pump(tester);
      await tester.tap(find.text('🌅 Scenic Viewpoint'));
      await tester.pump();
      expect(await _tiles(tester, explore), ['Sigiriya Rock', 'Oia']);
    });

    testWidgets('tapping a tile opens the viewer on the stories shown, at that one', (tester) async {
      final explore = _Explore(_feed());
      await explore.pump(tester);
      await tester.tap(find.text('Near you'));
      await tester.pump();
      await tester.tap(find.text('Lake Gregory'));
      final (shown, index) = explore.opened.single;
      expect(shown.map((s) => s.locationName).toList(),
          ['Sri Lanka', 'Sigiriya Rock', 'Dambulla Caves', 'Lake Gregory']);
      expect(index, 3);
    });

    testWidgets('staggered: tall then short on the left, short then tall on the right',
        (tester) async {
      await _Explore(_feed()).pump(tester);
      Rect tile(String place) =>
          tester.getRect(find.ancestor(of: find.text(place), matching: _tile));
      final first = tile('Santorini'), second = tile('Sigiriya Rock');
      final third = tile('Lake Gregory'), fourth = tile('Dambulla Caves');
      expect(first.left, lessThan(second.left));
      expect(first.height, greaterThan(second.height));
      expect(third.left, first.left);
      expect(fourth.left, second.left);
      // Both columns of a block end level, so the next block starts clean.
      expect(third.bottom, moreOrLessEquals(fourth.bottom));
      expect(tile('Pinnawala').top, greaterThan(third.bottom));
    });

    testWidgets('another country: its stories, no "Near you", back to All', (tester) async {
      final explore = _Explore(_feed());
      await explore.pump(tester);
      await tester.tap(find.text('Near you'));
      await tester.pump();

      await tester.tap(find.text('🌐 Global'));
      expect(explore.countryPicks, 1);
      // The home page reloads the feed for Greece; no distances with a country.
      explore.change([
        _story('tb-santorini', place: 'Santorini', category: 'GREECE · SANTORINI', country: 'Greece', official: true),
        _story('oia', place: 'Oia', category: '🌅 Scenic Viewpoint', country: 'Greece'),
      ], label: 'Greece');
      await tester.pump();

      expect(find.text('Greece'), findsWidgets);
      expect(_chips(tester), ['All', '🌅 Scenic Viewpoint']);
      expect(await _tiles(tester, explore), ['Santorini', 'Oia']);
    });

    testWidgets('says so when a chip has nothing', (tester) async {
      await _Explore([
        _story('far', place: 'Far away', km: 900),
        _story('farther', place: 'Farther', km: 1200),
      ]).pump(tester);
      await tester.tap(find.text('Near you'));
      await tester.pump();
      expect(find.text('No stories within 150 km yet'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('lays out without overflow at text size x$scale', (tester) async {
        await _Explore(_feed()).pump(tester, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
