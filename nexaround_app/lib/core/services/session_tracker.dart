import 'package:flutter/widgets.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';

/// Measures how long the app stays in the foreground and reports each completed
/// session to the backend (`POST /auth/me/session`). This feeds the admin
/// panel's REAL "Daily Active Users" and "Avg Session Length" metrics — without
/// it those would have no data. Fire-and-forget; analytics never blocks the UI.
class SessionTracker with WidgetsBindingObserver {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  DateTime? _foregroundSince;
  bool _registered = false;

  /// Call once at startup. The app is foreground at launch, so the clock starts.
  void start() {
    if (_registered) return;
    _registered = true;
    WidgetsBinding.instance.addObserver(this);
    _foregroundSince = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foregroundSince = DateTime.now();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _flush();
    }
  }

  Future<void> _flush() async {
    final since = _foregroundSince;
    _foregroundSince = null;
    if (since == null) return;
    final seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 2) return; // ignore trivial blips
    try {
      await ApiClient.instance.post(
        '${ApiConstants.apiVersion}/auth/me/session',
        data: {'duration_seconds': seconds},
      );
    } catch (_) {
      // Best-effort: a failed analytics ping must never surface to the user.
    }
  }
}
