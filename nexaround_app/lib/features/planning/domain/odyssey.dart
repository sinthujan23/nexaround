/// Domain models for an AI-generated "Odyssey" (a full trip blueprint).
///
/// An Odyssey is persisted on the backend by reusing the existing `itineraries`
/// table: the title/status/id map to the Itinerary columns, and the whole
/// structured plan rides inside the flexible JSON `items` list as:
///   items[0]      -> the meta header  ({'kind': 'odyssey_meta', ...})
///   items[1..n]   -> one block per day ({'kind': 'day', 'day': 1, ...})
/// This needs no DB migration — the backend stores/returns the JSON verbatim.
library;

import 'package:nexaround_app/core/utils/number_format.dart';

/// Activity type classification for rendering type-specific action buttons.
enum ActivityType {
  transport,   // "Travel to X" → Uber/taxi button
  attraction,  // Museums, temples, landmarks → Headout ticket button
  dining,      // Lunch, Dinner → Restaurant LIST button
  exploration, // "Explore X" (free/self-guided) → GET A GUIDE button
  accommodation, // Check into hotel
  other,       // Fallback
}

/// A single restaurant suggestion within a dining activity.
class RestaurantOption {
  final String name;
  final String cuisine;
  final String priceRange; // e.g. "INR 1,500 – 3,000"
  final String rating;     // e.g. "4.5"
  final String tip;

  const RestaurantOption({
    required this.name,
    this.cuisine = '',
    this.priceRange = '',
    this.rating = '',
    this.tip = '',
  });

