import 'package:flutter/material.dart';

/// How a package category looks in the app: the filter chip, the pill on a
/// card, and the tinted placeholder shown when a package has no photo.
///
/// One table, so the chip row and the cards cannot drift apart. The values are
/// the backend's `category` strings (see the admin and partner forms).
class ExperienceCategory {
  final String? value;
  final String emoji;
  final IconData icon;

  /// Short form for the filter chips.
  final String chipLabel;

  /// Full form for the pill on a card.
  final String label;

  /// Two stops for the no-photo placeholder gradient.
  final List<Color> tint;

  /// Signature accent color for vector icons, chips, and card pills.
  final Color accent;

  const ExperienceCategory(
    this.value,
    this.emoji,
    this.icon,
    this.chipLabel,
    this.label,
    this.tint,
    this.accent,
  );
}

const experienceCategories = <ExperienceCategory>[
  ExperienceCategory(
    null,
    '🧭',
    Icons.grid_view_rounded,
    'All',
    'Experience',
    [Color(0xFF00A3A6), Color(0xFF005E60)],
    Color(0xFF007A7C),
  ),
  ExperienceCategory(
    'boat',
    '⛵',
    Icons.sailing_rounded,
    'Boat',
    'Boat ride',
    [Color(0xFF38BDF8), Color(0xFF0369A1)],
    Color(0xFF0284C7),
  ),
  ExperienceCategory(
    'water_sports',
    '🏄',
    Icons.surfing_rounded,
    'Water',
    'Water sports',
    [Color(0xFF22D3EE), Color(0xFF0E7490)],
    Color(0xFF0891B2),
  ),
  ExperienceCategory(
    'guided_tour',
    '🧭',
    Icons.explore_rounded,
    'Guides',
    'Guided tour',
    [Color(0xFFFBBF24), Color(0xFFB45309)],
    Color(0xFFD97706),
  ),
  ExperienceCategory(
    'wildlife',
    '🐾',
    Icons.pets_rounded,
    'Wildlife',
    'Wildlife',
    [Color(0xFF4ADE80), Color(0xFF15803D)],
    Color(0xFF16A34A),
  ),
  ExperienceCategory(
    'cultural',
    '🏛️',
    Icons.temple_buddhist_rounded,
    'Cultural',
    'Cultural',
    [Color(0xFFC084FC), Color(0xFF7E22CE)],
    Color(0xFF9333EA),
  ),
  ExperienceCategory(
    'adventure',
    '🧗',
    Icons.hiking_rounded,
    'Adventure',
    'Adventure',
    [Color(0xFFFB923C), Color(0xFFC2410C)],
    Color(0xFFEA580C),
  ),
  ExperienceCategory(
    'food',
    '🍽️',
    Icons.restaurant_rounded,
    'Food',
    'Food',
    [Color(0xFFFB7185), Color(0xFFBE123C)],
    Color(0xFFE11D48),
  ),
];

/// The style for a package's category; unknown and 'other' fall back to the
/// generic entry.
ExperienceCategory experienceCategoryFor(String? value) {
  for (final c in experienceCategories) {
    if (c.value != null && c.value == value) return c;
  }
  return experienceCategories.first;
}
