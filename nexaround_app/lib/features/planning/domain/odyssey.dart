/// Domain models for an AI-generated "Odyssey" (a full trip blueprint).
///
/// An Odyssey is persisted on the backend by reusing the existing `itineraries`
/// table: the title/status/id map to the Itinerary columns, and the whole
/// structured plan rides inside the flexible JSON `items` list as:
///   items[0]      -> the meta header  ({'kind': 'odyssey_meta', ...})
///   items[1..n]   -> one block per day ({'kind': 'day', 'day': 1, ...})
/// This needs no DB migration — the backend stores/returns the JSON verbatim.
library;

import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/utils/number_format.dart';

/// A single scheduled stop within a day.
class OdysseyActivity {
  final String time; // e.g. "09:00" or "Morning"
  final String name; // place / activity name
  final String tip; // short practical note
  final String cost; // optional human-readable cost, e.g. "LKR 1,500"
  final bool visited; // ticked off as the traveler completes the trip

  const OdysseyActivity({
    required this.time,
    required this.name,
    this.tip = '',
    this.cost = '',
    this.visited = false,
  });

  OdysseyActivity copyWith({bool? visited}) => OdysseyActivity(
        time: time,
        name: name,
        tip: tip,
        cost: cost,
        visited: visited ?? this.visited,
      );

  factory OdysseyActivity.fromJson(Map<String, dynamic> json) => OdysseyActivity(
        time: (json['time'] ?? '').toString(),
        name: (json['name'] ?? json['attraction_name'] ?? '').toString(),
        tip: (json['tip'] ?? json['note'] ?? '').toString(),
        cost: (json['cost'] ?? '').toString(),
        visited: json['visited'] == true,
      );

