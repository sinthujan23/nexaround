/// Distance bands for the Around You / Discovery sections.
///
/// Each category's range is split into three contiguous bands and the section
/// shows five places from each — fifteen in all — so the list reads as a
/// progression outward rather than fifteen variations on "the nearest thing".
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

  static const int placesPerBand = 5;
  static const int bandsPerCategory = 3;
  static const int totalPerCategory = placesPerBand * bandsPerCategory;

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
  };

  static List<PlaceBand> forCategory(String category) =>
      byCategory[category] ?? byCategory['POI']!;

  /// Outer edge of a category's last band — the radius worth fetching at all.
  static double maxKmFor(String category) => forCategory(category).last.maxKm;

  static double maxMetresFor(String category) => maxKmFor(category) * 1000.0;
}
