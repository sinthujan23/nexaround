import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/core/utils/number_format.dart';

/// Trip Wallet answers from `/trip-wallet` (nexaround_backend/app/api/v1/trip_wallet.py).
///
/// Money comes as whole minor units (paise, cents) with the trip's
/// `decimals`, so nothing here rounds.

String _s(dynamic v) => v?.toString() ?? '';
int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// A money formatter for one trip's currency: "₹4,000", "₹4,000.50".
class WalletMoney {
  final String currency;
  final int decimals;

  const WalletMoney(this.currency, this.decimals);

  String get symbol {
    for (final c in CurrencyService.supportedCurrencies) {
      if (c['code'] == currency) return c['symbol'] ?? currency;
    }
    return currency;
  }

  num _major(int minor) {
    var div = 1;
    for (var i = 0; i < decimals; i++) {
      div *= 10;
    }
    return minor / div;
  }

  /// Whole amounts drop their ".00".
  String format(int minor, {bool signed = false}) {
    final abs = minor.abs();
    final major = _major(abs);
    final whole = decimals == 0 || abs % _pow() == 0;
    final text = formatAmount(major, decimals: whole ? 0 : decimals);
    final sym = symbol;
    final spaced = sym.length > 1 && RegExp(r'^[A-Z]+$').hasMatch(sym);
    final body = spaced ? '$sym $text' : '$sym$text';
    if (!signed || minor == 0) return body;
    return minor > 0 ? '+$body' : '−$body';
  }

  int _pow() {
    var p = 1;
    for (var i = 0; i < decimals; i++) {
      p *= 10;
    }
    return p;
  }

  /// What an edit field should show for a stored amount: "4000.5" → "4000.50".
  String plain(int minor) {
    final major = _major(minor);
    if (decimals == 0 || minor % _pow() == 0) return major.toStringAsFixed(0);
    return major.toStringAsFixed(decimals);
  }

  /// "4,000.50" → 400050, or null when it is not a valid amount for this
  /// currency. Mirrors the server's check.
  int? parse(String text) {
    final clean = text.replaceAll(',', '').trim();
    if (clean.isEmpty) return null;
    final m = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(clean);
    if (m == null) return null;
    final frac = m.group(2) ?? '';
    if (frac.length > decimals) return null;
    final whole = int.tryParse(m.group(1)!) ?? 0;
    final fracPadded = frac.padRight(decimals, '0');
    final fracValue = decimals == 0 ? 0 : int.tryParse(fracPadded) ?? 0;
    return whole * _pow() + fracValue;
  }
}

class WalletTripCard {
  final String id;
  final String name;
  final String currency;
  final int decimals;
  final bool isOwner;
  final int memberCount;
  final int expenseCount;
  final int totalSpent;
  final int myNet;
  final int pendingCount;

  const WalletTripCard({
    required this.id,
    required this.name,
    required this.currency,
    required this.decimals,
    required this.isOwner,
    required this.memberCount,
    required this.expenseCount,
    required this.totalSpent,
    required this.myNet,
    this.pendingCount = 0,
  });

  WalletMoney get money => WalletMoney(currency, decimals);

  factory WalletTripCard.fromJson(Map<String, dynamic> j) => WalletTripCard(
        id: _s(j['id']),
        name: _s(j['name']),
        currency: _s(j['currency']),
        decimals: _i(j['decimals']),
        isOwner: j['is_owner'] == true,
        memberCount: _i(j['member_count']),
        expenseCount: _i(j['expense_count']),
        totalSpent: _i(j['total_spent']),
        myNet: _i(j['my_net']),
        pendingCount: _i(j['pending_count']),
      );
}

class WalletMember {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final bool isMe;
  final bool hasApp;
  final bool left;

  const WalletMember({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    required this.isMe,
    required this.hasApp,
    required this.left,
  });

  bool get isOwner => role == 'owner';

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  factory WalletMember.fromJson(Map<String, dynamic> j) => WalletMember(
        id: _s(j['id']),
        displayName: _s(j['display_name']),
        avatarUrl: j['avatar_url']?.toString(),
        role: _s(j['role']),
        isMe: j['is_me'] == true,
        hasApp: j['has_app'] == true,
        left: j['left'] == true,
      );
}

class WalletShare {
  final String memberId;
  final int amount;
  const WalletShare(this.memberId, this.amount);
}

class WalletExpense {
  final String id;
  final String title;
  final String category;
  final int amount;
  final DateTime spentOn;
  final String paidByMemberId;
  final String splitMode;
  final List<WalletShare> shares;
  final String? receiptUrl;
  final bool canEdit;

  const WalletExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.spentOn,
    required this.paidByMemberId,
    required this.splitMode,
    required this.shares,
    this.receiptUrl,
    required this.canEdit,
  });

  factory WalletExpense.fromJson(Map<String, dynamic> j) => WalletExpense(
        id: _s(j['id']),
        title: _s(j['title']),
        category: _s(j['category']),
        amount: _i(j['amount_minor']),
        spentOn: DateTime.tryParse(_s(j['spent_on'])) ?? DateTime.now(),
        paidByMemberId: _s(j['paid_by_member_id']),
        splitMode: _s(j['split_mode']),
        shares: [
          for (final s in (j['shares'] as List? ?? const []))
            WalletShare(_s((s as Map)['member_id']), _i(s['amount_minor'])),
        ],
        receiptUrl: j['receipt_url']?.toString(),
        canEdit: j['can_edit'] == true,
      );
}

class WalletBalance {
  final String memberId;
  final int paid;
  final int share;
  final int sent;
  final int received;
  final int net;

