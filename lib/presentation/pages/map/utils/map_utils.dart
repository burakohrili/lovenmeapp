import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapUtils {
  // Calculate distance between two coordinates
  static double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    double lat1Rad = point1.latitude * (math.pi / 180);
    double lat2Rad = point2.latitude * (math.pi / 180);
    double deltaLatRad = (point2.latitude - point1.latitude) * (math.pi / 180);
    double deltaLngRad = (point2.longitude - point1.longitude) * (math.pi / 180);

    double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLngRad / 2) *
            math.sin(deltaLngRad / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  // Format distance for display
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()}m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  // Check if user is within check-in range
  static bool isWithinCheckInRange(
    LatLng userLocation,
    LatLng venueLocation,
    double maxDistance,
  ) {
    final distance = calculateDistance(userLocation, venueLocation);
    return distance <= maxDistance;
  }

  // Calculate bounds for multiple markers
  static LatLngBounds calculateBounds(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      throw ArgumentError('Coordinates list cannot be empty');
    }

    double minLat = coordinates.first.latitude;
    double maxLat = coordinates.first.latitude;
    double minLng = coordinates.first.longitude;
    double maxLng = coordinates.first.longitude;

    for (final coord in coordinates) {
      minLat = math.min(minLat, coord.latitude);
      maxLat = math.max(maxLat, coord.latitude);
      minLng = math.min(minLng, coord.longitude);
      maxLng = math.max(maxLng, coord.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Get appropriate zoom level based on distance
  static double getZoomLevel(double distanceInMeters) {
    if (distanceInMeters <= 100) return 18.0;
    if (distanceInMeters <= 500) return 16.0;
    if (distanceInMeters <= 1000) return 15.0;
    if (distanceInMeters <= 5000) return 13.0;
    if (distanceInMeters <= 10000) return 12.0;
    return 11.0;
  }

  // Convert meters to approximate LatLng degrees
  static double metersToLatLngDegrees(double meters) {
    return meters / 111320; // Approximate conversion
  }

  // Get center point of multiple coordinates
  static LatLng getCenterPoint(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      throw ArgumentError('Coordinates list cannot be empty');
    }

    double totalLat = 0;
    double totalLng = 0;

    for (final coord in coordinates) {
      totalLat += coord.latitude;
      totalLng += coord.longitude;
    }

    return LatLng(
      totalLat / coordinates.length,
      totalLng / coordinates.length,
    );
  }

  // Check if coordinate is valid
  static bool isValidCoordinate(LatLng coordinate) {
    return coordinate.latitude >= -90 &&
           coordinate.latitude <= 90 &&
           coordinate.longitude >= -180 &&
           coordinate.longitude <= 180;
  }

  // Get bearing between two points
  static double getBearing(LatLng start, LatLng end) {
    double startLat = start.latitude * (math.pi / 180);
    double startLng = start.longitude * (math.pi / 180);
    double endLat = end.latitude * (math.pi / 180);
    double endLng = end.longitude * (math.pi / 180);

    double deltaLng = endLng - startLng;

    double y = math.sin(deltaLng) * math.cos(endLat);
    double x = math.cos(startLat) * math.sin(endLat) -
               math.sin(startLat) * math.cos(endLat) * math.cos(deltaLng);

    double bearing = math.atan2(y, x);
    bearing = bearing * (180 / math.pi);
    bearing = (bearing + 360) % 360;

    return bearing;
  }

  // Animate camera to show all markers
  static CameraUpdate getCameraUpdateToShowAllMarkers(
    List<LatLng> coordinates, {
    double padding = 100.0,
  }) {
    if (coordinates.isEmpty) {
      throw ArgumentError('Coordinates list cannot be empty');
    }

    if (coordinates.length == 1) {
      return CameraUpdate.newLatLngZoom(coordinates.first, 15.0);
    }

    final bounds = calculateBounds(coordinates);
    return CameraUpdate.newLatLngBounds(bounds, padding);
  }
}

// Extension methods for LatLng
extension LatLngExtensions on LatLng {
  // Get distance to another coordinate
  double distanceTo(LatLng other) {
    return MapUtils.calculateDistance(this, other);
  }

  // Get formatted distance to another coordinate
  String formattedDistanceTo(LatLng other) {
    return MapUtils.formatDistance(distanceTo(other));
  }

  // Check if within range of another coordinate
  bool isWithinRange(LatLng other, double maxDistance) {
    return distanceTo(other) <= maxDistance;
  }

  // Get bearing to another coordinate
  double bearingTo(LatLng other) {
    return MapUtils.getBearing(this, other);
  }
}