  Map<String, dynamic> toJson() => {
        'time': time,
        'name': name,
        'tip': tip,
        'cost': cost,
        'visited': visited,
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

  OdysseyDay copyWith({List<OdysseyActivity>? activities}) => OdysseyDay(
        day: day,
        theme: theme,
        activities: activities ?? this.activities,
      );

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

class OdysseyBookingPartner {
  final String name;
  final String type; // hotels | tours | transit
  final String url;

  const OdysseyBookingPartner({
    required this.name,
    required this.type,
    required this.url,
  });

  factory OdysseyBookingPartner.fromJson(Map<String, dynamic> json) =>
      OdysseyBookingPartner(
        name: (json['name'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'url': url,
      };
}

class FlightStrategy {
  final int rank;
  final String strategy;
  final String title;
  final String description;
  final String estimatedSavings;
  final String priceRange;
  final List<String> airlines;
  final String route;
  final int stops;
  final String duration;
  final String convenience;
  final String providerName;
  final String tip;
  final String bookingUrl;

  const FlightStrategy({
    required this.rank,
    required this.strategy,
    required this.title,
    required this.description,
    required this.estimatedSavings,
    required this.priceRange,
    required this.airlines,
    required this.route,
    required this.stops,
    required this.duration,
    required this.convenience,
    required this.providerName,
    required this.tip,
    required this.bookingUrl,
  });

  static int _parseInt(dynamic val, [int fallback = 0]) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? fallback;
    return fallback;
  }

  factory FlightStrategy.fromJson(Map<String, dynamic> json) => FlightStrategy(
        rank: _parseInt(json['rank'], 1),
        strategy: (json['strategy'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        estimatedSavings: (json['estimated_savings'] ?? '').toString(),
        priceRange: (json['estimated_price_range'] ?? json['price_range'] ?? '').toString(),
        airlines: (json['airlines'] is List)
            ? (json['airlines'] as List).map((e) => e.toString()).toList()
            : (json['airlines'] != null && json['airlines'].toString().isNotEmpty)
                ? [json['airlines'].toString()]
                : <String>[],
        route: (json['route'] ?? '').toString(),
        stops: _parseInt(json['stops'], 0),
        duration: (json['total_duration'] ?? json['duration'] ?? '').toString(),
        convenience: (json['convenience'] ?? '').toString(),
        providerName: (json['provider_name'] ?? json['provider'] ?? '').toString(),
        tip: (json['tip'] ?? '').toString(),
        bookingUrl: (json['booking_url'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'strategy': strategy,
        'title': title,
        'description': description,
        'estimated_savings': estimatedSavings,
        'estimated_price_range': priceRange,
        'airlines': airlines,
        'route': route,
        'stops': stops,
        'total_duration': duration,
        'convenience': convenience,
        'provider_name': providerName,
        'tip': tip,
        'booking_url': bookingUrl,
      };
}

class HotelStrategy {
  final int rank;
  final String name;
  final String providerName;
  final String category;
  final String rating;
  final String pricePerNight;
  final String totalEstimatedCost;
  final String location;
  final List<String> amenities;
  final String description;
  final String bookingUrl;

  const HotelStrategy({
    required this.rank,
    required this.name,
    required this.providerName,
    required this.category,
    required this.rating,
    required this.pricePerNight,
    required this.totalEstimatedCost,
    required this.location,
    required this.amenities,
    required this.description,
    required this.bookingUrl,
  });

  factory HotelStrategy.fromJson(Map<String, dynamic> json) => HotelStrategy(
        rank: FlightStrategy._parseInt(json['rank'], 1),
        name: (json['name'] ?? '').toString(),
        providerName: (json['provider_name'] ?? json['provider'] ?? 'Booking.com').toString(),
        category: (json['category'] ?? '').toString(),
        rating: (json['rating'] ?? '').toString(),
        pricePerNight: (json['price_per_night'] ?? '').toString(),
        totalEstimatedCost: (json['total_estimated_cost'] ?? json['total_cost'] ?? '').toString(),
        location: (json['location'] ?? '').toString(),
        amenities: (json['amenities'] is List)
            ? (json['amenities'] as List).map((e) => e.toString()).toList()
            : <String>[],
        description: (json['description'] ?? '').toString(),
        bookingUrl: (json['booking_url'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'name': name,
        'provider_name': providerName,
        'category': category,
        'rating': rating,
        'price_per_night': pricePerNight,
        'total_estimated_cost': totalEstimatedCost,
        'location': location,
        'amenities': amenities,
        'description': description,
        'booking_url': bookingUrl,
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
  final List<OdysseyBookingPartner> bookingPartners;
  final List<FlightStrategy> flightStrategies; // NEW
  final List<String> flightGeneralTips; // NEW
  final String flightBestMonths; // NEW
  final List<HotelStrategy> hotelStrategies;
  final List<String> hotelGeneralTips;
  final String hotelBestAreas;
  final String status; // active | draft | completed
  final DateTime? createdAt;
  final String? coverUrl;
  final String? startDate;
  final String? endDate;

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
    this.bookingPartners = const [],
    this.flightStrategies = const [], // NEW
    this.flightGeneralTips = const [], // NEW
    this.flightBestMonths = '', // NEW
    this.hotelStrategies = const [],
    this.hotelGeneralTips = const [],
    this.hotelBestAreas = '',
    this.status = 'active',
    this.createdAt,
    this.coverUrl,
    this.startDate,
    this.endDate,
  });

  Odyssey copyWith({
    String? id,
    String? status,
    List<OdysseyDay>? dayPlans,
    List<OdysseyBookingPartner>? bookingPartners,
    List<FlightStrategy>? flightStrategies, // NEW
    List<String>? flightGeneralTips, // NEW
    String? flightBestMonths, // NEW
    List<HotelStrategy>? hotelStrategies,
    List<String>? hotelGeneralTips,
    String? hotelBestAreas,
    String? coverUrl,
    String? startDate,
    String? endDate,
  }) =>
      Odyssey(
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
        dayPlans: dayPlans ?? this.dayPlans,
        bookingPartners: bookingPartners ?? this.bookingPartners,
        flightStrategies: flightStrategies ?? this.flightStrategies, // NEW
        flightGeneralTips: flightGeneralTips ?? this.flightGeneralTips, // NEW
        flightBestMonths: flightBestMonths ?? this.flightBestMonths, // NEW
        hotelStrategies: hotelStrategies ?? this.hotelStrategies,
        hotelGeneralTips: hotelGeneralTips ?? this.hotelGeneralTips,
        hotelBestAreas: hotelBestAreas ?? this.hotelBestAreas,
        status: status ?? this.status,
        createdAt: createdAt,
        coverUrl: coverUrl ?? this.coverUrl,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
      );

  // ── Trip progress (per-place check-off) ──────────────────────────────────
  int get totalActivities =>
      dayPlans.fold(0, (n, d) => n + d.activities.length);
  int get visitedActivities => dayPlans.fold(
      0, (n, d) => n + d.activities.where((a) => a.visited).length);
  bool get isComplete =>
      totalActivities > 0 && visitedActivities == totalActivities;

  /// One-line stats label used on cards, e.g. "4 Days · LKR 120,000".
  String get statsLabel =>
      '$days ${days == 1 ? 'Day' : 'Days'} · $currency ${formatAmount(budget)}';

  /// User-facing date range string, e.g. "Aug 10, 2026 – Aug 13, 2026".
  String get formattedDateRange {
    final s = startDate?.trim() ?? '';
    final e = endDate?.trim() ?? '';
    if (s.isEmpty) return '';
    try {
      final startDt = DateTime.parse(s);
      final startFormatted = _formatDateNice(startDt);
      if (e.isNotEmpty) {
        final endDt = DateTime.parse(e);
        final endFormatted = _formatDateNice(endDt);
        return '$startFormatted – $endFormatted';
      }
      return startFormatted;
    } catch (_) {
      if (e.isNotEmpty) {
        return '$s – $e';
      }
      return s;
    }
  }

  static String _formatDateNice(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
      bookingPartners: ((json['booking_partners'] ?? const []) as List)
          .whereType<Map>()
          .map((bp) => OdysseyBookingPartner.fromJson(bp.cast<String, dynamic>()))
          .toList(),
      coverUrl: (json['cover_url'] ?? '').toString(),
      startDate: (json['start_date'] ?? '').toString(),
      endDate: (json['end_date'] ?? '').toString(),
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
          'booking_partners': bookingPartners.map((bp) => bp.toJson()).toList(),
          'flight_strategies': {
            'strategies': flightStrategies.map((fs) => fs.toJson()).toList(),
            'general_tips': flightGeneralTips,
            'best_months': flightBestMonths,
          },
          'hotel_strategies': {
            'strategies': hotelStrategies.map((hs) => hs.toJson()).toList(),
            'general_tips': hotelGeneralTips,
            'best_areas': hotelBestAreas,
          },
          'cover_url': coverUrl ?? '',
          'start_date': startDate ?? '',
          'end_date': endDate ?? '',
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

    final flightStrategiesRaw = meta['flight_strategies'];
    final List<FlightStrategy> flightStrategies = [];
    final List<String> flightGeneralTips = [];
    String flightBestMonths = '';

    try {
      if (flightStrategiesRaw is Map) {
        final strategiesList = flightStrategiesRaw['strategies'] as List?;
        if (strategiesList != null) {
          for (final item in strategiesList) {
            if (item is Map) {
              flightStrategies.add(FlightStrategy.fromJson(item.cast<String, dynamic>()));
            }
          }
        }
        final tipsList = flightStrategiesRaw['general_tips'] as List?;
        if (tipsList != null) {
          for (final item in tipsList) {
            flightGeneralTips.add(item.toString());
          }
        }
        flightBestMonths = (flightStrategiesRaw['best_months'] ?? '').toString();
      } else if (flightStrategiesRaw is List) {
        for (final item in flightStrategiesRaw) {
          if (item is Map) {
            flightStrategies.add(FlightStrategy.fromJson(item.cast<String, dynamic>()));
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing flight strategies in Odyssey: $e');
    }

    final hotelStrategiesRaw = meta['hotel_strategies'];
    final List<HotelStrategy> hotelStrategies = [];
    final List<String> hotelGeneralTips = [];
    String hotelBestAreas = '';

    try {
      if (hotelStrategiesRaw is Map) {
        final strategiesList = hotelStrategiesRaw['strategies'] as List?;
        if (strategiesList != null) {
          for (final item in strategiesList) {
            if (item is Map) {
              hotelStrategies.add(HotelStrategy.fromJson(item.cast<String, dynamic>()));
            }
          }
        }
        final tipsList = hotelStrategiesRaw['general_tips'] as List?;
        if (tipsList != null) {
          for (final item in tipsList) {
            hotelGeneralTips.add(item.toString());
          }
        }
        hotelBestAreas = (hotelStrategiesRaw['best_areas'] ?? '').toString();
      } else if (hotelStrategiesRaw is List) {
        for (final item in hotelStrategiesRaw) {
          if (item is Map) {
            hotelStrategies.add(HotelStrategy.fromJson(item.cast<String, dynamic>()));
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing hotel strategies in Odyssey: $e');
    }

    return Odyssey(
      id: json['id']?.toString(),
      title: (json['title'] ?? 'Odyssey').toString(),
      destination: (meta['destination'] ?? '').toString(),
      mood: (meta['mood'] ?? '').toString(),
      budget: (meta['budget'] as num?)?.toDouble() ?? 0,
      currency: (meta['currency'] ?? 'USD').toString(),
      days: (meta['days'] as num?)?.toInt() ?? dayItems.length,
      nights: (meta['nights'] as num?)?.toInt() ?? 0,
      summary: (meta['summary'] ?? '').toString(),
      budgetSplit: (meta['budget_split'] ?? '').toString(),
      visa: (meta['visa'] ?? '').toString(),
      logistics: (meta['logistics'] ?? '').toString(),
      dayPlans: dayItems.map((d) => OdysseyDay.fromJson(d)).toList(),
      bookingPartners: ((meta['booking_partners'] ?? const []) as List)
          .whereType<Map>()
          .map((bp) => OdysseyBookingPartner.fromJson(bp.cast<String, dynamic>()))
          .toList(),
      flightStrategies: flightStrategies,
      flightGeneralTips: flightGeneralTips,
      flightBestMonths: flightBestMonths,
      hotelStrategies: hotelStrategies,
      hotelGeneralTips: hotelGeneralTips,
      hotelBestAreas: hotelBestAreas,
      status: (json['status'] ?? 'active').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      coverUrl: (meta['cover_url'] ?? '').toString(),
      startDate: (meta['start_date'] ?? meta['flight_start_date'] ?? meta['hotel_check_in_date'] ?? json['trip_date'] ?? '').toString(),
      endDate: (meta['end_date'] ?? meta['flight_end_date'] ?? meta['hotel_check_out_date'] ?? '').toString(),
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
