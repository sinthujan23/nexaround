import 'package:flutter/material.dart';

/// How a package category looks in the app: the filter chip, the pill on a
/// card, and the tinted placeholder shown when a package has no photo.
///
/// One table, so the chip row and the cards cannot drift apart. The values are
/// the backend's `category` strings (see the admin and partner forms).
class ExperienceCategory {
  final String? value;
  final String emoji;

  /// Short form for the filter chips.
  final String chipLabel;

  /// Full form for the pill on a card.
  final String label;

  /// Two stops for the no-photo placeholder gradient.
  final List<Color> tint;

  const ExperienceCategory(
    this.value,
    this.emoji,
    this.chipLabel,
    this.label,
    this.tint,
  );
}

const experienceCategories = <ExperienceCategory>[
  ExperienceCategory(null, '✨', 'All', 'Experience',
      [Color(0xFF00A3A6), Color(0xFF005E60)]),
  ExperienceCategory('boat', '🛥️', 'Boat', 'Boat ride',
      [Color(0xFF38BDF8), Color(0xFF0369A1)]),
  ExperienceCategory('water_sports', '🏄', 'Water', 'Water sports',
      [Color(0xFF22D3EE), Color(0xFF0E7490)]),
  ExperienceCategory('guided_tour', '🧭', 'Guides', 'Guided tour',
      [Color(0xFFFBBF24), Color(0xFFB45309)]),
  ExperienceCategory('wildlife', '🐘', 'Wildlife', 'Wildlife',
      [Color(0xFF4ADE80), Color(0xFF15803D)]),
  ExperienceCategory('cultural', '🛕', 'Cultural', 'Cultural',
      [Color(0xFFC084FC), Color(0xFF7E22CE)]),
  ExperienceCategory('adventure', '🧗', 'Adventure', 'Adventure',
      [Color(0xFFFB923C), Color(0xFFC2410C)]),
  ExperienceCategory('food', '🍽️', 'Food', 'Food',
      [Color(0xFFFB7185), Color(0xFFBE123C)]),
];

/// The style for a package's category; unknown and 'other' fall back to the
/// generic entry.
ExperienceCategory experienceCategoryFor(String? value) {
  for (final c in experienceCategories) {
    if (c.value != null && c.value == value) return c;
  }
  return experienceCategories.first;
}
