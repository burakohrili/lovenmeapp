// Venue model - Bu zaten ayrı bir dosya olmalı
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/models/checkedin_user.dart';

class Venue {
  final String id;
  final String placeId;
  final String name;
  final String category;
  final LatLng location;
  final double rating;
  final String vicinity;
  bool isFavorite;
  final String? mayorUserId;
  final String? mayorName;
  final String? mayorPhoto;
  final int mayorCheckIns;
  final int mayorDiamonds;
  final List<CheckedInUser> checkedInUsers;
  final int totalCheckIns;
  final String? logoUrl;
  final String? closingTime;
  final String? openingTime;
  final List<String> photos;
  
  // 💎 SPONSOR FIELDS
  final bool isSponsored;
  final String? sponsorLogoUrl;
  final String? sponsorBadgeText;
  final int sponsorPriority;
  final DateTime? sponsorStartDate;
  final DateTime? sponsorEndDate;

  Venue({
    required this.id,
    required this.placeId,
    required this.name,
    required this.category,
    required this.location,
    this.rating = 0.0,
    this.vicinity = '',
    this.isFavorite = false,
    this.mayorUserId,
    this.mayorName,
    this.mayorPhoto,
    this.mayorCheckIns = 0,
    this.mayorDiamonds = 0,
    this.checkedInUsers = const [],
    this.totalCheckIns = 0,
    this.logoUrl,
    this.closingTime,
    this.openingTime,
    this.photos = const [],
    this.isSponsored = false,
    this.sponsorLogoUrl,
    this.sponsorBadgeText,
    this.sponsorPriority = 0,
    this.sponsorStartDate,
    this.sponsorEndDate,
  });

  factory Venue.fromPlaceData(
    Map<String, dynamic> data, {
    bool isFavorite = false,
  }) {
    // Extract location coordinates - check both flat and nested structure
    double latitude = 0.0;
    double longitude = 0.0;
    
    // First try flat structure (from VenueService)
    if (data['latitude'] != null && data['longitude'] != null) {
      latitude = (data['latitude'] as num).toDouble();
      longitude = (data['longitude'] as num).toDouble();
    } else {
      // Fallback to nested structure
      final locationData = data['location'] ?? {};
      latitude = (locationData['latitude'] ?? 0.0) as double;
      longitude = (locationData['longitude'] ?? 0.0) as double;
    }
    
    // Extract display name from formattedAddress or name
    String displayName = data['name'] ?? 'Unknown';
    if (displayName.startsWith('places/')) {
      // Extract name from formattedAddress if available
      final formattedAddress = data['formattedAddress'] ?? '';
      if (formattedAddress.isNotEmpty) {
        // Try to extract business name from address
        displayName = _extractNameFromAddress(formattedAddress);
      } else {
        displayName = 'Mekan';
      }
    }
    
    return Venue(
      id: data['id'] ?? data['place_id'] ?? '',
      placeId: data['id'] ?? data['place_id'] ?? '',
      name: displayName,
      category: data['category'] ?? _inferCategoryFromTypes(data['types']),
      location: LatLng(latitude, longitude),
      rating: (data['rating'] ?? 0.0).toDouble(),
      vicinity: data['vicinity'] ?? '',
      isFavorite: isFavorite,
      mayorDiamonds: data['mayorDiamonds'] ?? 0,
      mayorPhoto: data['mayorPhoto'],
      logoUrl: data['logoUrl'],
      closingTime: data['closingTime'],
      openingTime: data['openingTime'],
      photos: data['photos'] != null && data['photos'] is List
          ? List<String>.from(data['photos'])
          : [],
      // 💎 SPONSOR FIELDS
      isSponsored: data['isSponsored'] ?? false,
      sponsorLogoUrl: data['sponsorLogoUrl'],
      sponsorBadgeText: data['sponsorBadgeText'],
      sponsorPriority: data['sponsorPriority'] ?? 0,
      sponsorStartDate: data['sponsorStartDate'] != null 
          ? DateTime.tryParse(data['sponsorStartDate'].toString()) 
          : null,
      sponsorEndDate: data['sponsorEndDate'] != null 
          ? DateTime.tryParse(data['sponsorEndDate'].toString()) 
          : null,
    );
  }

