import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience_request.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/my_experience_requests_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _request({
  String id = 'r1',
  String status = 'confirmed',
  String? confirmed = '2026-10-20',
  String? lastFree = '2026-10-17',
  bool canCancel = true,
}) =>
    {
      'id': id,
      'package_id': 'p1',
      'package_title': 'Sunset boat ride',
      'vendor_name': 'Lagoon Tours',
      'vendor_whatsapp': '94771234567',
      'preferred_date': '2026-10-20',
      'party_size': 2,
      'status': status,
      'created_at': '2026-10-10T09:00:00Z',
      'confirmed_date': confirmed,
      'free_cancellation_last_day': lastFree,
      'can_cancel': canCancel,
      'late_cancellation': false,
    };

/// My requests and cancel. [cancelled] collects cancel calls.
class _Server implements HttpClientAdapter {
  List<Map<String, dynamic>> requests = [_request()];
  final List<Map<String, dynamic>> cancelled = [];
  final List<Map<String, dynamic>> offerAnswers = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object body;
    if (options.path.endsWith('/enquiries/mine')) {
      body = {'enquiries': requests};
    } else if (options.path.endsWith('/offer')) {
      final answer = Map<String, dynamic>.from(options.data as Map);
      offerAnswers.add(answer);
      final accepted = answer['accept'] == true;
      body = {
        ...requests.first,
        'status': accepted ? 'confirmed' : 'customer_cancelled',
        'confirmed_date': accepted ? requests.first['offered_date'] : null,
        'cancellation_reason': accepted ? null : 'Declined the other date offered',
        'offered_date': null,
      };
    } else if (options.path.endsWith('/cancel')) {
      cancelled.add(Map<String, dynamic>.from(options.data as Map? ?? {}));
      body = {
        ...requests.first,
        'status': 'customer_cancelled',
        'cancelled_at': '2026-10-16T09:00:00Z',
        'can_cancel': false,
      };
    } else {
      body = {};
    }
    return ResponseBody.fromString(json.encode(body), 200, headers: {
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
    ApiClient.reset();
    server = _Server();
    ApiClient.instance.httpClientAdapter = server;
  });

  group('the 72-hour check on the traveller\'s calendar', () {
    final booking = ExperienceRequest.fromJson(_request());

    test('free through the last free day', () {
      expect(booking.isLateToCancel(DateTime(2026, 10, 17, 23, 59)), isFalse);
    });

    test('late from the day after it', () {
      expect(booking.isLateToCancel(DateTime(2026, 10, 18, 0, 1)), isTrue);
    });

    test('a request not yet confirmed is never late', () {
      final request = ExperienceRequest.fromJson(
          _request(status: 'new', confirmed: null, lastFree: null));
      expect(request.isLateToCancel(DateTime(2026, 10, 20)), isFalse);
    });
  });

  test('the list is saved for offline, and dropped on sign-out', () async {
    final fetched = await ExperiencesService.fetchMyRequests();
    expect(fetched?.single.packageTitle, 'Sunset boat ride');
    expect(ExperiencesService.cachedMyRequests()?.single.id, 'r1');

    await CacheService.clearUserData();
    expect(ExperiencesService.cachedMyRequests(), isNull);
  });

  testWidgets('a traveller cancels from the request, with a reason',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: MyExperienceRequestsPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Sunset boat ride'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);

    await tester.tap(find.text('Sunset boat ride'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Free cancellation until the end of'),
        findsOneWidget);

    await tester.tap(find.text('Cancel booking'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this booking?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Flight moved');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel booking'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(server.cancelled.single['reason'], 'Flight moved');
    expect(find.text('Cancelled by you'), findsWidgets);
    expect(find.text('Cancel booking'), findsNothing);
  });

  testWidgets('keeping the request sends nothing', (tester) async {
    tester.view.physicalSize = const Size(1500, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: MyExperienceRequestsPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Sunset boat ride'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel booking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(server.cancelled, isEmpty);
  });

  group('another date offered by the provider', () {
    Future<void> openOffer(WidgetTester tester, _Server server) async {
      server.requests = [
        {
          ..._request(status: 'new', confirmed: null, lastFree: null),
          'offered_date': '2026-10-22',
          'offer_reason': 'Fully booked that day',
        },
      ];
      tester.view.physicalSize = const Size(1500, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: MyExperienceRequestsPage()));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('New date offered'), findsOneWidget);
      await tester.tap(find.text('Sunset boat ride'));
      await tester.pumpAndSettle();
      expect(find.text('Another date offered'), findsOneWidget);
    }

    testWidgets('accepting books it for that date', (tester) async {
      await openOffer(tester, server);
      await tester.tap(find.textContaining('Accept '));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Accept'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(server.offerAnswers.single['accept'], isTrue);
      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('Another date offered'), findsNothing);
    });

    testWidgets('declining cancels the request', (tester) async {
      await openOffer(tester, server);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Decline'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(server.offerAnswers.single['accept'], isFalse);
      expect(find.textContaining('You declined the other date'), findsOneWidget);
    });
  });
}
