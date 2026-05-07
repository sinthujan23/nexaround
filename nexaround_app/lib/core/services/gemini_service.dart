import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:nexaround_app/core/constants/api_constants.dart';

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  static const String _modelName = 'gemini-2.5-flash';
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// Text-only prompt
  Future<String> getResponse(String prompt, {String? context}) async {
    final url = Uri.parse('$_baseUrl/$_modelName:generateContent?key=${ApiConstants.geminiApiKey}');
    
    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": context != null ? "Context: $context\n\nUser Question: $prompt" : prompt}
          ]
        }
      ]
    });

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': ApiConstants.geminiApiKey,
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final text = data['candidates'][0]['content']['parts'][0]['text'];
          print('✅ Gemini Response: $text');
          return text;
        }
        return "No response text found.";
      } else {
        print('❌ Gemini API Error: ${response.statusCode} - ${response.body}');
        return "I'm having a bit of trouble connecting to my central processing. Status: ${response.statusCode}";
      }
    } catch (e) {
      print('❌ Gemini Exception: $e');
      return "An unexpected error occurred while talking to Neva: $e";
    }
  }

  /// Vision: send an image (bytes) + text prompt to Gemini
  Future<String> identifyPlace({
    required Uint8List imageBytes,
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse('$_baseUrl/$_modelName:generateContent?key=${ApiConstants.geminiApiKey}');

    final base64Image = base64Encode(imageBytes);

    final prompt = '''You are NexAround's AI travel assistant "Neva". Analyze this image taken at GPS coordinates ($latitude, $longitude).

TASK:
1. Identify the place, landmark, building, or scene in this image
2. Provide a rich, engaging description

RESPOND IN THIS EXACT JSON FORMAT (no markdown, no code blocks):
{
  "identified": true,
  "name": "Place Name",
  "category": "Temple/Restaurant/Park/Museum/Beach/Monument/Market/Hotel",
  "confidence": 0.85,
  "description": "A rich 2-3 sentence description of the place, its history, significance, and what makes it special for tourists.",
  "fun_fact": "One interesting fun fact about this place.",
  "tips": "A practical tip for visitors."
}

If you cannot identify a specific place, set "identified" to false and provide your best guess based on the scene.''';

    final body = jsonEncode({
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
    });

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': ApiConstants.geminiApiKey,
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final text = data['candidates'][0]['content']['parts'][0]['text'];
          print('✅ Gemini Vision Response: $text');
          return text;
        }
        return '{"identified": false, "name": "Unknown", "category": "Unknown", "confidence": 0, "description": "Could not process the image.", "fun_fact": "", "tips": ""}';
      } else {
        print('❌ Gemini Vision Error: ${response.statusCode} - ${response.body}');
        return '{"identified": false, "name": "Unknown", "category": "Unknown", "confidence": 0, "description": "API error: ${response.statusCode}", "fun_fact": "", "tips": ""}';
      }
    } catch (e) {
      print('❌ Gemini Vision Exception: $e');
      return '{"identified": false, "name": "Unknown", "category": "Unknown", "confidence": 0, "description": "Error: $e", "fun_fact": "", "tips": ""}';
    }
  }
}
