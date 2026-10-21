import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';

import 'vendor_portal_models.dart';

/// The partner API, the same one partner.nexaround.com uses, for a traveller
/// an admin gave a vendor to.
///
/// The traveller's own token never reaches a partner endpoint, and the
/// partner token never reaches a traveller one: [ApiClient] (traveller token)
/// only trades for a partner token at POST /partner/app/session, and every
/// vendor call goes through this class's own Dio, which carries nothing but
/// that partner token. The partner token lasts an hour and has no refresh
/// token; when it runs out the next call trades again.
class VendorPortalApi {
  final String vendorId;

  VendorPortalApi(this.vendorId);

  /// Tests answer the partner API (and the trade) with this.
  @visibleForTesting
  static HttpClientAdapter? testAdapter;

  static const _base = '${ApiConstants.apiVersion}/partner';

  /// The vendors the signed-in traveller may manage; empty for everyone else.
  static Future<List<VendorAccess>> access() async {
    final res = await ApiClient.instance.get('$_base/app/access');
    final list = (res.data as Map)['vendors'] as List? ?? const [];
    return list
        .map((v) => VendorAccess.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  String? _token;
  Future<VendorMe>? _trading;
  VendorMe? me;

  late final Dio _dio = _createDio();

  Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    ));
    if (testAdapter != null) dio.httpClientAdapter = testAdapter!;
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          if (_token == null) await signIn();
          options.headers['Authorization'] = 'Bearer $_token';
          handler.next(options);
        } on DioException catch (e) {
          handler.reject(e);
        }
      },
      onError: (error, handler) async {
        // The hour is up, or the session was ended: trade again, once.
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['retried'] != true) {
          try {
            _token = null;
            await signIn();
            final opts = error.requestOptions
              ..extra['retried'] = true
              ..headers['Authorization'] = 'Bearer $_token';
            return handler.resolve(await dio.fetch(opts));
          } on DioException catch (e) {
            return handler.next(e);
          }
        }
        handler.next(error);
      },
    ));
    return dio;
  }

  /// Trades the traveller's token for a partner token. Concurrent callers
  /// share one trade. Throws a [DioException]: 404 when the access was taken
  /// away, 403 when the listing is suspended.
  Future<VendorMe> signIn() {
    return _trading ??= () async {
      try {
        final traveller = ApiClient.instance;
        final res = await traveller.post(
          '$_base/app/session',
          data: {'vendor_id': vendorId},
        );
        final data = Map<String, dynamic>.from(res.data as Map);
        _token = data['access_token'] as String?;
        return me = VendorMe.fromJson(Map<String, dynamic>.from(data['me'] as Map));
      } finally {
        _trading = null;
      }
    }();
  }

  /// Ends this device's vendor session (the traveller stays signed in).
  Future<void> signOut() async {
    if (_token == null) return;
    try {
      await _dio.post('$_base/auth/logout');
    } catch (_) {}
    _token = null;
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async {
    final res = await _dio.get('$_base$path', queryParameters: query);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> _put(String path, Object body) async {
    final res = await _dio.put('$_base$path', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await _dio.post('$_base$path', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ── Agreement ─────────────────────────────────────────────────────────────

  Future<PartnerAgreement> agreement() async =>
      PartnerAgreement.fromJson(await _get('/agreement'));

  Future<PartnerAgreement> acceptAgreement(int version) async =>
      PartnerAgreement.fromJson(await _post('/agreement/accept', {'version': version}));

  // ── Dashboard and packages ────────────────────────────────────────────────

  Future<VendorStats> stats() async => VendorStats.fromJson(await _get('/stats'));

  Future<List<VendorPackage>> packages() async {
    final data = await _get('/packages');
    return ((data['packages'] as List?) ?? const [])
        .map((p) => VendorPackage.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
  }

  Future<VendorPackage> package(String id) async =>
      VendorPackage.fromJson(await _get('/packages/$id'));

  Future<VendorPackage> savePackage(VendorPackage pkg) async {
    final data = pkg.id == null
        ? await _post('/packages', pkg.toJson())
        : await _put('/packages/${pkg.id}', pkg.toJson());
    return VendorPackage.fromJson(data);
  }

  Future<void> deletePackage(String id) async {
    await _dio.delete('$_base/packages/$id');
  }

  /// Uploads photos; returns their URLs in the order given.
  Future<List<String>> uploadPhotos(List<String> filePaths) async {
    final form = FormData();
    for (final path in filePaths) {
      form.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(path, filename: path.split('/').last.split('\\').last),
      ));
    }
    final res = await _dio.post('$_base/upload', data: form);
    return ((res.data as Map)['urls'] as List? ?? const []).map((u) => u.toString()).toList();
  }

  Future<List<VendorPlace>> searchPlaces(String query, double lat, double lng) async {
    final data = await _get('/place-search', {'query': query, 'lat': lat, 'lng': lng});
    return ((data['places'] as List?) ?? const [])
        .map((p) => VendorPlace.fromJson(Map<String, dynamic>.from(p as Map)))
        .where((p) => p.latitude != 0 || p.longitude != 0)
        .toList();
  }

  // ── Reviews ───────────────────────────────────────────────────────────────

  Future<VendorReviewPage> reviews({int page = 1, bool unansweredOnly = false}) async =>
      VendorReviewPage.fromJson(await _get('/reviews', {
        'page': page,
        'page_size': 25,
        if (unansweredOnly) 'unanswered': true,
      }));

  Future<VendorReview> reply(String reviewId, String? reply) async =>
      VendorReview.fromJson(await _put('/reviews/$reviewId/reply', {'reply': reply}));

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<VendorProfile> profile() async => VendorProfile.fromJson(await _get('/profile'));

  Future<VendorProfile> saveProfile(VendorProfile profile) async =>
      VendorProfile.fromJson(await _put('/profile', profile.toJson()));

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<VendorActivityPage> activity({DateTime? before}) async =>
      VendorActivityPage.fromJson(await _get('/activity', {
        'scope': 'notifications',
        if (before != null) 'before': before.toUtc().toIso8601String(),
      }));

  Future<int> unread() async => ((await _get('/activity/unread'))['unread'] as num?)?.toInt() ?? 0;

  Future<void> markSeen() async {
    await _post('/activity/seen', const {});
  }
}
