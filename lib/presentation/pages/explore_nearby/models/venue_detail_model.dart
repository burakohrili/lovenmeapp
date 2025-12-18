// lib/presentation/pages/explore_nearby/models/venue_detail_model.dart

/// Mekan detay sayfası için model
class VenueDetail {
  final String id;
  final String name;
  final String category;
  final String? photoUrl;
  final List<String> photos;
  final double? rating;
  final String? vicinity;
  
  // About bilgileri
  final String? description;
  final String? formattedAddress;
  final String? phoneNumber;
  final String? website;
  
  // Features
  final List<String> features;
  
  // Check-in yapan kullanıcılar
  final List<VenueUser> checkedInUsers;
  final int totalCheckInCount;
  
  // Muhtar bilgileri
  final String? mayorUserId;
  final String? mayorName;
  final String? mayorPhotoUrl;
  final int mayorCheckIns;
  final bool isDiamondMayor; // Elmas ile kazanılan muhtar mı?
  
  // Sponsor bilgileri
  final bool isSponsored;
  final String? sponsorLogoUrl;
  final String? sponsorBadgeText;
  final String? sponsorDescription;
  
  // Konum bilgileri
  final double? latitude;
  final double? longitude;

  VenueDetail({
    required this.id,
    required this.name,
    required this.category,
    this.photoUrl,
    this.photos = const [],
    this.rating,
    this.vicinity,
    this.description,
    this.formattedAddress,
    this.phoneNumber,
    this.website,
    this.features = const [],
    this.checkedInUsers = const [],
    this.totalCheckInCount = 0,
    this.mayorUserId,
    this.mayorName,
    this.mayorPhotoUrl,
    this.mayorCheckIns = 0,
    this.isDiamondMayor = false,
    this.isSponsored = false,
    this.sponsorLogoUrl,
    this.sponsorBadgeText,
    this.sponsorDescription,
    this.latitude,
    this.longitude,
  });

  factory VenueDetail.fromFirestore(
    String venueId,
    Map<String, dynamic> venueData,
    List<VenueUser> checkedInUsers,
    Map<String, dynamic>? mayorData,
  ) {
    // Fotoğrafları al
    List<String> photosList = [];
    if (venueData['photos'] != null) {
      photosList = List<String>.from(venueData['photos']);
    }
    final mainPhoto = photosList.isNotEmpty ? photosList[0] : venueData['photoUrl'];
    
    // Features'ı oluştur
    List<String> featuresList = [];
    if (venueData['features'] != null) {
      featuresList = List<String>.from(venueData['features']);
    } else {
      // Default features from category
      featuresList = _getDefaultFeatures(venueData['category']);
    }

    return VenueDetail(
      id: venueId,
      name: venueData['name'] ?? 'Unknown Venue',
      category: venueData['category'] ?? 'Other',
      photoUrl: mainPhoto,
      photos: photosList,
      rating: venueData['rating']?.toDouble(),
      vicinity: venueData['vicinity'],
      description: venueData['description'],
      formattedAddress: venueData['formattedAddress'] ?? venueData['vicinity'],
      phoneNumber: venueData['phoneNumber'],
      website: venueData['website'],
      features: featuresList,
      checkedInUsers: checkedInUsers,
      totalCheckInCount: venueData['totalCheckIns'] ?? 0,
      mayorUserId: mayorData?['currentMayorId'],
      mayorName: mayorData?['mayorName'],
      mayorPhotoUrl: mayorData?['mayorPhoto'],
      mayorCheckIns: mayorData?['checkInCount'] ?? 0,
      isSponsored: venueData['isSponsored'] ?? false,
      sponsorLogoUrl: venueData['sponsorLogoUrl'],
      sponsorBadgeText: venueData['sponsorBadgeText'],
      sponsorDescription: venueData['sponsorDescription'],
      latitude: venueData['latitude']?.toDouble(),
      longitude: venueData['longitude']?.toDouble(),
    );
  }

  static List<String> _getDefaultFeatures(String? category) {
    switch (category?.toLowerCase()) {
      case 'cafe':
      case 'kafe':
        return ['Wi-Fi', 'Kahve', 'Tatlı', 'Çalışma Alanı'];
      case 'restaurant':
      case 'restoran':
        return ['Yemek', 'İçecek', 'Rezervasyon', 'Açık Alan'];
      case 'bar':
        return ['Alkol', 'Müzik', 'Kokteyl', 'Gece Hayatı'];
      case 'cinema':
      case 'sinema':
        return ['Film Gösterimi', 'Mısır', 'Kolalı Menü', 'Konforlu Koltuklar'];
      case 'park':
        return ['Açık Alan', 'Piknik', 'Yürüyüş', 'Doğa'];
      default:
        return ['Hoş Ortam', 'Samimi Atmosfer'];
    }
  }

  // Public static method for service layer
  static List<String> getDefaultFeatures(String category) {
    return _getDefaultFeatures(category);
  }
}

/// Mekan detayındaki kullanıcı modeli
class VenueUser {
  final String userId;
  final String name;
  final String? surname;
  final int age;
  final String? photoUrl;
  final List<String> photos;
  final String? bio;
  final String? gender;
  final bool isPremium;
  final bool isMayor;
  final bool isDiamondMayor; // Elmas ile kazanılan muhtar mı?
  final int checkInCount; // Bu mekanda kaç kez check-in yaptı
  final DateTime lastCheckIn;

  VenueUser({
    required this.userId,
    required this.name,
    this.surname,
    required this.age,
    this.photoUrl,
    this.photos = const [],
    this.bio,
    this.gender,
    this.isPremium = false,
    this.isMayor = false,
    this.isDiamondMayor = false,
    this.checkInCount = 0,
    required this.lastCheckIn,
  });

  factory VenueUser.fromFirestore(
    Map<String, dynamic> userData,
    String userId,
    bool isMayor,
    int checkInCount,
    DateTime lastCheckIn,
  ) {
    List<String> photosList = [];
    if (userData['photos'] != null) {
      photosList = List<String>.from(userData['photos']);
    }

    return VenueUser(
      userId: userId,
      name: userData['name'] ?? 'User',
      surname: userData['surname'],
      age: userData['age'] ?? 18,
      photoUrl: photosList.isNotEmpty ? photosList[0] : null,
      photos: photosList,
      bio: userData['bio'],
      gender: userData['gender'],
      isPremium: userData['isPremium'] ?? false,
      isMayor: isMayor,
      checkInCount: checkInCount,
      lastCheckIn: lastCheckIn,
    );
  }

  String get fullName => surname != null ? '$name $surname' : name;
}
