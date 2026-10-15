import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experiences_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two endpoints the tab calls, with the admin's switch set to [countryMode].
class _ServerAdapter implements HttpClientAdapter {
  final bool countryMode;
  final List<String> paths = [];

  _ServerAdapter({required this.countryMode});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.uri.toString());
    final body = options.path.endsWith('/countries')
        ? {'countries': [], 'country_mode': countryMode}
        : {
            'packages': [],
            'total': 0,
            'has_nearby': true,
            'country_mode': countryMode,
          };
    return ResponseBody.fromString(json.encode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  Future<_ServerAdapter> pumpTab(WidgetTester tester,
      {required bool countryMode}) async {
    await CacheService.clearAll();
    ApiClient.reset();
    final adapter = _ServerAdapter(countryMode: countryMode);
    ApiClient.instance.httpClientAdapter = adapter;

    // Wider than a phone: the test font draws every letter as a full square,
    // so the hero's fixed-height title would wrap and overflow at 360 wide.
    tester.view.physicalSize = const Size(1500, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // No location: the case where the two modes differ most.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ExperiencesTab()),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return adapter;
  }

  testWidgets('country mode lists every country without a location',
      (tester) async {
    final adapter = await pumpTab(tester, countryMode: true);

    expect(adapter.paths.any((p) => p.contains('/experiences/nearby')), isTrue);
    expect(find.text('All countries'), findsOneWidget);
    expect(find.text('ALL COUNTRIES'), findsOneWidget);
    expect(find.text('Near Me'), findsNothing);
    expect(find.textContaining('Turn on location'), findsNothing);
  });

  testWidgets('nearest-first mode still asks for location', (tester) async {
    final adapter = await pumpTab(tester, countryMode: false);

    expect(adapter.paths.any((p) => p.contains('/experiences/nearby')), isFalse);
    expect(find.text('Near Me'), findsOneWidget);
    expect(find.text('All countries'), findsNothing);
    expect(find.textContaining('Turn on location'), findsWidgets);
  });
}
