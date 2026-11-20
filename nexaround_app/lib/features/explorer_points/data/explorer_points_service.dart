import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/explorer_points/domain/explorer_points.dart';

/// Explorer Points from the server. The last answers are kept on the phone
/// (CacheService) so the level shows at once and offline; [summary] and
/// [info] notify the widgets that show them.
class ExplorerPointsService {
  ExplorerPointsService._();

  static const String pushType = 'explorer_points';
  static const String _base = '${ApiConstants.apiVersion}/points';

  static final ValueNotifier<PointsSummary?> summary = ValueNotifier(_cachedSummary());
  static final ValueNotifier<PointsInfo?> info = ValueNotifier(_cachedInfo());

  static PointsSummary? _cachedSummary() {
    try {
      final s = CacheService.getExplorerPointsJson();
      if (s == null || s.isEmpty) return null;
      return PointsSummary.fromJson(json.decode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static PointsInfo? _cachedInfo() {
    try {
      final s = CacheService.getExplorerPointsInfoJson();
      if (s == null || s.isEmpty) return null;
      return PointsInfo.fromJson(json.decode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// The explainer: levels, how to earn, rules. Public (no sign-in needed).
  static Future<PointsInfo?> loadInfo({bool refresh = false}) async {
    if (!refresh && info.value != null) return info.value;
    try {
      final response = await ApiClient.instance.get('$_base/info');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final parsed = PointsInfo.fromJson(data);
        info.value = parsed;
        await CacheService.saveExplorerPointsInfoJson(json.encode(data));
        return parsed;
      }
    } catch (e) {
      debugPrint('❌ Error fetching points info: $e');
    }
    return info.value ?? _cachedInfo();
  }

  /// The signed-in traveller's points, fresh from the server.
  static Future<PointsSummary?> refresh() async {
    if (!CacheService.isLoggedIn()) return null;
    try {
      final response = await ApiClient.instance.get('$_base/me');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final parsed = PointsSummary.fromJson(data);
        summary.value = parsed;
        await CacheService.saveExplorerPointsJson(json.encode(data));
        return parsed;
      }
    } catch (e) {
      debugPrint('❌ Error fetching my points: $e');
    }
    return null;
  }

  /// On every start of the signed-in app: sends the old phone-only XP once
  /// (the server tops the account up to it, capped), then reads the points.
  static Future<void> sync() async {
    // A sign-out cleared the stored copy: never show the last account's level.
    summary.value = _cachedSummary();
    if (!CacheService.isLoggedIn()) return;
    unawaited(loadInfo(refresh: true));
    final legacy = CacheService.getLegacyExplorerXp();
    if (legacy != null) {
      try {
        if (legacy > 0) {
          await ApiClient.instance.post('$_base/carry-over', data: {'xp': legacy});
        }
        await CacheService.clearLegacyExplorerXp();
      } catch (e) {
        // Kept for the next start.
        debugPrint('❌ Points carry-over failed: $e');
      }
    }
    await refresh();
  }

  /// After signing out.
  static void clear() => summary.value = null;
}
