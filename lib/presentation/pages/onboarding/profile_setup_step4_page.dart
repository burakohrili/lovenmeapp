import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'user_profile_provider.dart';
import '../../../config/api_keys.dart';
import '../../../core/theme/app_colors.dart';
import 'profile_setup_step5_page.dart';

class ProfileSetupStep4Page extends ConsumerStatefulWidget {
  const ProfileSetupStep4Page({super.key});

  @override
  ConsumerState<ProfileSetupStep4Page> createState() => _ProfileSetupStep4PageState();
}

class _ProfileSetupStep4PageState extends ConsumerState<ProfileSetupStep4Page> {
  // State variables
  List<String> selectedVenues = [];
  Map<String, String> selectedVenueIds = {};
  List<Map<String, dynamic>> selectedVenueDetails = [];
  List<Map<String, dynamic>> allVenues = [];
  List<Map<String, dynamic>> searchResults = [];
  final int minVenues = 3;
  final int maxVenues = 5;
  
  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final Completer<GoogleMapController> _mapController = Completer();
  
  // Location & Map
  String currentCity = "İzmir";
  Position? userLocation;
  Set<Marker> mapMarkers = {};
  LatLng? mapCenter;
  double currentZoom = 12.0;
  
  // Loading states
  bool isLoadingLocation = true;
  bool isLoadingVenues = false;
  bool isSearching = false;
  bool hasLocationError = false;
  bool isApiKeyConfigured = false;
  bool showMapMode = false;
  bool isFullScreenMap = false;
  
  // API Configuration
  static const int maxVenuesPerCategory = 50;

  @override
  void initState() {
    super.initState();
    _checkApiConfiguration();
    _loadExistingVenues(); // 🔥 YENİ: Önce mevcut mekanları yükle
    _initializeLocationAndVenues();
  }
  
  // 🔥 YENİ: Provider'dan mevcut favori mekanları yükle
  void _loadExistingVenues() {
    final profile = ref.read(userProfileProvider);
    if (profile.favoriteVenueDetails.isNotEmpty) {
      setState(() {
        selectedVenueDetails = List.from(profile.favoriteVenueDetails);
        selectedVenues = List.from(profile.favoriteVenues);
        
        // İsimleri de al
        for (var venue in selectedVenueDetails) {
          if (venue['name'] != null) {
            selectedVenueIds[venue['name']] = venue['place_id'] ?? '';
          }
        }
      });
    }
  }

  @override
  void dispose() {
    mapMarkers.clear();
    _searchController.dispose();
    super.dispose();
  }

  void _checkApiConfiguration() {
    final apiKey = ApiKeys.googlePlacesApiKey;
    isApiKeyConfigured = apiKey.isNotEmpty && 
                        apiKey.startsWith("AIza") && 
                        apiKey.length >= 35;
    
  }

  Future<void> _initializeLocationAndVenues() async {
    try {
      setState(() {
        isLoadingLocation = true;
        hasLocationError = false;
      });

      // iOS ve Android için farklı izin sistemleri
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS için Geolocator'ın kendi izin sistemi
        LocationPermission permission = await Geolocator.checkPermission();
        
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw 'iOS konum izni reddedildi';
          }
        }
        
