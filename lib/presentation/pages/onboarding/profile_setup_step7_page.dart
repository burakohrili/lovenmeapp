import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../../core/theme/app_colors.dart';
import 'user_profile_provider.dart';
import '../home/home_page.dart';

class ProfileSetupStep7Page extends ConsumerStatefulWidget {
  const ProfileSetupStep7Page({super.key});

  @override
  ConsumerState<ProfileSetupStep7Page> createState() => _ProfileSetupStep7PageState();
}

class _ProfileSetupStep7PageState extends ConsumerState<ProfileSetupStep7Page> {
  bool isUploading = false;
  double uploadProgress = 0.0;
  String uploadStatus = '';
  
  // Legal acceptance durumunu kontrol et
  Future<Map<String, dynamic>> _getLegalAcceptanceStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'termsAccepted': false,
        'privacyAccepted': false,
        'acceptanceDate': null,
      };
    }

    try {
      // Legal acceptances koleksiyonundan kullanıcının kabullerini sorgula
      final termsQuery = await FirebaseFirestore.instance
          .collection('legal_acceptances')
          .where('userId', isEqualTo: user.uid)
          .where('documentType', isEqualTo: 'terms')
          .orderBy('acceptedAt', descending: true)
          .limit(1)
          .get();

      final privacyQuery = await FirebaseFirestore.instance
          .collection('legal_acceptances')
          .where('userId', isEqualTo: user.uid)
          .where('documentType', isEqualTo: 'privacy')
          .orderBy('acceptedAt', descending: true)
          .limit(1)
          .get();

      final bool termsAccepted = termsQuery.docs.isNotEmpty;
      final bool privacyAccepted = privacyQuery.docs.isNotEmpty;

      DateTime? latestAcceptanceDate;
      if (termsAccepted || privacyAccepted) {
        final List<DateTime> dates = [];
        if (termsAccepted) {
          final timestamp = termsQuery.docs.first.data()['acceptedAt'] as Timestamp?;
          if (timestamp != null) dates.add(timestamp.toDate());
        }
        if (privacyAccepted) {
          final timestamp = privacyQuery.docs.first.data()['acceptedAt'] as Timestamp?;
          if (timestamp != null) dates.add(timestamp.toDate());
        }
        if (dates.isNotEmpty) {
          dates.sort((a, b) => b.compareTo(a)); // En yeni tarih
          latestAcceptanceDate = dates.first;
        }
      }

      return {
        'termsAccepted': termsAccepted,
        'privacyAccepted': privacyAccepted,
        'bothAccepted': termsAccepted && privacyAccepted,
        'acceptanceDate': latestAcceptanceDate?.toIso8601String(),
        'acceptanceTimestamp': latestAcceptanceDate != null 
          ? Timestamp.fromDate(latestAcceptanceDate)
          : null,
      };
    } catch (e) {
      return {
        'termsAccepted': false,
        'privacyAccepted': false,
        'bothAccepted': false,
        'acceptanceDate': null,
        'error': e.toString(),
      };
    }
  }
  
  // Fotoğrafları Firebase Storage'a yükle
  Future<List<String>> _uploadPhotosToStorage(List<String> localPaths) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Kullanıcı oturumu bulunamadı');
    
    List<String> photoUrls = [];
    int totalPhotos = localPaths.length;
    
    // 🔧 FIX: Eğer fotoğraf yoksa boş liste dön
    if (totalPhotos == 0) {
      return photoUrls;
    }
    
    for (int i = 0; i < localPaths.length; i++) {
      try {
        setState(() {
          uploadStatus = 'Fotoğraf ${i + 1}/$totalPhotos yükleniyor...';
          uploadProgress = (i / totalPhotos);
        });
        
        final file = File(localPaths[i]);
        
        // Dosya var mı kontrol et
        if (!file.existsSync()) {
          continue;
        }
        
        // Storage referansı oluştur
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'profile_${i}_$timestamp.jpg';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('users')
            .child(user.uid)
            .child('profile_photos')
            .child(fileName);
        
        // Dosyayı yükle
        final uploadTask = storageRef.putFile(
          file,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {
              'userId': user.uid,
              'photoIndex': i.toString(),
              'uploadedAt': DateTime.now().toIso8601String(),
            },
          ),
        );
        
        // Upload progress'i dinle
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          setState(() {
            uploadProgress = ((i + progress) / totalPhotos);
          });
        });
        
        // Upload tamamlanana kadar bekle
        final snapshot = await uploadTask;
        
        // Download URL'ini al
        final downloadUrl = await snapshot.ref.getDownloadURL();
        photoUrls.add(downloadUrl);
        
        
      } catch (e) {
        // Hata olsa bile devam et
      }
    }
    
    if (photoUrls.isEmpty) {
      throw Exception('Hiçbir fotoğraf yüklenemedi');
    }
    
    return photoUrls;
  }

  // Firebase'e profil kaydet
  Future<void> _saveProfileToFirebase() async {
    final profile = ref.read(userProfileProvider);
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı oturumu bulunamadı'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    
    setState(() {
      isUploading = true;
      uploadProgress = 0.0;
      uploadStatus = 'Profil hazırlanıyor...';
    });
    
    try {
      List<String> photoUrls = [];
      
      // Fotoğrafları yükle (eğer local path'ler varsa)
      if (profile.localPhotoPaths.isNotEmpty) {
        photoUrls = await _uploadPhotosToStorage(profile.localPhotoPaths);
      }
      
      setState(() {
        uploadStatus = 'Profil bilgileri kaydediliyor...';
        uploadProgress = 0.9;
      });
      
      // Cinsiyet-nötr tercih (Apple 4.3 uyumu)
      List<String> matchPreferences = ['Erkek', 'Kadın', 'Diğer'];

      // Kayıt tamamlandığında çağrılacak:
      final userProfile = ref.read(userProfileProvider);
      if (userProfile.favoriteVenueDetails.isNotEmpty) {
        await ref.read(userProfileProvider.notifier)
            .saveFavoriteVenuesWithCheckIn(userProfile.favoriteVenueDetails);
      }
      
      // Yaş aralığı tercihleri (varsayılan)
      Map<String, int> agePreferences = {
        'minAge': 18,
        'maxAge': 55,
      };
      
      // Konum tercihleri (varsayılan - km cinsinden)
      int maxDistance = 50;
      
      // Bio oluştur (eğer yoksa)
      String bio = profile.bio ?? '';
      if (bio.isEmpty && profile.hobbies.isNotEmpty) {
        bio = '${profile.hobbies.take(3).join(', ')} severim.';
      }
      
      // Firestore'a TÜM profil bilgilerini kaydet
      final userData = {
        // Temel bilgiler
        'uid': user.uid,
        'email': user.email ?? profile.email ?? '',
        'name': profile.name ?? '',
        'surname': profile.surname ?? '',
        'fullName': '${profile.name ?? ''} ${profile.surname ?? ''}',
        'age': profile.age ?? 18,
        'gender': profile.gender ?? 'Belirtilmemiş',
        'bio': bio,
        
        // Fotoğraflar (Firebase Storage URL'leri)
        'photos': photoUrls,
        'mainPhoto': photoUrls.isNotEmpty ? photoUrls.first : '',
        'photoCount': photoUrls.length,
        
        // Hobiler
        'hobbies': profile.hobbies,
        'hobbyCount': profile.hobbies.length,
        
        // Favori mekanlar
        'favoriteVenues': profile.favoriteVenues,
        'favoriteVenueDetails': profile.favoriteVenueDetails.map((venue) => {
          'place_id': venue['place_id'] ?? '',
          'name': venue['name'] ?? '',
          'category': venue['category'] ?? '',
          'rating': venue['rating'] ?? 0.0,
          'latitude': venue['latitude'] ?? 0.0,
          'longitude': venue['longitude'] ?? 0.0,
          'vicinity': venue['vicinity'] ?? '',
        }).toList(),
        'venueCount': profile.favoriteVenues.length,
        
        // İletişim bilgileri
        'phone': profile.phone ?? '',
        'isEmailVerified': profile.isEmailVerified,
        'isPhoneVerified': profile.isPhoneVerified,
        
        // Eşleşme tercihleri
        'matchPreferences': matchPreferences,
        'agePreferences': agePreferences,
        'maxDistance': maxDistance,
        'showMe': true, // Keşfette göster
        
        // Profil durumu
        'isProfileComplete': true,
        'profileCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
        'completionProgress': 1.0,
        
        // Legal Acceptances (Yasal Kabuller)
        'legalAcceptances': await _getLegalAcceptanceStatus(),
        
        // Premium ve limitler
        'isPremium': false,
        'premiumUntil': null,
        'dailyLikesRemaining': 5,
        'dailyLikesResetAt': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'superLikesRemaining': 0,
        'dailyRewindsRemaining': 0,
        
        // İstatistikler
        'totalLikes': 0,
        'totalMatches': 0,
        'totalCheckIns': 0,
        'profileViews': 0,
        
        // Ayarlar
        'settings': {
          'mapVisibility': true,
          'profileActive': true,
          'showDistance': true,
          'showLastActive': true,
          'notifications': true,
          'matchNotifications': true,
          'messageNotifications': true,
          'checkInNotifications': true,
          'soundEnabled': true,
          'vibrationEnabled': true,
        },
        
        // Rozetler ve başarımlar
        'badges': [],
        'achievements': [],
        
        // Engellenen kullanıcılar
        'blockedUsers': [],
        
        // Raporlama
        'reportCount': 0,
        'isReported': false,
        'isBanned': false,
        
        // Platform bilgileri
        'platform': 'mobile',
        'appVersion': '1.0.0',
        'deviceToken': null, // FCM token için
      };
      
      // Firestore'a kaydet (set ile override yap)
      await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(userData, SetOptions(merge: false));
      
      
      // Kullanıcı istatistiklerini başlat
      await FirebaseFirestore.instance
        .collection('user_stats')
        .doc(user.uid)
        .set({
          'userId': user.uid,
          'totalLikesGiven': 0,
          'totalLikesReceived': 0,
          'totalMatches': 0,
          'totalMessages': 0,
          'totalCheckIns': 0,
          'totalVenueVisits': 0,
          'joinedAt': FieldValue.serverTimestamp(),
        });
      
      setState(() {
        uploadStatus = 'Profil başarıyla oluşturuldu!';
        uploadProgress = 1.0;
      });
      
      // Provider'da profili tamamlandı olarak işaretle ve fotoğraf URL'lerini güncelle
      ref.read(userProfileProvider.notifier).updatePhotos(photoUrls);
      ref.read(userProfileProvider.notifier).clearLocalPhotoPaths();
      ref.read(userProfileProvider.notifier).setProfileComplete();
      
      
      // Kısa bir süre bekle
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Ana sayfaya yönlendir (izinler HomePage'de istenecek)
      if (mounted) {
        // Navigator.pushReplacement(
        //   context,
        //   MaterialPageRoute(
        //     builder: (context) => HomePage(initialIndex: 2), // Homepage sayfası
        //   ),
        // );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomePage(initialIndex: 2),),
          (route) => false, // Tüm önceki sayfaları sil
        );
      }
      
    } catch (e) {
      
      setState(() {
        isUploading = false;
        uploadProgress = 0.0;
        uploadStatus = '';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profil kaydedilemedi: ${e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final completionPercentage = (profile.completionProgress * 100).toInt();
    
    return Scaffold(
      backgroundColor: AppColors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryRegisterGradient,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                
                // Progress Indicator (7/7) - TAMAMLANDI
                Row(
                  children: List.generate(7, (index) {
                    return Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (index < 6)
                            Expanded(
                              child: Container(
                                height: 2,
                                color: AppColors.white,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),
                
                const SizedBox(height: 32),
                
                // Success Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white,
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 80,
                    color: AppColors.white,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'Tebrikler! 🎉',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Profilin hazır!',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.white.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 32),
                
                // Profile Summary Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // İsim ve Yaş
                      Row(
                        children: [
                          Icon(Icons.person, color: AppColors.white.withOpacity(0.8)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${profile.name ?? 'İsimsiz'} ${profile.surname ?? ''}, ${profile.age ?? 18}',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Cinsiyet
                      if (profile.gender != null) ...[
                        Row(
                          children: [
                            Icon(Icons.wc, color: AppColors.white.withOpacity(0.8)),
                            const SizedBox(width: 8),
                            Text(
                              profile.gender!,
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      
                      // Fotoğraflar
                      Row(
                        children: [
                          Icon(Icons.photo_camera, color: AppColors.white.withOpacity(0.8)),
                          const SizedBox(width: 8),
                          Text(
                            '${profile.localPhotoPaths.isNotEmpty ? profile.localPhotoPaths.length : profile.photos.length} fotoğraf',
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppColors.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // Hobiler
                      if (profile.hobbies.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.interests, color: AppColors.white.withOpacity(0.8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${profile.hobbies.length} hobi: ${profile.hobbies.take(3).join(', ')}${profile.hobbies.length > 3 ? '...' : ''}',
                                style: TextStyle(
                                  color: AppColors.white.withOpacity(0.9),
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      
                      // Mekanlar
                      Row(
                        children: [
                          Icon(Icons.location_on, color: AppColors.white.withOpacity(0.8)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${profile.favoriteVenues.length} favori mekan',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppColors.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // Doğrulama durumu
                      Row(
                        children: [
                          Icon(
                            profile.isEmailVerified || profile.isPhoneVerified
                                ? Icons.verified_user
                                : Icons.pending,
                            color: profile.isEmailVerified || profile.isPhoneVerified
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getVerificationStatus(profile),
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Completion Progress
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Profil Tamamlanma',
                        style: TextStyle(
                          color: AppColors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '%$completionPercentage',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: profile.completionProgress,
                        backgroundColor: AppColors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.white),
                        minHeight: 6,
                      ),
                      if (completionPercentage < 100) ...[
                        const SizedBox(height: 8),
                        Text(
                          _getMissingFields(profile),
                          style: TextStyle(
                            color: AppColors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Upload Progress (gösteriliyorsa)
                if (isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          uploadStatus,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: uploadProgress.isFinite ? uploadProgress : 0.0,
                          backgroundColor: AppColors.white.withOpacity(0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.white),
                          minHeight: 8,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${uploadProgress.isFinite ? (uploadProgress * 100).toInt() : 0}%',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Action Buttons
                ElevatedButton(
                  onPressed: isUploading ? null : _saveProfileToFirebase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: AppColors.white.withOpacity(0.5),
                  ),
                  child: isUploading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rocket_launch),
                            SizedBox(width: 8),
                            Text(
                              'Profili Tamamla ve Başla',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
                
                const SizedBox(height: 16),
                
                // Back Button (upload yoksa)
                if (!isUploading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Geri Dön ve Düzenle',
                      style: TextStyle(
                        color: AppColors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),
                
                const SizedBox(height: 20),
                
                // Premium Teaser
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.premium.withOpacity(0.3),
                        AppColors.accent.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.premium.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.stars,
                        color: AppColors.premium,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Premium ile Daha Fazlası',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Daha fazla bağlantı isteği, karşılaşma geçmişi ve daha fazlası!',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String _getVerificationStatus(UserProfile profile) {
    if (profile.isEmailVerified && profile.isPhoneVerified) {
      return 'Tam doğrulanmış profil';
    } else if (profile.isEmailVerified) {
      return 'Email doğrulandı';
    } else if (profile.isPhoneVerified) {
      return 'Telefon doğrulandı';
    } else {
      return 'Doğrulama bekliyor';
    }
  }
  
  String _getMissingFields(UserProfile profile) {
    List<String> missing = [];
    
    if (profile.name == null || profile.name!.isEmpty) missing.add('İsim');
    if (profile.surname == null || profile.surname!.isEmpty) missing.add('Soyisim');
    if (profile.age == null) missing.add('Yaş');
    if (profile.gender == null) missing.add('Cinsiyet');
    if (profile.localPhotoPaths.length < 2 && profile.photos.length < 2) missing.add('Fotoğraflar');
    if (profile.hobbies.length < 3) missing.add('Hobiler');
    if (profile.favoriteVenues.length < 3) missing.add('Mekanlar');
    if (!profile.isEmailVerified) missing.add('Email doğrulama');
    if (!profile.isPhoneVerified) missing.add('Telefon doğrulama');
    
    if (missing.isEmpty) return 'Profilin tamamlandı!';
    
    return 'Eksik: ${missing.join(', ')}';
  }
}