  factory RestaurantOption.fromJson(Map<String, dynamic> json) => RestaurantOption(
        name: (json['name'] ?? '').toString(),
        cuisine: (json['cuisine'] ?? '').toString(),
        priceRange: (json['price_range'] ?? '').toString(),
        rating: (json['rating'] ?? '').toString(),
        tip: (json['tip'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'cuisine': cuisine,
        'price_range': priceRange,
        'rating': rating,
        'tip': tip,
      };
}

/// A single scheduled stop within a day.
class OdysseyActivity {
  final String time; // e.g. "09:00" or "Morning"
  final String name; // place / activity name
  final String tip; // short practical note
  final String cost; // optional human-readable cost, e.g. "LKR 1,500"
  final String priceSource; // e.g. "Official Gate Ticket", "Uber / Metered Taxi", "Public Access"
  final String priceBasis; // explanation/details of the rate baseline
  final String priceConfidence; // "Fixed" | "Typical" | "Estimated" (from Google Search grounding)
  final bool visited; // ticked off as the traveler completes the trip
  final ActivityType type; // classified activity type
  final String actualCost; // user-entered actual cost after completing
  final String bookingUrl; // optional deep link for booking
  final List<RestaurantOption> restaurants; // dining activity restaurant list

  const OdysseyActivity({
    required this.time,
    required this.name,
    this.tip = '',
    this.cost = '',
    this.priceSource = '',
    this.priceBasis = '',
    this.priceConfidence = '',
    this.visited = false,
    this.type = ActivityType.other,
    this.actualCost = '',
    this.bookingUrl = '',
    this.restaurants = const [],
  });

  OdysseyActivity copyWith({
    bool? visited,
    String? actualCost,
    ActivityType? type,
    String? priceSource,
    String? priceBasis,
    String? priceConfidence,
  }) =>
      OdysseyActivity(
        time: time,
        name: name,
        tip: tip,
        cost: cost,
        priceSource: priceSource ?? this.priceSource,
        priceBasis: priceBasis ?? this.priceBasis,
        priceConfidence: priceConfidence ?? this.priceConfidence,
        visited: visited ?? this.visited,
        type: type ?? this.type,
        actualCost: actualCost ?? this.actualCost,
        bookingUrl: bookingUrl,
        restaurants: restaurants,
      );

  factory OdysseyActivity.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? json['attraction_name'] ?? '').toString();
    final cost = (json['cost'] ?? '').toString();
    final rawType = (json['type'] ?? '').toString().toLowerCase().trim();

    // Parse type from JSON or infer from name/cost heuristics
    final type = _parseType(rawType, name, cost);

    return OdysseyActivity(
      time: (json['time'] ?? '').toString(),
      name: name,
      tip: (json['tip'] ?? json['note'] ?? '').toString(),
      cost: cost,
      priceSource: (json['price_source'] ?? json['source'] ?? '').toString(),
      priceBasis: (json['price_basis'] ?? json['basis'] ?? '').toString(),
      priceConfidence: (json['price_confidence'] ?? '').toString(),
      visited: json['visited'] == true,
      type: type,
      actualCost: (json['actual_cost'] ?? '').toString(),
      bookingUrl: (json['booking_url'] ?? '').toString(),
      restaurants: ((json['restaurants'] as List?) ?? const [])
          .whereType<Map>()
          .map((r) => RestaurantOption.fromJson(r.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time,
        'name': name,
        'tip': tip,
        'cost': cost,
        'price_source': priceSource,
        'price_basis': priceBasis,
        'price_confidence': priceConfidence,
        'visited': visited,
        'type': type.name,
        'actual_cost': actualCost,
        'booking_url': bookingUrl,
        if (restaurants.isNotEmpty)
          'restaurants': restaurants.map((r) => r.toJson()).toList(),
      };

  /// Infer activity type from explicit JSON value or name/cost heuristics.
  /// Provides backward compatibility for odysseys generated before type field existed.
  static ActivityType _parseType(String rawType, String name, String cost) {
    // 1. Try explicit type from AI
    if (rawType.isNotEmpty) {
      switch (rawType) {
        case 'transport':
        case 'transit':
        case 'travel':
          return ActivityType.transport;
        case 'attraction':
        case 'museum':
        case 'landmark':
        case 'ticket':
          return ActivityType.attraction;
        case 'dining':
        case 'restaurant':
        case 'food':
        case 'meal':
          return ActivityType.dining;
        case 'exploration':
        case 'explore':
        case 'walk':
        case 'wander':
          return ActivityType.exploration;
        case 'accommodation':
        case 'hotel':
        case 'check-in':
        case 'checkin':
          return ActivityType.accommodation;
      }
    }

    // 2. Heuristic fallback: infer from activity name
    final lower = name.toLowerCase();

    // Transport
    if (lower.startsWith('travel to') ||
        lower.startsWith('drive to') ||
        lower.startsWith('taxi to') ||
        lower.startsWith('uber to') ||
        lower.startsWith('transfer to') ||
        lower.startsWith('ride to') ||
        lower.contains('airport transfer') ||
        lower.contains('ferry to') ||
        lower.contains('bus to') ||
        lower.contains('train to')) {
      return ActivityType.transport;
    }

    // Accommodation
    if (lower.startsWith('check into') ||
        lower.startsWith('check in') ||
        lower.contains('hotel') && lower.contains('check')) {
      return ActivityType.accommodation;
    }

    // Dining
    if (lower.startsWith('lunch') ||
        lower.startsWith('dinner') ||
        lower.startsWith('breakfast') ||
        lower.startsWith('brunch') ||
        lower.contains('lunch at') ||
        lower.contains('lunch in') ||
        lower.contains('dinner at') ||
        lower.contains('dinner in') ||
        lower.contains('breakfast at') ||
        lower.contains('street food') ||
        lower.contains('food tour') ||
        lower.contains('dining') ||
        lower.contains('restaurant')) {
      return ActivityType.dining;
    }

    // Exploration (free/self-guided)
    if (lower.startsWith('explore') ||
        lower.startsWith('wander') ||
        lower.startsWith('walk through') ||
        lower.startsWith('stroll') ||
        lower.contains('free walking') ||
        lower.contains('self-guided')) {
      return ActivityType.exploration;
    }

    // Attraction (ticketed places)
    final costLower = cost.toLowerCase();
    final hasCost = cost.isNotEmpty &&
        costLower != 'free' &&
        costLower != '0' &&
        !costLower.contains('free');
    if (hasCost &&
        (lower.contains('museum') ||
            lower.contains('cathedral') ||
            lower.contains('temple') ||
            lower.contains('palace') ||
            lower.contains('castle') ||
            lower.contains('fort') ||
            lower.contains('gallery') ||
            lower.contains('monument') ||
            lower.contains('basilica') ||
            lower.contains('church') ||
            lower.contains('mosque') ||
            lower.contains('catacomb') ||
            lower.contains('aquarium') ||
            lower.contains('zoo') ||
            lower.contains('tower') ||
            lower.contains('gardens') ||
            lower.contains('park') ||
            lower.contains('ruins'))) {
      return ActivityType.attraction;
    }

    return ActivityType.other;
  }
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

/// A real citation Gemini's Google Search grounding actually found — the
/// non-fabricated alternative to per-activity deep links, which the backend
/// deliberately refuses to invent.
class VerifiedSource {
  final String title;
  final String uri;

  const VerifiedSource({required this.title, required this.uri});

  factory VerifiedSource.fromJson(Map<String, dynamic> json) => VerifiedSource(
        title: (json['title'] ?? '').toString(),
        uri: (json['uri'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'title': title, 'uri': uri};
}

/// Upfront feasibility read: is the budget/timing realistic, and what's the
/// single biggest risk. `budgetTightness`/`minimumRequired` are computed
/// server-side from the deterministic cost floor; `biggestRisk` is Gemini's.
class OdysseyVerdict {
  final bool feasible;
  final String budgetTightness; // "tight" | "comfortable" | "unknown"
  final double? minimumRequired;
  final String biggestRisk;
  final String recommendation;

  const OdysseyVerdict({
    this.feasible = true,
    this.budgetTightness = 'unknown',
    this.minimumRequired,
    this.biggestRisk = '',
    this.recommendation = '',
  });

  factory OdysseyVerdict.fromJson(Map<String, dynamic> json) => OdysseyVerdict(
        feasible: json['feasible'] == null ? true : json['feasible'] == true,
        budgetTightness: (json['budget_tightness'] ?? 'unknown').toString(),
        minimumRequired: (json['minimum_required'] as num?)?.toDouble(),
        biggestRisk: (json['biggest_risk'] ?? '').toString(),
        recommendation: (json['recommendation'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'feasible': feasible,
        'budget_tightness': budgetTightness,
        'minimum_required': minimumRequired,
        'biggest_risk': biggestRisk,
        'recommendation': recommendation,
      };
}

class OdysseyPracticalInfo {
  final String money;
  final String connectivity;
  final String safety;
  final String customs;

  const OdysseyPracticalInfo({
    this.money = '',
    this.connectivity = '',
    this.safety = '',
    this.customs = '',
  });

  bool get isEmpty =>
      money.isEmpty && connectivity.isEmpty && safety.isEmpty && customs.isEmpty;

  factory OdysseyPracticalInfo.fromJson(Map<String, dynamic> json) => OdysseyPracticalInfo(
        money: (json['money'] ?? '').toString(),
        connectivity: (json['connectivity'] ?? '').toString(),
        safety: (json['safety'] ?? '').toString(),
        customs: (json['customs'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'money': money,
        'connectivity': connectivity,
        'safety': safety,
        'customs': customs,
      };
}

/// One priority-ordered checklist row, e.g. label "BOOK NOW", item "Check
/// into Hotel X". Assembled server-side from data already generated —
/// booking partners, confirmed flight/hotel, visa line — not a new LLM call.
class OdysseyBookingPlanItem {
  final String label; // BOOK NOW | BOOK AFTER VISA | BOOK CLOSER TO TRAVEL | CAN WAIT
  final String item;
  final String reason;
  final String url;

  const OdysseyBookingPlanItem({
    required this.label,
    required this.item,
    this.reason = '',
    this.url = '',
  });

  factory OdysseyBookingPlanItem.fromJson(Map<String, dynamic> json) => OdysseyBookingPlanItem(
        label: (json['label'] ?? '').toString(),
        item: (json['item'] ?? '').toString(),
        reason: (json['reason'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'item': item,
        'reason': reason,
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
  final int reviews;
  final String pricePerNight;
  final String totalEstimatedCost;
  final String location;
  final List<String> amenities;
  final String description;
  final String bookingUrl;
  final String serpApiLink;

  const HotelStrategy({
    required this.rank,
    required this.name,
    required this.providerName,
    required this.category,
    required this.rating,
    this.reviews = 0,
    required this.pricePerNight,
    required this.totalEstimatedCost,
    required this.location,
    required this.amenities,
    required this.description,
    required this.bookingUrl,
    this.serpApiLink = '',
  });

  factory HotelStrategy.fromJson(Map<String, dynamic> json) => HotelStrategy(
        rank: FlightStrategy._parseInt(json['rank'], 1),
        name: (json['name'] ?? '').toString(),
        providerName: (json['provider_name'] ?? json['provider'] ?? 'Booking.com').toString(),
        category: (json['category'] ?? '').toString(),
        rating: (json['rating'] ?? '').toString(),
        reviews: FlightStrategy._parseInt(json['reviews'], 0),
        pricePerNight: (json['price_per_night'] ?? '').toString(),
        totalEstimatedCost: (json['total_estimated_cost'] ?? json['total_cost'] ?? '').toString(),
        location: (json['location'] ?? '').toString(),
        amenities: (json['amenities'] is List)
            ? (json['amenities'] as List).map((e) => e.toString()).toList()
            : <String>[],
        description: (json['description'] ?? '').toString(),
        bookingUrl: (json['booking_url'] ?? '').toString(),
        serpApiLink: (json['serpapi_link'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'name': name,
        'provider_name': providerName,
        'category': category,
        'rating': rating,
        'reviews': reviews,
        'price_per_night': pricePerNight,
        'total_estimated_cost': totalEstimatedCost,
        'location': location,
        'amenities': amenities,
        'description': description,
        'booking_url': bookingUrl,
        'serpapi_link': serpApiLink,
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
  final String departureCity;
  final int travelers;
  final Map<String, double> budgetBreakdown;
  final String budgetAdvisory;
  final OdysseyVerdict? verdict;
  final Map<String, Map<String, double>> budgetScenarios;
  final OdysseyPracticalInfo practicalInfo;
  final List<OdysseyBookingPlanItem> bookingPlan;
  final List<VerifiedSource> verifiedSources;

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
    this.departureCity = '',
    this.travelers = 1,
    this.budgetBreakdown = const {},
    this.budgetAdvisory = '',
    this.verdict,
    this.budgetScenarios = const {},
    this.practicalInfo = const OdysseyPracticalInfo(),
    this.bookingPlan = const [],
    this.verifiedSources = const [],
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
    String? departureCity,
    int? travelers,
    Map<String, double>? budgetBreakdown,
    OdysseyVerdict? verdict,
    Map<String, Map<String, double>>? budgetScenarios,
    OdysseyPracticalInfo? practicalInfo,
    List<OdysseyBookingPlanItem>? bookingPlan,
    List<VerifiedSource>? verifiedSources,
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
        departureCity: departureCity ?? this.departureCity,
        travelers: travelers ?? this.travelers,
        budgetBreakdown: budgetBreakdown ?? this.budgetBreakdown,
        budgetAdvisory: budgetAdvisory,
        verdict: verdict ?? this.verdict,
        budgetScenarios: budgetScenarios ?? this.budgetScenarios,
        practicalInfo: practicalInfo ?? this.practicalInfo,
        bookingPlan: bookingPlan ?? this.bookingPlan,
        verifiedSources: verifiedSources ?? this.verifiedSources,
      );

  // ── Trip progress (per-place check-off) ──────────────────────────────────
  int get totalActivities =>
      dayPlans.fold(0, (n, d) => n + d.activities.length);
  int get visitedActivities => dayPlans.fold(
      0, (n, d) => n + d.activities.where((a) => a.visited).length);
  bool get isComplete =>
      totalActivities > 0 && visitedActivities == totalActivities;
  bool get isGenerating => status == 'generating';
  bool get isFailed => status == 'failed';

  /// Computes the exact number of calendar days based on date range (startDate..endDate),
  /// falling back to dayPlans.length or the default days property.
  int get actualDays {
    final s = startDate?.trim() ?? '';
    final e = endDate?.trim() ?? '';
    if (s.isNotEmpty && e.isNotEmpty) {
      try {
        final startDt = DateTime.parse(s);
        final endDt = DateTime.parse(e);
        final diff = endDt.difference(startDt).inDays;
        if (diff >= 0) return diff + 1;
      } catch (_) {}
    }
    if (dayPlans.isNotEmpty) {
      return dayPlans.length;
    }
    return days > 0 ? days : 1;
  }

  /// One-line stats label used on cards, e.g. "4 Days · LKR 120,000".
  String get statsLabel =>
      '$actualDays ${actualDays == 1 ? 'Day' : 'Days'} · $currency ${formatAmount(budget)}';

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

  /// Compact date range for small grid cards, e.g. "Aug 10–12" or "Aug 10 – Sep 2".
  String get formattedShortDateRange {
    final s = startDate?.trim() ?? '';
    final e = endDate?.trim() ?? '';
    if (s.isEmpty) return '';
    try {
      final startDt = DateTime.parse(s);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      if (e.isNotEmpty) {
        final endDt = DateTime.parse(e);
        if (startDt.month == endDt.month && startDt.year == endDt.year) {
          return '${months[startDt.month - 1]} ${startDt.day}–${endDt.day}';
        }
        return '${months[startDt.month - 1]} ${startDt.day} – ${months[endDt.month - 1]} ${endDt.day}';
      }
      return '${months[startDt.month - 1]} ${startDt.day}';
    } catch (_) {
      if (e.isNotEmpty) return '$s – $e';
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
      budgetBreakdown: json['budget_breakdown'] is Map
          ? (json['budget_breakdown'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0),
            )
          : const {},
      budgetAdvisory: (json['budget_advisory'] ?? '').toString(),
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
          'departure_city': departureCity,
          'travelers': travelers,
          'budget_breakdown': budgetBreakdown,
          'budget_advisory': budgetAdvisory,
          'verdict': verdict?.toJson() ?? {},
          'budget_scenarios': budgetScenarios,
          'practical_info': practicalInfo.toJson(),
          'booking_plan': bookingPlan.map((b) => b.toJson()).toList(),
          'verified_sources': verifiedSources.map((s) => s.toJson()).toList(),
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
    final List<FlightStrategy> flightStrategies = flightStrategiesRaw is Map
        ? ((flightStrategiesRaw['strategies'] as List?) ?? const [])
            .whereType<Map>()
            .map((fs) => FlightStrategy.fromJson(fs.cast<String, dynamic>()))
            .toList()
        : const [];
    final List<String> flightGeneralTips = flightStrategiesRaw is Map
        ? ((flightStrategiesRaw['general_tips'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList()
        : const [];
    final String flightBestMonths = flightStrategiesRaw is Map
        ? (flightStrategiesRaw['best_months'] ?? '').toString()
        : '';

    final hotelStrategiesRaw = meta['hotel_strategies'];
    final List<HotelStrategy> hotelStrategies = hotelStrategiesRaw is Map
        ? ((hotelStrategiesRaw['strategies'] as List?) ?? const [])
            .whereType<Map>()
            .map((hs) => HotelStrategy.fromJson(hs.cast<String, dynamic>()))
            .toList()
        : const [];
    final List<String> hotelGeneralTips = hotelStrategiesRaw is Map
        ? ((hotelStrategiesRaw['general_tips'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList()
        : const [];
    final String hotelBestAreas = hotelStrategiesRaw is Map
        ? (hotelStrategiesRaw['best_areas'] ?? '').toString()
        : '';

    final verdictRaw = meta['verdict'];
    final OdysseyVerdict? verdict = (verdictRaw is Map && verdictRaw.isNotEmpty)
        ? OdysseyVerdict.fromJson(verdictRaw.cast<String, dynamic>())
        : null;

    final budgetScenariosRaw = meta['budget_scenarios'];
    final Map<String, Map<String, double>> budgetScenarios = budgetScenariosRaw is Map
        ? budgetScenariosRaw.map((k, v) => MapEntry(
            k.toString(),
            v is Map
                ? v.map((ik, iv) => MapEntry(ik.toString(), (iv as num?)?.toDouble() ?? 0.0))
                : <String, double>{},
          ))
        : const {};

    final practicalInfoRaw = meta['practical_info'];
    final OdysseyPracticalInfo practicalInfo = practicalInfoRaw is Map
        ? OdysseyPracticalInfo.fromJson(practicalInfoRaw.cast<String, dynamic>())
        : const OdysseyPracticalInfo();

    final List<OdysseyBookingPlanItem> bookingPlan = ((meta['booking_plan'] ?? const []) as List)
        .whereType<Map>()
        .map((b) => OdysseyBookingPlanItem.fromJson(b.cast<String, dynamic>()))
        .toList();

    final List<VerifiedSource> verifiedSources = ((meta['verified_sources'] ?? const []) as List)
        .whereType<Map>()
        .map((s) => VerifiedSource.fromJson(s.cast<String, dynamic>()))
        .toList();

    return Odyssey(
      id: json['id']?.toString(),
      title: (meta['title'] ?? json['title'] ?? 'Odyssey').toString(),
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
      departureCity: (meta['departure_city'] ?? '').toString(),
      travelers: (meta['travelers'] as num?)?.toInt() ?? 1,
      budgetBreakdown: meta['budget_breakdown'] is Map
          ? (meta['budget_breakdown'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0),
            )
          : const {},
      budgetAdvisory: (meta['budget_advisory'] ?? '').toString(),
      verdict: verdict,
      budgetScenarios: budgetScenarios,
      practicalInfo: practicalInfo,
      bookingPlan: bookingPlan,
      verifiedSources: verifiedSources,
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