  factory Venue.fromGooglePlaces(Map<String, dynamic> googlePlace, String category) {
    // New Places API format - direct location coordinates
    final location = googlePlace['location'] ?? googlePlace['geometry']?['location'];
    
    // Extract photos from Google Places API
    List<String> photoUrls = [];
    if (googlePlace['photos'] != null && googlePlace['photos'] is List) {
      final photos = googlePlace['photos'] as List;
      // Google Places API returns photo references, we need to convert them to URLs
      // This will be handled in the service layer
      photoUrls = photos.map((photo) => photo['name'] as String? ?? '').where((url) => url.isNotEmpty).toList();
    }
    
    return Venue(
      id: googlePlace['place_id'] ?? googlePlace['id'] ?? '',
      placeId: googlePlace['place_id'] ?? googlePlace['id'] ?? '',
      name: googlePlace['name'] ?? googlePlace['displayName']?['text'] ?? 'Unknown',
      category: _mapGooglePlaceType(googlePlace['types'], category),
      location: LatLng(
        // New API uses 'latitude' and 'longitude', old API uses 'lat' and 'lng'
        location?['latitude']?.toDouble() ?? location?['lat']?.toDouble() ?? 0.0,
        location?['longitude']?.toDouble() ?? location?['lng']?.toDouble() ?? 0.0,
      ),
      rating: (googlePlace['rating'] ?? 0.0).toDouble(),
      vicinity: googlePlace['vicinity'] ?? googlePlace['formattedAddress'] ?? '',
      photos: photoUrls,
      // 💎 SPONSOR FIELDS - Default values for Google Places data
      isSponsored: false,
      sponsorLogoUrl: null,
      sponsorBadgeText: null,
      sponsorPriority: 0,
      sponsorStartDate: null,
      sponsorEndDate: null,
    );
  }

  static String _mapGooglePlaceType(List<dynamic>? types, String fallbackCategory) {
    if (types == null || types.isEmpty) return fallbackCategory;
    
    // Google Places API tip eşlemesi
    final typeMap = {
      'restaurant': 'Restoran',
      'cafe': 'Kafe',
      'bar': 'Bar',
      'night_club': 'Gece Kulübü',
      'shopping_mall': 'Alışveriş Merkezi',
      'movie_theater': 'Sinema',
      'gym': 'Spor Salonu',
      'hospital': 'Hastane',
      'pharmacy': 'Eczane',
      'gas_station': 'Benzin İstasyonu',
      'lodging': 'Konaklama',
      'tourist_attraction': 'Turistik Mekan',
    };
    
    for (final type in types) {
      if (typeMap.containsKey(type)) {
        return typeMap[type]!;
      }
    }
    
    return fallbackCategory;
  }

  Venue copyWith({
    String? id,
    String? placeId,
    String? name,
    String? category,
    LatLng? location,
    double? rating,
    String? vicinity,
    bool? isFavorite,
    String? mayorUserId,
    String? mayorName,
    String? mayorPhoto,
    int? mayorCheckIns,
    int? mayorDiamonds,
    List<CheckedInUser>? checkedInUsers,
    int? totalCheckIns,
    String? logoUrl,
    String? closingTime,
    String? openingTime,
    List<String>? photos,
    // Sponsor fields
    bool? isSponsored,
    String? sponsorLogoUrl,
    String? sponsorBadgeText,
    int? sponsorPriority,
    DateTime? sponsorStartDate,
    DateTime? sponsorEndDate,
  }) {
    return Venue(
      id: id ?? this.id,
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      category: category ?? this.category,
      location: location ?? this.location,
      rating: rating ?? this.rating,
      vicinity: vicinity ?? this.vicinity,
      isFavorite: isFavorite ?? this.isFavorite,
      mayorUserId: mayorUserId ?? this.mayorUserId,
      mayorName: mayorName ?? this.mayorName,
      mayorPhoto: mayorPhoto ?? this.mayorPhoto,
      mayorCheckIns: mayorCheckIns ?? this.mayorCheckIns,
      mayorDiamonds: mayorDiamonds ?? this.mayorDiamonds,
      checkedInUsers: checkedInUsers ?? this.checkedInUsers,
      totalCheckIns: totalCheckIns ?? this.totalCheckIns,
      logoUrl: logoUrl ?? this.logoUrl,
      closingTime: closingTime ?? this.closingTime,
      openingTime: openingTime ?? this.openingTime,
      photos: photos ?? this.photos,
      // Sponsor fields
      isSponsored: isSponsored ?? this.isSponsored,
      sponsorLogoUrl: sponsorLogoUrl ?? this.sponsorLogoUrl,
      sponsorBadgeText: sponsorBadgeText ?? this.sponsorBadgeText,
      sponsorPriority: sponsorPriority ?? this.sponsorPriority,
      sponsorStartDate: sponsorStartDate ?? this.sponsorStartDate,
      sponsorEndDate: sponsorEndDate ?? this.sponsorEndDate,
    );
  }

