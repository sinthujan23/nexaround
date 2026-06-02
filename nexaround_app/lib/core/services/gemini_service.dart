import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';

/// Per-request timeout for Gemini calls. The shared ApiClient uses a 20s
/// receiveTimeout, which is too short for generative requests (an itinerary can
/// take 20-40s end to end, and the backend proxy itself allows 60s upstream).
/// We override it here so long generations don't get their socket torn down.
final _kGeminiOptions = Options(
  receiveTimeout: const Duration(seconds: 120),
  sendTimeout: const Duration(seconds: 60),
);

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  /// Text-only prompt
  Future<String> getResponse(
    String prompt, {
    String? context,
    String? systemInstruction,
    double? temperature,
    int? maxOutputTokens,
    String? responseMimeType,
  }) async {
    final path = ApiConstants.geminiProxy;

    final Map<String, dynamic> requestBody = {
      "contents": [
        {
          "parts": [
            {"text": context != null ? "Context: $context\n\nUser Question: $prompt" : prompt}
          ]
        }
      ],
    };

    if (systemInstruction != null) {
      requestBody["system_instruction"] = {
        "parts": [{"text": systemInstruction}]
      };
    }

    final Map<String, dynamic> generationConfig = {};
    if (temperature != null) generationConfig["temperature"] = temperature;
    if (maxOutputTokens != null) generationConfig["maxOutputTokens"] = maxOutputTokens;
    if (responseMimeType != null) generationConfig["responseMimeType"] = responseMimeType;
    if (generationConfig.isNotEmpty) requestBody["generationConfig"] = generationConfig;

    try {
      final response = await ApiClient.instance.post(
        path,
        data: requestBody,
        options: _kGeminiOptions,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data['candidates'] != null && data['candidates'].isNotEmpty) {
          final text = data['candidates'][0]['content']['parts'][0]['text'];
          print('✅ Gemini Response: $text');
          return text;
        }
        return "No response text found.";
      } else {
        print('❌ Gemini Proxy API Error: ${response.statusCode} - ${response.data}');
        return "I'm having a bit of trouble connecting to my central processing. Status: ${response.statusCode}";
      }
    } catch (e) {
      print('❌ Gemini Proxy Exception: $e');
      return "An unexpected error occurred while talking to Neva: $e";
    }
  }

  /// Vision: send an image (bytes) + text prompt to Gemini
  Future<String> identifyPlace({
    required Uint8List imageBytes,
    required double latitude,
    required double longitude,
  }) async {
    final path = ApiConstants.geminiProxy;
    final base64Image = base64Encode(imageBytes);

    final prompt = '''You are NexAround's AI travel assistant "Neva". Analyze this image taken at GPS coordinates ($latitude, $longitude).

IMPORTANT CONTEXT:
- This could be a local business, office, residential building, or everyday location
- Focus on accuracy - if it's just an office or generic building, identify it as such
- Don't invent famous landmarks if the image shows a regular building
- Consider the GPS coordinates to verify your identification

TASK:
1. Identify what's actually shown - be honest if it's a regular office/building
2. If it's a specific named place, identify it accurately
3. If it's a generic office/building, describe it truthfully
4. Provide relevant information based on what's actually visible

RESPOND IN THIS EXACT JSON FORMAT (no markdown, no code blocks):
{
  "identified": true,
  "name": "Actual Place Name or 'Office Building'/'Local Business'/'Residential Building'",
  "category": "Office/Restaurant/Park/Museum/Beach/Monument/Market/Hotel/Local Business/Residential",
  "confidence": 0.85,
  "description": "Honest description of what this place actually is. If it's an office, say so. If it's a local shop, describe it. Don't exaggerate.",
  "fun_fact": "Relevant fact if it's a notable place, or general observation about the building type.",
  "tips": "Practical information relevant to this type of place."
}

If you cannot confidently identify the place, set "identified" to false and describe what you see (e.g., "Modern office building with glass facade").''';

    final requestBody = {
      "contents": [
        {
          "parts": [
            {"text": prompt},
            {
              "inline_data": {
                "mime_type": "image/jpeg",
                "data": base64Image,
              }
            }
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.4,
        "maxOutputTokens": 1024,
      }
    };

    try {
      final response = await ApiClient.instance.post(
        path,
        data: requestBody,
        options: _kGeminiOptions,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data['candidates'] != null && data['candidates'].isNotEmpty) {
          final text = data['candidates'][0]['content']['parts'][0]['text'];
          print('✅ Gemini Proxy Vision Response: $text');
          return text;
        }
        return '{"identified": false, "name": "Unknown", "category": "Unknown", "confidence": 0, "description": "Could not process the image.", "fun_fact": "", "tips": ""}';
      } else {
        print('❌ Gemini Proxy Vision Error: ${response.statusCode} - ${response.data}');
        return '{"identified": false, "name": "Unknown", "category": "Unknown", "confidence": 0, "description": "API error: ${response.statusCode}", "fun_fact": "", "tips": ""}';
      }
    } catch (e) {
      print('❌ Gemini Proxy Vision Exception: $e');
      return '{"identified": false, "name": "Unknown", "category": "Unknown", "confidence": 0, "description": "Error: $e", "fun_fact": "", "tips": ""}';
    }
  }
}
