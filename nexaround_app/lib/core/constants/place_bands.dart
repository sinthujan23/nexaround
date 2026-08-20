/// Distance bands for the Around You / Discovery sections.
///
/// Each category's range is split into three contiguous bands and the section
/// takes a quota from each — ten in all — so the list reads as a progression
/// outward rather than ten variations on "the nearest thing".
///
/// Bands are weighted, not equal thirds: splitting 0–50 km evenly would put
/// everything within 16.7 km into one band and collapse the distinction users
/// care about most (walkable vs. a drive vs. a day trip).
///
/// Mirrors `app/services/place_bands.py` on the backend. Keep the two in sync —
/// the server uses the table to decide what to fetch, this one decides what to
/// show, and a mismatch shows up as bands that look mis-sorted.
class PlaceBand {
  final double minKm;
  final double maxKm;

  const PlaceBand(this.minKm, this.maxKm);

  bool contains(double distanceKm) => distanceKm >= minKm && distanceKm <= maxKm;
}

class PlaceBands {
  const PlaceBands._();

  /// Places taken from each band, nearest first. Weighted rather than even
  /// because ten does not divide by three, and because the band a user can walk
  /// to is the one they actually read.
  static const List<int> bandQuotas = [4, 3, 3];

  /// How many places per band the app asks the backend for.
  ///
  /// Deliberately larger than [bandQuotas]: Discovery lists a full page per
  /// category, while Around You is the quick-access strip and slices only
  /// [bandQuotas] off the top of each band. One fetch serves both surfaces, so
  /// opening Discovery costs nothing extra and the two never disagree about
  /// which places exist.
  static const int fetchPerBand = 15;

  static const int bandsPerCategory = bandQuotas.length;
  static const int totalPerCategory = 10;

  /// How many places band [index] contributes to its section.
  static int quotaForBand(int index) =>
      (index >= 0 && index < bandQuotas.length)
          ? bandQuotas[index]
          : bandQuotas.last;

  /// The six sections, in the order Around You shows them.
  static const List<String> sections = [
    'Food & Drink',
    'POI',
    'Nature',
    'Shopping',
    'Medical',
    'Hospital',
  ];

  static const Map<String, List<PlaceBand>> byCategory = {
    'Food & Drink': [
      PlaceBand(0.0, 1.667),
      PlaceBand(1.667, 3.333),
      PlaceBand(3.333, 5.0),
    ],
    'POI': [
      PlaceBand(0.0, 10.0),
      PlaceBand(10.0, 25.0),
      PlaceBand(25.0, 50.0),
    ],
    'Nature': [
      PlaceBand(0.0, 10.0),
      PlaceBand(10.0, 25.0),
      PlaceBand(25.0, 50.0),
    ],
    'Shopping': [
      PlaceBand(0.0, 5.0),
      PlaceBand(5.0, 10.0),
      PlaceBand(10.0, 15.0),
    ],
    'Medical': [
      PlaceBand(0.0, 10.0),
      PlaceBand(10.0, 25.0),
      PlaceBand(25.0, 50.0),
    ],
    'Hospital': [
      PlaceBand(0.0, 10.0),
      PlaceBand(10.0, 25.0),
      PlaceBand(25.0, 50.0),
    ],
  };

  /// A rating shrunk toward the mean by how little backs it up.
  ///
  /// Mirrors `place_bands.quality_score` on the backend. A raw rating sort puts
  /// a 5.0 from one review above a 4.4 from 1,795 — which is how a nameless
  /// "Trincomalee" outranked Marble Beach. With few reviews the score sits near
  /// the prior; only real volume moves it.
  static double qualityScore(double? rating, int? reviewCount) {
    final r = rating ?? 0.0;
    if (r <= 0.0) return 0.0;
    final v = (reviewCount ?? 0).toDouble();
    const priorWeight = 30.0;
    const priorMean = 4.0;
    return (v * r + priorWeight * priorMean) / (v + priorWeight);
  }

  static List<PlaceBand> forCategory(String category) =>
      byCategory[category] ?? byCategory['POI']!;

  /// Outer edge of a category's last band — the radius worth fetching at all.
  static double maxKmFor(String category) => forCategory(category).last.maxKm;

  static double maxMetresFor(String category) => maxKmFor(category) * 1000.0;
}
