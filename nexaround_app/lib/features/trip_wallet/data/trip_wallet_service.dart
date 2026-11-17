import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/trip_wallet/domain/trip_wallet_models.dart';

/// Trip Wallet from `/trip-wallet`. Every change answers with the whole trip,
/// so a screen just shows what comes back.
class TripWalletService {
  final Dio _dio = ApiClient.instance;

  static const String _base = '${ApiConstants.apiVersion}/trip-wallet';

  /// Bumped when a Trip Wallet push arrives, so an open trip reloads.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static const String pushType = 'trip_wallet';

  WalletTrip _trip(Response r) => WalletTrip.fromJson((r.data as Map).cast<String, dynamic>());

  Future<List<WalletTripCard>> getTrips() async {
    final r = await _dio.get('$_base/trips');
    final list = ((r.data as Map)['trips'] as List? ?? const []);
    return [for (final t in list) WalletTripCard.fromJson((t as Map).cast<String, dynamic>())];
  }

  Future<WalletTrip> createTrip({required String name, required String currency}) async =>
      _trip(await _dio.post('$_base/trips', data: {'name': name, 'currency': currency}));

  Future<WalletTrip> getTrip(String id) async => _trip(await _dio.get('$_base/trips/$id'));

  Future<WalletTrip> updateTrip(String id, {String? name, String? currency}) async =>
      _trip(await _dio.patch('$_base/trips/$id', data: {
        if (name != null) 'name': name,
        if (currency != null) 'currency': currency,
      }));

  Future<void> deleteTrip(String id) => _dio.delete('$_base/trips/$id');

  Future<WalletTrip> resetInvite(String id) async =>
      _trip(await _dio.post('$_base/trips/$id/invite/reset'));

  Future<WalletInvitePreview> previewInvite(String code) async {
    final r = await _dio.get('$_base/join/${Uri.encodeComponent(code)}');
    return WalletInvitePreview.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<WalletTrip> join(String code) async =>
      _trip(await _dio.post('$_base/join/${Uri.encodeComponent(code)}'));

  Future<WalletTrip> addMember(String tripId, String name) async =>
      _trip(await _dio.post('$_base/trips/$tripId/members', data: {'display_name': name}));

  Future<WalletTrip> removeMember(String tripId, String memberId) async =>
      _trip(await _dio.delete('$_base/trips/$tripId/members/$memberId'));

  Future<void> leave(String tripId) => _dio.post('$_base/trips/$tripId/leave');

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
