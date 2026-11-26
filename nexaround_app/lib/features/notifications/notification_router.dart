import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/discovery_history_service.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tour_page.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/my_experience_requests_page.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/my_feedback_page.dart';
import 'package:nexaround_app/features/explorer_points/data/explorer_points_service.dart';
import 'package:nexaround_app/features/explorer_points/presentation/pages/explorer_points_page.dart';
import 'package:nexaround_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/travel_stories/presentation/pages/travel_stories_page.dart';
import 'package:nexaround_app/features/trip_wallet/data/trip_wallet_service.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/pages/wallet_trip_page.dart';
import 'package:nexaround_app/features/vendor_portal/presentation/pages/vendor_portal_page.dart';

/// Where a tap on a notification goes, for both kinds of tap: a push on the
/// phone (NotificationService.onOpen) and a line in the bell inbox
/// (NotificationsPage). Both come here, so they always open the same thing.
///
/// [open] reads the push's data as the server sends it: its `type` and the
/// id of what it is about.
///
/// | type               | id(s)                     | opens                              |
/// |--------------------|---------------------------|------------------------------------|
/// | odyssey_ready      | itinerary_id              | that plan                          |
/// | discovery_ready    | discovery_id              | that Neva discovery plan           |
/// | experience_request | enquiry_id                | My requests, that request open     |
/// | city_tour_trip     | tour_id                   | the guide, with the trip running   |
/// | trip_wallet        | trip_id                   | that Trip Split trip               |
/// | story_comment      | story_id                  | the story, its comments open       |
/// | vendor_request     | vendor_id, enquiry_id     | vendor portal, that request open   |
/// | vendor_review      | vendor_id, package_id?    | vendor portal, the package/profile |
/// | explorer_points    | -                         | My Explorer Points                 |
/// | feedback_reply     | feedback_id               | My feedback (the team's reply)     |
/// | broadcast, other   | -                         | the bell (push taps only)          |
class NotificationRouter {
  NotificationRouter._();

  static DateTime? _lastTap;

  /// Opens what [data] is about. [fromInbox]: the tap was on a line in the
  /// bell, so a notification with nothing else to open leaves it there; a
  /// push for one opens the bell, where its whole text is.
  static Future<void> open(Map<String, dynamic> data, {bool fromInbox = false}) async {
    // A double tap opens one page, not two.
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(seconds: 1)) return;
    _lastTap = now;

    final home = HomePage.homeKey.currentState;
    if (home == null || !home.mounted) return;
    final context = home.context;
    final type = (data['type'] ?? '').toString();

    // The page futures below complete only when that page is closed, so they
    // are not awaited: the tap is done once the page is on its way.
    try {
      if (type == 'plan_ready' || type.contains('odyssey')) {
        final id = _id(data, const ['itinerary_id', 'odyssey_id', 'odysseyId', 'id']);
        if (id != null) {
          unawaited(home.openOdysseyById(id));
        } else {
          await _openLatestOdyssey(home);
        }
        return;
      }
      if (type.contains('discovery')) {
        await _openDiscovery(home, _id(data, const ['discovery_id', 'id']));
        return;
      }
      switch (type) {
        case 'experience_request':
          unawaited(showMyExperienceRequests(context, openRequestId: _id(data, const ['enquiry_id'])));
        case 'city_tour_trip':
          final tourId = _id(data, const ['tour_id']);
          if (tourId != null) unawaited(openCityTourById(context, tourId));
        case TripWalletService.pushType:
          final tripId = _id(data, const ['trip_id']);
          if (tripId != null) unawaited(openWalletTripById(context, tripId));
        case 'story_comment':
          final storyId = _id(data, const ['story_id']);
          if (storyId != null) {
            unawaited(openStoryComments(context, storyId));
          } else {
            _toHome(context);
            home.switchToExplore();
          }
        case 'vendor_request':
          unawaited(openVendorPortal(context,
              vendorId: _id(data, const ['vendor_id']),
              requestId: _id(data, const ['enquiry_id']),
              toNotifications: true));
        case 'vendor_review':
          // NexAround's check of a package (package_id) or of the profile.
          final packageId = _id(data, const ['package_id']);
          unawaited(openVendorPortal(context,
              vendorId: _id(data, const ['vendor_id']),
              packageId: packageId,
              toProfile: packageId == null));
        case FeedbackService.pushType:
          // The team answered something the traveller sent.
          unawaited(Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyFeedbackPage()),
          ));
        case ExplorerPointsService.pushType:
          // A photo went live or a new level: the traveller's points.
          unawaited(Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ExplorerPointsPage()),
          ));
        default:
          // An announcement (broadcast) or a type this build doesn't know:
          // nothing to open but the message itself, which is in the bell.
          if (!fromInbox && !NotificationsPage.isShowing) {
            unawaited(Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            ));
          }
      }
    } catch (e) {
      debugPrint('Notification tap ($type) not opened: $e');
    }
  }

  /// The first of [keys] that holds a value.
  static String? _id(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k]?.toString().trim();
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  /// Back to the tabs: closes the bell, or whatever the push came in over.
  static void _toHome(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.popUntil((route) => route.isFirst);
  }

  /// A plan push without its id (older servers): the newest plan.
  static Future<void> _openLatestOdyssey(HomePageState home) async {
    try {
      final list = await OdysseyRepository().getMyOdysseys();
      if (list.isNotEmpty && home.mounted) {
        home.openOdysseyDetail(list.first);
        return;
      }
    } catch (e) {
      debugPrint('Plans not loaded for a notification tap: $e');
    }
    if (!home.mounted) return;
    _toHome(home.context);
    home.switchToPlans();
  }

  /// The Neva discovery the push was for (the newest without an id), over
  /// the Home tab.
  static Future<void> _openDiscovery(HomePageState home, String? discoveryId) async {
    _toHome(home.context);
    home.switchToExplore();
    CacheService.isDiscoveringNotifier.value = false;
    final history = await DiscoveryHistoryService.fetchHistory();
    Map<String, dynamic>? target;
    if (discoveryId != null) {
      for (final item in history) {
        if (item['id']?.toString() == discoveryId) {
          target = item;
          break;
        }
      }
    }
    target ??= history.isNotEmpty ? history.first : null;
    final result = target?['result'] as String?;
    if (target == null || result == null || result.isEmpty || !home.mounted) return;
    home.openDiscoveryPlan(
      result,
      location: target['location'] as String?,
      mode: target['mode'] as String?,
      mood: target['mood'] as String?,
    );
  }
}
