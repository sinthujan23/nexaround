import 'dart:math' as math;

import 'package:latlong2/latlong2.dart' as ll;

/// How far apart two places are, in metres.
double cityTourMetres(ll.LatLng a, ll.LatLng b) {
  const earth = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earth * math.asin(math.min(1.0, math.sqrt(h)));
}

/// "90 m", "1.4 km", "5412 km".
String cityTourDistanceText(double metres) {
  if (metres < 1000) return '${(metres / 10).round() * 10} m';
  if (metres < 100000) return '${(metres / 1000).toStringAsFixed(1)} km';
  return '${(metres / 1000).round()} km';
}

/// "8 min", "1 hr 5 min".
String cityTourTimeText(double seconds) {
  final minutes = math.max(1, (seconds / 60).ceil());
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} hr' : '${minutes ~/ 60} hr $rest min';
}

/// Where a place falls on a [CityTourRouteLine].
class CityTourLineSpot {
  /// Metres from the start of the line.
  final double along;

  /// Metres from the place to the line.
  final double off;

  const CityTourLineSpot(this.along, this.off);
}

/// A route's steps joined into one line, so a GPS fix can be placed on it.
class CityTourRouteLine {
  /// How far back a fix may fall from the last one: GPS wanders, but going
  /// further would land on an earlier pass of a street walked twice.
  static const double _backtrack = 30;

  final List<ll.LatLng> points = [];

  /// Metres from the start to the end of each step.
  final List<double> stepEnds = [];

  final List<double> _along = [];

  CityTourRouteLine(List<List<ll.LatLng>> steps) {
    for (final step in steps) {
      for (final point in step) {
        if (points.isEmpty) {
          _along.add(0);
        } else {
          final gap = cityTourMetres(points.last, point);
          if (gap == 0) continue;
          _along.add(_along.last + gap);
        }
        points.add(point);
      }
      stepEnds.add(_along.isEmpty ? 0 : _along.last);
    }
  }

  double get length => _along.isEmpty ? 0 : _along.last;

  /// The spot on the line nearest [here], from [from] metres along onward.
  CityTourLineSpot locate(ll.LatLng here, {double from = 0}) {
    if (points.length < 2) {
      return CityTourLineSpot(0, points.isEmpty ? 0 : cityTourMetres(here, points.first));
    }
    // Metres east and north of [here]: flat is near enough at this distance.
    final metresPerLng = 111320 * math.cos(here.latitude * math.pi / 180);
    const metresPerLat = 110540.0;
    final floor = from - _backtrack;
    var nearest = double.infinity;
    var along = from;
    for (var i = 0; i + 1 < points.length; i++) {
      if (_along[i + 1] < floor) continue;
      // How far into this piece the floor falls.
      final first = _along[i] >= floor ? 0.0 : (floor - _along[i]) / (_along[i + 1] - _along[i]);
      final ax = (points[i].longitude - here.longitude) * metresPerLng;
      final ay = (points[i].latitude - here.latitude) * metresPerLat;
      final dx = (points[i + 1].longitude - here.longitude) * metresPerLng - ax;
      final dy = (points[i + 1].latitude - here.latitude) * metresPerLat - ay;
      final span = dx * dx + dy * dy;
      final t = span == 0 ? first : (-(ax * dx + ay * dy) / span).clamp(first, 1.0);
      final px = ax + t * dx;
      final py = ay + t * dy;
      final off = math.sqrt(px * px + py * py);
      if (off < nearest) {
        nearest = off;
        along = _along[i] + t * (_along[i + 1] - _along[i]);
      }
    }
    return CityTourLineSpot(along, nearest);
  }

  /// The step that [along] metres down the line falls in.
  int stepAt(double along) {
    for (var i = 0; i < stepEnds.length; i++) {
      if (along < stepEnds[i]) return i;
    }
    return math.max(0, stepEnds.length - 1);
  }
}
