import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/trip_wallet/domain/trip_wallet_models.dart';

/// Trip Wallet from `/trip-wallet`. Every change answers with the whole trip,
/// so a screen just shows what comes back.
class TripWalletService {
  final Dio _dio = ApiClient.instance;

  static const String _base = '${ApiConstants.apiVersion}/trip-wallet';

  /// Bumped when a Trip Wallet push arrives, so an open trip reloads.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static const String pushType = 'trip_wallet';

  /// Every answer that carries a whole trip is also kept on the device as
  /// that trip's copy, so it opens at once next time.
  WalletTrip _trip(Response r) {
    final raw = Map<String, dynamic>.from(r.data as Map);
    final trip = WalletTrip.fromJson(raw);
    CacheService.cacheTripWalletTrip(trip.id, raw);
    return trip;
  }

  static List<WalletTripCard> _cards(Map<String, dynamic> raw) => [
        for (final t in (raw['trips'] as List? ?? const []))
          WalletTripCard.fromJson((t as Map).cast<String, dynamic>()),
      ];

  Future<List<WalletTripCard>> getTrips() async {
    final r = await _dio.get('$_base/trips');
    final raw = Map<String, dynamic>.from(r.data as Map);
    CacheService.cacheTripWalletTrips(raw);
    return _cards(raw);
  }

  /// The trip list as last loaded on this device, or null when there is
  /// none or it no longer reads (an older app's shape).
  List<WalletTripCard>? cachedTrips() {
    final raw = CacheService.getCachedTripWalletTrips();
    if (raw == null) return null;
    try {
      return _cards(raw);
    } catch (_) {
      return null;
    }
  }

  /// A trip as last loaded or changed on this device, or null.
  WalletTrip? cachedTrip(String id) {
    final raw = CacheService.getCachedTripWalletTrip(id);
    if (raw == null) return null;
    try {
      return WalletTrip.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// Drops a trip's kept copy, for a trip the traveller can no longer open.
  Future<void> forgetTrip(String id) => CacheService.removeCachedTripWalletTrip(id);

  Future<WalletTrip> createTrip({required String name, required String currency}) async =>
      _trip(await _dio.post('$_base/trips', data: {'name': name, 'currency': currency}));

  Future<WalletTrip> getTrip(String id) async => _trip(await _dio.get('$_base/trips/$id'));

  Future<WalletTrip> updateTrip(String id, {String? name, String? currency}) async =>
      _trip(await _dio.patch('$_base/trips/$id', data: {
        if (name != null) 'name': name,
        if (currency != null) 'currency': currency,
      }));

  Future<void> deleteTrip(String id) async {
    await _dio.delete('$_base/trips/$id');
    await forgetTrip(id);
  }

  Future<WalletTrip> resetInvite(String id) async =>
      _trip(await _dio.post('$_base/trips/$id/invite/reset'));

  Future<WalletInvitePreview> previewInvite(String code) async {
    final r = await _dio.get('$_base/join/${Uri.encodeComponent(code)}');
    return WalletInvitePreview.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<WalletTrip> join(String code) async =>
      _trip(await _dio.post('$_base/join/${Uri.encodeComponent(code)}'));

  Future<WalletTrip> removeMember(String tripId, String memberId) async =>
      _trip(await _dio.delete('$_base/trips/$tripId/members/$memberId'));

  Future<void> leave(String tripId) async {
    await _dio.post('$_base/trips/$tripId/leave');
    await forgetTrip(tripId);
  }

  /// [body] is ExpenseIn on the server: title, category, amount, spent_on,
  /// paid_by_member_id, split_mode, member_ids or shares, receipt_url.
  Future<WalletTrip> saveExpense(String tripId, Map<String, dynamic> body, {String? expenseId}) async {
    if (expenseId == null) {
      return _trip(await _dio.post('$_base/trips/$tripId/expenses', data: body));
    }
    return _trip(await _dio.patch('$_base/trips/$tripId/expenses/$expenseId', data: body));
  }

  Future<WalletTrip> deleteExpense(String tripId, String expenseId) async =>
      _trip(await _dio.delete('$_base/trips/$tripId/expenses/$expenseId'));

  /// Uploads a receipt photo; returns the path to put on the expense.
  Future<String> uploadReceipt(String tripId, String filePath) async {
    final form = FormData();
    form.files.add(MapEntry(
      'file',
      await MultipartFile.fromFile(filePath, filename: filePath.split('/').last),
    ));
    final r = await _dio.post('$_base/trips/$tripId/receipt', data: form);
    return (r.data as Map)['url'].toString();
  }

  Future<WalletTrip> markPaid(String tripId, WalletPayment p, String amount) async =>
      _trip(await _dio.post('$_base/trips/$tripId/settlements', data: {
        'from_member_id': p.fromMemberId,
        'to_member_id': p.toMemberId,
        'amount': amount,
      }));

  /// The owner confirms a payment someone marked.
  Future<WalletTrip> approvePaid(String tripId, String settlementId) async =>
      _trip(await _dio.post('$_base/trips/$tripId/settlements/$settlementId/approve'));

  /// Rejects (owner), withdraws (who marked it, while pending) or undoes
  /// (owner) a payment.
  Future<WalletTrip> undoPaid(String tripId, String settlementId) async =>
      _trip(await _dio.delete('$_base/trips/$tripId/settlements/$settlementId'));
}
