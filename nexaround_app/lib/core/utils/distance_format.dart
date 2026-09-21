/// Formats a distance in metres for display, switching to metres below 1km.
///
/// A flat "X.X km" format loses all resolution under 500m — anything closer
/// than 50m rounds to "0.0 km", which is how two genuinely different-distance
/// nearby places (8m and 45m away) ended up showing the identical "0.0 km" in
/// a list. This was already handled correctly in several places
/// (living_map_page.dart, ar_camera_page.dart) but reimplemented inline each
/// time rather than shared, so it kept getting missed elsewhere (discover_page.dart)
/// — use this instead of writing the km/m branch again.
String formatDistance(double? distanceM) {
  final m = distanceM ?? 0;
  final km = m / 1000;
  return km < 1 ? '${m.toInt()} m' : '${km.toStringAsFixed(1)} km';
}

/// Formats a long distance for the Experiences "nothing nearby" banner.
///
/// [formatDistance] renders 340 km as "340.0 km", and a trailing ".0" on a
/// number that large reads as false precision. Above 10 km this drops the
/// decimal; below that it defers to [formatDistance] so short distances keep
/// their resolution.
///
/// Deliberately a separate function rather than a change to [formatDistance],
/// which is used by living_map_page, ar_camera_page and discover_page — all of
/// them showing distances where the decimal matters.
String formatDistanceCoarse(double? distanceM) {
  final m = distanceM ?? 0;
  final km = m / 1000;
  if (km < 10) return formatDistance(distanceM);
  return '${km.round()} km';
}
