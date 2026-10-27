import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

/// One clip of Neva's reply that the backend signed for speaking: only these
/// can be turned into audio, by [NevaService.speak].
class NevaSpeechClip {
  final String text;
  final String lang;
  final String sig;

  const NevaSpeechClip({required this.text, required this.lang, required this.sig});

  Map<String, dynamic> toMap() => {'text': text, 'lang': lang, 'sig': sig};

  static NevaSpeechClip? fromMap(Map map) {
    final text = (map['text'] ?? '').toString();
    final sig = (map['sig'] ?? '').toString();
    if (text.isEmpty || sig.isEmpty) return null;
    return NevaSpeechClip(text: text, lang: (map['lang'] ?? '').toString(), sig: sig);
  }

  static List<NevaSpeechClip> listFrom(dynamic raw) {
    final clips = <NevaSpeechClip>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final clip = fromMap(item);
          if (clip != null) clips.add(clip);
        }
      }
    }
    return clips;
  }
}

/// One Neva reply from the backend: her text, plus the real places she found
/// when the question was "where is…" (empty otherwise), nearest first.
class NevaReply {
  final String text;
  final List<AttractionEntity> places;
  final String query;

  /// The reply as clips to speak, first one short so playback starts early.
  final List<NevaSpeechClip> speech;

  /// For a spoken question: what the user said ("" if it could not be written).
  final String transcript;

  /// For a spoken question: today's voice allowance is used up, so the reply
  /// is text only.
  final bool voicePaused;

  const NevaReply({
    required this.text,
    this.places = const [],
    this.query = '',
    this.speech = const [],
    this.transcript = '',
    this.voicePaused = false,
  });
}

/// Why a spoken question got no reply.
enum NevaVoiceFailure { noSpeech, voiceOff, unavailable }

class NevaVoiceOutcome {
  final NevaReply? reply;
  final NevaVoiceFailure? failure;

  const NevaVoiceOutcome.reply(NevaReply this.reply) : failure = null;
  const NevaVoiceOutcome.failed(NevaVoiceFailure this.failure) : reply = null;
}

/// Neva through `POST /api/v1/neva/chat`, which can search Google Maps near
/// the user and answer from what it finds (client request, 2026-10-01: "respond
/// with map integrated when asking help for location").
///
/// Returns null on any failure so the chat can fall back to the plain Gemini
/// proxy it used before — an older backend, a timeout or a 503 must never
/// leave the user without an answer.
///
/// Voice (2026-10-27): [voice] sends a recorded question to `/neva/voice`,
/// which hears it and answers briefly; [speak] fetches one clip of a reply as
/// audio from `/neva/speak` and keeps it on the device, so a replay is free.
class NevaService {
  static final _options = Options(
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
  );

  static Future<NevaReply?> chat({
    required String message,
    double? latitude,
    double? longitude,
    String? area,
    List<Map<String, String>>? history,
  }) async {
    try {
      final response = await ApiClient.instance.post(
        '${ApiConstants.apiVersion}/neva/chat',
        data: {
          'message': message,
          if (latitude != null && longitude != null) 'latitude': latitude,
          if (latitude != null && longitude != null) 'longitude': longitude,
          if (area != null && area.isNotEmpty && area != 'Nearby') 'area': area,
          if (history != null && history.isNotEmpty) 'history': history,
        },
        options: _options,
      );
      if (response.statusCode != 200) return null;
      return _parse(response.data);
    } catch (e) {
      debugPrint('Neva chat endpoint failed, falling back: $e');
      return null;
    }
  }

  /// Sends the recording at [audioPath] (16 kHz mono WAV) and returns Neva's
  /// short spoken-style reply with what the user said.
  static Future<NevaVoiceOutcome> voice({
    required String audioPath,
    double? latitude,
    double? longitude,
    String? area,
    List<Map<String, String>>? history,
  }) async {
    try {
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(audioPath, filename: 'question.wav'),
        if (latitude != null && longitude != null) 'latitude': latitude.toString(),
        if (latitude != null && longitude != null) 'longitude': longitude.toString(),
        if (area != null && area.isNotEmpty && area != 'Nearby') 'area': area,
        if (history != null && history.isNotEmpty) 'history': jsonEncode(history),
      });
      final response = await ApiClient.instance.post(
        '${ApiConstants.apiVersion}/neva/voice',
        data: form,
        options: _options,
      );
      final reply = response.statusCode == 200 ? _parse(response.data) : null;
      return reply == null
          ? const NevaVoiceOutcome.failed(NevaVoiceFailure.unavailable)
          : NevaVoiceOutcome.reply(reply);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final detail = data is Map ? data['detail']?.toString() : null;
      if (status == 422 && detail == 'no_speech') {
        return const NevaVoiceOutcome.failed(NevaVoiceFailure.noSpeech);
      }
      if (status == 503 && detail == 'voice_off') {
        return const NevaVoiceOutcome.failed(NevaVoiceFailure.voiceOff);
      }
      debugPrint('Neva voice failed: $e');
      return const NevaVoiceOutcome.failed(NevaVoiceFailure.unavailable);
    } catch (e) {
      debugPrint('Neva voice failed: $e');
      return const NevaVoiceOutcome.failed(NevaVoiceFailure.unavailable);
    }
  }

  /// A playable file for [clip]. `path` is null when no audio could be made;
  /// `paused` is true when today's voice allowance is used up or voice is off.
  static Future<({String? path, bool paused})> speak(NevaSpeechClip clip) async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/neva_voice');
      for (final ext in const ['mp3', 'wav']) {
        final file = File('${dir.path}/${clip.sig}.$ext');
        if (await file.exists() && await file.length() > 0) {
          return (path: file.path, paused: false);
        }
      }
      // A stream, not bytes: the logging interceptor would print every byte.
      final response = await ApiClient.instance.post<ResponseBody>(
        '${ApiConstants.apiVersion}/neva/speak',
        data: clip.toMap(),
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final body = response.data;
      if (body == null) return (path: null, paused: false);
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) return (path: null, paused: false);
      final type = response.headers.value(Headers.contentTypeHeader) ?? '';
      await dir.create(recursive: true);
      final file = File('${dir.path}/${clip.sig}.${type.contains('wav') ? 'wav' : 'mp3'}');
      await file.writeAsBytes(bytes, flush: true);
      return (path: file.path, paused: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) return (path: null, paused: true);
      debugPrint('Neva speech failed: $e');
      return (path: null, paused: false);
    } catch (e) {
      debugPrint('Neva speech failed: $e');
      return (path: null, paused: false);
    }
  }

  static NevaReply? _parse(dynamic data) {
    if (data is! Map) return null;
    final text = (data['text'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    final places = <AttractionEntity>[];
    for (final raw in (data['places'] as List?) ?? const []) {
      if (raw is! Map) continue;
      try {
        places.add(AttractionModel.fromJson(raw.cast<String, dynamic>()));
      } catch (e) {
        debugPrint('Neva place skipped: $e');
      }
    }
    return NevaReply(
      text: text,
      places: places,
      query: (data['query'] ?? '').toString(),
      speech: NevaSpeechClip.listFrom(data['speech']),
      transcript: (data['transcript'] ?? '').toString().trim(),
      voicePaused: data['voice_paused'] == true,
    );
  }
}
