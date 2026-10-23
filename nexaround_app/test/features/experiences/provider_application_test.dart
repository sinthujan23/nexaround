import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/provider_application_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_package_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every request; answers the application and the list.
class _Server implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final Object body = options.path.endsWith('/provider-applications')
        ? {'id': 'a1', 'status': 'new'}
        : {'packages': [], 'total': 0, 'country_mode': true};
    return ResponseBody.fromString(json.encode(body), 201, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Server server;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  setUp(() async {
    await CacheService.clearAll();
    await CacheService.setExperienceCurrency(null);
    ApiClient.reset();
    server = _Server();
    ApiClient.instance.httpClientAdapter = server;
  });

  group('List your experience', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ProviderApplicationPage()));
      await tester.pump();
    }

    Future<void> send(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Send my details'));
      await tester.tap(find.text('Send my details'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('nothing is sent until the required details are there', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Business name'), 'Blue Ocean Adventures');
      await send(tester);
      expect(server.requests, isEmpty);
      expect(find.text('Please enter your phone number.'), findsOneWidget);
    });

    testWidgets('a complete form reaches NexAround and says thanks', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Business name'), 'Blue Ocean Adventures');
      await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Ravi');
      await tester.enterText(find.byType(TextField).at(2), '771234567');
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'info@blueocean.lk');
      await tester.enterText(find.widgetWithText(TextField, 'City or town (optional)'), 'Trincomalee');
      await tester.enterText(find.widgetWithText(TextField, 'What do you offer?'),
          'Snorkeling and dolphin trips, LKR 7,000 per person.');
      await send(tester);

      final body = Map<String, dynamic>.from(server.requests.single.data as Map);
      expect(body['business_name'], 'Blue Ocean Adventures');
      expect(body['contact_phone'], startsWith('+'));
      expect(body['contact_phone'], endsWith('771234567'));
      expect(body['country_code'], hasLength(2));
      expect(body['city'], 'Trincomalee');
      expect(body.containsKey('links'), isFalse);
      expect(find.text('Thanks! We’ve got your details'), findsOneWidget);
    });
  });

  group('the currency the traveller picks', () {
    test('is sent with the list, and the original prices send none', () async {
      await ExperiencesService.fetchNearby();
      expect(server.requests.last.queryParameters.containsKey('currency'), isFalse);

      await CacheService.setExperienceCurrency('INR');
      await ExperiencesService.fetchNearby();
      expect(server.requests.last.queryParameters['currency'], 'INR');
    });

    testWidgets('the card shows the converted price when there is one', (tester) async {
      const package = ExperiencePackageEntity(
        id: 'p1',
        title: 'Doha City Tour',
        vendorId: 'v',
        vendorName: 'Desert Track Tourism',
        priceAmount: 475,
        priceCurrency: 'QAR',
        priceBasis: 'per_group',
        priceLabel: r'QAR 475 ($130) / group (max 6)',
        displayLabel: '≈ INR 12,350 / group (max 6)',
        latitude: 0,
        longitude: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ExperiencePackageCard(package: package, index: 0, onTap: () {}),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('≈ INR 12,350'), findsOneWidget);
      expect(find.text('per group (max 6)'), findsOneWidget);
    });
  });
}