        if (permission == LocationPermission.deniedForever) {
          throw 'iOS konum izni kalıcı olarak reddedildi. Ayarlardan izin verin.';
        }
        
      } else {
        // Android için permission_handler
        PermissionStatus permission = await Permission.location.status;
        
        if (permission.isDenied) {
          permission = await Permission.location.request();
          if (permission.isDenied) {
            throw 'Android konum izni reddedildi';
          }
        }

        if (permission.isPermanentlyDenied) {
          throw 'Android konum izni kalıcı olarak reddedildi';
        }
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Konum servisi kapalı. Lütfen GPS\'i açın.';
      }

      // Platform-specific timeouts
      final timeoutDuration = defaultTargetPlatform == TargetPlatform.iOS 
          ? const Duration(seconds: 35) 
          : const Duration(seconds: 40);

      userLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeoutDuration,
      );


      await _getCityName();
      
      setState(() {
        isLoadingLocation = false;
        mapCenter = LatLng(userLocation!.latitude, userLocation!.longitude);
      });
      
      if (isApiKeyConfigured) {
        await _loadAllCityVenues();
      }
        
    } catch (e) {
      
      // iOS için daha detaylı hata mesajı
      String errorMessage = e.toString().toLowerCase();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        if (errorMessage.contains('denied') || errorMessage.contains('permission')) {
          // iOS Settings'e yönlendirme önerisi göster
          _showLocationPermissionDialog();
        } else if (errorMessage.contains('disabled') || errorMessage.contains('location service')) {
          _showLocationServiceDialog();
        }
      }
      
      setState(() {
        hasLocationError = true;
        isLoadingLocation = false;
        currentCity = "İzmir";
        mapCenter = const LatLng(38.4332402, 27.4094315);
      });
      
      if (isApiKeyConfigured && mapCenter != null) {
        await _loadAllCityVenues();
      }
    }
  }

  Future<void> _getCityName() async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        userLocation!.latitude,
        userLocation!.longitude,
      ).timeout(const Duration(seconds: 10));
      
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        String cityName = placemark.locality ?? 
                         placemark.subAdministrativeArea ??
                         placemark.administrativeArea ?? 
                         "";
        
        setState(() {
          currentCity = cityName.isNotEmpty ? cityName : "İzmir";
        });
        
      }
    } catch (e) {
      setState(() {
        currentCity = _detectCityByCoordinates(
          userLocation?.latitude ?? 38.4332402,
          userLocation?.longitude ?? 27.4094315
        );
      });
    }
  }

  String _detectCityByCoordinates(double lat, double lng) {
    if (lat >= 40.8 && lat <= 41.3 && lng >= 28.5 && lng <= 29.5) return "İstanbul";
    if (lat >= 39.7 && lat <= 40.1 && lng >= 32.5 && lng <= 33.1) return "Ankara";
    if (lat >= 38.2 && lat <= 38.6 && lng >= 26.8 && lng <= 27.6) return "İzmir";
    if (lat >= 40.0 && lat <= 40.3 && lng >= 28.8 && lng <= 29.3) return "Bursa";
    if (lat >= 36.7 && lat <= 37.0 && lng >= 30.5 && lng <= 31.0) return "Antalya";
    return "İzmir";
  }

  Future<void> _loadAllCityVenues() async {
    if (!isApiKeyConfigured) return;

    setState(() {
      isLoadingVenues = true;
      allVenues.clear();
    });

    try {
      
      List<String> primaryCategories = [
        'cafe', 
        'bar',
        'night_club',
      ];

      List<String> extendedCategories = [
        'shopping_mall',
        // 'restaurant',
        // 'tourist_attraction',
        // 'museum',
        // 'movie_theater',
        // 'gym',
        // 'park',
        // 'bakery',
        // 'fast_food',
      ];

      List<double> radiusPoints = [
        5000.0,
        10000.0,
        20000.0,
        30000.0,
        50000.0,
      ];

      Set<String> uniquePlaceIds = {};
      List<Map<String, dynamic>> tempVenues = [];

      for (String category in primaryCategories) {
        for (double radius in radiusPoints) {
          
          final venues = await _fetchVenuesByType(
            category, 
            radius: radius,
            maxResults: 20
          );
          
          int addedCount = 0;
          for (var venue in venues) {
            String placeId = venue['place_id'] ?? '';
            if (placeId.isNotEmpty && !uniquePlaceIds.contains(placeId)) {
              uniquePlaceIds.add(placeId);
              tempVenues.add(venue);
              addedCount++;
            }
          }
          
          
          await Future.delayed(const Duration(milliseconds: 200));
          
          final categoryCount = tempVenues.where((v) => v['category'] == _getCategoryDisplayName(category)).length;
          
          if (categoryCount >= maxVenuesPerCategory) {
            break;
          }
        }
      }

      if (tempVenues.length < 200) {
        for (String category in extendedCategories) {
          
          final venues = await _fetchVenuesByType(
            category, 
            radius: 15000.0,
            maxResults: 10
          );
          
          for (var venue in venues) {
            String placeId = venue['place_id'] ?? '';
            if (placeId.isNotEmpty && !uniquePlaceIds.contains(placeId)) {
              uniquePlaceIds.add(placeId);
              tempVenues.add(venue);
            }
          }
          
          await Future.delayed(const Duration(milliseconds: 200));
          
          if (tempVenues.length >= 300) break;
        }
      }

      List<String> popularChains = [
        'Starbucks',
        // 'McDonald\'s',
        // 'Burger King',
        // 'KFC',
        // 'Domino\'s',
        // 'Pizza Hut',
        // 'Subway',
        // 'Popeyes',
      ];

      for (String chain in popularChains) {
        
        final venues = await _searchVenuesByText(
          '$chain $currentCity',
          maxResults: 5
        );
        
        for (var venue in venues) {
          String placeId = venue['place_id'] ?? '';
          if (placeId.isNotEmpty && !uniquePlaceIds.contains(placeId)) {
            uniquePlaceIds.add(placeId);
            tempVenues.add(venue);
          }
        }
        
        await Future.delayed(const Duration(milliseconds: 200));
      }

      setState(() {
        allVenues = tempVenues;
        isLoadingVenues = false;
      });

      _createMapMarkers();
      
      
    } catch (e) {
      setState(() {
        isLoadingVenues = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchVenuesByType(
    String type, {
    double radius = 10000.0,
    int maxResults = 20,
  }) async {
    try {
      
      const String url = 'https://places.googleapis.com/v1/places:searchNearby';
      
      final Map<String, dynamic> requestBody = {
        'includedTypes': [type],
        'maxResultCount': maxResults,
        'locationRestriction': {
          'circle': {
            'center': {
              'latitude': mapCenter?.latitude ?? 38.4332402,
              'longitude': mapCenter?.longitude ?? 27.4094315,
            },
            'radius': radius,
          }
        }
      };

      final apiKey = ApiKeys.googlePlacesApiKey;
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.rating,places.location,places.types',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 15));
      
      
      if (response.statusCode != 200) {
        return []; // Return empty list on error
      }
      
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
            
            return {
              'place_id': placeId,
              'name': displayName,
              'category': _getCategoryDisplayName(type),
              'rating': rating,
              'vicinity': formattedAddress,
              'icon': _getCategoryIcon(type),
              'color': _getCategoryColor(type),
              'latitude': location?['latitude']?.toDouble() ?? mapCenter!.latitude,
              'longitude': location?['longitude']?.toDouble() ?? mapCenter!.longitude,
              'type': type,
            };
          }).toList();
        } else {
        }
      } else {
      }
      
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchVenuesByText(
    String query, {
    int maxResults = 10,
  }) async {
    try {
      
      const String url = 'https://places.googleapis.com/v1/places:searchText';
      
      final Map<String, dynamic> requestBody = {
        'textQuery': query,
        'maxResultCount': maxResults,
        'locationBias': {
          'circle': {
            'center': {
              'latitude': mapCenter?.latitude ?? 38.4332402,
              'longitude': mapCenter?.longitude ?? 27.4094315,
            },
            'radius': 30000.0,
          }
        }
      };

      final apiKey = ApiKeys.googlePlacesApiKey;

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.rating,places.location,places.types',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 15));
      
      
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
            final types = (place['types'] as List?)?.cast<String>() ?? [];
            
            String category = 'Mekan';
            String mainType = 'place';
            
            for (String type in types) {
              if (type.contains('restaurant')) {
                category = 'Restoran';
                mainType = 'restaurant';
                break;
              } else if (type.contains('cafe')) {
                category = 'Kafe';
                mainType = 'cafe';
                break;
              } else if (type.contains('bar')) {
                category = 'Bar';
                mainType = 'bar';
                break;
              } else if (type.contains('night_club')) {
                category = 'Gece Kulübü';
                mainType = 'night_club';
                break;
              } else if (type.contains('shopping')) {
                category = 'AVM';
                mainType = 'shopping_mall';
                break;
              }
            }
            
            return {
              'place_id': placeId,
              'name': displayName,
              'category': category,
              'rating': rating,
              'vicinity': formattedAddress,
              'icon': _getCategoryIcon(mainType),
              'color': _getCategoryColor(mainType),
              'latitude': location?['latitude']?.toDouble() ?? mapCenter!.latitude,
              'longitude': location?['longitude']?.toDouble() ?? mapCenter!.longitude,
              'type': mainType,
            };
          }).toList();
        } else {
        }
      } else {
      }
      
      return [];
    } catch (e) {
      return [];
    }
  }

  void _createMapMarkers() {
    setState(() {
      mapMarkers.clear();
      
      final displayVenues = searchResults.isNotEmpty ? searchResults : allVenues;
      
      
      int maxMarkersToShow = _getMaxMarkersForZoom(currentZoom);
      List<Map<String, dynamic>> venuesToShow = displayVenues.take(maxMarkersToShow).toList();
      
      for (var venue in venuesToShow) {
        final isSelected = selectedVenueDetails.any((v) => v['place_id'] == venue['place_id']);
        
        mapMarkers.add(
          Marker(
            markerId: MarkerId(venue['place_id'] ?? 'venue_${venue['name']}'),
            position: LatLng(venue['latitude'], venue['longitude']),
            onTap: () => _toggleVenue(venue),
            icon: isSelected 
                ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
                : _getMarkerIconForCategory(venue['type'] ?? venue['category']),
            infoWindow: InfoWindow(
              title: venue['name'],
              snippet: '${venue['category']} • ${venue['rating']?.toStringAsFixed(1) ?? "N/A"} ⭐\n${isSelected ? "Kaldırmak" : "Seçmek"} için tıkla',
              onTap: () => _toggleVenue(venue),
            ),
          ),
        );
      }
      
    });
  }

  int _getMaxMarkersForZoom(double zoom) {
    if (zoom < 10) return 30;
    if (zoom < 11) return 50;
    if (zoom < 12) return 100;
    if (zoom < 13) return 150;
    if (zoom < 14) return 200;
    if (zoom < 15) return 300;
    return 500;
  }

  BitmapDescriptor _getMarkerIconForCategory(String type) {
    switch (type.toLowerCase()) {
      case 'restaurant':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case 'cafe':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      case 'bar':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta);
      case 'night_club':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      case 'shopping_mall':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
  }

  String _getCategoryDisplayName(String type) {
    switch (type) {
      case 'restaurant': return 'Restoran';
      case 'cafe': return 'Kafe';
      case 'bar': return 'Bar';
      case 'night_club': return 'Gece Kulübü';
      case 'shopping_mall': return 'AVM';
      case 'park': return 'Park';
      case 'tourist_attraction': return 'Turistik';
      case 'gym': return 'Spor Salonu';
      case 'movie_theater': return 'Sinema';
      case 'museum': return 'Müze';
      case 'bakery': return 'Fırın';
      case 'fast_food': return 'Fast Food';
      default: return 'Mekan';
    }
  }

  IconData _getCategoryIcon(String type) {
    switch (type) {
      case 'restaurant': return Icons.restaurant;
      case 'cafe': return Icons.local_cafe;
      case 'bar': return Icons.local_bar;
      case 'night_club': return Icons.nightlife;
      case 'shopping_mall': return Icons.local_mall;
      case 'park': return Icons.park;
      case 'tourist_attraction': return Icons.place;
      case 'gym': return Icons.fitness_center;
      case 'movie_theater': return Icons.movie;
      case 'museum': return Icons.museum;
      case 'bakery': return Icons.bakery_dining;
      case 'fast_food': return Icons.fastfood;
      default: return Icons.place;
    }
  }

  Color _getCategoryColor(String type) {
    switch (type) {
      case 'restaurant': return AppColors.warning;
      case 'cafe': return AppColors.grey700;
      case 'bar': return AppColors.primary;
      case 'night_club': return AppColors.primaryDark;
      case 'shopping_mall': return AppColors.error;
      case 'park': return AppColors.success;
      case 'tourist_attraction': return AppColors.superLike;
      case 'gym': return AppColors.accent;
      case 'movie_theater': return AppColors.secondary;
      case 'museum': return AppColors.premium;
      case 'bakery': return AppColors.warning;
      case 'fast_food': return AppColors.error;
      default: return AppColors.grey500;
    }
  }

  void _toggleVenue(Map<String, dynamic> venue) {
    final venueName = venue['name'];
    final venueId = venue['place_id'] ?? '';
    
    setState(() {
      final isAlreadySelected = selectedVenueDetails.any((v) => v['place_id'] == venueId);
      
      if (isAlreadySelected) {
        selectedVenues.remove(venueName);
        selectedVenueIds.remove(venueName);
        selectedVenueDetails.removeWhere((v) => v['place_id'] == venueId);
      } else {
        if (selectedVenues.length < maxVenues) {
          selectedVenues.add(venueName);
          selectedVenueIds[venueName] = venueId;
          selectedVenueDetails.add(venue);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('En fazla $maxVenues mekan seçebilirsiniz'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }
    });
    
    _createMapMarkers();
  }

  Future<void> _searchVenues(String query) async {
    if (query.trim().isEmpty || !isApiKeyConfigured) return;
    
    setState(() {
      isSearching = true;
      searchResults.clear();
    });

    try {
      final results = await _searchVenuesByText('$query $currentCity', maxResults: 20);
      
      setState(() {
        searchResults = results;
        isSearching = false;
      });
      
      if (showMapMode && searchResults.isNotEmpty) {
        _createMapMarkers();
      }
      
      
    } catch (e) {
      setState(() {
        isSearching = false;
      });
    }
  }

  Widget _buildGoogleMap({bool isFullScreen = false}) {
    if (mapCenter == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.white),
      );
    }

    return GoogleMap(
      onMapCreated: (GoogleMapController controller) {
        if (!_mapController.isCompleted) {
          _mapController.complete(controller);
        }
        Future.delayed(const Duration(milliseconds: 500), () {
          _fitMapToMarkers();
        });
      },
      initialCameraPosition: CameraPosition(
        target: mapCenter!,
        zoom: currentZoom,
      ),
      markers: mapMarkers,
      myLocationEnabled: true,
      myLocationButtonEnabled: isFullScreen,
      zoomControlsEnabled: isFullScreen,
      mapToolbarEnabled: false,
      compassEnabled: true,
      onCameraMove: (CameraPosition position) {
        if ((position.zoom - currentZoom).abs() > 0.5) {
          currentZoom = position.zoom;
          _createMapMarkers();
        }
      },
      onTap: isFullScreen ? null : (LatLng position) {
        setState(() {
          isFullScreenMap = true;
        });
      },
    );
  }

  void _fitMapToMarkers() async {
    if (mapMarkers.isEmpty || !_mapController.isCompleted) return;
    
    try {
      final GoogleMapController controller = await _mapController.future;
      
      if (mapMarkers.length == 1) {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: mapMarkers.first.position,
              zoom: 15.0,
            ),
          ),
        );
      } else if (mapMarkers.length > 1) {
        double minLat = mapMarkers.map((m) => m.position.latitude).reduce(min);
        double maxLat = mapMarkers.map((m) => m.position.latitude).reduce(max);
        double minLng = mapMarkers.map((m) => m.position.longitude).reduce(min);
        double maxLng = mapMarkers.map((m) => m.position.longitude).reduce(max);
        
        controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            100.0,
          ),
        );
      }
    } catch (e) {
    }
  }

  void _handleNext() {
    if (selectedVenues.length < minVenues) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('En az $minVenues favori mekan seçmelisiniz'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Provider'a favori mekanları kaydet
    ref.read(userProfileProvider.notifier).updateFavoriteVenues(selectedVenues);
    ref.read(userProfileProvider.notifier).updateFavoriteVenueDetails(selectedVenueDetails);
    
    // Favori mekanları check-in olarak da kaydet
    ref.read(userProfileProvider.notifier).saveFavoriteVenuesWithCheckIn(selectedVenueDetails);
    
    final profile = ref.read(userProfileProvider);
    for (var venue in selectedVenueDetails) {
    }
    
    ref.read(userProfileProvider.notifier).printAllInfo();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Favori mekanlar kaydedildi ve check-in\'ler oluşturuldu! 📍'),
        backgroundColor: AppColors.success,
      ),
    );

    // Navigate to Step 5 - Email Verification
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileSetupStep5Page(),
      ),
    );

  }

  Widget _buildVenueCard(Map<String, dynamic> venue) {
    final isSelected = selectedVenueDetails.any((v) => v['place_id'] == venue['place_id']);
    
    return GestureDetector(
      onTap: () => _toggleVenue(venue),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? venue['color'].withOpacity(0.2)
              : AppColors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
                ? venue['color'] 
                : AppColors.white.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected 
                    ? venue['color'].withOpacity(0.3)
                    : AppColors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                venue['icon'],
                color: isSelected ? venue['color'] : AppColors.white.withOpacity(0.8),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venue['name'],
                    style: TextStyle(
                      color: isSelected ? AppColors.white : AppColors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: venue['color'].withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          venue['category'],
                          style: TextStyle(
                            color: venue['color'],
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (venue['rating'] != null && venue['rating'] > 0) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.star,
                          color: AppColors.premium,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          venue['rating'].toStringAsFixed(1),
                          style: TextStyle(
                            color: AppColors.white.withOpacity(0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: venue['color'],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppColors.white,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.location_off,
            size: 80,
            color: AppColors.grey400,
          ),
          const SizedBox(height: 24),
          const Text(
            'Veri Alınamadı',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasLocationError 
                ? 'Lütfen konum servisini açın'
                : 'Lütfen internet bağlantınızı kontrol edin',
            style: TextStyle(
              color: AppColors.white.withOpacity(0.8),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _initializeLocationAndVenues,
            icon: const Icon(Icons.refresh),
            label: const Text('Yeniden Dene'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isFullScreenMap) {
      return Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Stack(
            children: [
              _buildGoogleMap(isFullScreen: true),
              Positioned(
                top: 16,
                left: 16,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: AppColors.white,
                  onPressed: () => setState(() => isFullScreenMap = false),
                  child: const Icon(Icons.close, color: AppColors.primary),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selectedVenues.length >= minVenues ? AppColors.success : AppColors.warning,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${selectedVenues.length}/$maxVenues seçildi',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryRegisterGradient,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Progress indicator
                  Row(
                    children: List.generate(7, (index) {
                      final isCompleted = index < 4;
                      return Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isCompleted ? AppColors.white : AppColors.white.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (index < 6)
                              Expanded(
                                child: Container(
                                  height: 2,
                                  color: isCompleted ? AppColors.white : AppColors.white.withOpacity(0.3),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  const Text(
                    'Favori Mekanların',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    '4/7 - En az $minVenues, en fazla $maxVenues mekan seç',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.white.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Status info
                  if (!hasLocationError && (isApiKeyConfigured || allVenues.isNotEmpty)) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: AppColors.success,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$currentCity (${allVenues.length} mekan)',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Mode toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => showMapMode = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: !showMapMode ? AppColors.white : AppColors.transparent,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.list,
                                      color: !showMapMode ? AppColors.primary : AppColors.white.withOpacity(0.7),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Liste',
                                      style: TextStyle(
                                        color: !showMapMode ? AppColors.primary : AppColors.white.withOpacity(0.7),
                                        fontWeight: !showMapMode ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => showMapMode = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: showMapMode ? AppColors.white : AppColors.transparent,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.map,
                                      color: showMapMode ? AppColors.primary : AppColors.white.withOpacity(0.7),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Harita',
                                      style: TextStyle(
                                        color: showMapMode ? AppColors.primary : AppColors.white.withOpacity(0.7),
                                        fontWeight: showMapMode ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Venue counter
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.favorite, color: AppColors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedVenues.length} / $maxVenues seçildi',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                  ],
                  
                  // Content area
                  if (hasLocationError || (!isApiKeyConfigured && allVenues.isEmpty)) ...[
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: _buildErrorState(),
                    ),
                  ] else if (isLoadingVenues) ...[
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Mekanlar yükleniyor...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (allVenues.isEmpty) ...[
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: _buildErrorState(),
                    ),
                  ] else ...[
                    if (showMapMode) ...[
                      // Map view
                      GestureDetector(
                        onTap: () => setState(() => isFullScreenMap = true),
                        child: Container(
                          height: 500,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _buildGoogleMap(),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: FloatingActionButton(
                                  mini: true,
                                  backgroundColor: Colors.white,
                                  onPressed: () => setState(() => isFullScreenMap = true),
                                  child: const Icon(Icons.fullscreen, color: Color(0xFF6B46C1)),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${mapMarkers.length} mekan gösteriliyor',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // List view with search
                      if (isApiKeyConfigured) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _searchController,
                            scrollPadding: const EdgeInsets.only(bottom: 100),
                            onChanged: (value) {
                              if (value.length >= 2) {
                                _searchVenues(value);
                              } else {
                                setState(() {
                                  searchResults.clear();
                                });
                              }
                            },
                            style: const TextStyle(color: AppColors.textOnDark),
                            decoration: InputDecoration(
                              hintText: 'Mekan ara...',
                              hintStyle: const TextStyle(color: AppColors.textOnDark),
                              prefixIcon: Icon(Icons.search, color: AppColors.textOnDark.withOpacity(0.8)),
                              suffixIcon: isSearching 
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : _searchController.text.isNotEmpty
                                      ? IconButton(
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              searchResults.clear();
                                            });
                                          },
                                          icon: const Icon(Icons.clear, color: Colors.white),
                                        )
                                      : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Venue list
                      if (searchResults.isNotEmpty) ...[
                        Text(
                          'Arama Sonuçları (${searchResults.length}):',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...searchResults.map((venue) => _buildVenueCard(venue)),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 16),
                      ],
                      
                      // Category sections
                      if (searchResults.isEmpty) ...[
                        _buildCategorySection('Restoranlar', 'restaurant'),
                        const SizedBox(height: 24),
                        _buildCategorySection('Kafeler', 'cafe'),
                        const SizedBox(height: 24),
                        _buildCategorySection('Barlar', 'bar'),
                        const SizedBox(height: 24),
                        _buildCategorySection('Gece Kulüpleri', 'night_club'),
                      ],
                    ],
                  ],
                  
                  const SizedBox(height: 32),
                  
                  // Bottom buttons - NOT fixed, scrollable
                  ElevatedButton(
                    onPressed: selectedVenues.length >= minVenues ? _handleNext : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedVenues.length >= minVenues 
                          ? Colors.white 
                          : Colors.grey[400],
                      foregroundColor: selectedVenues.length >= minVenues 
                          ? const Color(0xFF6B46C1) 
                          : Colors.grey[600],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          selectedVenues.length >= minVenues 
                              ? 'İleri' 
                              : 'En az $minVenues mekan seç',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (selectedVenues.length >= minVenues) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Geri',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySection(String title, String type) {
    final categoryVenues = allVenues.where((v) => v['type'] == type).toList();
    
    if (categoryVenues.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title (${categoryVenues.length})',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...categoryVenues.take(5).map((venue) => _buildVenueCard(venue)),
        if (categoryVenues.length > 5)
          TextButton(
            onPressed: () {
              setState(() {
                searchResults = categoryVenues;
              });
            },
            child: Text(
              'Tümünü Göster (${categoryVenues.length - 5} daha)',
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    );
  }

  // iOS için konum izni dialog'u
  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Konum İzni Gerekli'),
          content: const Text(
            'Venue önerilerini gösterebilmek için konum izni vermelisiniz. '
            'Ayarlar > Gizlilik ve Güvenlik > Konum Hizmetleri\'nden uygulamaya izin verebilirsiniz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // iOS ayarlara yönlendirme
                await openAppSettings();
              },
              child: const Text('Ayarlara Git'),
            ),
          ],
        );
      },
    );
  }

  // iOS için GPS servisi dialog'u
  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('GPS Servisi Gerekli'),
          content: const Text(
            'Konumunuzu alabilmek için GPS servisini açmanız gerekiyor. '
            'Ayarlar > Gizlilik ve Güvenlik > Konum Hizmetleri\'nden açabilirsiniz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }
}