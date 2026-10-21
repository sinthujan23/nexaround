import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/travel_stories/data/models/travel_story.dart';
import 'package:nexaround_app/features/travel_stories/presentation/pages/story_experience_page.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/story_photo_preview.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/travel_story_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only what the card reads: who is signed in, for a traveller's own name.
class _SignedOut extends Cubit<AuthState> implements AuthBloc {
  _SignedOut() : super(const AuthUnauthenticated());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// A 32 x 24 WebP, the size the server sends (app/services/image_preview.py).
const _preview =
    'UklGRmIAAABXRUJQVlA4IFYAAAAQBACdASogABgAPu1sqk+tNiOqMBgIAsAdiWgAnTKEdJCwsxgUCUyhAAD9rrwsYK/Tnap3fkhsTcLIsXovNGyzHSs58WH46BfwfXfmCdwSAGBqAphgAA==';

const _photos = [
  '/static/uploads/experiences/a.jpg',
  '/static/uploads/experiences/b.jpg',
  '/static/uploads/experiences/c.jpg',
  '/static/uploads/experiences/d.jpg',
  '/static/uploads/experiences/e.jpg',
];

TravelStory _travelByte({
  String id = 'tb-furong',
  String category = 'CHINA · FURONG TOWN',
  String description =
      'Imagine walking through a centuries-old Chinese village as the sound '
      'of rushing water fills the air. Wooden houses cling to the hillsides.',
  Map<String, String>? previews,
}) =>
    TravelStory(
      id: id,
      userId: 'official',
      userName: 'TravelByte',
      userAvatar: '',
      locationName: 'Furong Ancient Town',
      category: category,
      description: description,
      imageUrl: _photos.first,
      imageUrls: _photos,
      comments: [],
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      distanceM: 3752000,
      isOfficial: true,
      title: 'Furong Ancient Town',
      articleMd: '## Furong\nA long read.',
      imagePreviews: previews ?? {for (final u in _photos) u: _preview},
    );

TravelStory _travellersStory() => TravelStory(
      id: 'marble',
      userId: 'u1',
      userName: 'Martin Mendis the Long-Named Traveller',
      userAvatar: '',
      locationName: 'Marble Beach, Trincomalee, Eastern Province, Sri Lanka',
      category: 'Hidden Gem',
      description: 'One of Sri Lanka’s most beautiful beaches, with clear '
          'water, white sand and calm swimming for most of the year. ' * 3,
      imageUrl: _photos.first,
      imageUrls: _photos.take(3).toList(),
      comments: [],
      createdAt: DateTime.now().subtract(const Duration(days: 60)),
      distanceM: 12000,
    );

/// The card as the home row lays it out: a horizontal list 425 high with 12
/// on top, so each card gets 413.
Future<void> _pumpRow(
  WidgetTester tester,
  TravelStory story, {
  double textScale = 1.0,
  int travelByteCount = 1,
  VoidCallback? onShuffle,
}) async {
  tester.view.physicalSize = const Size(412 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BlocProvider<AuthBloc>.value(
    value: _SignedOut(),
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(412, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SizedBox(
            height: 425,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 6, 0),
              scrollDirection: Axis.horizontal,
              children: [
                TravelStoryCard(
                  story: story,
                  travelByteCount: travelByteCount,
                  onShuffle: onShuffle,
                  onLikeTap: () {},
                  onCommentTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ));
  // Lets the "See more" pill's looping shimmer start; without it the test
  // ends with its start timer still pending.
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  // The long read (opened by "See more") looks up the other TravelBytes.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
    Hive.init(Directory.systemTemp.createTempSync('stories').path);
    await Hive.openBox('travel_stories_box');
  });

  testWidgets('a photo that is still loading shows its blurred preview, not a spinner',
      (tester) async {
    await _pumpRow(tester, _travelByte(), travelByteCount: 4, onShuffle: () {});

    // The grid shows three photos, each over its own preview.
    expect(find.byType(StoryPhotoPreview), findsNWidgets(3));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a story the server sent no previews for falls back to the spinner',
      (tester) async {
    await _pumpRow(tester, _travelByte(previews: {}));

    expect(find.byType(StoryPhotoPreview), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
  });

  testWidgets('previews come through the JSON the feed and the Hive cache use',
      (tester) async {
    final story = TravelStory.fromJson(_travelByte().toJson());
    expect(story.imagePreviews, hasLength(_photos.length));
    expect(story.imagePreviews[_photos.first], _preview);
  });

  // The row is a fixed 425 high, so anything that makes the card taller -
  // a long label wrapping the header, the phone's text size - used to push
  // the footer out ("BOTTOM OVERFLOWED BY 1.00 PIXELS"). Any overflow fails
  // the test.
  for (final scale in [1.0, 1.15, 1.3, 1.6, 2.0]) {
    testWidgets('the TravelByte card fits its row at text size x$scale',
        (tester) async {
      await _pumpRow(
        tester,
        _travelByte(category: 'UNITED ARAB EMIRATES · ABU DHABI'),
        textScale: scale,
        travelByteCount: 4,
        onShuffle: () {},
      );
      expect(tester.takeException(), isNull);
      expect(find.text('See more'), findsOneWidget);
    });

    testWidgets("a traveller's card fits its row at text size x$scale",
        (tester) async {
      await _pumpRow(tester, _travellersStory(), textScale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('"See more" opens the long read of the TravelByte on the card',
      (tester) async {
    await _pumpRow(tester, _travelByte(id: 'tb-shown'),
        travelByteCount: 4, onShuffle: () {});
    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final page = tester.widget<StoryExperiencePage>(find.byType(StoryExperiencePage));
    expect(page.story.id, 'tb-shown');
  });

  testWidgets('the shuffle button shows only when the row gives it a job, and does it',
      (tester) async {
    var shuffles = 0;
    await _pumpRow(tester, _travelByte(),
        travelByteCount: 4, onShuffle: () => shuffles++);
    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    expect(shuffles, 1);

    await _pumpRow(tester, _travellersStory());
    expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
  });
}
