import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CheckedInUser {
  final String id;
  final String name;
  final String? photoUrl;
  final DateTime checkInTime;
  final bool isPremium;
  final int totalCheckIns;
  final bool mapVisibility;

  CheckedInUser({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.checkInTime,
    this.isPremium = false,
    this.totalCheckIns = 1,
    this.mapVisibility = true,
  });

  factory CheckedInUser.fromFirestore(Map<String, dynamic> data,
      {bool mapVisibility = true}) {
    DateTime checkInTime;
    try {
      if (data['checkInTime'] != null && data['checkInTime'] is Timestamp) {
        checkInTime = (data['checkInTime'] as Timestamp).toDate();
      } else {
        checkInTime = DateTime.now();
      }
    } catch (e) {
      checkInTime = DateTime.now();
    }

    String userName = 'İsimsiz';
    if (data['userName'] != null && data['userName'].toString().isNotEmpty) {
      userName = data['userName'];
    } else if (data['name'] != null && data['name'].toString().isNotEmpty) {
      userName = data['name'];
    }

    return CheckedInUser(
      id: data['userId'] ?? '',
      name: userName,
      photoUrl: data['userPhoto'] ?? data['profilePhoto'],
      checkInTime: checkInTime,
      isPremium: data['isPremium'] ?? false,
      totalCheckIns: data['totalCheckIns'] ?? 1,
      mapVisibility: mapVisibility,
    );
  }
}

class Venue {
  final String id;
  final String placeId;
  final String name;
  final String category;
  final LatLng location;
  final double rating;
  final String vicinity;
  final bool isFavorite;
  final bool isSponsored; // 💎 SPONSOR FEATURE
  final String? sponsorLogoUrl; // 💎 SPONSOR LOGO
  final String? sponsorBadgeText; // 💎 SPONSOR BADGE
  final int sponsorPriority; // 💎 SPONSOR PRIORITY (1-10)
  final DateTime? sponsorStartDate; // 💎 SPONSOR START
  final DateTime? sponsorEndDate; // 💎 SPONSOR END
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
  final Map<String, dynamic>? photos;

  Venue({
    required this.id,
    required this.placeId,
    required this.name,
    required this.category,
    required this.location,
    this.rating = 0.0,
    this.vicinity = '',
    this.isFavorite = false,
    this.isSponsored = false, // 💎 SPONSOR DEFAULT
    this.sponsorLogoUrl,
    this.sponsorBadgeText,
    this.sponsorPriority = 0,
    this.sponsorStartDate,
    this.sponsorEndDate,
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
    this.photos,
  });

  factory Venue.fromPlaceData(
    Map<String, dynamic> data, {
    bool isFavorite = false,
    bool isSponsored = false, // 💎 SPONSOR PARAMETER
    String? sponsorLogoUrl,
    String? sponsorBadgeText,
    int sponsorPriority = 0,
    DateTime? sponsorStartDate,
    DateTime? sponsorEndDate,
  }) {
    // Handle closing time - if null, keep as null (24/7 venues), otherwise use provided or default
    final String? closingTime = data['closingTime'];
    final String? openingTime = data['openingTime'];
    
    
    return Venue(
      id: data['place_id'] ?? '',
      placeId: data['place_id'] ?? '',
      name: data['name'] ?? 'Unknown',
      category: data['category'] ?? 'Mekan',
      location: LatLng(
        data['latitude'] ?? 0.0,
        data['longitude'] ?? 0.0,
      ),
      rating: (data['rating'] ?? 0.0).toDouble(),
      vicinity: data['vicinity'] ?? '',
      isFavorite: isFavorite,
      isSponsored: isSponsored, // 💎 SPONSOR ASSIGNMENT
      sponsorLogoUrl: sponsorLogoUrl,
      sponsorBadgeText: sponsorBadgeText,
      sponsorPriority: sponsorPriority,
      sponsorStartDate: sponsorStartDate,
      sponsorEndDate: sponsorEndDate,
      mayorDiamonds: data['mayorDiamonds'] ?? 0,
      mayorPhoto: data['mayorPhoto'],
      logoUrl: data['logoUrl'],
      closingTime: closingTime, // Use null for 24/7 venues, provided value otherwise
      openingTime: openingTime,
    );
  }

  // Google Places API verisi için factory metod
  factory Venue.fromGooglePlaces(Map<String, dynamic> data) {
    // Konum bilgisini al - VenueService'den gelen yapıya uygun
    final lat = data['latitude']?.toDouble() ?? 0.0;
    final lng = data['longitude']?.toDouble() ?? 0.0;

    // Debug: Koordinatları kontrol et
    if (kDebugMode) {
    }

    // Kategoriyi belirle (types listesinden ilkini al)
    String category = 'Mekan';
    final types = data['types'] as List<dynamic>?;
    if (types != null && types.isNotEmpty) {
      final type = types.first.toString();
      category = _mapGooglePlaceType(type);
    }

    return Venue(
      id: data['id'] ?? '',
      placeId: data['id'] ?? '',
      name: data['displayName']?['text'] ?? data['formattedAddress'] ?? 'Unknown',
      category: category,
      location: LatLng(lat, lng),
      rating: (data['rating']?.toDouble() ?? 0.0),
      vicinity: data['formattedAddress'] ?? '',
    );
  }

  // Google Places tiplerini Türkçe kategorilere çevir
  static String _mapGooglePlaceType(String type) {
    switch (type.toLowerCase()) {
      case 'restaurant':
      case 'food':
      case 'meal_takeaway':
        return 'Restoran';
      case 'cafe':
      case 'coffee_shop':
        return 'Kafe';
      case 'bar':
      case 'night_club':
        return 'Bar';
      case 'movie_theater':
        return 'Sinema';
      case 'shopping_mall':
      case 'store':
        return 'AVM';
      case 'gym':
      case 'fitness':
        return 'Spor Salonu';
      case 'hospital':
        return 'Hastane';
      case 'school':
      case 'university':
        return 'Okul';
      default:
        return 'Mekan';
    }
  }

  factory Venue.fromJson(Map<String, dynamic> json) {
    return Venue(
      id: json['place_id'] ?? '',
      placeId: json['place_id'] ?? '',
      name: json['name'] ?? 'Unknown',
      category: _getCategoryFromTypes(json['types']),
      location: LatLng(
        json['geometry']['location']['lat']?.toDouble() ?? 0.0,
        json['geometry']['location']['lng']?.toDouble() ?? 0.0,
      ),
      rating: json['rating']?.toDouble() ?? 0.0,
      vicinity: json['vicinity'] ?? json['formatted_address'] ?? '',
    );
  }

  static String _getCategoryFromTypes(List<dynamic>? types) {
    if (types == null || types.isEmpty) return 'Mekan';
    
    const categoryMap = {
      'restaurant': 'Restoran',
      'cafe': 'Kafe',
      'bar': 'Bar',
      'night_club': 'Gece Kulübü',
      'gym': 'Spor Salonu',
      'shopping_mall': 'AVM',
      'movie_theater': 'Sinema',
      'park': 'Park',
      'hospital': 'Hastane',
      'school': 'Okul',
      'gas_station': 'Benzin İstasyonu',
      'bank': 'Banka',
      'pharmacy': 'Eczane',
    };

    for (final type in types) {
      if (categoryMap.containsKey(type)) {
        return categoryMap[type]!;
      }
    }
    
    return 'Mekan';
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
    Map<String, dynamic>? photos,
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
    );
  }
}
