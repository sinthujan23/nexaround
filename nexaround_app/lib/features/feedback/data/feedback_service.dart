import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One "What should we build next?" choice of a survey round.
class SurveyOption {
  const SurveyOption({required this.key, required this.label, required this.icon});
  final String key;
  final String label;
  final String icon;

  factory SurveyOption.fromJson(Map<String, dynamic> j) => SurveyOption(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        icon: (j['icon'] ?? 'lightbulb').toString(),
      );
}

class SurveyRound {
  const SurveyRound({required this.id, required this.name, required this.options});
  final String id;
  final String name;
  final List<SurveyOption> options;

  factory SurveyRound.fromJson(Map<String, dynamic> j) => SurveyRound(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        options: [
          for (final o in (j['build_next_options'] as List? ?? const []))
            SurveyOption.fromJson((o as Map).cast<String, dynamic>()),
        ],
      );
}

/// What Home shows: the open survey round (or none), whether this explorer
/// answered it, and whether it may pop up by itself now.
class SurveyState {
  const SurveyState({this.round, this.answered = false, this.autoShow = false});
  final SurveyRound? round;
  final bool answered;
  final bool autoShow;

  bool get showTicket => round != null && !answered;

  factory SurveyState.fromJson(Map<String, dynamic> j) => SurveyState(
        round: j['round'] is Map ? SurveyRound.fromJson((j['round'] as Map).cast<String, dynamic>()) : null,
        answered: j['answered'] == true,
        autoShow: j['auto_show'] == true,
      );
}

class SurveyAnswer {
  int? nps;
  final Set<String> features = <String>{};
  final List<String> buildNext = <String>[];
  String buildNextOther = '';
  String? wouldPay;
  String? priceRange;
  final Set<String> whyNot = <String>{};
  String comment = '';
}

class MyFeedbackItem {
  const MyFeedbackItem({
    required this.id,
    required this.type,
    required this.text,
    required this.status,
    required this.createdAt,
    required this.replies,
  });
  final String id;
  final String type;
  final String text;
  final String status;
  final DateTime? createdAt;
  final List<({String text, DateTime? at})> replies;

  factory MyFeedbackItem.fromJson(Map<String, dynamic> j) => MyFeedbackItem(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? 'other').toString(),
        text: (j['text'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        replies: [
          for (final r in (j['replies'] as List? ?? const []))
            (text: ((r as Map)['text'] ?? '').toString(), at: DateTime.tryParse((r['at'] ?? '').toString())),
        ],
      );
}

/// Feedback and the quarterly survey, from `/feedback` and `/survey`.
class FeedbackService {
  final Dio _dio = ApiClient.instance;

  static const String _base = ApiConstants.apiVersion;
  static const String pushType = 'feedback_reply';

  /// Bumped after the survey is answered or snoozed, so the Home card
  /// reloads and turns back into "Tell us what you want".
  static final ValueNotifier<int> surveyRevision = ValueNotifier<int>(0);

  static String get _osVersion {
    try {
      final v = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      return v.length > 80 ? v.substring(0, 80) : v;
    } catch (_) {
      return '';
    }
  }

  /// Uploads one screenshot; returns the name to send with the message.
  Future<String> uploadScreenshot(String filePath) async {
    final form = FormData();
    form.files.add(MapEntry(
      'file',
      await MultipartFile.fromFile(filePath, filename: filePath.split('/').last),
    ));
    final r = await _dio.post('$_base/feedback/screenshots', data: form);
    return ((r.data as Map)['name'] ?? '').toString();
  }

  Future<void> send({
    required String type,
    required String text,
    List<String> screenshots = const [],
    bool canReply = true,
    String? sourceScreen,
    String? feature,
    String? refId,
    String? refLabel,
  }) async {
    await _dio.post('$_base/feedback', data: {
      'type': type,
      'text': text,
      'screenshots': screenshots,
      'can_reply': canReply,
      if (sourceScreen != null) 'source_screen': sourceScreen,
      if (feature != null) 'feature': feature,
      if (refId != null) 'ref_id': refId,
      if (refLabel != null) 'ref_label': refLabel,
      'os_version': _osVersion,
    });
  }

  Future<List<MyFeedbackItem>> mine() async {
    final r = await _dio.get('$_base/feedback/mine');
    return [
      for (final i in ((r.data as Map)['items'] as List? ?? const []))
        MyFeedbackItem.fromJson((i as Map).cast<String, dynamic>()),
    ];
  }

  // ── One-tap "How was it?" ───────────────────────────────────────────────

  static String _ratedKey(String feature, String refId) => 'feedback_rated_v1:$feature:$refId';

  /// Whether this device already asked about [refId] (each plan, trip or
  /// challenge is asked once).
  static Future<bool> alreadyAsked(String feature, String refId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ratedKey(feature, refId)) ?? false;
  }

  static Future<void> markAsked(String feature, String refId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ratedKey(feature, refId), true);
  }

  Future<void> rate({
    required String feature,
    required String refId,
    String? refLabel,
    required bool good,
    List<String> reasons = const [],
  }) async {
    await _dio.post('$_base/feedback/quick', data: {
      'feature': feature,
      'ref_id': refId,
      if (refLabel != null) 'ref_label': refLabel,
      'rating': good ? 'good' : 'bad',
      'reasons': reasons,
    });
  }

  // ── Quarterly survey ────────────────────────────────────────────────────

  Future<SurveyState> currentSurvey() async {
    final r = await _dio.get('$_base/survey/current');
    return SurveyState.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> surveyShown(String roundId) async {
    await _dio.post('$_base/survey/$roundId/shown');
  }

  Future<void> surveyLater(String roundId) async {
    await _dio.post('$_base/survey/$roundId/later');
    surveyRevision.value++;
  }

  Future<void> answerSurvey(String roundId, SurveyAnswer a) async {
    final pays = a.wouldPay == 'yes' || a.wouldPay == 'maybe';
    await _dio.post('$_base/survey/$roundId/answer', data: {
      'nps': a.nps,
      'features': a.features.toList(),
      'build_next': a.buildNext,
      if (a.buildNextOther.trim().isNotEmpty) 'build_next_other': a.buildNextOther.trim(),
      'would_pay': a.wouldPay,
      if (pays) 'price_range': a.priceRange,
      'why_not': pays ? <String>[] : a.whyNot.toList(),
      if (a.comment.trim().isNotEmpty) 'comment': a.comment.trim(),
    });
    surveyRevision.value++;
  }

  /// The server's message for a failed call, or a plain fallback.
  static String errorText(Object e, String fallback) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        return 'No connection. Please try again.';
      }
    }
    return fallback;
  }
}
