import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';

/// The signed-in user's subscription plan (Explorer / Voyager / Globetrotter)
/// as the backend reports it from `GET /billing/plan`.
///
/// The server enforces every limit; this only mirrors them so screens can show
/// "2 plans left", lock the 10 km AR range, and open the plans screen before a
/// request is refused. When the server says limits are not switched on yet
/// (`enforced: false`), every gate here stays open.
class PlanStatus {
  final String plan; // explorer | voyager | globetrotter
  final String planName;
  final String? period; // monthly | yearly
  final String? store; // app_store | play_store | admin
  final String? status; // active | cancelled | billing_issue | expired
  final DateTime? periodEnd;
  final bool autoRenew;
  final bool enforced;
  final Map<String, dynamic> limits;
  final Map<String, dynamic> usage;
  final List<Map<String, dynamic>> catalog;

  const PlanStatus({
    required this.plan,
    required this.planName,
    this.period,
    this.store,
    this.status,
    this.periodEnd,
    this.autoRenew = false,
    this.enforced = false,
    this.limits = const {},
    this.usage = const {},
    this.catalog = const [],
  });

  factory PlanStatus.fromJson(Map<String, dynamic> j) {
    return PlanStatus(
      plan: (j['plan'] ?? 'explorer').toString(),
      planName: (j['plan_name'] ?? 'Explorer').toString(),
      period: j['period'] as String?,
      store: j['store'] as String?,
      status: j['status'] as String?,
      periodEnd: DateTime.tryParse((j['period_end'] ?? '').toString()),
      autoRenew: j['auto_renew'] == true,
      enforced: j['enforced'] == true,
      limits: Map<String, dynamic>.from((j['limits'] as Map?) ?? const {}),
      usage: Map<String, dynamic>.from((j['usage'] as Map?) ?? const {}),
      catalog: ((j['catalog'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(),
    );
  }

  bool get isPaid => plan != 'explorer';

  int _int(Map<String, dynamic> m, String k, int fallback) {
    final v = m[k];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? fallback;
  }

  int get odysseyLeft => _int(usage, 'odyssey_left', 999);
  int get odysseyPerPeriod => _int(limits, 'odyssey_per_period', 999);
  int get odysseyMaxDays => _int(limits, 'odyssey_max_days', 14);
  int get nevaLeft => _int(usage, 'neva_left', 999);
  int get nevaPerDay => _int(limits, 'neva_per_day', 999);
  int get arRadiusM => _int(limits, 'ar_radius_m', 10000);
  int get bandedMaxBands => _int(limits, 'banded_max_bands', 3);
  bool get odysseyLite => limits['odyssey_lite'] == true;
  bool get mapLimited => usage['map_limited'] == true;
  DateTime? get odysseyResetsAt =>
      DateTime.tryParse('${usage['odyssey_resets_at'] ?? ''}');
}

/// A plan limit the server refused a request for (HTTP 429, code=plan_limit).
class PlanLimitEvent {
  final String feature; // odyssey | odyssey_days | neva | ar_range | live_map | bands | discover
  final String message;
  final int? limit;
  final DateTime? resetsAt;

  const PlanLimitEvent({
    required this.feature,
    required this.message,
    this.limit,
    this.resetsAt,
  });
}

class PlanService {
  PlanService._();

  /// Null until the first answer (or when signed out): treat as unlimited.
  static final ValueNotifier<PlanStatus?> status = ValueNotifier<PlanStatus?>(null);

  /// Every plan limit the app runs into. A listener near the app root shows
  /// the plans sheet; the screen that made the request only stops its spinner.
  static final StreamController<PlanLimitEvent> _limits =
      StreamController<PlanLimitEvent>.broadcast();
  static Stream<PlanLimitEvent> get limitEvents => _limits.stream;

  static DateTime? _lastMapNotice;

  static Future<PlanStatus?> refresh() async {
    try {
      final res = await ApiClient.instance.get('${ApiConstants.apiVersion}/billing/plan');
      if (res.statusCode == 200 && res.data is Map) {
        status.value = PlanStatus.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
    } catch (e) {
      debugPrint('PlanService.refresh failed: $e');
    }
    return status.value;
  }

  /// After a purchase or restore: the server re-reads RevenueCat now.
  static Future<PlanStatus?> sync() async {
    try {
      final res = await ApiClient.instance.post('${ApiConstants.apiVersion}/billing/sync');
      if (res.statusCode == 200 && res.data is Map) {
        status.value = PlanStatus.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
    } catch (e) {
      debugPrint('PlanService.sync failed: $e');
    }
    return status.value;
  }

  static void clear() => status.value = null;

  /// True when [error] is the server refusing a request for a plan limit.
  static bool isPlanLimit(Object? error) {
    if (error is! DioException) return false;
    final res = error.response;
    if (res?.statusCode != 429) return false;
    final data = res?.data;
    return data is Map && data['code'] == 'plan_limit';
  }

  /// The server's sentence for a plan-limit error, or null.
  static String? limitMessage(Object? error) {
    if (!isPlanLimit(error)) return null;
    final data = (error as DioException).response?.data;
    return (data is Map ? data['detail'] : null)?.toString();
  }

  /// Called by ApiClient for every 429 plan_limit response.
  static void reportLimit(Response<dynamic>? response) {
    final data = response?.data;
    if (data is! Map) return;
    _limits.add(PlanLimitEvent(
      feature: (data['feature'] ?? 'plan').toString(),
      message: (data['detail'] ?? '').toString(),
      limit: data['limit'] is num ? (data['limit'] as num).toInt() : null,
      resetsAt: DateTime.tryParse('${data['resets_at'] ?? ''}'),
    ));
    // The counters on screen are now stale.
    unawaited(refresh());
  }

  /// Called by ApiClient when a response carries `X-Plan-Limit: live_map`:
  /// the request worked, with saved places only. Told once an hour at most.
  static void reportMapLimited() {
    final now = DateTime.now();
    if (_lastMapNotice != null && now.difference(_lastMapNotice!) < const Duration(hours: 1)) {
      return;
    }
    _lastMapNotice = now;
    _limits.add(const PlanLimitEvent(
      feature: 'live_map',
      message: "Today's live map updates are used up, so you're seeing saved places.",
    ));
  }

  /// For screens that limit themselves before asking (AR range, trip length).
  static void showLimit(String feature, String message) {
    _limits.add(PlanLimitEvent(feature: feature, message: message));
  }
}

/// Plan checks screens make before they ask the server for something the plan
/// would refuse. Open (no limit) whenever the plan is unknown or limits are
/// not switched on.
class PlanGate {
  PlanGate._();

  static const _uncappedCategories = {'medical', 'hospital'};

  static PlanStatus? get _s {
    final s = PlanService.status.value;
    return (s != null && s.enforced) ? s : null;
  }

  static int get odysseyMaxDays => _s?.odysseyMaxDays ?? 14;

  /// Largest AR range (km) this plan allows for [filter].
  static int arMaxKm(String filter) {
    if (_uncappedCategories.contains(filter.trim().toLowerCase())) return 10;
    final s = _s;
    if (s == null) return 10;
    return (s.arRadiusM / 1000).floor().clamp(1, 10);
  }

  /// Whether Around You / Discover hides this category's farthest band.
  static bool bandsLimited(String category) {
    if (_uncappedCategories.contains(category.trim().toLowerCase())) return false;
    final s = _s;
    return s != null && s.bandedMaxBands < 3;
  }
}
