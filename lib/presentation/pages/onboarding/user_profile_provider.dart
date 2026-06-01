import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// User Profile Model
class UserProfile {
  final String? name;
  final String? surname;
  final int? age;
  final String? gender;
  final String? bio;
  final List<String> photos;
  final List<String> localPhotoPaths;
  final List<String> hobbies;
  final List<String> favoriteVenues;
  final List<Map<String, dynamic>> favoriteVenueDetails;
  final String? email;
  final String? phone;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final bool isProfileComplete;

  UserProfile({
    this.name,
    this.surname,
    this.age,
    this.gender,
    this.bio,
    this.photos = const [],
    this.localPhotoPaths = const [],
    this.hobbies = const [],
    this.favoriteVenues = const [],
    this.favoriteVenueDetails = const [],
    this.email,
    this.phone,
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    this.isProfileComplete = false,
  });

  UserProfile copyWith({
    String? name,
    String? surname,
    int? age,
    String? gender,
    String? bio,
    List<String>? photos,
    List<String>? localPhotoPaths,
    List<String>? hobbies,
    List<String>? favoriteVenues,
    List<Map<String, dynamic>>? favoriteVenueDetails,
    String? email,
    String? phone,
    bool? isEmailVerified,
    bool? isPhoneVerified,
    bool? isProfileComplete,
  }) {
    return UserProfile(
      name: name ?? this.name,
      surname: surname ?? this.surname,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      photos: photos ?? this.photos,
      localPhotoPaths: localPhotoPaths ?? this.localPhotoPaths,
      hobbies: hobbies ?? this.hobbies,
      favoriteVenues: favoriteVenues ?? this.favoriteVenues,
      favoriteVenueDetails: favoriteVenueDetails ?? this.favoriteVenueDetails,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
    );
  }

  @override
  String toString() {
    return '''
UserProfile {
  name: $name,
  surname: $surname,
  age: $age,
  gender: $gender,
  bio: $bio,
  photos: ${photos.length} fotoğraf URL,
  localPhotoPaths: ${localPhotoPaths.length} local fotoğraf,
  hobbies: $hobbies,
  favoriteVenues: $favoriteVenues,
  favoriteVenueDetails: ${favoriteVenueDetails.length} mekan detayı,
  email: $email,
  phone: $phone,
  isEmailVerified: $isEmailVerified,
  isPhoneVerified: $isPhoneVerified,
  isProfileComplete: $isProfileComplete
}''';
  }

  double get completionProgress {
    double progress = 0.0;

    if (name != null && name!.isNotEmpty) progress += 0.1;
    if (surname != null && surname!.isNotEmpty) progress += 0.1;
    if (age != null) progress += 0.1;
    if (gender != null && gender!.isNotEmpty) progress += 0.05;
    if (localPhotoPaths.length >= 2 || photos.length >= 2) progress += 0.2;
    if (hobbies.length >= 3) progress += 0.15;
    if (favoriteVenues.length >= 3) progress += 0.2;
    if (isEmailVerified) progress += 0.05;
    if (isPhoneVerified) progress += 0.05;

    return progress;
  }

  bool get isValidForStep1 =>
      name != null && surname != null && age != null && gender != null;
  bool get isValidForStep2 => localPhotoPaths.length >= 2;
}

// User Profile Provider
class UserProfileNotifier extends StateNotifier<UserProfile> {
  UserProfileNotifier() : super(UserProfile());

  // Favori mekanları Firebase'e kaydet ve otomatik check-in oluştur
  Future<void> saveFavoriteVenuesWithCheckIn(
      List<Map<String, dynamic>> favoriteVenues) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      updateFavoriteVenueDetails(favoriteVenues);
      updateFavoriteVenues(
          favoriteVenues.map((v) => v['place_id'] as String).toList());

      // 🔧 FIX: Firebase'ten değil, provider state'ten user bilgilerini al
      // Firebase'te henüz profil kaydedilmemiş olabilir, ama state'te var
      final userName =
          '${state.name ?? 'İsimsiz'} ${(state.surname?.isNotEmpty == true) ? state.surname![0] : ''}.';
      final userPhoto = state.photos.isNotEmpty ? state.photos.first : null;

      int successCount = 0;
      int errorCount = 0;

