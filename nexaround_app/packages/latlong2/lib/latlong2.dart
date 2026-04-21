library latlong2;

import 'dart:math';

class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(double latitude, double longitude)
      : latitude = latitude,
        longitude = longitude;

  double get lat => latitude;
  double get lng => longitude;

  @override
  String toString() => 'LatLng(lat: $latitude, long: $longitude)';

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;

  LatLng round({int decimals = 6}) {
    final rel = pow(10, decimals);
    return LatLng(
      (latitude * rel).round() / rel,
      (longitude * rel).round() / rel,
    );
  }
}

class Distance {
  final double radius;
  const Distance({this.radius = 6371000});

  double as(LengthUnit unit, LatLng p1, LatLng p2) {
    var lat1 = p1.latitude * pi / 180;
    var lat2 = p2.latitude * pi / 180;
    var lon1 = p1.longitude * pi / 180;
    var lon2 = p2.longitude * pi / 180;

    var dLat = lat2 - lat1;
    var dLon = lon2 - lon1;

    var a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));

    var distance = radius * c;
    return distance;
  }

  double distance(LatLng p1, LatLng p2) => as(LengthUnit.Meter, p1, p2);
  
  LatLng offset(LatLng from, double distanceInMeter, double bearing) {
      return from; // Stub
  }
}

enum LengthUnit { Meter, Kilometer }
