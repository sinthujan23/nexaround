import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/pages/package_editor_page.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/pages/vendor_notifications_page.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/pages/vendor_portal_page.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/pages/vendor_profile_tab.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/vendor_ui.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/widgets/availability_calendar.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/widgets/description_editor.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/widgets/vendor_portal_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _traveller = 'Bearer traveller-token';

/// The partner API and the one traveller endpoint that trades for it.
/// Records which token every request carried.
class _Server implements HttpClientAdapter {
  final requests = <({String method, String path, String? auth, Object? body})>[];
  List<Map<String, dynamic>> access = [
    {'vendor_id': 'v1', 'vendor_name': 'Desert Track Tourism', 'logo_url': null},
  ];
  int sessionStatus = 200;
  bool agreementRequired = false;
  int trades = 0;

  /// No network at all: every call fails before reaching the server.
  bool offline = false;

  /// Where the vendor's edits to package p1 stand.
  Map<String, dynamic> p1Review = {};

  /// The one request the vendor has, as the partner API sends it.
  Map<String, dynamic> request = {
    'id': 'r1', 'reference': '#BBCB96', 'package_id': 'p1', 'package_title': 'Desert Safari',
    'preferred_date': '2030-11-02', 'confirmed_date': null, 'party_size': 4,
    'price_label': 'QAR 499 / group (max 7)', 'status': 'new', 'vendor_response': null,
    'vendor_offered_date': null, 'vendor_response_reason': null, 'vendor_responded_at': null,
    'can_answer': true, 'created_at': '2026-10-22T08:10:00Z',
  };

  /// Partner tokens the server no longer accepts (expired).
  final Set<String> expired = {};

  Map<String, dynamic> get _me => {
        'login_id': 'l1',
        'email': null,
        'display_name': 'Ilham',
        'vendor_id': 'v1',
        'vendor_name': 'Desert Track Tourism',
        'vendor_is_active': true,
      };

