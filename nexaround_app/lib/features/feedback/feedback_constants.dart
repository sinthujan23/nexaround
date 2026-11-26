import 'package:flutter/material.dart';

/// Fixed vocabularies of the "Tell us what you want" feedback, the one-tap
/// "How was it?" and the quarterly survey. The keys must match the server's
/// `app/services/feedback_service.py`; the labels and icons are the app's.
class FeedbackKind {
  const FeedbackKind(this.key, this.label, this.icon, this.color);
  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

class FeedbackVocab {
  FeedbackVocab._();

  static const teal = Color(0xFF00797B);
  static const tealDark = Color(0xFF005E60);
  static const mint = Color(0xFF5EEAD4);
  static const tint = Color(0xFFE9F6F5);

  /// What a message is about.
  static const types = [
    FeedbackKind('idea', 'Idea', Icons.lightbulb_rounded, Color(0xFFF59E0B)),
    FeedbackKind('problem', 'Problem', Icons.bug_report_rounded, Color(0xFFEF4444)),
    FeedbackKind('love', 'Love it', Icons.favorite_rounded, Color(0xFFEC4899)),
    FeedbackKind('other', 'Other', Icons.chat_bubble_rounded, Color(0xFF64748B)),
  ];

  static FeedbackKind type(String key) =>
      types.firstWhere((t) => t.key == key, orElse: () => types.last);

  /// Survey question 2: the features an explorer can say they use.
  static const features = [
    FeedbackKind('ar', 'AR camera', Icons.view_in_ar_rounded, teal),
    FeedbackKind('odyssey', 'Odyssey', Icons.auto_awesome_rounded, teal),
    FeedbackKind('neva', 'NEVA', Icons.smart_toy_rounded, teal),
    FeedbackKind('discover', 'Discover', Icons.explore_rounded, teal),
    FeedbackKind('city_guides', 'City Guides', Icons.tour_rounded, teal),
    FeedbackKind('walking_challenge', 'Walking Challenge', Icons.directions_walk_rounded, teal),
    FeedbackKind('trip_split', 'Trip Split', Icons.receipt_long_rounded, teal),
    FeedbackKind('travel_stories', 'Travel Stories', Icons.photo_library_rounded, teal),
    FeedbackKind('experiences', 'Experiences', Icons.local_activity_rounded, teal),
    FeedbackKind('museums', 'Museums', Icons.museum_rounded, teal),
    FeedbackKind('forum', 'Forum', Icons.forum_rounded, teal),
  ];

  /// Survey question 4 when the answer is Yes or Maybe (USD a month).
  static const priceRanges = [
    ('lt2', 'Under \$2'),
    ('2to5', '\$2–5'),
    ('5to8', '\$5–8'),
    ('8to12', '\$8–12'),
    ('gt12', 'Over \$12'),
  ];

  /// Survey question 4 when the answer is No.
  static const whyNot = [
    FeedbackKind('free_apps', 'Free apps do this', Icons.savings_rounded, teal),
    FeedbackKind('travel_rarely', 'I travel rarely', Icons.flight_takeoff_rounded, teal),
    FeedbackKind('too_expensive', 'Too expensive', Icons.sell_rounded, teal),
    FeedbackKind('other', 'Other', Icons.more_horiz_rounded, teal),
  ];

  /// The quick "Not great" reasons per finished thing.
  static const quickReasons = <String, List<FeedbackKind>>{
    'odyssey': [
      FeedbackKind('wrong_places', 'Wrong places', Icons.wrong_location_rounded, Color(0xFFEF4444)),
      FeedbackKind('too_rushed', 'Too rushed', Icons.speed_rounded, Color(0xFFEF4444)),
      FeedbackKind('prices_off', 'Prices were off', Icons.payments_rounded, Color(0xFFEF4444)),
      FeedbackKind('other', 'Other', Icons.more_horiz_rounded, Color(0xFFEF4444)),
    ],
    'city_guides': [
      FeedbackKind('route_confusing', 'Route confusing', Icons.alt_route_rounded, Color(0xFFEF4444)),
      FeedbackKind('places_closed', 'Places were closed', Icons.door_front_door_rounded, Color(0xFFEF4444)),
      FeedbackKind('too_long', 'Too long', Icons.timer_rounded, Color(0xFFEF4444)),
      FeedbackKind('other', 'Other', Icons.more_horiz_rounded, Color(0xFFEF4444)),
    ],
    'walking_challenge': [
      FeedbackKind('too_far', 'Too far to walk', Icons.directions_walk_rounded, Color(0xFFEF4444)),
      FeedbackKind('clues_hard', 'Clues too hard', Icons.psychology_rounded, Color(0xFFEF4444)),
      FeedbackKind('map_problem', 'Map problem', Icons.map_rounded, Color(0xFFEF4444)),
      FeedbackKind('other', 'Other', Icons.more_horiz_rounded, Color(0xFFEF4444)),
    ],
  };

  /// Icons the team can give a "What should we build next?" choice in the
  /// admin panel (feedback_service.OPTION_ICONS). Unknown names: a bulb.
  static const _optionIcons = <String, IconData>{
    'lightbulb': Icons.lightbulb_rounded,
    'wifi_off': Icons.wifi_off_rounded,
    'public': Icons.public_rounded,
    'hotel': Icons.hotel_rounded,
    'flight': Icons.flight_rounded,
    'notifications_active': Icons.notifications_active_rounded,
    'groups': Icons.groups_rounded,
    'dark_mode': Icons.dark_mode_rounded,
    'translate': Icons.translate_rounded,
    'map': Icons.map_rounded,
    'directions_car': Icons.directions_car_rounded,
    'restaurant': Icons.restaurant_rounded,
    'photo_camera': Icons.photo_camera_rounded,
    'payments': Icons.payments_rounded,
    'train': Icons.train_rounded,
    'hiking': Icons.hiking_rounded,
    'event': Icons.event_rounded,
    'language': Icons.language_rounded,
  };

  static const _optionColors = [
    Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFF10B981), Color(0xFF334155), Color(0xFF8B5CF6), Color(0xFFEC4899),
  ];

  static IconData optionIcon(String name) => _optionIcons[name] ?? Icons.lightbulb_rounded;
  static Color optionColor(int index) => _optionColors[index % _optionColors.length];
}
