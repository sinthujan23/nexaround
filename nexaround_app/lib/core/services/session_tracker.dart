import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Measures each visit to the app (time in the foreground) and reports it to
/// the backend (`POST /auth/me/session`). This feeds the admin panel's
/// explorer activity, DAU and average-session-length metrics.
///
/// Some phones cut an app's network the moment it leaves the screen, so a
/// report sent only then never arrived from them: an explorer could use the
/// app for weeks and show two sessions. Each visit therefore has its own id
/// and is reported
///  - while still on screen, once it reaches 30 s (the admin's threshold for
///    an active day) and then every 5 minutes;
///  - when it ends; that report is kept on the phone until the server has it
///    and is resent on the next open;
///  - up to its last checkpoint, if the app was killed during it.
/// The server keeps one row per visit id, so repeated reports are harmless.
/// Fire-and-forget: analytics never blocks the UI or shows an error.
class SessionTracker with WidgetsBindingObserver {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  /// Ended visits not yet delivered: [{id, seconds, ended}], `ended` in UTC.
  static const _pendingKey = 'session_tracker_pending';

  /// The visit on screen when last saved: {id: {since, seen}}, in UTC. One
  /// still here at the next open belongs to a run that was killed.
  static const _openKey = 'session_tracker_open';

  static const _firstReportSeconds = 30;
  static const _reportEverySeconds = 300;
  static const _minSeconds = 2; // shorter visits are blips, not reported
  static const _tick = Duration(seconds: 15);
  static const _keepFor = Duration(days: 7); // the server drops older reports
  static const _maxPending = 50;
  static const _sendTimeout = Duration(seconds: 20);

  bool _registered = false;
  String? _visitId;
  DateTime? _since;
  int _reportedSeconds = 0;
  bool _reporting = false;
  Timer? _timer;

  /// Storage work runs one job at a time, in the order it was asked for.
  Future<void> _queue = Future<void>.value();

  /// Call once at startup. A visit starts once the app is on screen, so an
  /// app woken in the background (a push on iOS) records nothing.
  void start() {
    if (_registered) return;
    _registered = true;
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _begin();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_visitId == null) _begin();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _end();
    }
  }

  void _begin() {
    final id = const Uuid().v4();
    final since = DateTime.now().toUtc();
    _visitId = id;
    _since = since;
    _reportedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _onTick());

    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      // A visit still marked open was cut short by the app being killed; it
      // lasted until its last checkpoint.
      final pending = _readList(prefs, _pendingKey);
      _readMap(prefs, _openKey).forEach((oldId, value) {
        if (value is! Map) return;
        final start = DateTime.tryParse('${value['since']}');
        final seen = DateTime.tryParse('${value['seen']}');
        if (start == null || seen == null) return;
        final seconds = seen.difference(start).inSeconds;
        if (seconds >= _minSeconds) {
          pending.add({'id': oldId, 'seconds': seconds, 'ended': seen.toIso8601String()});
        }
      });
      await prefs.setString(_openKey, jsonEncode({id: _openEntry(since, since)}));
      await _savePending(prefs, pending);
      await _deliver(prefs);
    });
  }

  void _onTick() {
    final id = _visitId;
    final since = _since;
    if (id == null || since == null) return;
    final now = DateTime.now().toUtc();
    final seconds = now.difference(since).inSeconds;

    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      final open = _readMap(prefs, _openKey);
      open[id] = _openEntry(since, now);
      await prefs.setString(_openKey, jsonEncode(open));
    });

    final due = _reportedSeconds == 0
        ? seconds >= _firstReportSeconds
        : seconds - _reportedSeconds >= _reportEverySeconds;
    if (!due || _reporting) return;
    _reporting = true;
    _send(id, seconds, now).then((ok) {
      if (ok && _visitId == id) _reportedSeconds = seconds;
    }).whenComplete(() => _reporting = false);
  }

  void _end() {
    final id = _visitId;
    final since = _since;
    _timer?.cancel();
    _timer = null;
    _visitId = null;
    _since = null;
    _reportedSeconds = 0;
    if (id == null || since == null) return;
    final now = DateTime.now().toUtc();
    final seconds = now.difference(since).inSeconds;

    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      final open = _readMap(prefs, _openKey)..remove(id);
      await prefs.setString(_openKey, jsonEncode(open));
      if (seconds < _minSeconds) return;
      // Saved before sending: if the phone cuts the network or kills the app
      // now, the next open sends it.
      final pending = _readList(prefs, _pendingKey)
        ..add({'id': id, 'seconds': seconds, 'ended': now.toIso8601String()});
      await _savePending(prefs, pending);
      await _deliver(prefs);
    });
  }

  /// Sends the waiting reports, oldest first. Stops at the first failure (the
  /// network is probably down) and keeps the rest for the next open.
  Future<void> _deliver(SharedPreferences prefs) async {
    final pending = _readList(prefs, _pendingKey);
    if (pending.isEmpty) return;
    final now = DateTime.now().toUtc();
    final left = <Map<String, dynamic>>[];
    var failed = false;
    for (final visit in pending) {
      final ended = DateTime.tryParse('${visit['ended']}');
      final seconds = visit['seconds'];
      if (ended == null || seconds is! num || now.difference(ended) > _keepFor) {
        continue;
      }
      if (failed || !await _send('${visit['id']}', seconds.toInt(), ended)) {
        failed = true;
        left.add(visit);
      }
    }
    await _savePending(prefs, left);
  }

  Future<bool> _send(String id, int seconds, DateTime ended) async {
    try {
      await ApiClient.instance.post(
        '${ApiConstants.apiVersion}/auth/me/session',
        data: {
          'visit_id': id,
          'duration_seconds': seconds,
          'ended_at': ended.toUtc().toIso8601String(),
        },
      ).timeout(_sendTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _serial(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object _) {});
  }

  static Map<String, String> _openEntry(DateTime since, DateTime seen) =>
      {'since': since.toIso8601String(), 'seen': seen.toIso8601String()};

  static Map<String, dynamic> _readMap(SharedPreferences prefs, String key) {
    try {
      final value = jsonDecode(prefs.getString(key) ?? '{}');
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static List<Map<String, dynamic>> _readList(SharedPreferences prefs, String key) {
    try {
      final value = jsonDecode(prefs.getString(key) ?? '[]');
      return value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _savePending(
      SharedPreferences prefs, List<Map<String, dynamic>> pending) {
    final keep = pending.length > _maxPending
        ? pending.sublist(pending.length - _maxPending)
        : pending;
    return prefs.setString(_pendingKey, jsonEncode(keep));
  }
}