  Map<String, dynamic> _agreement() => {
        'document': {
          'kind': 'provider_agreement',
          'version': 2,
          'title': 'Provider Agreement',
          'body': '## Bookings\n\nNexAround arranges every booking.',
          'highlights': <String>[],
          'published_at': '2026-10-16T09:00:00Z',
          'updated_at': '2026-10-16T09:00:00Z',
        },
        'accepted_version': agreementRequired ? null : 2,
        'required': agreementRequired,
        'grace_ends_at': '2026-11-16T09:00:00Z',
        'listed': true,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final path = options.path.replaceFirst('/api/v1/partner', '');
    final auth = options.headers['Authorization'] as String?;
    if (offline) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    requests.add((method: options.method, path: path, auth: auth, body: options.data));
    var status = 200;
    Object body = {};

    if (path == '/app/access') {
      body = {'vendors': access};
    } else if (path == '/app/session') {
      status = sessionStatus;
      trades++;
      body = status == 200
          ? {'access_token': 'partner-$trades', 'refresh_token': null, 'token_type': 'bearer', 'me': _me}
          : {'detail': "You don't manage this business."};
    } else if (auth != null && expired.contains(auth.replaceFirst('Bearer ', ''))) {
      status = 401;
      body = {'detail': 'Could not validate credentials'};
    } else if (path == '/agreement') {
      body = _agreement();
    } else if (path == '/agreement/accept') {
      agreementRequired = false;
      body = _agreement();
    } else if (path == '/stats') {
      body = {'packages_total': 2, 'packages_published': 1};
    } else if (path == '/packages' && options.method == 'GET') {
      body = {
        'packages': [
          {'id': 'p1', 'vendor_id': 'v1', 'title': 'Desert Safari', 'price_amount': 499,
           'price_currency': 'QAR', 'is_active': true, 'is_published': true, 'category': 'adventure',
           ...p1Review},
        ],
      };
    } else if (path == '/packages/p1' && options.method == 'GET') {
      body = {'id': 'p1', 'vendor_id': 'v1', 'title': 'Desert Safari', 'price_amount': 499,
              'price_currency': 'QAR', 'is_active': true, 'is_published': true, 'category': 'adventure',
              ...p1Review};
    } else if (path == '/packages' && options.method == 'POST') {
      body = {...Map<String, dynamic>.from(options.data as Map), 'id': 'p2', 'vendor_id': 'v1'};
    } else if (path == '/requests') {
      body = {'requests': [request], 'total': 1, 'waiting': request['vendor_response'] == null ? 1 : 0};
    } else if (path == '/requests/r1') {
      body = request;
    } else if (path == '/requests/r1/answer') {
      final answer = Map<String, dynamic>.from(options.data as Map);
      request = {
        ...request,
        'vendor_response': answer['action'],
        'status': switch (answer['action']) {
          'confirmed' => 'confirmed',
          'cancelled' => 'provider_cancelled',
          _ => 'new',
        },
        'confirmed_date': answer['action'] == 'confirmed' ? request['preferred_date'] : null,
        'vendor_offered_date': answer['day'],
        'can_answer': answer['action'] == 'other_date',
      };
      body = request;
    } else if (path == '/reviews') {
      body = {'reviews': [], 'total': 0, 'review_count': 0, 'unanswered': 0};
    } else if (path == '/profile') {
      body = {'id': 'v1', 'name': 'Desert Track Tourism', 'country_code': 'QA', 'is_active': true,
              'photo_urls': [], 'website': 'https://deserttrack.example', 'city': 'Doha'};
    } else if (path == '/activity/unread') {
      body = {'unread': 1, 'seen_at': null};
    } else if (path == '/activity') {
      body = {
        'items': [
          {'id': 'a1', 'kind': 'request.received', 'title': 'New request: Desert Safari',
           'body': 'Sun 25 Oct · 4 guests. NexAround will contact you to arrange it.',
           'actor': 'traveller', 'created_at': '2026-10-21T10:00:00Z'},
        ],
        'has_more': false, 'unread': 1, 'seen_at': '2026-10-20T10:00:00Z',
      };
    } else if (path == '/activity/seen') {
      body = {'unread': 0, 'seen_at': '2026-10-21T11:00:00Z'};
    } else if (path == '/auth/logout') {
      body = {'status': 'ok', 'message': 'Signed out.'};
    } else {
      status = 404;
      body = {'detail': 'Not Found'};
    }
    return ResponseBody.fromString(json.encode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _access = VendorAccess(vendorId: 'v1', vendorName: 'Desert Track Tourism');

void main() {
  late _Server server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'access_token': 'traveller-token', 'is_logged_in': true});
    await CacheService.init();
    ApiClient.reset();
    server = _Server();
    ApiClient.instance.httpClientAdapter = server;
    VendorPortalApi.testAdapter = server;
    // CacheService keeps its prefs from test to test: start with nothing kept.
    await CacheService.removeCachedVendor('v1');
    await CacheService.cacheVendorAccess([]);
  });

  tearDown(() => VendorPortalApi.testAdapter = null);

  /// Closing the portal signs the vendor session out; let that finish.
  Future<void> closePortal(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpPortal(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: VendorPortalPage(access: _access)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('signing in', () {
    testWidgets('the traveller token is used only to trade for the vendor session', (tester) async {
      await pumpPortal(tester);
      expect(find.text('Desert Track Tourism'), findsWidgets);

      final partnerCalls = server.requests.where((r) => r.path != '/app/session').toList();
      expect(partnerCalls, isNotEmpty);
      expect(partnerCalls.every((r) => r.auth == 'Bearer partner-1'), isTrue,
          reason: partnerCalls.map((r) => '${r.path} ${r.auth}').join('\n'));
      final trade = server.requests.singleWhere((r) => r.path == '/app/session');
      expect(trade.auth, _traveller);
      expect(trade.body, {'vendor_id': 'v1'});

      await closePortal(tester);
      expect(server.requests.last.path, '/auth/logout');
      expect(server.requests.last.auth, 'Bearer partner-1');
    });

    testWidgets('an access that was taken away says so', (tester) async {
      server.sessionStatus = 404;
      await pumpPortal(tester);
      expect(find.textContaining('no longer have access'), findsOneWidget);
      await closePortal(tester);
    });

    testWidgets('the Provider Agreement comes first until it is accepted', (tester) async {
      server.agreementRequired = true;
      await pumpPortal(tester);
      expect(find.text('I accept the Provider Agreement'), findsOneWidget);
      expect(find.text('Packages'), findsNothing);

      // Not before the "I am authorised" box is ticked: the server refuses it.
      await tester.tap(find.text('I accept the Provider Agreement'));
      await tester.pump();
      expect(server.requests.where((r) => r.path == '/agreement/accept'), isEmpty);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('I accept the Provider Agreement'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final accept = server.requests.singleWhere((r) => r.path == '/agreement/accept');
      expect(accept.body, {'version': 2, 'authorised': true});
      expect(find.text('Packages'), findsOneWidget);
      await closePortal(tester);
    });

    test('an expired vendor session is traded again once, then the call retried', () async {
      final api = VendorPortalApi('v1');
      await api.signIn();
      server.expired.add('partner-1');
      final stats = await api.stats();
      expect(stats.packagesPublished, 1);
      expect(server.trades, 2);
      expect(server.requests.where((r) => r.path == '/stats').map((r) => r.auth),
          ['Bearer partner-1', 'Bearer partner-2']);
    });
  });

  group('the button in Experiences', () {
    testWidgets('shows for a traveller who manages a business', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VendorPortalBanner())));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Vendor portal'), findsOneWidget);
      expect(find.text('Manage Desert Track Tourism'), findsOneWidget);
    });

    testWidgets('takes no room for everyone else', (tester) async {
      server.access = [];
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VendorPortalBanner())));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Vendor portal'), findsNothing);
    });
  });

  testWidgets('a request shows as package, date and guests, and the feed is marked seen',
      (tester) async {
    final api = VendorPortalApi('v1');
    await tester.pumpWidget(MaterialApp(home: VendorNotificationsPage(api: api)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('New request: Desert Safari'), findsOneWidget);
    expect(find.text('Sun 25 Oct · 4 guests. NexAround will contact you to arrange it.'), findsOneWidget);
    expect(server.requests.where((r) => r.path == '/activity/seen'), hasLength(1));
  });

  testWidgets('a new package is sent as the web portal sends it', (tester) async {
    final api = VendorPortalApi('v1');
    await tester.pumpWidget(MaterialApp(home: PackageEditorPage(api: api)));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Title *'), 'Dune bashing at sunset');
    await tester.tap(find.text('Send for review'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final create = server.requests.singleWhere((r) => r.path == '/packages' && r.method == 'POST');
    final body = Map<String, dynamic>.from(create.body as Map);
    expect(body['title'], 'Dune bashing at sunset');
    expect(body['is_active'], isTrue);
    // Where travellers meet the vendor is NexAround's to set.
    expect(body.containsKey('uses_vendor_location'), isFalse);
    expect(body.containsKey('meeting_point_address'), isFalse);
    expect(body.containsKey('latitude'), isFalse);
    expect(body['price_amount'], isNull);
    expect(create.auth, 'Bearer partner-1');
  });

  testWidgets('a package can be saved hidden, as with the web editor\'s switch', (tester) async {
    final api = VendorPortalApi('v1');
    await tester.pumpWidget(MaterialApp(home: PackageEditorPage(api: api)));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Title *'), 'Draft trip');
    await tester.tap(find.text('Show in the app'));
    await tester.pump();
    expect(find.text('Hidden (draft)'), findsOneWidget);
    await tester.tap(find.text('Send for review'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final create = server.requests.singleWhere((r) => r.path == '/packages' && r.method == 'POST');
    expect(Map<String, dynamic>.from(create.body as Map)['is_active'], isFalse);
  });

  testWidgets('a package can be sold at two prices', (tester) async {
    final api = VendorPortalApi('v1');
    await tester.pumpWidget(MaterialApp(home: PackageEditorPage(api: api)));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Title *'), 'Pigeon Island');

    // The form is a lazy list: scroll a field into being, then to the middle
    // of the screen, clear of the Create bar, before using it.
    Future<void> reach(Finder f) async {
      await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await Scrollable.ensureVisible(tester.element(f.first), alignment: 0.5);
      await tester.pump();
    }

    Future<void> tap(Finder f) async {
      await reach(f);
      await tester.tap(f);
      await tester.pump();
    }

    Future<void> type(Finder f, String text) async {
      await reach(f);
      await tester.enterText(f, text);
    }

    final price = find.widgetWithText(TextFormField, 'Price (LKR)');
    await type(price, '30000');
    await tap(find.text('Add price option'));
    await reach(find.text('Option 2'));
    await tester.enterText(price.at(1), '8000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Min people').at(1), '3');
    // A third, then removed again: the second keeps what was typed in it.
    await tap(find.text('Add price option'));
    await reach(find.text('Option 3'));
    await tester.tap(find.text('Remove').last);
    await tester.pump();
    expect(find.text('Option 3'), findsNothing);
    expect(find.text('8000'), findsOneWidget);

    await tester.tap(find.text('Send for review'), warnIfMissed: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final create = server.requests.singleWhere((r) => r.path == '/packages' && r.method == 'POST');
    final options = (Map<String, dynamic>.from(create.body as Map)['price_options'] as List)
        .cast<Map<String, dynamic>>();
    expect(options.map((o) => o['amount']), [30000, 8000]);
    expect(options[1]['min_people'], 3);
    expect(options.every((o) => !o.containsKey('usd')), isTrue);
  });

  group('NexAround checks the changes', () {
    testWidgets('a package sent back shows NexAround\'s note, in the editor and the list', (tester) async {
      server.p1Review = {'review_status': 'changes_requested', 'review_note': 'Use a photo of the boat.'};
      await pumpPortal(tester);
      await tester.tap(find.text('Packages'));
      await tester.pump();
      expect(find.text('Changes needed'), findsOneWidget);
      await closePortal(tester);

      await tester.pumpWidget(MaterialApp(home: PackageEditorPage(api: VendorPortalApi('v1'), packageId: 'p1')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('NexAround asked for changes'), findsOneWidget);
      expect(find.text('Use a photo of the boat.'), findsOneWidget);
    });

    testWidgets('a new package waiting for approval says it is not live yet', (tester) async {
      server.p1Review = {'review_status': 'pending', 'is_approved': false, 'is_published': false};
      await pumpPortal(tester);
      await tester.tap(find.text('Packages'));
      await tester.pump();
      expect(find.text('Not live yet'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
      await closePortal(tester);
    });

    testWidgets('the website and where the business is are shown, not edited', (tester) async {
      await pumpPortal(tester);
      await tester.tap(find.text('Profile'));
      await tester.pump();
      // The "Set by NexAround" list is at the foot of the form.
      await tester.scrollUntilVisible(find.text('https://deserttrack.example'), 300,
          scrollable: find.descendant(of: find.byType(VendorProfileTab), matching: find.byType(Scrollable)).first);
      expect(find.text('https://deserttrack.example'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Website'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Address'), findsNothing);
      expect(find.text('Doha'), findsOneWidget);
      await closePortal(tester);
    });
  });

  group('requests', () {
    Future<void> openRequests(WidgetTester tester) async {
      await pumpPortal(tester);
      await tester.tap(find.text('Requests'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('a request shows package, date, guests and price, and is confirmed in one tap', (tester) async {
      await openRequests(tester);
      expect(find.text('Desert Safari'), findsWidgets);
      expect(find.text('Sat 2 Nov 2030'), findsOneWidget);
      expect(find.text('QAR 499 / group (max 7)'), findsOneWidget);
      expect(find.text('Waiting for your answer'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.tap(find.text('Confirm booking'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final answer = server.requests.singleWhere((r) => r.path == '/requests/r1/answer');
      expect(Map<String, dynamic>.from(answer.body as Map)['action'], 'confirmed');
      await closePortal(tester);
    });

    testWidgets('with no other date the vendor cancels, giving a reason', (tester) async {
      await openRequests(tester);
      await tester.tap(find.text('Can’t do this date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No other date'));
      await tester.pump();
      await tester.tap(find.text('Why not the date asked?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fully booked that day').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Note to NexAround (optional)'), 'Busy week');
      await tester.tap(find.text('Cancel request'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final body = Map<String, dynamic>.from(
          server.requests.singleWhere((r) => r.path == '/requests/r1/answer').body as Map);
      expect(body['action'], 'cancelled');
      expect(body['reason'], 'fully_booked');
      expect(body['note'], 'Busy week');
      await closePortal(tester);
    });

    testWidgets('a push about a request opens it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VendorPortalPage(access: _access, requestId: 'r1')));
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(server.requests.where((r) => r.path == '/requests/r1'), isNotEmpty);
      expect(find.byType(BottomSheet), findsOneWidget);
      await closePortal(tester);
    });
  });

  group('what the device keeps', () {
    testWidgets('a second visit opens on the kept packages, even offline', (tester) async {
      await pumpPortal(tester);
      expect(find.text('Desert Safari'), findsOneWidget);
      await closePortal(tester);

      server.offline = true;
      await pumpPortal(tester);
      expect(find.text('Desert Track Tourism'), findsWidgets);
      expect(find.text('Desert Safari'), findsOneWidget);
      expect(find.text('Showing saved data. Pull down to refresh.'), findsOneWidget);
      await closePortal(tester);
    });

    testWidgets('a kept list cannot switch a package off: that saves the whole package',
        (tester) async {
      await pumpPortal(tester);
      await closePortal(tester);

      server.offline = true;
      await pumpPortal(tester);
      await tester.tap(find.text('Packages'));
      await tester.pump();
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
      await closePortal(tester);
    });

    testWidgets('the editor shows the list\'s copy but saves only the server\'s', (tester) async {
      server.offline = true;
      final api = VendorPortalApi('v1');
      await tester.pumpWidget(MaterialApp(
        home: PackageEditorPage(
          api: api,
          packageId: 'p1',
          initial: const VendorPackage(id: 'p1', title: 'Desert Safari (kept)', isPublished: true),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Desert Safari (kept)'), findsOneWidget);
      expect(find.text('Showing the saved copy. Connect to save changes.'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(find.textContaining('Can’t reach NexAround'), findsOneWidget);

      // Back online: the server's copy replaces the kept one, then saves.
      server.offline = false;
      await tester.tap(find.text('Save changes'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Desert Safari'), findsOneWidget);
      expect(server.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('changes typed on a kept copy move onto the fresh one', () {
      final base = {'title': 'Boat', 'summary': 'old', 'photo_urls': ['a']};
      final mine = {'title': 'Boat trip', 'summary': 'old', 'photo_urls': ['a']};
      final fresh = {'title': 'Boat', 'summary': 'new', 'photo_urls': ['a', 'b']};
      expect(rebaseEdits(base, mine, fresh), {
        'title': 'Boat trip',
        'summary': 'new',
        'photo_urls': ['a', 'b'],
      });
    });

    test('signing out drops what was kept', () async {
      final api = VendorPortalApi('v1');
      await api.stats();
      await VendorPortalApi.access();
      expect(api.cachedStats(), isNotNull);
      expect(VendorPortalApi.cachedAccess(), isNotEmpty);
      await CacheService.clearUserData();
      expect(api.cachedStats(), isNull);
      expect(VendorPortalApi.cachedAccess(), isEmpty);
    });
  });

  group('the forms', () {
    test('blocked days join into ranges and split back', () {
      final days = {
        DateTime(2026, 10, 25), DateTime(2026, 10, 26), DateTime(2026, 10, 27),
        DateTime(2026, 11, 2),
      };
      final ranges = rangesOf(days);
      expect(ranges, [
        BlockedRange(DateTime(2026, 10, 25), DateTime(2026, 10, 27)),
        BlockedRange(DateTime(2026, 11, 2), DateTime(2026, 11, 2)),
      ]);
      expect(blockedDays(ranges), days);
      expect(ranges.first.toJson(), {'start': '2026-10-25', 'end': '2026-10-27'});
      // Across a month end.
      expect(rangesOf({DateTime(2026, 10, 31), DateTime(2026, 11, 1)}),
          [BlockedRange(DateTime(2026, 10, 31), DateTime(2026, 11, 1))]);
    });

    test('no package or profile body carries where the vendor is', () {
      const elsewhere = VendorPackage(title: 'Boat', usesVendorLocation: false, latitude: 25.1, longitude: 51.5);
      expect(elsewhere.toJson().keys, isNot(contains('latitude')));
      const profile = VendorProfile(name: 'Boat Co', website: 'https://x.example', address: 'Jetty 3', city: 'Doha');
      expect(profile.toJson().keys, unorderedEquals(['name', 'description', 'contact_email', 'logo_url', 'photo_urls']));
      final pkg = VendorPackage.fromJson({
        'id': 'p1', 'title': 'Boat', 'unavailable_ranges': [{'start': '2026-10-25', 'end': '2026-10-26'}],
        'price_amount': 7500, 'price_currency': 'LKR', 'is_published': true, 'is_active': true,
      });
      expect(pkg.visibility, 'Live');
      expect(pkg.copyWith(isActive: false).visibility, 'Hidden');
      expect(pkg.toJson()['unavailable_ranges'], [{'start': '2026-10-25', 'end': '2026-10-26'}]);
    });

    test('the description buttons write the Markdown the web editor writes', () {
      var edit = MarkdownEdit.bold('Bring water', const TextSelection(baseOffset: 6, extentOffset: 11));
      expect(edit.text, 'Bring **water**');
      edit = MarkdownEdit.prefixLines('Day one\nDay two', const TextSelection(baseOffset: 0, extentOffset: 15), '- ');
      expect(edit.text, '- Day one\n- Day two');
      edit = MarkdownEdit.prefixLines(edit.text, TextSelection(baseOffset: 0, extentOffset: edit.text.length), '- ');
      expect(edit.text, 'Day one\nDay two');
      edit = MarkdownEdit.prefixLines('Itinerary', const TextSelection.collapsed(offset: 3), '## ');
      expect(edit.text, '## Itinerary');
    });

    test('prices and currencies match the web portal', () {
      expect(formatPrice(7500, 'LKR'), 'LKR 7,500');
      expect(formatPrice(null, 'LKR'), 'On request');
      expect(packageCurrencies.map((c) => c['code']), isNot(contains('KPW')));
      expect(packageCurrencies.map((c) => c['code']), contains('QAR'));
      expect(vendorCategories.map((c) => c.value), contains('other'));
      expect(categoryLabel('other'), 'Other');
    });
  });
}
