import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

/// Generates a full trip "Odyssey" with Gemini.
///
/// Uses [GeminiService] (which proxies through the backend, so the API key never
/// ships in the app) and forces a JSON response via `responseMimeType`, so the
/// model returns a parseable plan rather than prose.
class OdysseyService {
  OdysseyService({GeminiService? gemini})
      : _gemini = gemini ?? GeminiService();

  final GeminiService _gemini;

  static const String _systemInstruction =
      'You are NexAround\'s expert local travel designer. '
      'You craft realistic, budget-aware, day-by-day trip blueprints. '
      'You always reply with a single JSON object that matches the requested '
      'schema exactly — no markdown, no commentary, no code fences. '
      'CRITICAL HOTEL REQUIREMENT: Recommend ONLY genuine, real, famous, and currently operating hotels that are bookable on major platforms like Booking.com and Agoda. DO NOT invent fictitious names or append company suffixes like "Pvt Ltd" or "City". Use the exact official hotel name as listed on Google Maps / Booking.com (e.g., "The Heritage Madurai", "Hotel Royal Court", "Courtyard by Marriott Madurai"). Exclude non-existent or unbookable properties.';

  Future<Odyssey> generate({
    required String destination,
    required String mood,
    required double budget,
    int days = 3,
    String currency = 'USD',
  }) async {
    final prompt = _buildPrompt(
      destination: destination,
      mood: mood,
      budget: budget,
      days: days,
      currency: currency,
    );

    final raw = await _gemini.getResponse(
      prompt,
      systemInstruction: _systemInstruction,
      temperature: 0.8,
      maxOutputTokens: 4096,
      responseMimeType: 'application/json',
    );

    final json = _extractJson(raw);
    if (json == null) {
      throw const OdysseyGenerationException(
        'The AI returned an unexpected response. Please try again.',
      );
    }

    final odyssey = Odyssey.fromGemini(
      json,
      destination: destination,
      mood: mood,
      budget: budget,
      currency: currency,
    );

    if (odyssey.dayPlans.isEmpty) {
      throw const OdysseyGenerationException(
        'Could not build a plan for this trip. Try a different destination or budget.',
      );
    }
    return odyssey;
  }

  String _buildPrompt({
    required String destination,
    required String mood,
    required double budget,
    required int days,
    required String currency,
  }) {
    final nights = days > 1 ? days - 1 : 0;
    return '''
Design a $days-day travel Odyssey.

Trip brief:
- Destination: $destination
- Travel style / mood: $mood
- Total budget: ${budget.toStringAsFixed(0)} $currency (hard cap for the entire trip)
- Currency to use in all costs: $currency

CRITICAL — LIVE SEARCH GROUNDING RULES:
1. You MUST find current prices — do not recall prices from memory/training data.
2. For EVERY costed activity (attraction tickets, transit fares, typical meal prices, hotel/night rates), search for that specific item before writing its cost.
3. If a search genuinely returns no usable price for an item, set "price_confidence": "Estimated" and state in "price_basis": "No current search result found; figure is a general regional estimate, not sourced."
4. "price_source" must name the actual source you found (the site, publisher, or official page name) — never a generic label with no real anchor behind it.
5. The ONLY links allowed are the fixed "booking_partners" URLs given below.

CRITICAL PRICE JUSTIFICATION RULES:
1. Every non-zero cost MUST cite a concrete, named reference point — never a vague category.
2. "price_basis" MUST state the actual anchor rate/figure found and any currency conversion applied, in one sentence.
3. Add "price_confidence" to every costed activity ("Fixed" | "Typical" | "Estimated").

Return ONLY a JSON object with EXACTLY this shape:
{
  "title": "Evocative 2-4 word trip name",
  "destination": "$destination",
  "days": $days,
  "nights": $nights,
  "currency": "$currency",
  "summary": "1-2 sentence overview matching the '$mood' style.",
  "budget_split": "Short split, e.g. '35% Stay - 45% Transit - 12% Food - 8% Activities'",
  "budget_breakdown": {
    "stay": 0,
    "transit": 0,
    "food": 0,
    "activities": 0,
    "total": ${budget.toInt()}
  },
  "visa": "One line on visa/entry needs for this destination (or 'No visa info' if domestic).",
  "logistics": ["3-5 short practical tips: transport, money, SIM, entry fees, timing"],
  "booking_partners": [
    { "name": "Booking.com", "type": "hotels", "url": "https://www.booking.com" },
    { "name": "Viator", "type": "tours", "url": "https://www.viator.com" },
    { "name": "Skyscanner", "type": "transit", "url": "https://www.skyscanner.com" }
  ],
  "day_plans": [
    {
      "day": 1,
      "theme": "Short day theme",
      "activities": [
        {
          "time": "09:00",
          "name": "Place or activity name",
          "tip": "Short practical tip",
          "cost": "$currency amount or 'Free'",
          "price_source": "Named source actually found (site/publisher/official page)",
          "price_basis": "1-sentence statement of the actual anchor rate/figure found and any conversion applied",
          "price_confidence": "Fixed | Typical | Estimated",
          "type": "transport|attraction|dining|exploration|accommodation|other",
          "restaurants": []
        }
      ]
    }
  ]
}

Rules:
- Produce exactly $days entries in "day_plans", each with 3-5 activities.
- Keep the SUM of all activity costs within the ${budget.toStringAsFixed(0)} $currency budget.
- Use real, recognisable places near "$destination".
- Be concise; tips under ~12 words.
''';
  }

  /// Pull a JSON object out of the model's text. Handles clean JSON, stray code
  /// fences, or leading/trailing prose.
  Map<String, dynamic>? _extractJson(String raw) {
    final text = raw.trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // fall through to brace-slicing
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end > start) {
      try {
        final decoded = jsonDecode(text.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (e) {
        debugPrint('OdysseyService: JSON parse failed: $e');
      }
    }
    return null;
  }
}

class OdysseyGenerationException implements Exception {
  final String message;
  const OdysseyGenerationException(this.message);
  @override
  String toString() => message;
}
