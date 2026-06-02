import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';

/// Persists finished Mini Tours on the backend by reusing the `/itineraries`
/// table — each tour is an itinerary row whose JSON `items` start with a
/// `mini_tour_meta` marker. No dedicated table or migration needed (the same
/// approach Odysseys use). A Mini Tour record is `{id, area, places, xp, date}`.
class MiniTourRepository {
  final Dio _dio = ApiClient.instance;

  /// MUST keep the trailing slash — see [OdysseyRepository] for the 307→301
  /// redirect that otherwise drops the Authorization header (→ 401).
  static final String _collection = '${ApiConstants.itineraries}/';

  Future<void> saveMiniTour({
    required String area,
    required List<String> placeNames,
    required int xp,
  }) async {
    await _dio.post(
      _collection,
      data: {
        'title': 'Mini Tour · $area',
        'trip_date': null,
        'items': [
          {
            'kind': 'mini_tour_meta',
            'area': area,
            'places': placeNames,
            'xp': xp,
            'date': DateTime.now().toIso8601String(),
          }
        ],
        'status': 'completed',
      },
    );
    // Lets any open History screen (which listens to this notifier) refresh.
    OdysseyRepository.revision.value++;
  }

  /// All finished Mini Tours for the current user, newest first.
  Future<List<Map<String, dynamic>>> getMiniTours() async {
    final response = await _dio.get(_collection);
    final list = (response.data as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where(_isMiniTour)
        .map(_toRecord)
        .toList();
    list.sort((a, b) => _date(b).compareTo(_date(a)));
    return list;
  }

  static bool _isMiniTour(Map<String, dynamic> json) {
    final items = json['items'];
    return items is List &&
        items.isNotEmpty &&
        items.first is Map &&
        (items.first as Map)['kind'] == 'mini_tour_meta';
  }

  static Map<String, dynamic> _toRecord(Map<String, dynamic> json) {
    final meta = ((json['items'] as List).first as Map).cast<String, dynamic>();
    return {
      'id': json['id']?.toString(),
      'area': (meta['area'] ?? 'Mini Tour').toString(),
      'places':
          (meta['places'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[],
      'xp': (meta['xp'] as num?)?.toInt() ?? 0,
      'date': (meta['date'] ?? json['created_at'] ?? '').toString(),
    };
  }

  static DateTime _date(Map<String, dynamic> r) =>
      DateTime.tryParse((r['date'] ?? '').toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
