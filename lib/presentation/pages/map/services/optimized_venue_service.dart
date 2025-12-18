import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../../../config/api_keys.dart';
import '../../../models/venue.dart';
import '../../../../core/services/venue_cache_service.dart';

class OptimizedVenueService {
  static const String _nearbyUrl = 'https://places.googleapis.com/v1/places:searchNearby';
  // static const String _searchUrl = 'https://places.googleapis.com/v1/places:searchText';
  
  // API çağrı sayacı ve rate limiting
  static int _apiCallCount = 0;
  static DateTime? _lastApiCall;
  static const Duration _minApiInterval = Duration(milliseconds: 300); // 300ms arasında bekleme
  
  // Priority kategori sıralaması: Belirlenen kategoriler
  static const List<String> _priorityCategories = [
    'cafe',                    // 1. Kafe
    'restaurant',             // 2. Restoran
    'bakery',                 // 3. Fırın & Kafe (bakery = fırın)
    'gym',                    // 4. Spor salonu
    'movie_theater',          // 5. Sinema
    'night_club',             // 6. Gece kulübü  
    'bar',                    // 7. Bar
  ];

  // TEK API ÇAĞRISI ile TÜM KATEGORİLERİ getir
  Future<List<Venue>> fetchVenuesOptimized(
    LatLng location, {
    double radius = 200.0, // 200m default
    int maxResults = 20, // Google Places API max limit per request
    bool sortByDistance = true, // Distance sorting eklendi
    bool priorityByDistance = true, // PURE distance sorting option (default true)
  }) async {
    _apiCallCount++;
    
    // 1. CACHE KONTROLÜ
    final cachedVenues = await VenueCacheService.getCachedVenues(location, radius);
    if (cachedVenues != null && cachedVenues.isNotEmpty) {
      final sortedVenues = _sortVenuesByPreference(cachedVenues, location, sortByDistance, priorityByDistance);
      return sortedVenues;
    }
    
    // 2. RATE LIMITING
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
      if (apiKey.isEmpty || apiKey.length < 25) { // Daha gevşek kontrol
        return [];
      }


      // 3. TEK API ÇAĞRISI - TÜM KATEGORİLER BİRDEN
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
        'includedTypes': _priorityCategories, // TÜM KATEGORİLER BİRDEN!
        'maxResultCount': maxResults,
        'languageCode': 'tr',
        'regionCode': 'TR',
      };


