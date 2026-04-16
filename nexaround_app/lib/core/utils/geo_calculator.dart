import 'dart:math';

class GeoCalculator {
  /// Calculate the initial bearing (azimuth) between two points on the earth.
  static double bearing(double lat1, double lon1, double lat2, double lon2) {
    double lat1Rad = lat1 * pi / 180;
    double lat2Rad = lat2 * pi / 180;
    double deltaLon = (lon2 - lon1) * pi / 180;

    double y = sin(deltaLon) * cos(lat2Rad);
    double x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(deltaLon);
    
    double bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
  }

  /// Calculate the distance in meters between two coordinates.
  static double distance(double lat1, double lon1, double lat2, double lon2) {
    const double radius = 6371000; // Earth radius in meters
    double lat1Rad = lat1 * pi / 180;
    double lat2Rad = lat2 * pi / 180;
    double deltaLat = (lat2 - lat1) * pi / 180;
    double deltaLon = (lon2 - lon1) * pi / 180;

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLon / 2) * sin(deltaLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return radius * c;
  }
}
