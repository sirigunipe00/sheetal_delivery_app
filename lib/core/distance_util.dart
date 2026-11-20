import 'package:geolocator/geolocator.dart';

class DistanceUtil {
  const DistanceUtil._();

  static double? kmBetween({
    required double? lat1,
    required double? lng1,
    required double? lat2,
    required double? lng2,
  }) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return null;
    }
    final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return meters / 1000.0;
  }

  static String? labelKm(double? km) {
    if (km == null) return null;
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }
}