  /// Extract business name from Google Places formattedAddress
  static String _extractNameFromAddress(String formattedAddress) {
    // Try to get the first part before comma which usually contains the business name
    final parts = formattedAddress.split(',');
    if (parts.isNotEmpty) {
      String firstPart = parts.first.trim();
      
      // Remove common address prefixes
      firstPart = firstPart.replaceAll(RegExp(r'^No:\s*\d+[A-Za-z]*\s*'), '');
      firstPart = firstPart.replaceAll(RegExp(r'^\d+[A-Za-z]*\s+'), '');
      
      if (firstPart.isNotEmpty && firstPart.length > 3) {
        return firstPart;
      }
    }
    
    return 'Mekan';
  }

  /// Infer category from Google Places types array
  static String _inferCategoryFromTypes(List<dynamic>? types) {
    if (types == null || types.isEmpty) return 'venue';
    
    // Convert to lowercase strings for comparison
    final typeStrings = types.map((e) => e.toString().toLowerCase()).toList();
    
    // Priority-based category mapping
    if (typeStrings.any((t) => ['restaurant', 'food', 'meal_takeaway'].contains(t))) {
      return 'restaurant';
    }
    if (typeStrings.any((t) => ['cafe', 'coffee_shop'].contains(t))) {
      return 'cafe';
    }
    if (typeStrings.any((t) => ['bar', 'night_club', 'bar_and_grill'].contains(t))) {
      return 'bar';
    }
    if (typeStrings.any((t) => ['gym', 'fitness', 'sports_activity_location'].contains(t))) {
      return 'gym';
    }
    if (typeStrings.any((t) => ['shopping_mall', 'store'].contains(t))) {
      return 'shopping';
    }
    
    return 'venue';
  }

  // JSON serialization for caching
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'placeId': placeId,
      'name': name,
      'category': category,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'rating': rating,
      'vicinity': vicinity,
      'isFavorite': isFavorite,
      'mayorUserId': mayorUserId,
      'mayorName': mayorName,
      'mayorPhoto': mayorPhoto,
      'mayorCheckIns': mayorCheckIns,
      'mayorDiamonds': mayorDiamonds,
      'totalCheckIns': totalCheckIns,
      'logoUrl': logoUrl,
      'closingTime': closingTime,
      'openingTime': openingTime,
      'photos': photos,
      'checkedInUsers': checkedInUsers.map((user) => user.toJson()).toList(),
    };
  }

  factory Venue.fromJson(Map<String, dynamic> json) {
    return Venue(
      id: json['id'] ?? '',
      placeId: json['placeId'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      location: LatLng(
        json['latitude']?.toDouble() ?? 0.0,
        json['longitude']?.toDouble() ?? 0.0,
      ),
      rating: json['rating']?.toDouble() ?? 0.0,
      vicinity: json['vicinity'] ?? '',
      isFavorite: json['isFavorite'] ?? false,
      mayorUserId: json['mayorUserId'],
      mayorName: json['mayorName'],
      mayorPhoto: json['mayorPhoto'],
      mayorCheckIns: json['mayorCheckIns'] ?? 0,
      mayorDiamonds: json['mayorDiamonds'] ?? 0,
      totalCheckIns: json['totalCheckIns'] ?? 0,
      logoUrl: json['logoUrl'],
      closingTime: json['closingTime'],
      openingTime: json['openingTime'],
      photos: List<String>.from(json['photos'] ?? []),
      checkedInUsers: (json['checkedInUsers'] as List<dynamic>?)
          ?.map((user) => CheckedInUser.fromJson(user))
          .toList() ?? [],
    );
  }
}
