/// Domain models for an AI-generated "Odyssey" (a full trip blueprint).
///
/// An Odyssey is persisted on the backend by reusing the existing `itineraries`
/// table: the title/status/id map to the Itinerary columns, and the whole
/// structured plan rides inside the flexible JSON `items` list as:
///   items[0]      -> the meta header  ({'kind': 'odyssey_meta', ...})
///   items[1..n]   -> one block per day ({'kind': 'day', 'day': 1, ...})
/// This needs no DB migration — the backend stores/returns the JSON verbatim.
library;

/// A single scheduled stop within a day.
class OdysseyActivity {
  final String time; // e.g. "09:00" or "Morning"
  final String name; // place / activity name
  final String tip; // short practical note
  final String cost; // optional human-readable cost, e.g. "LKR 1,500"

  const OdysseyActivity({
    required this.time,
    required this.name,
    this.tip = '',
    this.cost = '',
  });

  factory OdysseyActivity.fromJson(Map<String, dynamic> json) => OdysseyActivity(
        time: (json['time'] ?? '').toString(),
        name: (json['name'] ?? json['attraction_name'] ?? '').toString(),
        tip: (json['tip'] ?? json['note'] ?? '').toString(),
        cost: (json['cost'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'time': time,
        'name': name,
        'tip': tip,
        'cost': cost,
      };
}

/// A themed day made up of ordered activities.
class OdysseyDay {
  final int day;
  final String theme;
  final List<OdysseyActivity> activities;

  const OdysseyDay({
    required this.day,
    required this.theme,
    required this.activities,
  });

  factory OdysseyDay.fromJson(Map<String, dynamic> json) => OdysseyDay(
        day: (json['day'] as num?)?.toInt() ?? 0,
        theme: (json['theme'] ?? '').toString(),
        activities: ((json['activities'] as List?) ?? const [])
            .whereType<Map>()
            .map((a) => OdysseyActivity.fromJson(a.cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'kind': 'day',
        'day': day,
        'theme': theme,
        'activities': activities.map((a) => a.toJson()).toList(),
      };
}

class Odyssey {
  /// Backend itinerary id. Null until the Odyssey has been saved.
  final String? id;
  final String title;
  final String destination;
  final String mood;
  final double budget;
  final String currency;
  final int days;
  final int nights;
  final String summary;
  final String budgetSplit; // e.g. "40% Stay · 30% Food · 30% Experiences"
  final String visa; // e.g. "ETA required (online)"
  final String logistics; // multi-line blueprint
  final List<OdysseyDay> dayPlans;
  final String status; // active | draft | completed
  final DateTime? createdAt;

  const Odyssey({
    this.id,
    required this.title,
    required this.destination,
    required this.mood,
    required this.budget,
    required this.currency,
    required this.days,
    required this.nights,
    required this.summary,
    required this.budgetSplit,
    required this.visa,
    required this.logistics,
    required this.dayPlans,
    this.status = 'active',
    this.createdAt,
  });

  Odyssey copyWith({String? id, String? status}) => Odyssey(
        id: id ?? this.id,
        title: title,
        destination: destination,
        mood: mood,
        budget: budget,
        currency: currency,
        days: days,
        nights: nights,
        summary: summary,
        budgetSplit: budgetSplit,
        visa: visa,
        logistics: logistics,
        dayPlans: dayPlans,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  /// One-line stats label used on cards, e.g. "4 Days · LKR 120,000".
  String get statsLabel {
    final b = budget >= 1000
        ? '${(budget / 1000).toStringAsFixed(budget % 1000 == 0 ? 0 : 1)}k'
        : budget.toStringAsFixed(0);
    return '$days ${days == 1 ? 'Day' : 'Days'} · $currency $b';
  }

  // ── Gemini output ────────────────────────────────────────────────────────
  /// Build from the JSON object Gemini returns. Tolerant of missing fields so a
  /// partial model never crashes the UI.
  factory Odyssey.fromGemini(
    Map<String, dynamic> json, {
    required String destination,
    required String mood,
    required double budget,
    required String currency,
  }) {
    final days = ((json['days'] ?? json['duration_days']) as num?)?.toInt() ??
        ((json['day_plans'] ?? json['plan']) as List?)?.length ??
        1;
    return Odyssey(
      title: (json['title'] ?? 'Your Odyssey').toString(),
      destination: (json['destination'] ?? destination).toString(),
      mood: mood,
      budget: budget,
      currency: (json['currency'] ?? currency).toString(),
      days: days,
      nights: (json['nights'] as num?)?.toInt() ?? (days > 1 ? days - 1 : 0),
      summary: (json['summary'] ?? '').toString(),
      budgetSplit: (json['budget_split'] ?? '').toString(),
      visa: (json['visa'] ?? json['visa_status'] ?? '').toString(),
      logistics: _logisticsToText(json['logistics']),
      dayPlans: ((json['day_plans'] ?? json['plan'] ?? const []) as List)
          .whereType<Map>()
          .map((d) => OdysseyDay.fromJson(d.cast<String, dynamic>()))
          .toList(),
    );
  }

  // ── Backend itinerary mapping ────────────────────────────────────────────
  /// The JSON `items` list stored in the itineraries table.
  List<Map<String, dynamic>> toItineraryItems() => [
        {
          'kind': 'odyssey_meta',
          'destination': destination,
          'mood': mood,
          'budget': budget,
          'currency': currency,
          'days': days,
          'nights': nights,
          'summary': summary,
          'budget_split': budgetSplit,
          'visa': visa,
          'logistics': logistics,
        },
        ...dayPlans.map((d) => d.toJson()),
      ];

  /// True when a raw itinerary JSON (from GET /itineraries) is an Odyssey.
  static bool isOdyssey(Map<String, dynamic> itineraryJson) {
    final items = itineraryJson['items'];
    return items is List &&
        items.isNotEmpty &&
        items.first is Map &&
        (items.first as Map)['kind'] == 'odyssey_meta';
  }

  /// Reconstruct an Odyssey from a backend itinerary JSON row.
  factory Odyssey.fromItinerary(Map<String, dynamic> json) {
    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final meta = items.isNotEmpty
        ? items.firstWhere(
            (e) => e['kind'] == 'odyssey_meta',
            orElse: () => <String, dynamic>{},
          )
        : <String, dynamic>{};
    final dayItems = items.where((e) => e['kind'] == 'day').toList();

    return Odyssey(
      id: json['id']?.toString(),
      title: (json['title'] ?? 'Odyssey').toString(),
      destination: (meta['destination'] ?? '').toString(),
      mood: (meta['mood'] ?? '').toString(),
      budget: (meta['budget'] as num?)?.toDouble() ?? 0,
      currency: (meta['currency'] ?? 'LKR').toString(),
      days: (meta['days'] as num?)?.toInt() ?? dayItems.length,
      nights: (meta['nights'] as num?)?.toInt() ?? 0,
      summary: (meta['summary'] ?? '').toString(),
      budgetSplit: (meta['budget_split'] ?? '').toString(),
      visa: (meta['visa'] ?? '').toString(),
      logistics: (meta['logistics'] ?? '').toString(),
      dayPlans: dayItems.map((d) => OdysseyDay.fromJson(d)).toList(),
      status: (json['status'] ?? 'active').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  /// Logistics can arrive as a string or a list of steps — normalise to text.
  static String _logisticsToText(dynamic raw) {
    if (raw is String) return raw;
    if (raw is List) {
      return raw
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
    }
    return '';
  }
}
