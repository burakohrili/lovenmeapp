import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../../../config/api_keys.dart';
import '../../../models/venue.dart';

class VenueService {
  static const String _nearbyUrl = 'https://places.googleapis.com/v1/places:searchNearby';
  static const String _searchUrl = 'https://places.googleapis.com/v1/places:searchText';
  
  // API çağrı sayacı ve rate limiting
  static int _apiCallCount = 0;
  static DateTime? _lastApiCall;
  static const Duration _minApiInterval = Duration(milliseconds: 200); // 200ms arasında minimum bekleme

  Future<List<Map<String, dynamic>>> fetchVenuesByType(
    String type,
    LatLng location, {
    double radius = 5000.0,
    int maxResults = 5,
  }) async {
    // ✅ GOOGLE MAPS API ENABLED - REAL API CALLS WITH DETAILED LOGGING
    _apiCallCount++;
    
    // Rate limiting kontrolü
    if (_lastApiCall != null) {
      final timeSinceLastCall = DateTime.now().difference(_lastApiCall!);
      if (timeSinceLastCall < _minApiInterval) {
        final waitTime = _minApiInterval - timeSinceLastCall;
        await Future.delayed(waitTime);
      }
    }
    _lastApiCall = DateTime.now();
    
    try {
      final apiKey = ApiKeys.googlePlacesApiKey;
      if (apiKey.isEmpty || apiKey.length < 30 || !apiKey.startsWith('AIza')) {
        return _generateMockVenues(type, location, maxResults);
      }


      final Map<String, dynamic> requestBody = {
        'locationRestriction': {
          'circle': {
            'center': {
              'latitude': location.latitude,
              'longitude': location.longitude,
            },
            'radius': radius,
          },
        },
        'includedTypes': [type],
        'maxResultCount': maxResults,
        'languageCode': 'tr',
        'regionCode': 'TR',
      };


      final response = await http.post(
        Uri.parse(_nearbyUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          // places.photos eksikti: bu yoldan gelen mekanlarin HIC fotografi olmuyordu.
          'X-Goog-FieldMask': 'places.id,places.name,places.displayName,places.location,places.rating,places.formattedAddress,places.types,places.regularOpeningHours,places.photos',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 10));

      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final List<dynamic> places = data['places'] ?? [];
        
        return places.map((place) {
          // Extract actual venue name from the response
          String venueName = place['name'] ?? 'Unknown';
          
          // Sometimes Google Places API returns name as "places/ChIJxxxx" format
          // Try to get displayName.text instead
          if (venueName.startsWith('places/')) {
            venueName = place['displayName']?['text'] ?? 
                       _extractNameFromAddress(place['formattedAddress']) ?? 
                       'Mekan';
          }
          
          final result = {
            'place_id': place['id'] ?? '',
            'name': venueName,
            'category': getCategoryDisplayName(type),
            'rating': (place['rating'] ?? 0.0).toDouble(),
            'vicinity': place['formattedAddress'] ?? '',
            'latitude': place['location']?['latitude'] ?? location.latitude,
            'longitude': place['location']?['longitude'] ?? location.longitude,
            'type': type,
            'closingTime': _extractClosingTime(place['regularOpeningHours']),
            'openingTime': _extractOpeningTime(place['regularOpeningHours']),
          };
          
          // Debug: Opening hours data'sını kontrol et
          
          return result;
        }).cast<Map<String, dynamic>>().toList();
      } else {
        
        // Try legacy Places API if new one fails with 403
        if (response.statusCode == 403) {
          final legacyResult = await _tryLegacyPlacesApi(type, location, radius, maxResults);
          if (legacyResult.isNotEmpty) {
            return legacyResult;
          }
        }
        
        return _generateMockVenues(type, location, maxResults);
      }
    } catch (e) {
      
      // Try legacy Places API as fallback
      final legacyResult = await _tryLegacyPlacesApi(type, location, radius, maxResults);
      if (legacyResult.isNotEmpty) {
        return legacyResult;
      }
      
      return _generateMockVenues(type, location, maxResults);
    }
  }

  // Mock venue generator for testing without API costs
  List<Map<String, dynamic>> _generateMockVenues(String type, LatLng location, int maxResults) {
    final List<Map<String, dynamic>> mockVenues = [];
    
    for (int i = 0; i < maxResults; i++) {
      // Generate venues in a small radius around the location
      final double latOffset = (math.Random().nextDouble() - 0.5) * 0.01; // ~1km range
      final double lngOffset = (math.Random().nextDouble() - 0.5) * 0.01;
      
      mockVenues.add({
        'place_id': 'mock_${type}_${i}_${DateTime.now().millisecondsSinceEpoch}',
        'name': _getMockVenueName(type, i),
        'category': getCategoryDisplayName(type),
        'rating': 3.5 + (math.Random().nextDouble() * 1.5), // 3.5-5.0
        'vicinity': _getMockAddress(type, i),
        'latitude': location.latitude + latOffset,
        'longitude': location.longitude + lngOffset,
        'type': type,
        'closingTime': _getMockClosingTime(),
      });
    }
    
    return mockVenues;
  }

  String _getMockVenueName(String type, int index) {
    final names = {
      'restaurant': ['Lezzet Durağı', 'Gurme Köşe', 'Tadım Restaurant', 'Sofra Evi', 'Damak Zevki'],
      'cafe': ['Kahve Diyarı', 'Sıcak Nokta', 'Espresso Bar', 'Keyif Kahvesi', 'Sohbet Mekanı'],
      'bar': ['Gece Işığı', 'Cocktail Corner', 'Rüya Bar', 'Sahil Barı', 'Mavi Gece'],
      'gym': ['Fit Center', 'Power Gym', 'Sağlık Merkezi', 'Spor Kulübü', 'Atletik Merkez'],
    };
    
    final typeNames = names[type] ?? ['Test Mekan'];
    return '${typeNames[index % typeNames.length]} ${index + 1}';
  }

  String _getMockAddress(String type, int index) {
    final addresses = [
      'Merkez Mahallesi, Test Caddesi No:${index + 1}',
      'Şehir Merkezi, Örnek Sokak ${index + 10}',
      'Yeni Mahalle, Demo Bulvarı ${index + 20}',
      'Test Bölgesi, Sahte Cadde ${index + 30}',
    ];
    return addresses[index % addresses.length];
  }

  String _getMockClosingTime() {
    final hours = ['22:00', '23:00', '00:00', '01:00', '24:00'];
    return hours[math.Random().nextInt(hours.length)];
  }

  String _extractClosingTime(Map<String, dynamic>? openingHours) {
    try {
      
      if (openingHours == null) {
        return '22:00';
      }
      
      final periods = openingHours['periods'] as List<dynamic>?;
      if (periods == null || periods.isEmpty) {
        return '22:00';
      }
      
      // Google Places API: 0 = Pazar, 1 = Pazartesi, ... 6 = Cumartesi
      // Dart DateTime.weekday: 1 = Pazartesi, 2 = Salı, ... 7 = Pazar
      final dartWeekday = DateTime.now().weekday;
      final googleDay = dartWeekday == 7 ? 0 : dartWeekday; // Pazar için 7 -> 0 dönüşümü
      
      
      // Bugünkü kapanış saatlerini bul
      for (int i = 0; i < periods.length; i++) {
        final period = periods[i];
        final open = period['open'];
        if (open != null && open['day'] == googleDay) {
          
          final close = period['close'];
          
          // NEW: Try different access methods
          final closeAsDynamic = period['close'] as Map<String, dynamic>?;
          
          final closeAsMap = period['close'] as Map?;
          
          
          if (close != null) {
            
            // Handle both formats: {time: "0130"} and {hour: 1, minute: 30}
            final time = close['time'];
            final hour = close['hour'];
            final minute = close['minute'];
            
            
            if (time != null && time.toString().length == 4) {
              // Format: "0130" -> "01:30"
              final timeStr = time.toString();
              final formattedTime = '${timeStr.substring(0, 2)}:${timeStr.substring(2, 4)}';
              return formattedTime;
            } else if (hour != null && minute != null) {
              // Format: {hour: 1, minute: 30} -> "01:30"
              int hourInt = hour is int ? hour : int.tryParse(hour.toString()) ?? 0;
              int minuteInt = minute is int ? minute : int.tryParse(minute.toString()) ?? 0;
              final formattedTime = '${hourInt.toString().padLeft(2, '0')}:${minuteInt.toString().padLeft(2, '0')}';
              return formattedTime;
            } else {
            }
          } else {
          }
        } else {
        }
      }
      
      return '22:00'; // Default closing time
    } catch (e) {
      return '22:00';
    }
  }

  String _extractOpeningTime(Map<String, dynamic>? openingHours) {
    try {
      
      if (openingHours == null) {
        return '08:00';
      }
      
      final periods = openingHours['periods'] as List<dynamic>?;
      if (periods == null || periods.isEmpty) {
        return '08:00';
      }
      
      // Google Places API: 0 = Pazar, 1 = Pazartesi, ... 6 = Cumartesi
      // Dart DateTime.weekday: 1 = Pazartesi, 2 = Salı, ... 7 = Pazar
      final dartWeekday = DateTime.now().weekday;
      final googleDay = dartWeekday == 7 ? 0 : dartWeekday; // Pazar için 7 -> 0 dönüşümü
      
      
      // Bugünkü açılış saatlerini bul
      for (int i = 0; i < periods.length; i++) {
        final period = periods[i];
        final open = period['open'];
        if (open != null && open['day'] == googleDay) {
          
          // Handle both formats: {time: "0800"} and {hour: 8, minute: 0}
          final time = open['time'] as String?;
          final hour = open['hour'];
          final minute = open['minute'];
          
          
          if (time != null && time.length == 4) {
            // Format: "0800" -> "08:00"
            final formattedTime = '${time.substring(0, 2)}:${time.substring(2, 4)}';
            return formattedTime;
          } else if (hour != null && minute != null) {
            // Format: {hour: 8, minute: 0} -> "08:00"
            int hourInt = hour is int ? hour : int.tryParse(hour.toString()) ?? 8;
            int minuteInt = minute is int ? minute : int.tryParse(minute.toString()) ?? 0;
            final formattedTime = '${hourInt.toString().padLeft(2, '0')}:${minuteInt.toString().padLeft(2, '0')}';
            return formattedTime;
          } else {
          }
        } else {
        }
      }
      
      return '08:00'; // Default opening time
    } catch (e) {
      return '08:00';
    }
  }

  // Helper function to extract venue name from address when name is not available
  String? _extractNameFromAddress(String? address) {
    if (address == null || address.isEmpty) return null;
    
    // Try to extract a meaningful name from the address
    // Format: "Venue Name, Street Address, City"
    final parts = address.split(',');
    if (parts.isNotEmpty) {
      final firstPart = parts[0].trim();
      // Skip if it's just a street name or number
      if (!firstPart.contains('No:') && 
          !firstPart.contains('Cd.') && 
          !firstPart.contains('Sk.') &&
          !RegExp(r'^\d').hasMatch(firstPart)) {
        return firstPart;
      }
    }
    
    return null;
  }

  // Legacy Places API fallback method
  Future<List<Map<String, dynamic>>> _tryLegacyPlacesApi(
    String type,
    LatLng location,
    double radius,
    int maxResults,
  ) async {
    try {
      final apiKey = ApiKeys.googlePlacesApiKey;
      
      // Convert type to legacy API format
      String legacyType = _convertToLegacyType(type);
      
      final String legacyUrl = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${location.latitude},${location.longitude}'
          '&radius=${radius.toInt()}'
          '&type=$legacyType'
          '&language=tr'
          '&key=$apiKey';


      final response = await http.get(Uri.parse(legacyUrl)).timeout(const Duration(seconds: 10));
      
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> results = data['results'] ?? [];
        
        
        return results.take(maxResults).map((place) {
          return {
            'place_id': place['place_id'] ?? '',
            'name': place['name'] ?? 'Unknown',
            'category': getCategoryDisplayName(type),
            'rating': (place['rating'] ?? 0.0).toDouble(),
            'vicinity': place['vicinity'] ?? '',
            'latitude': place['geometry']?['location']?['lat'] ?? location.latitude,
            'longitude': place['geometry']?['location']?['lng'] ?? location.longitude,
            'type': type,
            'closingTime': '22:00', // Default for legacy API
          };
        }).cast<Map<String, dynamic>>().toList();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Convert new API types to legacy API types
  String _convertToLegacyType(String newType) {
    const typeMapping = {
      'restaurant': 'restaurant',
      'cafe': 'cafe',
      'bar': 'bar',
      'gym': 'gym',
      'night_club': 'night_club',
      'shopping_mall': 'shopping_mall',
      'art_gallery': 'art_gallery',
      'museum': 'museum',
      'theater': 'movie_theater',
    };
    
    return typeMapping[newType] ?? newType;
  }

  /* 
  // ORIGINAL API METHOD - COMMENTED OUT FOR COST SAVINGS
  Future<List<Map<String, dynamic>>> fetchVenuesByType(
    String type,
    LatLng location, {
    double radius = 5000.0,
    int maxResults = 5,
  }) async {
    try {
      final apiKey = ApiKeys.googlePlacesApiKey;
      if (apiKey.isEmpty || apiKey.length < 30 || !apiKey.startsWith('AIza')) {
        return [];
      }


      final Map<String, dynamic> requestBody = {
        'includedTypes': [type],
        'maxResultCount': maxResults,
        'locationRestriction': {
          'circle': {
            'center': {
              'longitude': location.longitude,
            },
            'radius': math.min(radius, 5000).toInt(), // Maksimum 50km
          }
        }
      };

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': apiKey,
              'X-Goog-FieldMask':
                  'places.id,places.displayName,places.formattedAddress,places.rating,places.location,places.currentOpeningHours',
            },
            body: json.encode(requestBody),
          )
          .timeout(Duration(seconds: Platform.isIOS ? 30 : 25));


      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['places'] != null) {
          final places = data['places'] as List;
          

          return places.map((place) {
            final displayName = place['displayName']?['text'] ?? 'Unknown Place';
            final formattedAddress = place['formattedAddress'] ?? '';
            final rating = (place['rating'] as num?)?.toDouble() ?? 0.0;
            final placeId = place['id'] ?? '';
            final location = place['location'];
            
            String? closingTime;
            if (place['currentOpeningHours'] != null) {
              final openingHours = place['currentOpeningHours'];
              if (openingHours['periods'] != null && openingHours['periods'].isNotEmpty) {
                final today = DateTime.now().weekday - 1;
                final todayPeriod = openingHours['periods'].firstWhere(
                  (p) => p['open']['day'] == today,
                  orElse: () => null,
                );
                
                if (todayPeriod != null && todayPeriod['close'] != null) {
                  closingTime = "${todayPeriod['close']['hour']}:${todayPeriod['close']['minute'] ?? '00'}";
                }
              }
            }

            final result = {
              'place_id': placeId,
              'name': displayName,
              'category': getCategoryDisplayName(type),
              'rating': rating,
              'vicinity': formattedAddress,
              'latitude': location?['latitude']?.toDouble() ?? 0.0,
              'longitude': location?['longitude']?.toDouble() ?? 0.0,
              'type': type,
              'closingTime': closingTime,
            };
            
            return result;
          }).toList();
        }
      }

      return [];
    } catch (e) {
      final platform = Platform.isIOS ? 'iOS' : 'Android';
      return [];
    }
  }
  */

  Future<List<Venue>> searchVenues(String query, LatLng currentPosition) async {
    // 🚫 SEARCH API ALSO DISABLED - NO COST MODE
    await Future.delayed(const Duration(milliseconds: 300));
    return []; // Return empty search results
  }

  String getCategoryDisplayName(String type) {
    switch (type) {
      case 'cafe':
        return 'Kafe';
      case 'bar':
        return 'Bar';
      case 'night_club':
        return 'Gece Kulübü';
      case 'restaurant':
        return 'Restoran';
      case 'gym':
        return 'Spor Salonu';
      case 'sports_complex':
        return 'Spor Kompleksi';
      case 'art_gallery':
        return 'Sanat Galerisi';
      case 'museum':
        return 'Müze';
      case 'theater':
        return 'Tiyatro';
      case 'cultural_center':
        return 'Kültür Merkezi';
      case 'event_venue':
        return 'Etkinlik Alanı';
      case 'convention_center':
        return 'Kongre Merkezi';
      case 'amusement_park':
        return 'Lunapark';
      case 'bowling_alley':
        return 'Bowling Salonu';
      case 'shopping_mall':
        return 'Alışveriş Merkezi';
      default:
        return 'Mekan';
    }
  }

  double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000;

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

  /// Venue ID'den venue name'i al
  Future<String> getVenueNameById(String venueId) async {
    try {
      final apiKey = ApiKeys.googlePlacesApiKey;
      if (apiKey.isEmpty || apiKey.length < 30 || !apiKey.startsWith('AIza')) {
        return 'İsimsiz Mekan';
      }

      final url = 'https://places.googleapis.com/v1/places/$venueId';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'name,displayName',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Extract venue name
        String venueName = data['name'] ?? 'İsimsiz Mekan';
        
        // If name starts with "places/", try to get displayName
        if (venueName.startsWith('places/')) {
          venueName = data['displayName']?['text'] ?? 'İsimsiz Mekan';
        }
        
        return venueName;
      } else {
        return 'İsimsiz Mekan';
      }
    } catch (e) {
      return 'İsimsiz Mekan';
    }
  }
}
