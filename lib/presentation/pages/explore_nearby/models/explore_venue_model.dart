// lib/presentation/pages/explore_nearby/models/explore_venue_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Explore Nearby sayfası için mekan modeli
class ExploreVenue {
  final String id;
  final String name;
  final String category;
  final String? description;
  final String? photoUrl;
  final double? rating;
  final String? vicinity;
  
  // Check-in bilgileri
  final int totalCheckIns;
  final List<CheckedInUserPreview> recentUsers; // Son 3-5 kişi
  
  // Muhtar bilgileri
  final String? mayorUserId;
  final String? mayorName;
  final String? mayorPhotoUrl;
  final int mayorCheckIns;
  final bool isUserMayor; // Kullanıcı bu mekanda muhtar mı?
  
  // Sponsor bilgileri
  final bool isSponsored;
  final String? sponsorBadgeText;
  final int sponsorPriority;
  
  // Favori bilgisi
  final bool isFavorite; // Kayıt sırasında seçilen favori mekanlar
  
  // Tarih bilgisi
  final DateTime? lastCheckInDate;
  final DateTime lastCheckInTime; // Service'den gelecek
  
  // Konum bilgileri
  final double? latitude;
  final double? longitude;

  ExploreVenue({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    this.photoUrl,
    this.rating,
    this.vicinity,
    this.totalCheckIns = 0,
    this.recentUsers = const [],
    this.mayorUserId,
    this.mayorName,
    this.mayorPhotoUrl,
    this.mayorCheckIns = 0,
    this.isUserMayor = false,
    this.isSponsored = false,
    this.sponsorBadgeText,
    this.sponsorPriority = 0,
    this.isFavorite = false,
    this.lastCheckInDate,
    required this.lastCheckInTime,
    this.latitude,
    this.longitude,
  });

  factory ExploreVenue.fromFirestore(
    String venueId,
    Map<String, dynamic> venueData,
    List<CheckedInUserPreview> recentUsers,
    Map<String, dynamic>? mayorData,
  ) {
    return ExploreVenue(
      id: venueId,
      name: venueData['name'] ?? 'Unknown Venue',
      category: venueData['category'] ?? 'Other',
      description: venueData['description'],
      photoUrl: venueData['photoUrl'] ?? venueData['photos']?[0],
      rating: venueData['rating']?.toDouble(),
      vicinity: venueData['vicinity'] ?? venueData['formattedAddress'],
      totalCheckIns: venueData['totalCheckIns'] ?? 0,
      recentUsers: recentUsers,
      mayorUserId: mayorData?['currentMayorId'],
      mayorName: mayorData?['mayorName'],
      mayorPhotoUrl: mayorData?['mayorPhoto'],
      mayorCheckIns: mayorData?['checkInCount'] ?? 0,
      isSponsored: venueData['isSponsored'] ?? false,
      sponsorBadgeText: venueData['sponsorBadgeText'],
      sponsorPriority: venueData['sponsorPriority'] ?? 0,
      lastCheckInDate: venueData['lastCheckInDate'] != null
          ? (venueData['lastCheckInDate'] as Timestamp).toDate()
          : null,
      lastCheckInTime: venueData['lastCheckInTime'] != null
          ? (venueData['lastCheckInTime'] as Timestamp).toDate()
          : DateTime.now(),
      latitude: venueData['latitude']?.toDouble(),
      longitude: venueData['longitude']?.toDouble(),
    );
  }

  /// Sıralama için karşılaştırma
  /// 1. Sponsor mekanlar
  /// 2. Kullanıcının muhtar olduğu mekanlar
  /// 3. Check-in sayısı (çoktan aza)
  /// 4. Son check-in tarihi (yeniden eskiye)
  int compareTo(ExploreVenue other) {
    // 1. Sponsorlu mekanlar önce
    if (isSponsored && !other.isSponsored) return -1;
    if (!isSponsored && other.isSponsored) return 1;
    
    // 1.1. Sponsor priority (düşük değer = yüksek öncelik)
    if (isSponsored && other.isSponsored) {
      final priorityDiff = sponsorPriority - other.sponsorPriority;
      if (priorityDiff != 0) return priorityDiff;
    }
    
    // 2. Kullanıcının muhtar olduğu mekanlar önce
    if (isUserMayor && !other.isUserMayor) return -1;
    if (!isUserMayor && other.isUserMayor) return 1;
    
    // 3. Check-in sayısı (fazladan aza)
    final checkInDiff = other.totalCheckIns - totalCheckIns;
    if (checkInDiff != 0) return checkInDiff;
    
    // 4. Son check-in tarihi (yeniden eskiye)
    if (lastCheckInDate != null && other.lastCheckInDate != null) {
      return other.lastCheckInDate!.compareTo(lastCheckInDate!);
    }
    
    return 0;
  }
}

/// Check-in yapmış kullanıcı önizlemesi (avatar için)
class CheckedInUserPreview {
  final String userId;
  final String name;
  final String? photoUrl;
  final bool isMayor;
  final bool isDiamondMayor; // Elmas ile kazanılan muhtar mı?
  final DateTime checkInTime;

  CheckedInUserPreview({
    required this.userId,
    required this.name,
    this.photoUrl,
    this.isMayor = false,
    this.isDiamondMayor = false,
    required this.checkInTime,
  });

  factory CheckedInUserPreview.fromFirestore(
    Map<String, dynamic> userData,
    String userId,
    bool isMayor,
    DateTime checkInTime,
  ) {
    return CheckedInUserPreview(
      userId: userId,
      name: userData['name'] ?? 'User',
      photoUrl: userData['photos'] != null && (userData['photos'] as List).isNotEmpty
          ? (userData['photos'] as List).first
          : null,
      isMayor: isMayor,
      checkInTime: checkInTime,
    );
  }
}