      for (int i = 0; i < favoriteVenues.length; i++) {
        var venue = favoriteVenues[i];

        final venueData = {
          'userId': user.uid,
          'userName': userName,
          'userPhoto': userPhoto,
          'venueId': venue['place_id'],
          'venueName': venue['name'],
          'venueCategory': venue['category'] ?? 'Mekan',
          'venueLocation': {
            'latitude': venue['latitude'],
            'longitude': venue['longitude'],
          },
          'checkInTime': FieldValue.serverTimestamp(),
          'isAutoCheckIn': true,
          'totalCheckIns': 1,
        };

        try {
          // 0️⃣ MEKAN KAYDI: venues koleksiyonuna mekan bilgilerini ekle (eğer yoksa)
          // ⚡ SetOptions.merge kullanarak eğer yoksa oluştur, varsa güncelleme
          try {
            final venueRef = FirebaseFirestore.instance
                .collection('venues')
                .doc(venue['place_id']);
            await venueRef.set({
              'place_id': venue['place_id'],
              'name': venue['name'] ?? 'İsimsiz Mekan',
              'category': venue['category'] ?? 'Mekan',
              'formattedAddress': venue['formatted_address'] ?? '',
              'vicinity': venue['vicinity'] ?? '',
              'latitude': venue['latitude'] ?? 0.0,
              'longitude': venue['longitude'] ?? 0.0,
              'rating': venue['rating'] ?? 0.0,
              'photoUrl': venue['photo_url'],
              'isSponsored': false,
              'totalCheckIns': 0,
              'createdAt': FieldValue.serverTimestamp(),
              'addedBy': 'favorite_onboarding',
            }, SetOptions(merge: true)); // Mekan varsa mevcut veriyi korur
          } catch (venueError) {
            // Mekan kaydı başarısız olsa bile check-in'ler oluşturulsun
          }

          // 1️⃣ GÜNLÜK CHECK-IN: Harita için (resetlenecek)
          await FirebaseFirestore.instance.collection('check_ins').add({
            ...venueData,
            'fromFavorite':
                false, // Normal check-in gibi davranacak (günlük reset)
            'isInitialRegistration':
                true, // İlk kayıtta oluşturulan check-in (cooldown için önemsiz)
          });

          // 2️⃣ KALICI CHECK-IN: Discover için (kalıcı kalacak)
          await FirebaseFirestore.instance
              .collection('favorite_venue_history')
              .add({
            ...venueData,
            'fromFavorite': true, // 🔍 Discover için kalıcı
            'isPermanent': true, // ♻️ Reset edilmeyecek
            'registrationDate': FieldValue.serverTimestamp(),
          });

          successCount++;
        } catch (venueError) {
          errorCount++;
        }
      }
    } catch (e) {}
  }

  // Profil kaydederken limit değerlerini de ekle
  Future<Map<String, dynamic>> getCompleteUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Kullanıcı bulunamadı');

    // Temel profil verileri
    final profileData = {
      'uid': user.uid,
      'email': state.email ?? user.email,
      'name': state.name,
      'surname': state.surname,
      'age': state.age,
      'gender': state.gender,
      'bio': state.bio,
      'photos': state.photos,
      'hobbies': state.hobbies,
      'favoriteVenues': state.favoriteVenues,
      'favoriteVenueDetails': state.favoriteVenueDetails,
      'isProfileComplete': state.isProfileComplete,
      'isEmailVerified': state.isEmailVerified,
      'isPhoneVerified': state.isPhoneVerified,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),

      // Varsayılan ayarlar
      'mapVisibility': true,
      'profileActive': true,
      'isPremium': false,

      // Günlük limitler - YENİ
      'dailyLikesRemaining': 5,
      'dailySuperLikesRemaining': 0,
      'lastLimitReset': FieldValue.serverTimestamp(),
    };

    return profileData;
  }

  // Step 1: Temel bilgiler
  void updateBasicInfo({
    required String name,
    required String surname,
    required int age,
    String? gender,
  }) {
    state = state.copyWith(
      name: name,
      surname: surname,
      age: age,
      gender: gender,
    );
  }

  void updateGender(String gender) {
    state = state.copyWith(gender: gender);
  }

  // Step 2: Fotoğraflar
  void updateLocalPhotoPaths(List<String> paths) {
    state = state.copyWith(localPhotoPaths: paths);
    for (int i = 0; i < paths.length; i++) {}
  }

  void updatePhotos(List<String> photos) {
    state = state.copyWith(photos: photos);
  }

  void addLocalPhotoPath(String photoPath) {
    if (state.localPhotoPaths.length < 6) {
      final updatedPaths = List<String>.from(state.localPhotoPaths);
      updatedPaths.add(photoPath);
      state = state.copyWith(localPhotoPaths: updatedPaths);
    }
  }

  void removeLocalPhotoPath(int index) {
    if (index >= 0 && index < state.localPhotoPaths.length) {
      final updatedPaths = List<String>.from(state.localPhotoPaths);
      updatedPaths.removeAt(index);
      state = state.copyWith(localPhotoPaths: updatedPaths);
    }
  }

  // Step 3: Hobiler
  void updateHobbies(List<String> hobbies) {
    state = state.copyWith(hobbies: hobbies);
  }

  // Step 4: Favori Mekanlar
  void updateFavoriteVenues(List<String> venues) {
    state = state.copyWith(favoriteVenues: venues);
  }

  void updateFavoriteVenueDetails(List<Map<String, dynamic>> venueDetails) {
    state = state.copyWith(favoriteVenueDetails: venueDetails);
    for (var venue in venueDetails) {}
  }

  // Step 5: İletişim bilgileri
  void updateEmail(String email) {
    state = state.copyWith(email: email);
  }

  void updatePhone(String phone) {
    state = state.copyWith(phone: phone);
  }

  void setEmailVerified(bool verified) {
    state = state.copyWith(isEmailVerified: verified);
  }

  void setPhoneVerified(bool verified) {
    state = state.copyWith(isPhoneVerified: verified);
  }

  // Step 6: Bio
  void updateBio(String bio) {
    state = state.copyWith(bio: bio);
  }

  // Genel metodlar
  void updateProfile(UserProfile newProfile) {
    state = newProfile;
  }

  void setProfileComplete() {
    state = state.copyWith(isProfileComplete: true);
  }

  void resetProfile() {
    state = UserProfile();
  }

  void clearLocalPhotoPaths() {
    state = state.copyWith(localPhotoPaths: []);
  }

  void printAllInfo() {
    if (state.favoriteVenueDetails.isNotEmpty) {
      for (var venue in state.favoriteVenueDetails) {}
    }
  }
}

// Provider tanımı
final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  return UserProfileNotifier();
});

// Computed providers
final userNameProvider = Provider<String>((ref) {
  final profile = ref.watch(userProfileProvider);
  return '${profile.name ?? ''} ${profile.surname ?? ''}'.trim();
});

final profileProgressProvider = Provider<double>((ref) {
  final profile = ref.watch(userProfileProvider);
  return profile.completionProgress;
});

final isProfileCompleteProvider = Provider<bool>((ref) {
  final profile = ref.watch(userProfileProvider);
  return profile.completionProgress >= 1.0;
});
