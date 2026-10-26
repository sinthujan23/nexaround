import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_request_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/legal_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The terms endpoint and the enquiry endpoint. [enquiryStatus] lets a test
/// make the server refuse with 409, as when the terms changed mid-request.
class _Server implements HttpClientAdapter {
  int termsVersion = 1;
  bool termsAccepted = false;
  int enquiryStatus = 201;
  final List<Map<String, dynamic>> enquiries = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    late final Object body;
    var status = 200;
    if (options.path.endsWith('/legal/experience_customer')) {
      body = {
        'kind': 'experience_customer',
        'version': termsVersion,
        'title': 'Experience Booking Terms',
        'body': '## Payment\n\nPay the provider on the day.',
        'highlights': ['Pay the provider directly at the location.'],
        'published_at': '2026-10-16T09:00:00Z',
        'updated_at': '2026-10-16T09:00:00Z',
        'accepted': termsAccepted,
      };
    } else {
      enquiries.add(Map<String, dynamic>.from(options.data as Map));
      status = enquiryStatus;
      body = status == 409
          ? {
              'detail': 'The Experience Booking Terms have been updated. '
                  'Please review and accept them to continue.',
            }
          : {'id': 'e1', 'status': 'new', 'created_at': '2026-10-16T09:00:00Z'};
    }
    return ResponseBody.fromString(json.encode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _package = ExperiencePackageEntity(
  id: 'p1',
  title: 'Sunset boat ride',
  vendorId: 'v1',
  vendorName: 'Lagoon Tours',
  latitude: 6,
  longitude: 80,
);

void main() {
  late _Server server;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  setUp(() async {
    await CacheService.clearAll();
    ApiClient.reset();
    server = _Server();
    ApiClient.instance.httpClientAdapter = server;
  });

  group('the document format', () {
    test('headings, bullets and paragraphs are told apart', () {
      final blocks = parseLegalBody(
        '## Payment\n\nPay on the day.\n\n- Cash\n- Card\n\nSecond\nline.',
      );

      expect(blocks.map((b) => b.type), [
        LegalBlockType.heading,
        LegalBlockType.paragraph,
        LegalBlockType.bullet,
        LegalBlockType.bullet,
        LegalBlockType.paragraph,
      ]);
      expect(blocks.first.text, 'Payment');
      // A hard-wrapped paragraph reads as one.
      expect(blocks.last.text, 'Second line.');
    });
  });

  group('the service', () {
    test('fetched terms are saved, and dropped on sign-out', () async {
      expect(ExperiencesService.cachedTerms(), isNull);

      final terms = await ExperiencesService.fetchTerms();
      expect(terms?.version, 1);
      expect(ExperiencesService.cachedTerms()?.highlights, isNotEmpty);

      await CacheService.clearUserData();
      expect(ExperiencesService.cachedTerms(), isNull);
    });

    test('a request carries the accepted version and marks it accepted',
        () async {
      await ExperiencesService.fetchTerms();

      final result = await ExperiencesService.submitEnquiry(
        packageId: 'p1',
        contactName: 'Test Traveller',
        contactPhone: '715550000',
        acceptedTermsVersion: 1,
      );

      expect(result.sent, isTrue);
      expect(server.enquiries.single['accepted_terms_version'], 1);
      expect(ExperiencesService.cachedTerms()?.accepted, isTrue);
    });

    test('a 409 reports that the terms changed', () async {
      server.enquiryStatus = 409;

      final result = await ExperiencesService.submitEnquiry(
        packageId: 'p1',
        contactName: 'Test Traveller',
        contactPhone: '715550000',
        acceptedTermsVersion: 1,
      );

      expect(result.sent, isFalse);
      expect(result.termsChanged, isTrue);
      expect(result.error, contains('updated'));
    });
  });

  group('the request page', () {
    Future<void> openSheet(WidgetTester tester, {bool fill = true}) async {
      tester.view.physicalSize = const Size(1500, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExperienceRequestPage(context, _package),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (!fill) return;
      await tester.enterText(
          find.widgetWithText(TextField, 'Your name'), 'Test Traveller');
      await tester.enterText(
          find.widgetWithText(TextField, 'Phone number'), '715550000');
    }

    testWidgets('the close button leaves at once when nothing was typed',
        (tester) async {
      await openSheet(tester, fill: false);
      expect(find.text('Request this experience'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Request this experience'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('closing after typing asks before discarding', (tester) async {
      await openSheet(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this request?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Request this experience'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Request this experience'), findsNothing);
    });

    Future<void> send(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Send request'));
      await tester.tap(find.text('Send request'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('nothing is sent until the terms are ticked', (tester) async {
      await openSheet(tester);

      expect(find.text('Before you send'), findsOneWidget);
      await send(tester);
      expect(server.enquiries, isEmpty);
      expect(find.text('Tick the box to agree to the terms before sending.'),
          findsOneWidget);

      // Below the fold on the full-page form.
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await send(tester);

      expect(server.enquiries.single['accepted_terms_version'], 1);
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Good to know'), findsOneWidget);
    });

    testWidgets('a traveller who accepted this version sees a reminder instead',
        (tester) async {
      server.termsAccepted = true;
      await openSheet(tester);

      expect(find.byType(Checkbox), findsNothing);
      expect(
        find.textContaining('By sending this request you agree to the',
            findRichText: true),
        findsOneWidget,
      );
      await send(tester);
      expect(server.enquiries.single['accepted_terms_version'], 1);
    });

    testWidgets('terms changed mid-request are shown again to accept',
        (tester) async {
      server.termsAccepted = true;
      await openSheet(tester);
      server
        ..enquiryStatus = 409
        ..termsVersion = 2
        ..termsAccepted = false;

      await send(tester);

      expect(find.textContaining('have been updated'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });
  });

  group('a package with several prices', () {
    const twoPrices = ExperiencePackageEntity(
      id: 'p2',
      title: 'Pigeon Island snorkeling',
      vendorId: 'v1',
      vendorName: 'Blue Ocean Adventures',
      latitude: 6,
      longitude: 80,
      priceLabel: r'LKR 30,000 ($90) / group (max 7)',
      priceOptions: [
        ExperiencePriceOption(id: 'a', label: r'LKR 30,000 ($90) / group (max 7)',
            basis: 'per_group', maxPeople: 7),
        ExperiencePriceOption(id: 'b', label: r'LKR 8,000 ($24) / person (min 3)',
            minPeople: 3, maxPeople: 7),
      ],
    );

    Future<void> open(WidgetTester tester, ExperiencePackageEntity package) async {
      server.termsAccepted = true;
      tester.view.physicalSize = const Size(1500, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExperienceRequestPage(context, package),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.enterText(
          find.widgetWithText(TextField, 'Your name'), 'Test Traveller');
      await tester.enterText(
          find.widgetWithText(TextField, 'Phone number'), '715550000');
    }

    Future<void> send(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Send request'));
      await tester.tap(find.text('Send request'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the first price is chosen until another is picked', (tester) async {
      await open(tester, twoPrices);

      expect(find.text('Price'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
      expect(find.text('Up to 7 guests for this experience'), findsOneWidget);
      await send(tester);

      expect(server.enquiries.single['price_option_id'], 'a');
      expect(server.enquiries.single['party_size'], 2);
    });

    testWidgets('a per-person price with a minimum raises the guests to it',
        (tester) async {
      await open(tester, twoPrices);

      await tester.ensureVisible(find.text(r'LKR 8,000 ($24) / person (min 3)'));
      await tester.tap(find.text(r'LKR 8,000 ($24) / person (min 3)'));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);

      await send(tester);
      expect(server.enquiries.single['price_option_id'], 'b');
      expect(server.enquiries.single['party_size'], 3);
    });

    testWidgets('below a price\'s minimum, the price that fits is chosen', (tester) async {
      await open(tester, twoPrices);
      await tester.ensureVisible(find.text(r'LKR 8,000 ($24) / person (min 3)'));
      await tester.tap(find.text(r'LKR 8,000 ($24) / person (min 3)'));
      await tester.pump();
      await _tapMid(tester, find.byIcon(Icons.remove_rounded));
      expect(find.text('2'), findsOneWidget);
      await send(tester);
      expect(server.enquiries.single['price_option_id'], 'a');
      expect(server.enquiries.single['party_size'], 2);
    });

    testWidgets('per-boat bands follow the guests, and the boat\'s size is the limit', (tester) async {
      const bands = ExperiencePackageEntity(
        id: 'p3',
        title: 'Dolphin Watching Adventure',
        vendorId: 'v1',
        vendorName: 'Blue Ocean Adventures',
        latitude: 6,
        longitude: 80,
        maxParticipants: 7,
        priceLabel: r'LKR 28,000 ($84) / group (min 2, max 3)',
        priceOptions: [
          ExperiencePriceOption(id: 'a', label: r'LKR 28,000 ($84) / group (min 2, max 3)',
              basis: 'per_group', minPeople: 2, maxPeople: 3),
          ExperiencePriceOption(id: 'b', label: r'LKR 30,000 ($90) / group (min 4, max 5)',
              basis: 'per_group', minPeople: 4, maxPeople: 5),
          ExperiencePriceOption(id: 'c', label: r'LKR 33,000 ($99) / group (min 6, max 7)',
              basis: 'per_group', minPeople: 6, maxPeople: 7),
        ],
      );
      await open(tester, bands);
      expect(find.text('2–7 guests for this experience'), findsOneWidget);

      // The + button's own handler (null once the boat is full).
      Future<void> plus(int times) async {
        for (var i = 0; i < times; i++) {
          final button = tester.widget<GestureDetector>(find
              .ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(GestureDetector))
              .first);
          button.onTap?.call();
          await tester.pump();
        }
      }

      // 2 -> 4 guests: the 4–5 band.
      await plus(2);
      expect(find.text('4'), findsOneWidget);
      // 4 -> 9 taps: stops at 7, the 6–7 band.
      await plus(5);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('8'), findsNothing);
      await send(tester);
      expect(server.enquiries.single['price_option_id'], 'c');
      expect(server.enquiries.single['party_size'], 7);
    });

    testWidgets('a package with no prices sends no option', (tester) async {
      await open(tester, _package);

      expect(find.text('Price'), findsNothing);
      await send(tester);
      expect(server.enquiries.single.containsKey('price_option_id'), isFalse);
    });
  });
}

/// Taps [finder] scrolled to mid-screen, clear of the fixed Send bar.
Future<void> _tapMid(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}