  const WalletBalance({
    required this.memberId,
    required this.paid,
    required this.share,
    required this.sent,
    required this.received,
    required this.net,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> j) => WalletBalance(
        memberId: _s(j['member_id']),
        paid: _i(j['paid']),
        share: _i(j['share']),
        sent: _i(j['sent']),
        received: _i(j['received']),
        net: _i(j['net']),
      );
}

/// A payment: one still to make (settle-up list, no id), or one recorded.
/// A recorded one marked by anyone but the trip owner is `pending` until the
/// owner approves it, and counts in no balance till then.
class WalletPayment {
  final String? id;
  final String fromMemberId;
  final String toMemberId;
  final int amount;
  final DateTime? createdAt;
  final String status;
  final bool markedByMe;
  final bool canApprove;
  final bool canDelete;

  const WalletPayment({
    this.id,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    this.createdAt,
    this.status = 'confirmed',
    this.markedByMe = false,
    this.canApprove = false,
    this.canDelete = false,
  });

  bool get isPending => status == 'pending';

  factory WalletPayment.fromJson(Map<String, dynamic> j) => WalletPayment(
        id: j['id']?.toString(),
        fromMemberId: _s(j['from_member_id']),
        toMemberId: _s(j['to_member_id']),
        amount: _i(j['amount_minor']),
        createdAt: DateTime.tryParse(_s(j['created_at']))?.toLocal(),
        status: j['status']?.toString() ?? 'confirmed',
        markedByMe: j['marked_by_me'] == true,
        canApprove: j['can_approve'] == true,
        canDelete: j['can_delete'] == true,
      );
}

class WalletTrip {
  final String id;
  final String name;
  final String currency;
  final int decimals;
  final String inviteCode;
  final String inviteUrl;
  final bool isOwner;
  final String myMemberId;
  final int totalSpent;
  final List<WalletMember> members;
  final List<WalletExpense> expenses;
  final List<WalletBalance> balances;
  final List<WalletPayment> settleUp;
  final List<WalletPayment> settlements;
  final int pendingCount;

  const WalletTrip({
    required this.id,
    required this.name,
    required this.currency,
    required this.decimals,
    required this.inviteCode,
    required this.inviteUrl,
    required this.isOwner,
    required this.myMemberId,
    required this.totalSpent,
    required this.members,
    required this.expenses,
    required this.balances,
    required this.settleUp,
    required this.settlements,
    this.pendingCount = 0,
  });

  WalletMoney get money => WalletMoney(currency, decimals);

  List<WalletPayment> get pendingPayments => settlements.where((p) => p.isPending).toList();
  List<WalletPayment> get confirmedPayments => settlements.where((p) => !p.isPending).toList();

  WalletMember? get owner {
    for (final m in members) {
      if (m.isOwner) return m;
    }
    return null;
  }

  /// A payment between these two already waiting for the owner.
  WalletPayment? pendingBetween(String fromId, String toId) {
    for (final p in settlements) {
      if (p.isPending && p.fromMemberId == fromId && p.toMemberId == toId) return p;
    }
    return null;
  }

  List<WalletMember> get activeMembers => members.where((m) => !m.left).toList();

  WalletMember? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  String nameOf(String memberId) {
    final m = member(memberId);
    if (m == null) return 'Someone';
    return m.isMe ? 'You' : m.displayName;
  }

  WalletBalance? balanceOf(String memberId) {
    for (final b in balances) {
      if (b.memberId == memberId) return b;
    }
    return null;
  }

  int get myNet => balanceOf(myMemberId)?.net ?? 0;

  factory WalletTrip.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String key) =>
        [for (final e in (j[key] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
    return WalletTrip(
      id: _s(j['id']),
      name: _s(j['name']),
      currency: _s(j['currency']),
      decimals: _i(j['decimals']),
      inviteCode: _s(j['invite_code']),
      inviteUrl: _s(j['invite_url']),
      isOwner: j['is_owner'] == true,
      myMemberId: _s(j['my_member_id']),
      totalSpent: _i(j['total_spent']),
      members: list('members').map(WalletMember.fromJson).toList(),
      expenses: list('expenses').map(WalletExpense.fromJson).toList(),
      balances: list('balances').map(WalletBalance.fromJson).toList(),
      settleUp: list('settle_up').map(WalletPayment.fromJson).toList(),
      settlements: list('settlements').map(WalletPayment.fromJson).toList(),
      pendingCount: _i(j['pending_count']),
    );
  }
}

class WalletInvitePreview {
  final String tripId;
  final String name;
  final String currency;
  final String? ownerName;
  final int memberCount;
  final List<String> memberNames;
  final bool alreadyMember;

  const WalletInvitePreview({
    required this.tripId,
    required this.name,
    required this.currency,
    this.ownerName,
    required this.memberCount,
    required this.memberNames,
    required this.alreadyMember,
  });

  factory WalletInvitePreview.fromJson(Map<String, dynamic> j) => WalletInvitePreview(
        tripId: _s(j['trip_id']),
        name: _s(j['name']),
        currency: _s(j['currency']),
        ownerName: j['owner_name']?.toString(),
        memberCount: _i(j['member_count']),
        memberNames: [for (final n in (j['member_names'] as List? ?? const [])) _s(n)],
        alreadyMember: j['already_member'] == true,
      );
}

/// The categories the server accepts, with their labels and icons in
/// trip_wallet_widgets.dart.
const walletCategories = ['hotel', 'transport', 'food', 'activities', 'shopping', 'other'];
