import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every request with [status] and [body], or fails like a dropped
/// connection when [offline] is set. Keeps the last request for inspection.
class _FakeAdapter implements HttpClientAdapter {
  int status = 200;
  Object? body;
  bool offline = false;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    if (offline) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'offline');
    }
    return ResponseBody.fromString(json.encode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _package(String id, {double? distanceM}) => {
      'id': id,
      'title': 'Boat ride $id',
      'vendor_id': 'v1',
      'vendor_name': 'Lagoon Tours',
      'latitude': 6.0,
      'longitude': 80.0,
      'distance_m': distanceM,
      'description': 'Two hours on the lagoon',
    };

void main() {
  late _FakeAdapter adapter;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  setUp(() async {
    await CacheService.clearAll();
    ApiClient.reset();
    adapter = _FakeAdapter();
    ApiClient.instance.httpClientAdapter = adapter;
  });

  group('nearby list', () {
    setUp(() {
      adapter.body = {
        'packages': [_package('a', distanceM: 900)],
        'total': 1,
        'nearest_distance_m': 900,
        'has_nearby': true,
      };
    });

    test('a fetched first page is served from the same spot', () async {
      expect(ExperiencesService.cachedNearby(latitude: 6, longitude: 80), isNull);

      await ExperiencesService.fetchNearby(latitude: 6, longitude: 80);
      final saved =
          ExperiencesService.cachedNearby(latitude: 6.001, longitude: 80);

      expect(saved?.packages.single.id, 'a');
      expect(saved?.total, 1);
      expect(saved?.hasNearby, isTrue);
    });

    test('is not served once the user has moved away', () async {
      await ExperiencesService.fetchNearby(latitude: 6, longitude: 80);

      // About 5.5 km north.
      expect(ExperiencesService.cachedNearby(latitude: 6.05, longitude: 80),
          isNull);
    });

    test('is kept per filter', () async {
      await ExperiencesService.fetchNearby(latitude: 6, longitude: 80);

      expect(
        ExperiencesService.cachedNearby(
            latitude: 6, longitude: 80, category: 'water_sports'),
        isNull,
      );
    });

    test('later pages are not saved over the first', () async {
      await ExperiencesService.fetchNearby(latitude: 6, longitude: 80);
      adapter.body = {
        'packages': [_package('b')],
        'total': 21,
      };
      await ExperiencesService.fetchNearby(
          latitude: 6, longitude: 80, offset: 20);

      expect(
        ExperiencesService.cachedNearby(latitude: 6, longitude: 80)
            ?.packages
            .single
            .id,
        'a',
      );
    });
  });

  group('package detail', () {
    const id = '0b8c6f1e-3a52-4c1d-9a51-6f3d2a1b7c90';

    test('stays available offline, with the distance the caller gives',
        () async {
      adapter.body = _package(id, distanceM: 1200);
      await ExperiencesService.fetchPackage(id);

      adapter.offline = true;
      expect(await ExperiencesService.fetchPackage(id), isNull);

      final saved = ExperiencesService.cachedPackage(id, distanceM: 300);
      expect(saved?.description, 'Two hours on the lagoon');
      expect(saved?.distanceM, 300);
    });

    test('a 404 drops the saved copy', () async {
      adapter.body = _package(id);
      await ExperiencesService.fetchPackage(id);

      adapter
        ..status = 404
        ..body = {'detail': 'Not found'};
      await ExperiencesService.fetchPackage(id);

      expect(ExperiencesService.cachedPackage(id), isNull);
    });

    test('a copy older than the max age is not served', () async {
      final old = DateTime.now()
          .subtract(ExperiencesService.cacheMaxAge + const Duration(hours: 1));
      await CacheService.cacheExperienceDetail(id, {
        'saved_at': old.millisecondsSinceEpoch,
        'data': _package(id),
      });

      expect(ExperiencesService.cachedPackage(id), isNull);
    });

    test('only the most recent packages are kept', () async {
      for (var i = 0; i < 31; i++) {
        adapter.body = _package('p$i');
        await ExperiencesService.fetchPackage('p$i');
      }

      expect(ExperiencesService.cachedPackage('p0'), isNull);
      expect(ExperiencesService.cachedPackage('p1'), isNotNull);
      expect(ExperiencesService.cachedPackage('p30'), isNotNull);
    });
  });

  test('countries fall back to the saved list when offline', () async {
    adapter.body = {
      'countries': [
        {'code': 'LK', 'name': 'Sri Lanka', 'count': 4},
      ],
    };
    await ExperiencesService.fetchActiveCountries();

    adapter.offline = true;
    final saved = await ExperiencesService.fetchActiveCountries();

    expect(saved.countries.single.code, 'LK');
    expect(saved.countries.single.count, 4);
  });

  group('browse by country', () {
    test('the countries response reports the mode, and it is saved', () async {
      adapter.body = {'countries': [], 'country_mode': true};
      expect((await ExperiencesService.fetchActiveCountries()).countryMode,
          isTrue);
      expect(ExperiencesService.cachedCountries().countryMode, isTrue);
    });

    test('a server that does not report the mode leaves it unknown', () async {
      adapter.body = {'countries': []};
      expect((await ExperiencesService.fetchActiveCountries()).countryMode,
          isNull);
    });

    test('a list can be fetched without a location', () async {
      adapter.body = {
        'packages': [_package('a')],
        'total': 1,
        'has_nearby': true,
        'country_mode': true,
      };
      final result = await ExperiencesService.fetchNearby();

      expect(result.countryMode, isTrue);
      expect(adapter.last!.queryParameters.containsKey('lat'), isFalse);
      expect(adapter.last!.queryParameters.containsKey('lng'), isFalse);
    });

    test('a saved by-country list holds wherever the user is', () async {
      adapter.body = {
        'packages': [_package('a')],
        'total': 1,
        'has_nearby': true,
        'country_mode': true,
      };
      await ExperiencesService.fetchNearby(latitude: 6, longitude: 80);

      expect(ExperiencesService.cachedNearby(latitude: 51.5, longitude: 0),
          isNotNull);
      expect(ExperiencesService.cachedNearby(), isNotNull);
    });
  });
}
