import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/session_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The features the backend counts (`FEATURES` in
/// app/services/feature_usage.py). It drops any other key.
class AppFeature {
  AppFeature._();

  static const home = 'home';
  static const ar = 'ar';
  static const neva = 'neva';
  static const discover = 'discover';
  static const plans = 'plans';
  static const odysseyPlanner = 'odyssey_planner';
  static const miniTour = 'mini_tour';
  static const cityGuides = 'city_guides';
  static const experiences = 'experiences';
  static const museums = 'museums';
  static const travelStories = 'travel_stories';
  static const travelJournal = 'travel_journal';
  static const forum = 'forum';
  static const placeDetails = 'place_details';
  static const fullMap = 'full_map';
  static const directions = 'directions';
  static const profile = 'profile';
  static const subscriptionPlans = 'subscription_plans';
}

/// Reports which features an explorer actually looks at, for the admin's
/// Feature usage page (`POST /analytics/feature-opens`).
///
/// A feature counts once per visit, and only after its screen has been on
/// screen for [_dwell] with the app in the foreground. Tabs kept alive out of
/// sight, screens passed through on the way somewhere else, and data loaded in
/// the background never count. Visits are [SessionTracker]'s, so the server can
/// set opens beside time in the app.
///
/// On screen is the newest open [TracksFeature] page or [FeatureScreen];
/// without one, the home tab, but only while the home page is the top route
/// (any page pushed over it hides the tab). Opens are saved on the phone before
/// sending and resent on the next start, like visits. Fire-and-forget: never
/// blocks the UI or shows an error.
class FeatureTracker with WidgetsBindingObserver {
  FeatureTracker._();
  static final FeatureTracker instance = FeatureTracker._();

  /// Registered on the router, so the home page hears when a page covers it.
  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();

  static const _dwell = Duration(seconds: 5);
  static const _pendingKey = 'feature_tracker_pending';
  static const _maxPending = 200;
  static const _batchSize = 50;
  static const _keepFor = Duration(days: 7); // the server drops older opens
  static const _sendDelay = Duration(seconds: 20);
  static const _sendTimeout = Duration(seconds: 20);

  bool _registered = false;
  bool _foreground = false;
  String? _tab;
  bool _homeCovered = false;
  final List<_Screen> _screens = [];
  String? _visible;
  Timer? _dwellTimer;
  Timer? _sendTimer;

  /// Features already counted in [_countedVisit].
  String? _countedVisit;
  final Set<String> _counted = {};

  /// Storage and sending run one job at a time, in the order asked for.
  Future<void> _queue = Future<void>.value();

  /// Call once at startup, after [SessionTracker.start].
  void start() {
    if (_registered) return;
    _registered = true;
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _send(); // what an earlier run could not deliver
    _restartDwell();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_foreground) return;
      _foreground = true;
      // A new visit: what is on screen counts again once it has stayed.
      _restartDwell();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      _dwellTimer?.cancel();
      _sendTimer?.cancel();
      _sendTimer = null;
      _send();
    }
  }

  /// The home page's visible tab; null once the home page is gone.
  void setTab(String? feature) {
    if (_tab == feature) return;
    _tab = feature;
    _update();
  }

  /// Whether a page is pushed over the home page.
  void setHomeCovered(bool covered) {
    if (_homeCovered == covered) return;
    _homeCovered = covered;
    _update();
  }

  /// A page of [feature] is open; pass the result to [leave] when it closes.
  Object enter(String feature) {
    final screen = _Screen(feature);
    _screens.add(screen);
    _update();
    return screen;
  }

  void leave(Object screen) {
    if (_screens.remove(screen)) _update();
  }

  String? get _current =>
      _screens.isNotEmpty ? _screens.last.feature : (_homeCovered ? null : _tab);

  void _update() {
    final now = _current;
    if (now == _visible) return;
    _visible = now;
    _restartDwell();
  }

  void _restartDwell() {
    _dwellTimer?.cancel();
    final feature = _visible;
    if (feature == null || !_foreground) return;
    _dwellTimer = Timer(_dwell, () => _record(feature));
  }

  void _record(String feature) {
    if (!_foreground || _visible != feature) return;
    final visit = SessionTracker.instance.visitId;
    if (visit == null) return;
    if (_countedVisit != visit) {
      _countedVisit = visit;
      _counted.clear();
    }
    if (!_counted.add(feature)) return;

    final open = {
      'visit_id': visit,
      'feature': feature,
      'opened_at': DateTime.now().toUtc().subtract(_dwell).toIso8601String(),
    };
    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      await _save(prefs, _read(prefs)..add(open));
    });
    // A few opens usually follow one another; send them together.
    _sendTimer ??= Timer(_sendDelay, () {
      _sendTimer = null;
      _send();
    });
  }

  /// Sends the waiting opens, oldest first. Stops at the first failure (the
  /// network is probably down) and keeps the rest for later.
  void _send() {
    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      final cutoff = DateTime.now().toUtc().subtract(_keepFor);
      var pending = _read(prefs).where((o) {
        final at = DateTime.tryParse('${o['opened_at']}');
        return at != null && at.isAfter(cutoff);
      }).toList();
      while (pending.isNotEmpty) {
        final batch = pending.take(_batchSize).toList();
        if (!await _post(batch)) break;
        pending = pending.sublist(batch.length);
      }
      await _save(prefs, pending);
    });
  }

  /// True once the server has the batch, or has refused it for good (resending
  /// a report it rejected would only fail again).
  Future<bool> _post(List<Map<String, dynamic>> opens) async {
    try {
      await ApiClient.instance.post(
        '${ApiConstants.apiVersion}/analytics/feature-opens',
        data: {'opens': opens},
      ).timeout(_sendTimeout);
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      return code != null && code >= 400 && code < 500 && code != 401 && code != 429;
    } catch (_) {
      return false;
    }
  }

  void _serial(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object _) {});
  }

  static List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    try {
      final value = jsonDecode(prefs.getString(_pendingKey) ?? '[]');
      return value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(SharedPreferences prefs, List<Map<String, dynamic>> pending) {
    final keep = pending.length > _maxPending
        ? pending.sublist(pending.length - _maxPending)
        : pending;
    return prefs.setString(_pendingKey, jsonEncode(keep));
  }
}

class _Screen {
  _Screen(this.feature);
  final String feature;
}

/// Counts a page as [trackedFeature] while it is open. Add it to the page's
/// State: `with TracksFeature<MyPage>`.
mixin TracksFeature<T extends StatefulWidget> on State<T> {
  String get trackedFeature;

  /// False when the page is shown as a home tab, which the home page reports.
  bool get featureTracked => true;

  Object? _featureScreen;

  @override
  void initState() {
    super.initState();
    if (featureTracked) _featureScreen = FeatureTracker.instance.enter(trackedFeature);
  }

  @override
  void dispose() {
    final screen = _featureScreen;
    if (screen != null) FeatureTracker.instance.leave(screen);
    super.dispose();
  }
}

/// Counts [child] as [feature] while it is open. For pages that are also home
/// tabs (counted there) when they are pushed on their own, and for pages
/// without a State.
class FeatureScreen extends StatefulWidget {
  const FeatureScreen({super.key, required this.feature, required this.child});

  final String feature;
  final Widget child;

  @override
  State<FeatureScreen> createState() => _FeatureScreenState();
}

class _FeatureScreenState extends State<FeatureScreen> with TracksFeature<FeatureScreen> {
  @override
  String get trackedFeature => widget.feature;

  @override
  Widget build(BuildContext context) => widget.child;
}
