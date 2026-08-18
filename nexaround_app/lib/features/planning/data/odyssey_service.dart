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
      'CRITICAL: If the user provides an unrealistically low or impossible budget (e.g. 1 USD or very low amount), '
      'DO NOT FAIL OR REFUSE. Instead, generate an ultra-low budget / free exploration itinerary for the destination, '
      'and include a clear, helpful "budget_advisory" disclaimer explaining the realistic costs required. '
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
    return '''
Design a $days-day travel Odyssey.

Trip brief:
- Destination: $destination
- Travel style / mood: $mood
- Total budget: ${budget.toStringAsFixed(0)} $currency (this is the hard cap for the whole trip)
- Currency to use in all costs: $currency

CRITICAL LOW / IMPOSSIBLE BUDGET HANDLING:
1. If the total budget of ${budget.toStringAsFixed(0)} $currency is too low to cover standard travel/hotel/flights for $destination for $days days (e.g. 1 $currency, very low funds):
   - NEVER fail or refuse to generate a plan.
   - Design an ultra-saver plan with free sights, public parks, iconic viewpoints, self-guided walks, and affordable street food.
   - Set "budget_advisory" with a clear disclaimer: "A total budget of ${budget.toStringAsFixed(0)} $currency is insufficient for a standard $days-day trip to $destination (realistic minimum starts from ~$currency X). This itinerary is generated as an ultra-saver plan with free sights and low-cost exploration, but additional funds will be needed for actual lodging, transit, and meals."
2. If the budget is sufficient, set "budget_advisory": "".

Return ONLY a JSON object with EXACTLY this shape:
{
  "title": "Evocative 2-4 word trip name",
  "destination": "$destination",
  "days": $days,
  "nights": ${days > 1 ? days - 1 : 0},
  "currency": "$currency",
  "summary": "1-2 sentence overview matching the '$mood' style.",
  "budget_split": "Short split, e.g. '40% Stay · 30% Food · 30% Experiences'",
  "budget_advisory": "Notice if budget cap is insufficient for realistic rates, otherwise empty string.",
  "visa": "One line on visa/entry needs for this destination (or 'No visa info' if domestic).",
  "logistics": ["3-5 short practical tips: transport, money, SIM, entry fees, timing"],
  "day_plans": [
    {
      "day": 1,
      "theme": "Short day theme",
      "activities": [
        { "time": "09:00", "name": "Place or activity name", "tip": "Short practical tip", "cost": "$currency amount or 'Free'" }
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
