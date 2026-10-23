import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

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
///
/// Every read is also kept on the device (CacheService), and the `cached…`
/// getters give it back, so the screens open at once and offline. A kept
/// package or profile is for showing only: saves replace the whole record,
/// so the screens save only what came fresh from the server.
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
    final raw = ((res.data as Map)['vendors'] as List? ?? const [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    CacheService.cacheVendorAccess(raw);
    return raw.map(VendorAccess.fromJson).toList();
  }

  /// What [access] last answered; empty when it never has.
  static List<VendorAccess> cachedAccess() {
    try {
      return (CacheService.getCachedVendorAccess() ?? const [])
          .map(VendorAccess.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String? _token;
  Future<VendorMe>? _trading;

  /// The last session's answer until this one's trade is done.
  late VendorMe? me = _cachedAs('me', VendorMe.fromJson);

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
        final raw = Map<String, dynamic>.from(data['me'] as Map);
        CacheService.cacheVendorData(vendorId, 'me', raw);
        return me = VendorMe.fromJson(raw);
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

  /// The answer, kept as [keepAs] when given.
  Map<String, dynamic> _answer(Response res, String? keepAs) {
    final data = Map<String, dynamic>.from(res.data as Map);
    if (keepAs != null) CacheService.cacheVendorData(vendorId, keepAs, data);
    return data;
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? query, String? keepAs}) async =>
      _answer(await _dio.get('$_base$path', queryParameters: query), keepAs);

  Future<Map<String, dynamic>> _put(String path, Object body, {String? keepAs}) async =>
      _answer(await _dio.put('$_base$path', data: body), keepAs);

  Future<Map<String, dynamic>> _post(String path, Object body, {String? keepAs}) async =>
      _answer(await _dio.post('$_base$path', data: body), keepAs);

  /// The kept answer [part], or null when there is none or it no longer
  /// reads (an older app's shape).
  T? _cachedAs<T>(String part, T Function(Map<String, dynamic> json) parse) {
    final raw = CacheService.getCachedVendorData(vendorId, part);
    if (raw == null) return null;
    try {
      return parse(raw);
    } catch (_) {
      return null;
    }
  }

  static List<VendorPackage> _packageList(Map<String, dynamic> data) =>
      ((data['packages'] as List?) ?? const [])
          .map((p) => VendorPackage.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();

  static String _reviewsPart(bool unansweredOnly) => unansweredOnly ? 'reviews_unanswered' : 'reviews';

  // ── Agreement ─────────────────────────────────────────────────────────────

  Future<PartnerAgreement> agreement() async =>
      PartnerAgreement.fromJson(await _get('/agreement', keepAs: 'agreement'));

  PartnerAgreement? cachedAgreement() => _cachedAs('agreement', PartnerAgreement.fromJson);

  /// [version] is the text the person read; the server also takes their word
  /// that they may accept for the business (the box they ticked).
  Future<PartnerAgreement> acceptAgreement(int version) async => PartnerAgreement.fromJson(
      await _post('/agreement/accept', {'version': version, 'authorised': true}, keepAs: 'agreement'));

  // ── Dashboard and packages ────────────────────────────────────────────────

  Future<VendorStats> stats() async => VendorStats.fromJson(await _get('/stats', keepAs: 'stats'));

  VendorStats? cachedStats() => _cachedAs('stats', VendorStats.fromJson);

  Future<List<VendorPackage>> packages() async =>
      _packageList(await _get('/packages', keepAs: 'packages'));

  List<VendorPackage>? cachedPackages() => _cachedAs('packages', _packageList);

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

  // ── Requests ──────────────────────────────────────────────────────────────

  /// "open" (to answer, oldest first; its first page is kept) or "all".
  Future<VendorRequestPage> requests({String scope = 'open', int page = 1}) async =>
      VendorRequestPage.fromJson(await _get('/requests',
          query: {'scope': scope, 'page': page, 'page_size': 25},
          keepAs: scope == 'open' && page == 1 ? 'requests' : null));

  VendorRequestPage? cachedRequests() => _cachedAs('requests', VendorRequestPage.fromJson);

  Future<VendorRequest> request(String id) async =>
      VendorRequest.fromJson(await _get('/requests/$id'));

  /// [action]: "confirmed" (for [day] when the traveller is flexible),
  /// "other_date" (offer [day]) or "cancelled". [reason] is one of
  /// [declineReasons]; [note] reaches NexAround only.
  Future<VendorRequest> answer(String id, String action,
          {DateTime? day, String? reason, String? note}) async =>
      VendorRequest.fromJson(await _post('/requests/$id/answer', {
        'action': action,
        'day': day == null
            ? null
            : '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        'reason': reason,
        'note': note,
      }));

  // ── Reviews ───────────────────────────────────────────────────────────────

  /// The first page is kept, one per filter.
  Future<VendorReviewPage> reviews({int page = 1, bool unansweredOnly = false}) async =>
      VendorReviewPage.fromJson(await _get('/reviews',
          query: {
            'page': page,
            'page_size': 25,
            if (unansweredOnly) 'unanswered': true,
          },
          keepAs: page == 1 ? _reviewsPart(unansweredOnly) : null));

  VendorReviewPage? cachedReviews({bool unansweredOnly = false}) =>
      _cachedAs(_reviewsPart(unansweredOnly), VendorReviewPage.fromJson);

  Future<VendorReview> reply(String reviewId, String? reply) async =>
      VendorReview.fromJson(await _put('/reviews/$reviewId/reply', {'reply': reply}));

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<VendorProfile> profile() async =>
      VendorProfile.fromJson(await _get('/profile', keepAs: 'profile'));

  VendorProfile? cachedProfile() => _cachedAs('profile', VendorProfile.fromJson);

  Future<VendorProfile> saveProfile(VendorProfile profile) async =>
      VendorProfile.fromJson(await _put('/profile', profile.toJson(), keepAs: 'profile'));

  // ── Notifications ─────────────────────────────────────────────────────────

  /// The first page is kept.
  Future<VendorActivityPage> activity({DateTime? before}) async =>
      VendorActivityPage.fromJson(await _get('/activity',
          query: {
            'scope': 'notifications',
            if (before != null) 'before': before.toUtc().toIso8601String(),
          },
          keepAs: before == null ? 'activity' : null));

  VendorActivityPage? cachedActivity() => _cachedAs('activity', VendorActivityPage.fromJson);

  Future<int> unread() async =>
      ((await _get('/activity/unread', keepAs: 'unread'))['unread'] as num?)?.toInt() ?? 0;

  int? cachedUnread() => _cachedAs('unread', (j) => (j['unread'] as num?)?.toInt() ?? 0);

  Future<void> markSeen() async {
    await _post('/activity/seen', const {}, keepAs: 'unread');
  }
}
