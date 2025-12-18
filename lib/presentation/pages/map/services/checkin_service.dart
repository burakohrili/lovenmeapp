import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../models/venue.dart';
import '../../../../core/models/checkedin_user.dart';
import '../../../../utils/image_picker_service.dart';
import '../../../../core/services/mayorship_request_service.dart';
import '../../../../core/services/mayor_conflict_detection_service.dart';
import '../../../../core/services/notification_service.dart';

enum CheckInDisplayMode {
  map,
  discover,
}

/// Check-in cooldown durumunu temsil eden class
class CheckInCooldownStatus {
  final bool canCheckIn;
  final int remainingMinutes;
  final DateTime? lastCheckInTime;
  final String message;

  CheckInCooldownStatus({
    required this.canCheckIn,
    required this.remainingMinutes,
    required this.lastCheckInTime,
    required this.message,
  });
}

class CheckInService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Kamera izni hata popup'ları
  static Future<void> _showPermissionDeniedDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 8),
            Text('İzin Reddedildi'),
          ],
        ),
        content: const Text(
          'Kamera izni reddedildi. Fotoğraflı check-in yapabilmek için kamera izni gereklidir.\n\n'
          'Lütfen tekrar deneyin veya ayarlardan izni etkinleştirin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showPermissionRestrictedDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.orange),
            SizedBox(width: 8),
            Text('İzin Kısıtlandı'),
          ],
        ),
        content: const Text(
          'Kamera izni cihaz politikası veya ebeveyn kontrolleri tarafından kısıtlanmış.\n\n'
          'Cihaz ayarlarınızı kontrol edin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showPermissionPermanentlyDeniedDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.blue),
            SizedBox(width: 8),
            Text('İzin Alma Hatası'),
          ],
        ),
        content: const Text(
          'Kamera izni kalıcı olarak reddedilmiş. Fotoğraflı check-in yapabilmek için ayarlardan kamera iznini manuel olarak açmanız gerekiyor.\n\n'
          'Ayarlar > Gizlilik ve Güvenlik > Kamera > LoveNMe',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ayarlara Git'),
          ),
        ],
      ),
    );
  }

  // İzin durumuna göre uygun popup göster
  static Future<void> _handlePermissionError(BuildContext context, PermissionStatus status) async {
    switch (status) {
      case PermissionStatus.permanentlyDenied:
        await _showPermissionPermanentlyDeniedDialog(context);
        break;
      case PermissionStatus.denied:
        await _showPermissionDeniedDialog(context);
        break;
      case PermissionStatus.restricted:
        await _showPermissionRestrictedDialog(context);
        break;
      default:
        break;
    }
  }

  // Fotoğrafı Firebase Storage'a upload et
  Future<String?> uploadImageToStorage(File image, String userId) async {
    try {
      // Her check-in için unique ID oluştur
      final checkInId = '${DateTime.now().millisecondsSinceEpoch}_$userId';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('checkins')
          .child(checkInId)
          .child('photo.jpg');
      
      final uploadTask = await storageRef.putFile(image);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      return null;
    }
  }

  Future<List<CheckedInUser>> getCheckedInUsers(
    String venueId, {
    bool isForDiscover = false,
    required bool isPremium,
    required Set<String> userCheckedInVenues,
    required Map<String, dynamic> globalVenueCache,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return [];
      }


      final hasCheckedInHere = userCheckedInVenues.contains(venueId);

      if (!isPremium && !hasCheckedInHere) {
        return [];
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final blockedUsers = List<String>.from(userDoc.data()?['blockedUsers'] ?? []);

      final now = DateTime.now();
      
      // 🔄 YENİ SİSTEM: Mekan kapanış saatine kadar o günkü check-in'ler gösterilir
      DateTime? timeFilterThreshold;
      
      if (!isForDiscover) {
        // Today's check-ins only - until venue closes
        final todayStart = DateTime(now.year, now.month, now.day);
        timeFilterThreshold = todayStart;
        
        // Venue closing time kontrolü
        final venueData = globalVenueCache[venueId];
        final venueClosingTime = venueData?['closingTime'] ?? '02:00';
        final timeParts = venueClosingTime.split(':');
        final closingHour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 2) : 2;
        final closingMinute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
        
        DateTime venueClosingDateTime;
        if (closingHour < 6) {
          // Gece 06:00'dan önce kapanan mekanlar ertesi gün kapanıyor
          venueClosingDateTime = DateTime(now.year, now.month, now.day + 1, closingHour, closingMinute);
        } else {
          // Normal kapanış saatleri
          venueClosingDateTime = DateTime(now.year, now.month, now.day, closingHour, closingMinute);
        }
        
        if (now.isAfter(venueClosingDateTime)) {
          await _clearVenueCheckInsAfterClosing(venueId, venueClosingDateTime);
          return [];
        }
        
      } else {
      }
      
      final checkInsSnapshot = await _firestore
          .collection('check_ins')
          .where('venueId', isEqualTo: venueId)
          .orderBy('checkInTime', descending: true)
          .limit(50)
          .get();


      List<CheckedInUser> users = [];
      Set<String> processedUserIds = {}; // Duplikasyonu önlemek için
      int processedNormalCheckIns = 0;

      // 1️⃣ GÜNLÜK CHECK-IN'LER (her zaman dahil)
      for (var doc in checkInsSnapshot.docs) {
        final data = doc.data();
        final userId = data['userId'];
        final isFromFavorite = data['fromFavorite'] == true;

        if (blockedUsers.contains(userId) || processedUserIds.contains(userId)) {
          continue;
        }

        if (data['checkInTime'] != null) {
          DateTime checkInTime;
          try {
            if (data['checkInTime'] is Timestamp) {
              checkInTime = (data['checkInTime'] as Timestamp).toDate();
            } else {
              continue;
            }
          } catch (e) {
            continue;
          }
          
          // Map modunda sadece bugünkü check-in'ler
          if (!isForDiscover) {
            if (timeFilterThreshold != null && checkInTime.isBefore(timeFilterThreshold)) {
              continue;
            }
          }

          final userDocData = await _firestore.collection('users').doc(userId).get();

          if (userDocData.exists) {
            final userData = userDocData.data()!;
            final mapVisibility = userData['mapVisibility'] ?? true;
            final profileActive = userData['profileActive'] ?? true;


            if (!mapVisibility && userId != user.uid) {
              if (isFromFavorite) {
              }
              continue;
            }

            if (!profileActive && userId != user.uid) {
              if (isFromFavorite) {
              }
              continue;
            }

            String userName = userData['name'] ?? 'İsimsiz';
            if (userData['surname'] != null && userData['surname'].toString().isNotEmpty) {
              final surname = userData['surname'].toString();
              if (surname.isNotEmpty) {
                userName = '$userName ${surname[0]}.';
              }
            }

            String? userPhoto;
            if (userData['photos'] != null && userData['photos'] is List) {
              final photos = userData['photos'] as List;
              if (photos.isNotEmpty) {
                userPhoto = photos[0].toString();
              }
            }

            final checkedInUser = CheckedInUser(
              userId: userId,
              userName: userName,
              userPhoto: userPhoto,
              checkInTime: checkInTime,
              latitude: data['latitude']?.toDouble() ?? 0.0,
              longitude: data['longitude']?.toDouble() ?? 0.0,
              fromFavorite: isFromFavorite,
            );

            users.add(checkedInUser);
            processedUserIds.add(userId);
            processedNormalCheckIns++;
          } else {
            // Orphaned check-in cleanup
            try {
              await doc.reference.delete();
            } catch (e) {
            }
          }
        }
      }

      // 2️⃣ KALICI FAVORİ GEÇMİŞİ (sadece discover modunda)
      if (isForDiscover) {
        try {
          final favoriteHistorySnapshot = await _firestore
              .collection('favorite_venue_history')
              .where('venueId', isEqualTo: venueId)
              .where('isPermanent', isEqualTo: true)
              .orderBy('registrationDate', descending: true)
              .limit(20)
              .get();

          for (var doc in favoriteHistorySnapshot.docs) {
            final data = doc.data();
            final userId = data['userId'];

            if (blockedUsers.contains(userId) || processedUserIds.contains(userId)) {
              continue;
            }

            final userDocData = await _firestore.collection('users').doc(userId).get();
            if (userDocData.exists) {
              final userData = userDocData.data()!;
              final mapVisibility = userData['mapVisibility'] ?? true;
              final profileActive = userData['profileActive'] ?? true;

              if ((!mapVisibility || !profileActive) && userId != user.uid) {
                continue;
              }

              String userName = userData['name'] ?? 'İsimsiz';
              if (userData['surname'] != null && userData['surname'].toString().isNotEmpty) {
                final surname = userData['surname'].toString();
                if (surname.isNotEmpty) {
                  userName = '$userName ${surname[0]}.';
                }
              }

              String? userPhoto;
              if (userData['photos'] != null && userData['photos'] is List) {
                final photos = userData['photos'] as List;
                if (photos.isNotEmpty) {
                  userPhoto = photos[0].toString();
                }
              }

              final registrationTime = data['registrationDate'] is Timestamp 
                  ? (data['registrationDate'] as Timestamp).toDate()
                  : DateTime.now();

              final checkedInUser = CheckedInUser(
                userId: userId,
                userName: userName,
                userPhoto: userPhoto,
                checkInTime: registrationTime,
                latitude: data['venueLocation']?['latitude']?.toDouble() ?? 0.0,
                longitude: data['venueLocation']?['longitude']?.toDouble() ?? 0.0,
                fromFavorite: true,
              );

              users.add(checkedInUser);
              processedUserIds.add(userId);
            }
          }
        } catch (e) {
        }
      }

      users.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
      
      // 🔄 YENİ SİSTEM: Muhtar bilgilerini ekle
      users = await _addMayorInfoToUsers(venueId, users);
      
      
      if (!isForDiscover && timeFilterThreshold != null) {
      } else {
      }

      if (users.isNotEmpty) {
        for (int i = 0; i < users.length && i < 5; i++) {
          final user = users[i];
        }
        if (users.length > 5) {
        }
      }

      return users;
    } catch (e) {
      return [];
    }
  }

  // 🔄 YENİ FONKSİYON: Mekan kapandıktan sonra o günkü check-in'leri temizle
  Future<void> _clearVenueCheckInsAfterClosing(String venueId, DateTime closingTime) async {
    try {
      
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      final checkInsToDelete = await _firestore
          .collection('check_ins')
          .where('venueId', isEqualTo: venueId)
          .where('checkInTime', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('checkInTime', isLessThanOrEqualTo: Timestamp.fromDate(closingTime))
          .get();
      
      final batch = _firestore.batch();
      for (final doc in checkInsToDelete.docs) {
        batch.delete(doc.reference);
      }
      
      if (checkInsToDelete.docs.isNotEmpty) {
        await batch.commit();
      }
      
      // Daily mayors da temizle
      await _clearDailyMayorAfterClosing(venueId);
      
    } catch (e) {
    }
  }

  // 🔄 YENİ FONKSİYON: Günlük muhtarı temizle
  Future<void> _clearDailyMayorAfterClosing(String venueId) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      
      await _firestore
          .collection('daily_mayors')
          .doc('${venueId}_$todayKey')
          .delete();
      
    } catch (e) {
    }
  }

  // 🔄 YENİ FONKSİYON: Kullanıcılara muhtar bilgilerini ekle
  Future<List<CheckedInUser>> _addMayorInfoToUsers(String venueId, List<CheckedInUser> users) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final mayorDocId = '${venueId}_$todayKey';
      
      // Bu venue için bugünün muhtarını getir
      final mayorDoc = await _firestore
          .collection('daily_mayors')
          .doc(mayorDocId)
          .get();
      
      if (!mayorDoc.exists) {
        return users;
      }
      
      final mayorData = mayorDoc.data()!;
      final mayorUserId = mayorData['userId'] as String;
      final mayorType = mayorData['mayorType'] as String;
      final isClickable = mayorData['isClickable'] ?? false;
      final canMessage = mayorData['canMessage'] ?? false;
      
      
      // Kullanıcı listesinde muhtarı bul ve bilgilerini güncelle
      final updatedUsers = users.map((user) {
        if (user.userId == mayorUserId) {
          return CheckedInUser(
            userId: user.userId,
            userName: user.userName,
            userPhoto: user.userPhoto,
            checkInTime: user.checkInTime,
            latitude: user.latitude,
            longitude: user.longitude,
            fromFavorite: user.fromFavorite,
            isMayor: true,
            mayorType: mayorType,
            isClickable: isClickable,
            canMessage: canMessage,
          );
        }
        return user;
      }).toList();
      
      // Muhtarı listenin başına taşı
      final mayorIndex = updatedUsers.indexWhere((user) => user.isMayor);
      if (mayorIndex != -1) {
        final mayor = updatedUsers.removeAt(mayorIndex);
        updatedUsers.insert(0, mayor);
      }
      
      return updatedUsers;
    } catch (e) {
      return users;
    }
  }

  // 🕐 COOLDOWN SİSTEMİ: Son check-in'den bu yana 20 dakika geçmiş mi kontrol et
  Future<CheckInCooldownStatus> getCheckInCooldownStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      return CheckInCooldownStatus(
        canCheckIn: false,
        remainingMinutes: 0,
        lastCheckInTime: null,
        message: 'Giriş yapmanız gerekiyor',
      );
    }

    try {
      // Son check-in'i bul (herhangi bir venue'da)
      final lastCheckInQuery = await _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: user.uid)
          .orderBy('checkInTime', descending: true)
          .limit(1)
          .get();

      if (lastCheckInQuery.docs.isEmpty) {
        return CheckInCooldownStatus(
          canCheckIn: true,
          remainingMinutes: 0,
          lastCheckInTime: null,
          message: 'Check-in yapabilirsiniz',
        );
      }

      final lastCheckInDoc = lastCheckInQuery.docs.first;
      final lastCheckInTimestamp = lastCheckInDoc.data()['checkInTime'] as Timestamp;
      final lastCheckInTime = lastCheckInTimestamp.toDate();
      final now = DateTime.now();
      
      // 20 dakika = 1200 saniye - YENİ COOLDOWN SÜRESİ
      const cooldownDuration = Duration(minutes: 20);
      final timeSinceLastCheckIn = now.difference(lastCheckInTime);
      

      if (timeSinceLastCheckIn >= cooldownDuration) {
        return CheckInCooldownStatus(
          canCheckIn: true,
          remainingMinutes: 0,
          lastCheckInTime: lastCheckInTime,
          message: 'Check-in yapabilirsiniz',
        );
      } else {
        final remainingTime = cooldownDuration - timeSinceLastCheckIn;
        final remainingMinutes = remainingTime.inMinutes;
        final remainingSeconds = remainingTime.inSeconds % 60;
        
        return CheckInCooldownStatus(
          canCheckIn: false,
          remainingMinutes: remainingMinutes,
          lastCheckInTime: lastCheckInTime,
          message: 'Bir sonraki check-in için $remainingMinutes dakika $remainingSeconds saniye bekleyin',
        );
      }
    } catch (e) {
      return CheckInCooldownStatus(
        canCheckIn: false,
        remainingMinutes: 0,
        lastCheckInTime: null,
        message: 'Cooldown kontrolü başarısız: $e',
      );
    }
  }

  Future<void> performCheckIn(Venue venue, {
    required double maxDistance,
    required LatLng? currentPosition,
    required Set<String> favoriteVenueIds,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Giriş yapmanız gerekiyor';

    // 🕐 COOLDOWN KONTROLÜ: 20 dakika geçmiş mi?
    final cooldownStatus = await getCheckInCooldownStatus();
    if (!cooldownStatus.canCheckIn) {
      throw cooldownStatus.message;
    }

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final existingCheckIn = await _firestore
        .collection('check_ins')
        .where('userId', isEqualTo: user.uid)
        .where('venueId', isEqualTo: venue.placeId)
        .where('checkInTime', isGreaterThan: todayStart)
        .where('checkInTime', isLessThan: todayEnd)
        .limit(1)
        .get();

    if (existingCheckIn.docs.isNotEmpty) {
      throw 'Bu mekana bugün zaten check-in yaptınız!';
    }

    if (currentPosition != null && !venue.isFavorite) {
      final userLocation = LatLng(currentPosition.latitude, currentPosition.longitude);
      final distance = _calculateDistance(userLocation, venue.location);

      if (distance > maxDistance) {
        throw 'Mekana çok uzaksınız! (${(distance / 1000).toStringAsFixed(1)}km uzakta)';
      }
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists) {
      throw 'Kullanıcı bilgileri bulunamadı';
    }

    final userData = userDoc.data()!;
    String userName = '';
    if (userData['name'] != null && userData['name'].toString().isNotEmpty) {
      userName = userData['name'];
      if (userData['surname'] != null && userData['surname'].toString().isNotEmpty) {
        userName = '$userName ${userData['surname'].toString()[0]}.';
      }
    } else {
      userName = 'İsimsiz Kullanıcı';
    }

    String? userPhoto;
    if (userData['photos'] != null && userData['photos'] is List) {
      final photos = userData['photos'] as List;
      if (photos.isNotEmpty && photos[0] != null) {
        userPhoto = photos[0].toString();
      }
    }

    final checkInRef = await _firestore.collection('check_ins').add({
      'userId': user.uid,
      'userName': userName,
      'userPhoto': userPhoto,
      'isPremium': userData['isPremium'] ?? false,
      'venueId': venue.placeId,
      'venueName': venue.name,
      'venueCategory': venue.category,
      'venueLocation': {
        'latitude': venue.location.latitude,
        'longitude': venue.location.longitude,
      },
      'checkInTime': FieldValue.serverTimestamp(),
      'discoverExpiryTime': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 3)),
      ),
      'totalCheckIns': (userData['totalCheckIns'] ?? 0) + 1,
    });

    // 🔄 YENİ: Discover sistemi için check-in'i history'e de kaydet (30 gün saklansın)
    await _firestore.collection('check_in_history').add({
      'userId': user.uid,
      'userName': userName,
      'userPhoto': userPhoto,
      'isPremium': userData['isPremium'] ?? false,
      'venueId': venue.placeId,
      'venueName': venue.name,
      'venueCategory': venue.category,
      'venueLocation': {
        'latitude': venue.location.latitude,
        'longitude': venue.location.longitude,
      },
      'checkInTime': FieldValue.serverTimestamp(),
      'originalCheckInId': checkInRef.id,
      'forDiscoverMatching': true,
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
      'totalCheckIns': (userData['totalCheckIns'] ?? 0) + 1,
    });


    await _firestore.collection('users').doc(user.uid).update({
      'totalCheckIns': FieldValue.increment(1),
      'lastCheckInDate': FieldValue.serverTimestamp(),
    });

    // 🔄 YENİ SİSTEM: İlk check-in yapan günlük muhtar oluyor
    await _checkAndAssignDailyMayor(venue.placeId, user.uid, userName, userPhoto);
  }

  // 🔄 YENİ FONKSİYON: Günlük muhtar kontrolü ve atama
  Future<void> _checkAndAssignDailyMayor(String venueId, String userId, String userName, String? userPhoto) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final mayorDocId = '${venueId}_$todayKey';
      
      
      // Bu venue için bugün zaten muhtar var mı kontrol et
      final existingMayor = await _firestore
          .collection('daily_mayors')
          .doc(mayorDocId)
          .get();
      
      if (!existingMayor.exists) {
        // Bu venue için bugün ilk check-in - muhtar ol!
        await _firestore.collection('daily_mayors').doc(mayorDocId).set({
          'venueId': venueId,
          'userId': userId,
          'userName': userName,
          'userPhoto': userPhoto,
          'mayorType': 'first_checkin', // İlk check-in muhtarı
          'isClickable': false, // Profil tıklanamaz
          'canMessage': false, // Mesaj atılamaz
          'assignedAt': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(DateTime(today.year, today.month, today.day)),
          'diamondsSpent': 0, // İlk check-in muhtarı için 0
        });
        
      } else {
        final mayorData = existingMayor.data()!;
        final existingMayorType = mayorData['mayorType'] ?? 'first_checkin';
        
        // Eğer mevcut muhtar elmas ile olduysa, o devam eder
        if (existingMayorType == 'diamond') {
        } else {
        }
      }
    } catch (e) {
    }
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
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

  // Günlük muhtarları yükle
  Future<Map<String, Map<String, dynamic>>> loadDailyMayors({bool forceRefresh = false}) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // 🔥 CACHE BYPASS: Force refresh için cache'i bypass et
      QuerySnapshot mayorsSnapshot;
      if (forceRefresh) {
        mayorsSnapshot = await _firestore
            .collection('daily_mayors')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('date', isLessThan: Timestamp.fromDate(endOfDay))
            .get(const GetOptions(source: Source.server)); // Server'dan zorunlu al
      } else {
        mayorsSnapshot = await _firestore
            .collection('daily_mayors')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('date', isLessThan: Timestamp.fromDate(endOfDay))
            .get();
      }

      Map<String, Map<String, dynamic>> dailyMayors = {};
      
      for (var doc in mayorsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final venueId = data['venueId'] as String;
        final mayorType = data['mayorType'] ?? 'first_checkin';
        final diamondsSpent = data['diamondsSpent'] ?? 0;
        
        
        // Eğer aynı venue için zaten bir mayor varsa, elmas muhtarlığını tercih et
        if (dailyMayors.containsKey(venueId)) {
          final existingMayor = dailyMayors[venueId]!;
          final existingDiamonds = existingMayor['diamondsSpent'] ?? 0;
          
          // Mevcut kayıt elmas muhtarlığı ise ve yeni kayıt da elmas muhtarlığı ise, daha yüksek elmas miktarını al
          // Mevcut kayıt ücretsiz ise ve yeni kayıt elmas muhtarlığı ise, yeni kaydı al
          if (diamondsSpent > existingDiamonds) {
            dailyMayors[venueId] = {
              'userId': data['userId'],
              'userName': data['userName'],
              'userPhoto': data['userPhoto'],
              'checkInTime': data['checkInTime'],
              'assignedAt': data['assignedAt'],
              'totalCheckIns': data['totalCheckIns'] ?? 1,
              'mayorType': mayorType,
              'isClickable': data['isClickable'] ?? false,
              'canMessage': data['canMessage'] ?? false,
              'diamondsSpent': data['diamondsSpent'] ?? 0,
              'diamondCount': data['diamondCount'] ?? data['diamondsSpent'] ?? 0,
            };
          } else {
          }
        } else {
          // İlk kez eklenen venue
          dailyMayors[venueId] = {
            'userId': data['userId'],
            'userName': data['userName'],
            'userPhoto': data['userPhoto'],
            'checkInTime': data['checkInTime'],
            'assignedAt': data['assignedAt'],
            'totalCheckIns': data['totalCheckIns'] ?? 1,
            'mayorType': mayorType,
            'isClickable': data['isClickable'] ?? false,
            'canMessage': data['canMessage'] ?? false,
            'diamondsSpent': data['diamondsSpent'] ?? 0,
            'diamondCount': data['diamondCount'] ?? data['diamondsSpent'] ?? 0,
          };
        }
      }

      return dailyMayors;
    } catch (e) {
      return {};
    }
  }

  // Belirli bir venue için günlük muhtarını yükle (cache bypass için)
  Future<Map<String, dynamic>?> getDailyMayorForVenue(String venueId, {bool forceRefresh = false}) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final mayorDocId = '${venueId}_$todayKey';


      // Direkt document ID ile al - atomic transaction ile aynı ID
      // 🔥 CACHE BYPASS: Force refresh için cache'i bypass et
      DocumentSnapshot mayorSnapshot;
      if (forceRefresh) {
        mayorSnapshot = await _firestore
            .collection('daily_mayors')
            .doc(mayorDocId)
            .get(const GetOptions(source: Source.server)); // Server'dan zorunlu al
      } else {
        mayorSnapshot = await _firestore
            .collection('daily_mayors')
            .doc(mayorDocId)
            .get();
      }


      if (mayorSnapshot.exists) {
        final data = mayorSnapshot.data()! as Map<String, dynamic>;
        
        final mayorData = {
          'userId': data['userId'],
          'userName': data['userName'],
          'userPhoto': data['userPhoto'],
          'checkInTime': data['checkInTime'],
          'assignedAt': data['assignedAt'],
          'totalCheckIns': data['totalCheckIns'] ?? 1,
          'mayorType': data['mayorType'] ?? 'first_checkin',
          'isClickable': data['isClickable'] ?? false,
          'canMessage': data['canMessage'] ?? false,
          'diamondsSpent': data['diamondsSpent'] ?? 0,
          'diamondCount': data['diamondCount'] ?? data['diamondsSpent'] ?? 0,
        };
        return mayorData;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Günlük muhtar kontrolü ve ataması
  Future<void> checkAndAssignDailyMayor(String venueId, String userId, String userName, String? userPhoto, {String? venueName}) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Bu gün bu mekanda muhtar var mı kontrol et
      final existingMayorSnapshot = await _firestore
          .collection('daily_mayors')
          .where('venueId', isEqualTo: venueId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .limit(1)
          .get();

      if (existingMayorSnapshot.docs.isEmpty) {
        // İlk check-in! Bu kullanıcı günün muhtarı oluyor
        
        // Kullanıcının toplam check-in sayısını al
        final userDoc = await _firestore.collection('users').doc(userId).get();
        final userData = userDoc.data();
        final totalCheckIns = userData?['totalCheckIns'] ?? 1;

        final mayorData = {
          'venueId': venueId,
          'userId': userId,
          'userName': userName,
          'userPhoto': userPhoto,
          'checkInTime': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(startOfDay),
          'totalCheckIns': totalCheckIns,
          'mayorType': 'first_checkin',
          'diamondCount': 0,
        };

        await _firestore.collection('daily_mayors').add(mayorData);
        // Note: No notification sent to new mayor - they are already aware they checked in
      } else {
      }
    } catch (e) {
    }
  }

  // Check-in sonrası feed post oluştur
  Future<void> createFeedPost({
    required String userId,
    required String userName,
    required int userAge,
    required String userProfileImage,
    required String venueName,
    required String venueAddress,
    required String venueCategory,
    required String venueId, // Venue'nin Place ID'si
    required double latitude,
    required double longitude,
    String? postImage,
    String? caption,
  }) async {
    try {
      await _firestore.collection('feed_posts').add({
        'userId': userId,
        'userName': userName,
        'userAge': userAge,
        'userProfileImage': userProfileImage,
        'venueName': venueName,
        'venueAddress': venueAddress,
        'venueCategory': venueCategory,
        'venueId': venueId, // Venue'nin Place ID'si burada kaydediliyor
        'checkInTime': FieldValue.serverTimestamp(),
        'postImage': postImage,
        'caption': caption,
        'likeCount': 0,
        'commentCount': 0,
        'likedBy': [],
        'latitude': latitude,
        'longitude': longitude,
        'type': 'check_in',
      });
    } catch (e) {
    }
  }

  // Muhtar olma fiyatını hesapla (yeni basamaklı sistem)
  Future<int> calculateMayorshipPrice(String venueId) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final documentId = '${venueId}_$todayKey';
      
      
      // ATOMIC DOCUMENT ID ile doğru muhtar verisini al
      final existingMayorDoc = await _firestore
          .collection('daily_mayors')
          .doc(documentId)
          .get();

      if (existingMayorDoc.exists) {
        final existingMayorData = existingMayorDoc.data()!;
        final existingDiamondCount = existingMayorData['diamondsSpent'] ?? 0;
        final existingMayorType = existingMayorData['mayorType'] ?? 'first_checkin';
        
        
        // Eğer first_checkin muhtarıysa, minimum fiyat başlar
        if (existingMayorType == 'first_checkin') {
          final minPrice = _getMinimumPrice();
          return minPrice;
        }
        
        // Eğer elmas muhtarıysa, basamaklı artış sistemi
        final nextPrice = _calculateNextPrice(existingDiamondCount);
        return nextPrice;
      } else {
        // İlk muhtar minimum fiyat ile başlar
        final minPrice = _getMinimumPrice();
        return minPrice;
      }
    } catch (e) {
      return _getMinimumPrice(); // Varsayılan fiyat
    }
  }

  // Basamaklı fiyat sistemi hesaplaması
  int _calculateNextPrice(int currentPrice) {
    int increment;
    
    // Basamaklı artış: 0–10: +5, 10–50: +10, 50–99: +25, 99+: +50
    if (currentPrice < 10) {
      increment = 5;
    } else if (currentPrice < 50) {
      increment = 10;
    } else if (currentPrice < 99) {
      increment = 25;
    } else {
      increment = 50;
    }
    
    int nextPrice = currentPrice + increment;
    return nextPrice;
  }

  // Minimum fiyat belirleme
  int _getMinimumPrice() {
    return 5; // İlk diamond mayor 5 elmas ile başlayabilir
  }

  // "Buy Now" fiyatını hesapla (mevcut muhtarın harcadığının 2 katı)
  Future<int> calculateBuyNowPrice(String venueId) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final documentId = '${venueId}_$todayKey';
      
      // ATOMIC DOCUMENT ID ile mevcut muhtar verisini al
      final existingMayorDoc = await _firestore
          .collection('daily_mayors')
          .doc(documentId)
          .get();

      if (existingMayorDoc.exists) {
        final existingMayorData = existingMayorDoc.data()!;
        final existingDiamondCount = existingMayorData['diamondsSpent'] ?? 0;
        final existingMayorType = existingMayorData['mayorType'] ?? 'first_checkin';
        
        // Eğer first_checkin muhtarıysa, minimum fiyatın 2 katı
        if (existingMayorType == 'first_checkin') {
          final minPrice = _getMinimumPrice();
          final buyNowPrice = minPrice * 2;
          return buyNowPrice;
        }
        
        // Eğer elmas muhtarıysa, harcadığının 2 katı
        final buyNowPrice = existingDiamondCount * 2;
        return buyNowPrice;
      } else {
        // Muhtar yoksa minimum fiyatın 2 katı
        final minPrice = _getMinimumPrice();
        final buyNowPrice = minPrice * 2;
        return buyNowPrice;
      }
    } catch (e) {
      final minPrice = _getMinimumPrice();
      return minPrice * 2; // Varsayılan fiyat
    }
  }

  // Normal elmas ile muhtar olma (basamaklı fiyat artışı)
  Future<Map<String, dynamic>> purchaseMayorshipWithDiamonds(
    String venueId,
    String venueName,
  ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'not_authenticated'};
      }

      // 🛡️ STEP 1: Request Deduplication Check
      final mayorshipService = MayorshipRequestService();
      final canProceed = await mayorshipService.canMakeRequest(
        venueId,
        currentUser.uid,
        'normal',
      );
      
      if (!canProceed) {
        return {
          'success': false, 
          'error': 'rate_limited',
          'message': 'Please wait before making another mayorship request'
        };
      }

      // Kullanıcının check-in durumunu kontrol et
      if (!await _hasCheckedInToday(currentUser.uid, venueId)) {
        return {'success': false, 'error': 'no_checkin_today'};
      }

      // Normal mayorship fiyatını hesapla
      final mayorshipPrice = await calculateMayorshipPrice(venueId);
      
      // Kullanıcının elmas bakiyesini kontrol et
      final userBalance = await getUserDiamondBalance(currentUser.uid);
      if (userBalance < mayorshipPrice) {
        return {
          'success': false, 
          'error': 'insufficient_diamonds',
          'required': mayorshipPrice,
          'available': userBalance,
        };
      }

      // Kullanıcı bilgilerini al
      final userRef = _firestore.collection('users').doc(currentUser.uid);
      final userSnapshot = await userRef.get();
      if (!userSnapshot.exists) {
        return {'success': false, 'error': 'user_not_found'};
      }

      final userData = userSnapshot.data()!;
      final userName = userData['name'] ?? 'İsimsiz';
      final userPhoto = userData['photos'] != null && userData['photos'].isNotEmpty 
          ? userData['photos'][0] 
          : null;

      // 🛡️ STEP 2: Execute Atomic Transaction with All Protections  
      // Variable to store final charged price for conflict detection
      int finalChargedPrice = mayorshipPrice; // Will be updated in transaction
      
      // Variables for notification (will be set in transaction)
      String? previousMayorId;
      int previousMayorDiamonds = 0;
      
      await _firestore.runTransaction((transaction) async {
        final startOfDay = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
        final mayorRef = _firestore.collection('daily_mayors').doc('${venueId}_${DateFormat('yyyy-MM-dd').format(startOfDay)}');
        
        // 1. Fresh user balance check (race condition prevention)
        final freshUserSnapshot = await transaction.get(userRef);
        if (!freshUserSnapshot.exists) {
          throw Exception('User document not found during transaction');
        }
        
        final currentBalance = freshUserSnapshot.data()!['diamonds'] ?? 0;
        
        // 2. Fresh mayor check and price validation
        final mayorSnapshot = await transaction.get(mayorRef);
        String? currentMayorUserId;
        int currentMayorDiamonds = 0;
        int actualRequiredPrice = mayorshipPrice;
        
        if (mayorSnapshot.exists) {
          final existingMayorData = mayorSnapshot.data()!;
          currentMayorUserId = existingMayorData['userId'] ?? '';
          currentMayorDiamonds = existingMayorData['diamondsSpent'] ?? 0;
          final existingMayorType = existingMayorData['mayorType'] ?? 'first_checkin';
          
          // Set values for notification
          previousMayorId = currentMayorUserId;
          previousMayorDiamonds = currentMayorDiamonds;
          
          // Fresh normal mayorship fiyat hesaplama
          if (existingMayorType == 'first_checkin') {
            actualRequiredPrice = 5; // First checkin'den sonra minimum
          } else {
            // Diamond mayor'dan sonra basamaklı artış hesapla
            actualRequiredPrice = _calculateNextPrice(currentMayorDiamonds);
          }
        } else {
          actualRequiredPrice = 5; // İlk muhtar minimum fiyat
        }
        
        
        // 🚨 PRICE VALIDATION: UI'dan gelen fiyat ile gerçek fiyat eşleşmeli
        if (mayorshipPrice != actualRequiredPrice) {
          throw Exception('Price changed! UI shows $mayorshipPrice diamonds, but current price is $actualRequiredPrice diamonds. Please refresh and try again.');
        }
        
        // Kullanıcının yeterli elması var mı kontrol et (fresh price ile)
        if (currentBalance < actualRequiredPrice) {
          throw Exception('Insufficient diamonds: $currentBalance < $actualRequiredPrice');
        }
        
        // Final diamond calculation
        int totalDiamondsSpent = actualRequiredPrice;
        if (mayorSnapshot.exists) {
          final existingMayorData = mayorSnapshot.data()!;
          currentMayorUserId = existingMayorData['userId'] ?? '';
          currentMayorDiamonds = existingMayorData['diamondsSpent'] ?? 0;
          final existingMayorType = existingMayorData['mayorType'] ?? 'first_checkin';
          
          // Aynı kullanıcıysa upgrade yap
          if (currentMayorUserId == currentUser.uid) {
            totalDiamondsSpent = currentMayorDiamonds + actualRequiredPrice;
          } else {
            // Farklı kullanıcıysa yeterli elmas kontrolü
            if (existingMayorType == 'diamond' && actualRequiredPrice <= currentMayorDiamonds) {
              throw Exception('Insufficient diamonds to replace current mayor: Need more than $currentMayorDiamonds, provided: $actualRequiredPrice');
            }
          }
        } else {
        }
        
        // Store final price for external use
        finalChargedPrice = actualRequiredPrice;
        
        // 🚨 CRITICAL RACE CONDITION FIX: Normal mayorship için conditional write
        // Transaction başladıktan sonra mayor değişip değişmediğini kontrol et
        // NOT: Yeni mayor durumunda (currentMayorUserId == null) race condition check'i bypass et
        if (currentMayorUserId != null) {
          final freshMayorCheck = await transaction.get(mayorRef);
          if (freshMayorCheck.exists) {
            final freshData = freshMayorCheck.data()!;
            final freshUserId = freshData['userId'] ?? '';
            final freshDiamonds = freshData['diamondsSpent'] ?? 0;
            
            // Başka biri aynı anda daha fazla elmasla muhtar olduysa transaction'ı reddet
            if (freshUserId != currentMayorUserId || freshDiamonds != currentMayorDiamonds) {
              throw Exception('RACE CONDITION DETECTED: Another user became mayor during this transaction. Current mayor: $freshUserId (was: $currentMayorUserId), diamonds: $freshDiamonds (was: $currentMayorDiamonds)');
            }
          }
        } else {
        }
        
        // 3. Diamond balance güncelle (fresh price ile)
        final newBalance = currentBalance - actualRequiredPrice;
        transaction.update(userRef, {
          'diamonds': newBalance,
          'lastDiamondUpdate': FieldValue.serverTimestamp(),
        });
        
        // 4. Mayor kaydını güncelle (enhanced audit trail)
        transaction.set(mayorRef, {
          'venueId': venueId,
          'userId': currentUser.uid,
          'userName': userName,
          'userPhoto': userPhoto,
          'mayorType': 'diamond',
          'isClickable': true,
          'canMessage': true,
          'assignedAt': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(startOfDay),
          'diamondsSpent': totalDiamondsSpent,
          'diamondCount': totalDiamondsSpent,
          'checkInTime': FieldValue.serverTimestamp(),
          'totalCheckIns': 1,
          // 🔥 ENHANCED AUDIT TRAIL
          'previousMayorId': currentMayorUserId,
          'previousMayorDiamonds': currentMayorDiamonds,
          'uiProvidedPrice': mayorshipPrice,
          'actualChargedPrice': actualRequiredPrice,
          'isUpgrade': currentMayorUserId == currentUser.uid,
          'transactionType': 'normal_mayorship',
        });
        
        // 5. Transaction log ekle (enhanced)
        final transactionRef = _firestore.collection('diamond_transactions').doc();
        transaction.set(transactionRef, {
          'userId': currentUser.uid,
          'venueId': venueId,
          'venueName': venueName,
          'amount': actualRequiredPrice, // Fresh calculated price
          'type': 'mayorship_purchase',
          'timestamp': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(startOfDay),
          'previousBalance': currentBalance,
          'newBalance': newBalance,
          'replacedMayorId': currentMayorUserId,
          'replacedMayorDiamonds': currentMayorDiamonds,
          'isAtomic': true,
          'uiProvidedPrice': mayorshipPrice,
          'actualChargedPrice': actualRequiredPrice,
          'priceValidation': mayorshipPrice == actualRequiredPrice ? 'PASSED' : 'FAILED',
          'raceConditionProtected': true,
        });
        
        if (currentMayorUserId != null) {
        }
      });

      // � STEP 2: Send notifications for mayorship change
      try {
        // Send notification to previous mayor if they existed
        if (previousMayorId != null && previousMayorId != currentUser.uid) {
          String mayorType = (previousMayorDiamonds == 0) ? 'first_checkin' : 'diamond';
          await NotificationService.sendMayorLostNotification(
            toUserId: previousMayorId!,
            venueName: venueName,
            mayorType: mayorType,
          );
        }
        // Note: No notification sent to new mayor - they initiated the action
      } catch (e) {
        // Continue without notifications - don't fail the transaction
      }

      // �🛡️ STEP 3: Register for conflict detection (same as Buy Now)
      try {
        final conflictService = MayorConflictDetectionService.instance;
        await conflictService.registerMayorAttempt(
          venueId: venueId,
          userId: currentUser.uid,
          diamondAmount: finalChargedPrice,
          transactionId: 'normal_purchase_${DateTime.now().millisecondsSinceEpoch}',
          monitoringDuration: const Duration(minutes: 10),
        );
      } catch (e) {
        // Continue without conflict detection
      }

      return {'success': true};
    } catch (e) {
      
      // 🚨 RACE CONDITION ERROR HANDLING
      if (e.toString().contains('RACE CONDITION DETECTED')) {
        return {'success': false, 'error': 'race_condition_detected'};
      }
      
      // 🚨 PRICE CHANGE ERROR HANDLING  
      if (e.toString().contains('Price changed!')) {
        return {'success': false, 'error': 'price_changed'};
      }
      
      // 🚨 INSUFFICIENT DIAMONDS
      if (e.toString().contains('Insufficient diamonds')) {
        return {'success': false, 'error': 'insufficient_diamonds'};
      }
      
      return {'success': false, 'error': 'purchase_failed'};
    }
  }

  // "Buy Now" ile muhtar olma (mevcut teklifin 2 katı)
  Future<Map<String, dynamic>> purchaseBuyNowMayorshipWithDiamonds(
    String venueId,
    String venueName,
  ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'not_authenticated'};
      }

      // 🛡️ STEP 1: Request Deduplication Check
      final mayorshipService = MayorshipRequestService();
      final canProceed = await mayorshipService.canMakeRequest(
        venueId,
        currentUser.uid,
        'buy_now',
      );
      
      if (!canProceed) {
        return {
          'success': false, 
          'error': 'rate_limited',
          'message': 'Please wait before making another mayorship request'
        };
      }

      // Kullanıcının check-in durumunu kontrol et
      if (!await _hasCheckedInToday(currentUser.uid, venueId)) {
        return {'success': false, 'error': 'no_checkin_today'};
      }

      // Buy Now fiyatını hesapla (regular fiyatın 2 katı)
      final buyNowPrice = await calculateBuyNowPrice(venueId);
      
      // Kullanıcının elmas bakiyesini kontrol et
      final userBalance = await getUserDiamondBalance(currentUser.uid);
      if (userBalance < buyNowPrice) {
        return {
          'success': false, 
          'error': 'insufficient_diamonds',
          'required': buyNowPrice,
          'available': userBalance
        };
      }

      // Kullanıcı bilgilerini al
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final userName = userData?['name'] ?? 'İsimsiz';
      final userPhoto = userData?['photos']?[0];

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final todayKey = DateFormat('yyyy-MM-dd').format(now);
      final mayorDocId = '${venueId}_$todayKey';

      // Mevcut mayor kontrolü (toplam hesaplamak için)
      final existingMayorQuery = await _firestore
          .collection('daily_mayors')
          .where('venueId', isEqualTo: venueId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(startOfDay.add(const Duration(days: 1))))
          .get();

      int totalDiamondsSpent = buyNowPrice; // Varsayılan: sadece buy now fiyatı

      if (existingMayorQuery.docs.isNotEmpty) {
        final existingMayor = existingMayorQuery.docs.first;
        final existingMayorData = existingMayor.data();
        final existingUserId = existingMayorData['userId'] ?? '';
        final existingDiamondCount = existingMayorData['diamondsSpent'] ?? 0;

        // Eğer aynı kullanıcıysa önceki elmasları da ekle
        if (existingUserId == currentUser.uid) {
          totalDiamondsSpent = existingDiamondCount + buyNowPrice;
        } else {
        }
      }

      // Buy Now ile direkt muhtar ol (mevcut muhtarın durumuna bakmadan)
      // NOT: Bu sadece pre-validation için, asıl işlem atomic transaction'da yapılacak

      // 🔥 ATOMIC TRANSACTION: Buy Now işlemini atomic yap
      // Variables for notification (will be set in transaction)
      String? previousMayorId;
      int previousMayorDiamonds = 0;
      
      await _firestore.runTransaction((transaction) async {
        // 1. User bakiyesini atomic olarak kontrol et
        final userRef = _firestore.collection('users').doc(currentUser.uid);
        final userSnapshot = await transaction.get(userRef);
        
        if (!userSnapshot.exists) {
          throw Exception('User not found');
        }
        
        final currentBalance = userSnapshot.data()!['diamonds'] ?? 0;
        if (currentBalance < buyNowPrice) {
          throw Exception('Insufficient diamonds for Buy Now: $currentBalance < $buyNowPrice');
        }
        
        // 2. Mayor kaydını atomic olarak kontrol et ve FRESH fiyat hesapla
        final mayorRef = _firestore.collection('daily_mayors').doc(mayorDocId);
        final mayorSnapshot = await transaction.get(mayorRef);
        
        // 🚨 FRESH PRICE CALCULATION: Panel açık kaldığında eski fiyat kullanılmasını önle
        String? currentMayorUserId;
        int currentMayorDiamonds = 0;
        int actualRequiredBuyNowPrice = 5 * 2; // Default: minimum price x 2
        
        if (mayorSnapshot.exists) {
          final existingMayorData = mayorSnapshot.data()!;
          currentMayorUserId = existingMayorData['userId'] ?? '';
          currentMayorDiamonds = existingMayorData['diamondsSpent'] ?? 0;
          final existingMayorType = existingMayorData['mayorType'] ?? 'first_checkin';
          
          // Set values for notification
          previousMayorId = currentMayorUserId;
          previousMayorDiamonds = currentMayorDiamonds;
          
          // Fresh Buy Now fiyat hesaplama
          if (existingMayorType == 'diamond') {
            actualRequiredBuyNowPrice = currentMayorDiamonds * 2;
          } else {
            // First checkin mayor için minimum fiyatın 2 katı
            actualRequiredBuyNowPrice = 5 * 2; // 10 elmas
          }
        }
        
        
        // 🚨 PRICE VALIDATION: UI'dan gelen fiyat ile gerçek fiyat eşleşmeli
        if (buyNowPrice != actualRequiredBuyNowPrice) {
          throw Exception('Price changed! UI shows $buyNowPrice diamonds, but current price is $actualRequiredBuyNowPrice diamonds. Please refresh and try again.');
        }
        
        // Kullanıcının yeterli elması var mı kontrol et (fresh price ile)
        if (currentBalance < actualRequiredBuyNowPrice) {
          throw Exception('Insufficient diamonds for Buy Now: $currentBalance < $actualRequiredBuyNowPrice');
        }
        
        // Final diamond calculation
        int finalTotalDiamonds = actualRequiredBuyNowPrice;
        if (currentMayorUserId == currentUser.uid) {
          finalTotalDiamonds = currentMayorDiamonds + actualRequiredBuyNowPrice;
        }
        
        // 🚨 CRITICAL RACE CONDITION FIX: Buy Now için conditional write
        // Eğer başka biri aynı anda daha fazla elmasla muhtar olduysa transaction fail etsin
        final conditionalMayorData = {
          'venueId': venueId,
          'userId': currentUser.uid,
          'userName': userName,
          'userPhoto': userPhoto,
          'mayorType': 'diamond',
          'isClickable': true,
          'canMessage': true,
          'assignedAt': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(startOfDay),
          'diamondsSpent': finalTotalDiamonds,
          'diamondCount': finalTotalDiamonds,
          'checkInTime': null,
          'totalCheckIns': 1,
          'previousMayorId': currentMayorUserId,
          'previousMayorDiamonds': currentMayorDiamonds,
          'buyNowAmount': actualRequiredBuyNowPrice,
          'uiProvidedPrice': buyNowPrice,
          'transactionType': 'buy_now_mayorship',
          'actualChargedPrice': actualRequiredBuyNowPrice,
          'isUpgrade': currentMayorUserId == currentUser.uid,
        };
        
        // 🔥 CONDITIONAL WRITE: Sadece mayor document'ı değişmemişse yazma işlemini yap
        if (mayorSnapshot.exists) {
          final currentData = mayorSnapshot.data()!;
          final currentDiamonds = currentData['diamondsSpent'] ?? 0;
          final currentUserId = currentData['userId'] ?? '';
          
          // Başka biri aynı anda daha fazla elmasla muhtar olduysa transaction'ı reddet
          if (currentUserId != currentMayorUserId || currentDiamonds != currentMayorDiamonds) {
            throw Exception('RACE CONDITION DETECTED: Another user became mayor during this transaction. Current mayor: $currentUserId (was: $currentMayorUserId), diamonds: $currentDiamonds (was: $currentMayorDiamonds)');
          }
        }
        
        // 3. Diamond balance güncelle (validated fresh price ile)
        transaction.update(userRef, {
          'diamonds': currentBalance - actualRequiredBuyNowPrice,
          'lastDiamondUpdate': FieldValue.serverTimestamp(),
        });
        
        // 4. Mayor kaydını atomic olarak güncelle (conditional)
        transaction.set(mayorRef, conditionalMayorData);
        
        // 5. Buy Now transaction log (enhanced with race condition protection)
        final transactionRef = _firestore.collection('diamond_transactions').doc();
        transaction.set(transactionRef, {
          'userId': currentUser.uid,
          'venueId': venueId,
          'venueName': venueName,
          'amount': actualRequiredBuyNowPrice,
          'type': 'buy_now_mayorship',
          'timestamp': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(startOfDay),
          'previousBalance': currentBalance,
          'newBalance': currentBalance - actualRequiredBuyNowPrice,
          'replacedMayorId': currentMayorUserId,
          'replacedMayorDiamonds': currentMayorDiamonds,
          'uiProvidedPrice': buyNowPrice,
          'actualChargedPrice': actualRequiredBuyNowPrice,
          'priceValidation': buyNowPrice == actualRequiredBuyNowPrice ? 'PASSED' : 'FAILED',
          'isAtomic': true,
          'isBuyNow': true,
          'raceConditionProtected': true,
        });
        
        // 6. Mayor transaction log (conflict detection için)
        final mayorLogRef = _firestore.collection('mayor_transaction_logs').doc(transactionRef.id);
        transaction.set(mayorLogRef, {
          'venueId': venueId,
          'userId': currentUser.uid,
          'transactionId': transactionRef.id,
          'amount': actualRequiredBuyNowPrice,
          'type': 'buy_now',
          'status': 'completed',
          'timestamp': FieldValue.serverTimestamp(),
          'replacedMayorId': currentMayorUserId,
          'isAtomic': true,
          'raceConditionProtected': true,
        });
        
      });

      // � STEP 2: Send notifications for mayorship change
      try {
        // Send notification to previous mayor if they existed
        if (previousMayorId != null && previousMayorId != currentUser.uid) {
          String mayorType = (previousMayorDiamonds == 0) ? 'first_checkin' : 'diamond';
          await NotificationService.sendMayorLostNotification(
            toUserId: previousMayorId!,
            venueName: venueName,
            mayorType: mayorType,
          );
        }
        // Note: No notification sent to new mayor - they initiated the action
      } catch (e) {
        // Continue without notifications - don't fail the transaction
      }

      // �🛡️ STEP 3: Register for conflict detection
      try {
        final conflictService = MayorConflictDetectionService.instance;
        await conflictService.registerMayorAttempt(
          venueId: venueId,
          userId: currentUser.uid,
          diamondAmount: buyNowPrice,
          transactionId: 'buy_now_${DateTime.now().millisecondsSinceEpoch}',
          monitoringDuration: const Duration(minutes: 10),
        );
      } catch (e) {
        // Continue without conflict detection
      }

      return {'success': true};
    } catch (e) {
      
      // 🚨 RACE CONDITION ERROR HANDLING
      if (e.toString().contains('RACE CONDITION DETECTED')) {
        return {'success': false, 'error': 'race_condition_detected'};
      }
      
      // 🚨 PRICE CHANGE ERROR HANDLING  
      if (e.toString().contains('Price changed!')) {
        return {'success': false, 'error': 'price_changed'};
      }
      
      // 🚨 INSUFFICIENT DIAMONDS
      if (e.toString().contains('Insufficient diamonds')) {
        return {'success': false, 'error': 'insufficient_diamonds'};
      }
      
      return {'success': false, 'error': 'purchase_failed'};
    }
  }

  // Kullanıcının bugün bu mekana check-in yapıp yapmadığını kontrol et
  Future<bool> _hasCheckedInToday(String userId, String venueId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final checkInQuery = await _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: userId)
          .where('venueId', isEqualTo: venueId)
          .where('checkInTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('checkInTime', isLessThan: Timestamp.fromDate(endOfDay))
          .limit(1)
          .get();

      return checkInQuery.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  Future<int> getUserDiamondBalance(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        final diamonds = userData?['diamonds'] ?? 0;
        
        return diamonds;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // Fotoğrafsız check-in
  Future<bool> performCheckInWithoutPhoto(Venue venue, Set<String> userCheckedInVenues) async {
    
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return false;
      }

      // 🕐 COOLDOWN KONTROLÜ: 20 dakika geçmiş mi?
      final cooldownStatus = await getCheckInCooldownStatus();
      if (!cooldownStatus.canCheckIn) {
        throw cooldownStatus.message;
      }


      // Firebase'e check-in dokümanı kaydet
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docRef = await _firestore.collection('check_ins').add({
        'userId': user.uid,
        'venueId': venue.id,
        'venueName': venue.name,
        'checkInTime': FieldValue.serverTimestamp(),
        'date': today, // Elmas muhtar kontrolü için gerekli
        'latitude': venue.location.latitude,
        'longitude': venue.location.longitude,
        'fromFavorite': false,
        'hasPhoto': false,
      });


      // 🔄 YENİ: Discover sistemi için check-in'i history'e de kaydet (30 gün saklansın)
      try {
        await _firestore.collection('check_in_history').add({
          'userId': user.uid,
          'venueId': venue.id,
          'venueName': venue.name,
          'checkInTime': FieldValue.serverTimestamp(),
          'date': today,
          'latitude': venue.location.latitude,
          'longitude': venue.location.longitude,
          'fromFavorite': false,
          'hasPhoto': false,
          'originalCheckInId': docRef.id,
          'forDiscoverMatching': true,
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        });
      } catch (historyError) {
        // Check-in devam etsin, sadece discover history kaydetme başarısız oldu
      }

      // User check-in listesini güncelle
      userCheckedInVenues.add(venue.id);
      
      // Kullanıcı bilgilerini al
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final userName = userData?['name'] ?? 'İsimsiz';
      final userPhoto = userData?['mainPhoto'];
      final userAge = userData?['age'] ?? 25;
      
      // Kullanıcının totalCheckIns sayısını artır
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'totalCheckIns': FieldValue.increment(1),
          'lastCheckInDate': FieldValue.serverTimestamp(),
        });
      } catch (statsError) {
      }
      
      // Günlük muhtar kontrolü ve ataması
      await checkAndAssignDailyMayor(venue.id, user.uid, userName, userPhoto, venueName: venue.name);

      // Feed post oluştur
      await createFeedPost(
        userId: user.uid,
        userName: userName,
        userAge: userAge,
        userProfileImage: userPhoto ?? '',
        venueName: venue.name,
        venueAddress: venue.vicinity,
        venueCategory: venue.category,
        venueId: venue.id, // Venue'nin Place ID'si
        latitude: venue.location.latitude,
        longitude: venue.location.longitude,
        caption: '${venue.name} mekanına check-in yaptı',
      );

      return true;
      
    } catch (e) {
      return false;
    }
  }

  // Fotoğraflı check-in için direkt kamera aç (CROP ile) - iOS için geliştirilmiş
  Future<File?> selectImageFromCamera(context) async {
    try {
      
      // Önce izin durumunu kontrol et
      final initialPermissionStatus = await Permission.camera.status;
      
      // iOS özel kontroller
      if (Platform.isIOS) {
        
        // iOS'ta farklı permission state'lerini kontrol et
        switch (initialPermissionStatus) {
          case PermissionStatus.denied:
            break;
          case PermissionStatus.granted:
            break;
          case PermissionStatus.restricted:
            break;
          case PermissionStatus.limited:
            break;
          case PermissionStatus.permanentlyDenied:
            break;
          case PermissionStatus.provisional:
            break;
        }
      }
      
      // Direkt kamera aç ve crop et
      final File? croppedImage = await ImagePickerService.pickAndCropImage(
        context: context,
        source: ImageSource.camera,
        aspectRatioPresets: [
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9,
        ],
      );
      
      if (croppedImage == null) {
        
        // Permission durumunu tekrar kontrol et
        final finalPermissionStatus = await Permission.camera.status;
        
        // iOS özel hata analizi
        if (Platform.isIOS) {
          
          if (initialPermissionStatus == PermissionStatus.denied && 
              finalPermissionStatus == PermissionStatus.denied) {
          }
        }
        
        // Eğer izin alma denemesi sonrası durum değiştiyse, son durumu kullan
        PermissionStatus statusToCheck = finalPermissionStatus;
        
        // Eğer initial denied idi ve şimdi hala denied ise, büyük ihtimalle permanently denied
        if (initialPermissionStatus == PermissionStatus.denied && 
            finalPermissionStatus == PermissionStatus.denied) {
          statusToCheck = PermissionStatus.permanentlyDenied;
        }
        
        // İzin durumuna göre uygun popup göster
        if (statusToCheck != PermissionStatus.granted) {
          await _handlePermissionError(context, statusToCheck);
        } else {
        }
        return null;
      } else {
        // File size kontrolü
        final fileSize = await croppedImage.length();
        return croppedImage;
      }
    } catch (e) {
      
      // iOS özel hata analizi
      if (Platform.isIOS) {
        if (e.toString().contains('permission')) {
        }
        if (e.toString().contains('cancelled')) {
        }
      }
      
      // Hata durumunda da permission check yap
      try {
        final permissionStatus = await Permission.camera.status;
        if (permissionStatus != PermissionStatus.granted) {
          await _handlePermissionError(context, permissionStatus);
        } else {
          // İzin var ama başka bir hata oluştu
          await _showPermissionDeniedDialog(context);
        }
      } catch (permissionError) {
        // Son çare olarak genel hata popup'ı göster
        await _showPermissionDeniedDialog(context);
      }
      return null;
    }
  }

  // Fotoğraflı check-in gerçekleştir
  Future<bool> performCheckInWithPhoto(Venue venue, File image, Set<String> userCheckedInVenues) async {
    
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return false;
      }

      // 🕐 COOLDOWN KONTROLÜ: 20 dakika geçmiş mi?
      final cooldownStatus = await getCheckInCooldownStatus();
      if (!cooldownStatus.canCheckIn) {
        throw cooldownStatus.message;
      }


      // 1. Önce kullanıcı bilgilerini al
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        return false;
      }
      
      final userData = userDoc.data()!;
      final userName = userData['name'] ?? 'İsimsiz';
      final userPhoto = userData['mainPhoto'];
      final userAge = userData['age'] ?? 25;
      

      // 2. Fotoğrafı Firebase Storage'a upload et (check-in öncesi)
      String? imageUrl;
      try {
        imageUrl = await uploadImageToStorage(image, user.uid);
        if (imageUrl != null) {
        } else {
        }
      } catch (uploadError) {
      }

      // 3. Firebase'e check-in dokümanı kaydet (fotoğraf ile)
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docRef = await _firestore.collection('check_ins').add({
        'userId': user.uid,
        'venueId': venue.id,
        'venueName': venue.name,
        'checkInTime': FieldValue.serverTimestamp(),
        'date': today, // Elmas muhtar kontrolü için gerekli
        'latitude': venue.location.latitude,
        'longitude': venue.location.longitude,
        'fromFavorite': false,
        'hasPhoto': true,
        'photoPath': image.path, // Local path
        'photoUrl': imageUrl, // Firebase Storage URL (null olabilir)
      });


      // 4. Photo check-in'i discover sistemi için history'e de kaydet
      try {
        await _firestore.collection('check_in_history').add({
          'userId': user.uid,
          'venueId': venue.id,
          'venueName': venue.name,
          'checkInTime': FieldValue.serverTimestamp(),
          'date': today,
          'latitude': venue.location.latitude,
          'longitude': venue.location.longitude,
          'fromFavorite': false,
          'hasPhoto': true,
          'photoPath': image.path,
          'photoUrl': imageUrl,
          'originalCheckInId': docRef.id,
          'forDiscoverMatching': true,
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        });
      } catch (historyError) {
        // Check-in devam etsin, sadece discover history kaydetme başarısız oldu
      }

      // 5. User check-in listesini güncelle
      userCheckedInVenues.add(venue.id);
      
      // 6. Kullanıcının totalCheckIns sayısını artır
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'totalCheckIns': FieldValue.increment(1),
          'lastCheckInDate': FieldValue.serverTimestamp(),
        });
      } catch (statsError) {
      }
      
      // 7. Günlük muhtar kontrolü ve ataması
      try {
        await checkAndAssignDailyMayor(venue.id, user.uid, userName, userPhoto, venueName: venue.name);
      } catch (mayorError) {
      }

      // 8. Feed post oluştur (fotoğraf ile)
      try {
        await createFeedPost(
          userId: user.uid,
          userName: userName,
          userAge: userAge,
          userProfileImage: userPhoto ?? '',
          venueName: venue.name,
          venueAddress: venue.vicinity,
          venueCategory: venue.category,
          venueId: venue.id, // Venue'nin Place ID'si
          latitude: venue.location.latitude,
          longitude: venue.location.longitude,
          postImage: imageUrl, // Firebase Storage URL (null olabilir)
          caption: '${venue.name} mekanına fotoğraflı check-in yaptı',
        );
      } catch (feedError) {
      }

      return true;
      
    } catch (e) {
      return false;
    }
  }
}