      final response = await http.post(
        Uri.parse(_nearbyUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'places.id,places.name,places.displayName,places.location,places.rating,places.formattedAddress,places.types,places.regularOpeningHours,places.photos',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> places = data['places'] ?? [];
        
        // 4. VENUE'LARI İŞLE ve CACHE'E KAYDET
        final venues = await _processVenuesFromApiResponse(places, location);
        
        // 5. CACHE'E KAYDET
        if (venues.isNotEmpty) {
          await VenueCacheService.cacheVenues(location, radius, venues);
        }
        
        // 6. DISTANCE + PRIORITY SORTING  
        final sortedVenues = _sortVenuesByPreference(venues, location, sortByDistance, priorityByDistance);
        
        return sortedVenues;
        
      } else {
        
        // 6. LEGACY API FALLBACK
        if (response.statusCode == 403) {
          return await _tryLegacyApiFallback(location, radius, maxResults, sortByDistance, priorityByDistance);
        }
        
        return [];
      }
    } catch (e) {
      
      // 7. LEGACY API FALLBACK
      final legacyResult = await _tryLegacyApiFallback(location, radius, maxResults, sortByDistance, priorityByDistance);
      if (legacyResult.isNotEmpty) {
        return legacyResult;
      }
      
      return [];
    }
  }

  // Sorting preference helper
  List<Venue> _sortVenuesByPreference(List<Venue> venues, LatLng userLocation, bool sortByDistance, bool priorityByDistance) {
    if (priorityByDistance) {
      return _sortVenuesByPureDistance(venues, userLocation);
    } else if (sortByDistance) {
      return _sortVenuesByDistanceAndPriority(venues, userLocation);
    } else {
      return _sortVenuesByPriority(venues);
    }
  }

  // PURE distance sorting - sadece mesafeye göre sırala
  List<Venue> _sortVenuesByPureDistance(List<Venue> venues, LatLng userLocation) {
    venues.sort((a, b) {
      final aDistance = _calculateDistance(userLocation, a.location);
      final bDistance = _calculateDistance(userLocation, b.location);
      return aDistance.compareTo(bDistance); // En yakından en uzağa
    });
    
    final nearestVenues = venues.take(5).map((v) {
      final distance = _calculateDistance(userLocation, v.location);
      return '${v.name}(${distance.toInt()}m)';
    }).join(', ');
    
    return venues;
  }

  // Venue'ları kategori önceliğine göre sırala
  List<Venue> _sortVenuesByPriority(List<Venue> venues) {
    venues.sort((a, b) {
      final aPriority = _getPriorityIndex(a.category);
      final bPriority = _getPriorityIndex(b.category);
      
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority); // Düşük index = yüksek öncelik
      }
      
      // Aynı kategorideyse isim alfabetik sıralama
      return a.name.compareTo(b.name);
    });
    
    return venues;
  }

  // Venue'ları DISTANCE + PRIORITY'ye göre sırala (DAHA İYİ)
  List<Venue> _sortVenuesByDistanceAndPriority(List<Venue> venues, LatLng userLocation) {
    // Her venue için distance hesapla
    venues.sort((a, b) {
      final aPriority = _getPriorityIndex(a.category);
      final bPriority = _getPriorityIndex(b.category);
      
      // Önce kategori önceliği
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      
      // Aynı kategorideyse distance'e göre sırala
      final aDistance = _calculateDistance(userLocation, a.location);
      final bDistance = _calculateDistance(userLocation, b.location);
      
      return aDistance.compareTo(bDistance); // Yakından uzağa
    });
    
    final nearestVenues = venues.take(5).map((v) {
      final distance = _calculateDistance(userLocation, v.location);
      return '${v.category}:${v.name}(${distance.toInt()}m)';
    }).join(', ');
    
    return venues;
  }

  // Distance hesaplama helper
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // metres
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

  int _getPriorityIndex(String category) {
    // Category'yi priority listesinde ara
    for (int i = 0; i < _priorityCategories.length; i++) {
      if (category.toLowerCase().contains(_priorityCategories[i]) || 
          _mapCategoryToPriority(category) == _priorityCategories[i]) {
        return i;
      }
    }
    return 999; // En düşük öncelik
  }

  String _mapCategoryToPriority(String category) {
    switch (category.toLowerCase()) {
      case 'kafe':
      case 'café':
      case 'coffee_shop':
        return 'cafe';
      case 'gece kulübü':
      case 'club':
      case 'night_club':
        return 'night_club';
      case 'bar':
      case 'pub':
        return 'bar';
      case 'spor salonu':
      case 'gym':
      case 'fitness':
        return 'gym';
      case 'restoran':
      case 'restaurant':
        return 'restaurant';
      default:
        return category;
    }
  }

  // API response'dan venue'ları işle
  Future<List<Venue>> _processVenuesFromApiResponse(List<dynamic> places, LatLng centerLocation) async {
    final List<Venue> venues = [];
    
    for (final place in places) {
      try {
        // Venue name extraction
        String venueName = place['name'] ?? 'Unknown';
        if (venueName.startsWith('places/')) {
          venueName = place['displayName']?['text'] ?? 
                     _extractNameFromAddress(place['formattedAddress']) ?? 
                     'Mekan';
        }
        
        // Kategori belirleme
        final types = place['types'] as List<dynamic>? ?? [];
        final category = _determineCategoryFromTypes(types);
        
        // Extract both opening and closing times
        final hoursTimes = _extractOpeningHours(place['regularOpeningHours']);
        
        // Extract photos from Google Places API
        List<String> photoUrls = [];
        if (place['photos'] != null && place['photos'] is List) {
          final photos = place['photos'] as List;
          final apiKey = ApiKeys.googlePlacesApiKey;
          
          // Convert photo references to URLs (max 5 photos)
          // Using NEW Google Places API format
          photoUrls = photos.take(5).map((photo) {
            final photoName = photo['name'] as String? ?? '';
            if (photoName.isNotEmpty) {
              // NEW Google Places API Photo URL format
              // Format: https://places.googleapis.com/v1/{photoName}/media?key={apiKey}&maxHeightPx=800
              return 'https://places.googleapis.com/v1/$photoName/media'
                  '?key=$apiKey'
                  '&maxHeightPx=800'
                  '&maxWidthPx=800';
            }
            return '';
          }).where((url) => url.isNotEmpty).toList();
          
          if (photoUrls.isNotEmpty) {
          }
        }
        
        
        final venueData = {
          'place_id': place['id'] ?? '',
          'name': venueName,
          'category': category,
          'rating': (place['rating'] ?? 0.0).toDouble(),
          'vicinity': place['formattedAddress'] ?? '',
          'latitude': place['location']?['latitude'] ?? centerLocation.latitude,
          'longitude': place['location']?['longitude'] ?? centerLocation.longitude,
          'type': category,
          'openingTime': hoursTimes['openingTime'],
          'closingTime': hoursTimes['closingTime'],
          'photos': photoUrls, // ✅ Fotoğraflar eklendi
        };
        
        
        final venue = Venue.fromPlaceData(venueData);
        venues.add(venue);
        
      } catch (e) {
        continue;
      }
    }
    
    return venues;
  }

  // Types'tan kategori belirle
  String _determineCategoryFromTypes(List<dynamic> types) {
    final typeStrings = types.map((e) => e.toString().toLowerCase()).toList();
    
    // Priority sırasına göre kontrol et
    if (typeStrings.any((t) => ['cafe', 'coffee_shop'].contains(t))) {
      return 'cafe';
    }
    if (typeStrings.any((t) => ['night_club'].contains(t))) {
      return 'night_club';
    }
    if (typeStrings.any((t) => ['bar', 'bar_and_grill'].contains(t))) {
      return 'bar';
    }
    if (typeStrings.any((t) => ['gym', 'fitness', 'sports_complex'].contains(t))) {
      return 'gym';
    }
    if (typeStrings.any((t) => ['restaurant', 'food', 'meal_takeaway'].contains(t))) {
      return 'restaurant';
    }
    
    return 'venue'; // Genel kategori
  }

  // Legacy API fallback
  Future<List<Venue>> _tryLegacyApiFallback(
    LatLng location, 
    double radius, 
    int maxResults, 
    bool sortByDistance,
    bool priorityByDistance,
  ) async {
    
    try {
      final apiKey = ApiKeys.googlePlacesApiKey;
      final venues = <Venue>[];
      
      // Her kategori için ayrı ayrı legacy API çağrısı (mecburen)
      for (String category in _priorityCategories.take(3)) { // Sadece ilk 3 kategori
        if (venues.length >= maxResults) break;
        
        final legacyType = _convertToLegacyType(category);
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
          
          for (final place in results.take(maxResults ~/ 3)) {
            final venueData = {
              'place_id': place['place_id'] ?? '',
              'name': place['name'] ?? 'Unknown',
              'category': category,
              'rating': (place['rating'] ?? 0.0).toDouble(),
              'vicinity': place['vicinity'] ?? '',
              'latitude': place['geometry']?['location']?['lat'] ?? location.latitude,
              'longitude': place['geometry']?['location']?['lng'] ?? location.longitude,
              'type': category,
              'closingTime': null, // Legacy API doesn't provide detailed opening hours
            };
            
            venues.add(Venue.fromPlaceData(venueData));
          }
        }
        
        // Legacy API için rate limiting
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      
      // Cache'e kaydet
      if (venues.isNotEmpty) {
        await VenueCacheService.cacheVenues(location, radius, venues);
      }
      
      return _sortVenuesByPreference(venues, location, sortByDistance, priorityByDistance);
      
    } catch (e) {
      return [];
    }
  }

  // Helper methods
  String _convertToLegacyType(String newType) {
    const typeMapping = {
      'cafe': 'cafe',
      'night_club': 'night_club',
      'bar': 'bar',
      'gym': 'gym',
      'restaurant': 'restaurant',
    };
    return typeMapping[newType] ?? newType;
  }

  String? _extractNameFromAddress(String? address) {
    if (address == null || address.isEmpty) return null;
    final parts = address.split(',');
    if (parts.isNotEmpty) {
      final firstPart = parts[0].trim();
      if (!firstPart.contains('No:') && !firstPart.contains('Cd.') && 
          !RegExp(r'^\d').hasMatch(firstPart)) {
        return firstPart;
      }
    }
    return null;
  }

  // Extract both opening and closing times from opening hours data
  Map<String, String?> _extractOpeningHours(Map<String, dynamic>? openingHours) {
    try {
      
      if (openingHours == null) {
        return {'openingTime': '07:00', 'closingTime': '02:00'};
      }
      
      // Check openNow status first
      final openNow = openingHours['openNow'];
      
      final periods = openingHours['periods'] as List<dynamic>?;
      if (periods == null || periods.isEmpty) {
        return {'openingTime': '07:00', 'closingTime': '02:00'};
      }
      
      final dartWeekday = DateTime.now().weekday;
      final googleDay = dartWeekday == 7 ? 0 : dartWeekday; // Pazar için 7 -> 0 dönüşümü
      
      
      String? openingTime;
      String? closingTime;
      
      for (final period in periods) {
        final open = period['open'];
        if (open != null && open['day'] == googleDay) {
          
          // Extract opening time
          final openTimeField = open['time'] as String?;
          final openHourField = open['hour'];
          final openMinuteField = open['minute'];
          
          if (openTimeField != null && openTimeField.length == 4) {
            openingTime = '${openTimeField.substring(0, 2)}:${openTimeField.substring(2, 4)}';
          } else if (openHourField != null && openMinuteField != null) {
            final hour = openHourField is int ? openHourField : int.tryParse(openHourField.toString()) ?? 0;
            final minute = openMinuteField is int ? openMinuteField : int.tryParse(openMinuteField.toString()) ?? 0;
            openingTime = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
          }
          
          // Extract closing time
          final close = period['close'];
          
          if (close != null) {
            final timeField = close['time'] as String?;
            final hourField = close['hour'];
            final minuteField = close['minute'];
            
            // Check for cross-day closing
            final openDay = open['day'];
            final closeDay = close['day'];
            final isCrossDay = openDay != null && closeDay != null && openDay != closeDay;
            
            if (timeField != null && timeField.length == 4) {
              final formattedTime = '${timeField.substring(0, 2)}:${timeField.substring(2, 4)}';
              closingTime = isCrossDay ? '+$formattedTime' : formattedTime;
            } else if (hourField != null && minuteField != null) {
              final hour = hourField is int ? hourField : int.tryParse(hourField.toString()) ?? 0;
              final minute = minuteField is int ? minuteField : int.tryParse(minuteField.toString()) ?? 0;
              final formattedTime = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
              closingTime = isCrossDay ? '+$formattedTime' : formattedTime;
            }
          }
          
          break; // Found today's period
        }
      }
      
      // Check if this is a 24/7 venue
      final weekdayDescriptions = openingHours['weekdayDescriptions'] as List?;
      if (weekdayDescriptions != null) {
        final is24_7 = weekdayDescriptions.any((desc) => 
          desc.toString().contains('24 saat açık'));
        if (is24_7) {
          return {'openingTime': openingTime ?? '00:00', 'closingTime': null}; // null for 24/7
        }
      }
      
      
      return {
        'openingTime': openingTime ?? '07:00',  // Default opening time
        'closingTime': closingTime ?? '02:00'   // Default closing time
      };
      
    } catch (e) {
      return {'openingTime': '07:00', 'closingTime': '02:00'};
    }
  }

  String getCategoryDisplayName(String type) {
    switch (type) {
      case 'cafe': return 'Kafe';
      case 'night_club': return 'Gece Kulübü';
      case 'bar': return 'Bar';
      case 'gym': return 'Spor Salonu';
      case 'restaurant': return 'Restoran';
      default: return 'Mekan';
    }
  }
  
  /// Cache temizleme methodu
  static Future<void> clearAllCaches() async {
    try {
      await VenueCacheService.clearCache();
    } catch (e) {
    }
  }
}
