// lib/presentation/pages/explore_nearby/services/explore_nearby_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/explore_venue_model.dart';
import '../models/venue_detail_model.dart';

class ExploreNearbyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🎯 CACHE: Memory cache for venues
  static final Map<String, List<ExploreVenue>> _venueCache = {};
  static DateTime? _lastCacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// 🎯 CACHE: Cache'den al veya yükle
  Future<List<ExploreVenue>> getCachedUserCheckedInVenues(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();

    // Cache geçerliyse ve force refresh değilse cache'den dön
    if (!forceRefresh &&
        _venueCache.containsKey(userId) &&
        _lastCacheTime != null &&
        now.difference(_lastCacheTime!) < _cacheDuration) {
      return _venueCache[userId]!;
    }

    final venues = await getUserCheckedInVenues(userId);

    // Cache'e kaydet
    _venueCache[userId] = venues;
    _lastCacheTime = now;

    return venues;
  }

  /// 🔄 CACHE: Manuel cache temizleme
  static void clearCache() {
    _venueCache.clear();
    _lastCacheTime = null;
  }

  /// Kullanıcının check-in yaptığı mekanları getirir - OPTIMIZED VERSION
  /// Batch query ile tüm veriyi tek seferde çeker
  Future<List<ExploreVenue>> getUserCheckedInVenues(
    String userId, {
    int? limit,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();

      // 🎯 PAGINATION: Query builder
      Query checkInsQuery = _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: userId)
          .orderBy('checkInTime', descending: true);

      // Pagination desteği
      if (lastDocument != null) {
        checkInsQuery = checkInsQuery.startAfterDocument(lastDocument);
      }

      if (limit != null) {
        checkInsQuery = checkInsQuery.limit(limit);
      }

      // 1. Normal check-in'leri getir
      final checkInsSnapshot = await checkInsQuery.get();

      // 2. Favori mekanlardan gelen permanent check-in'leri getir
      final favoriteCheckInsSnapshot = await _firestore
          .collection('favorite_venue_history')
          .where('userId', isEqualTo: userId)
          .where('isPermanent', isEqualTo: true)
          .get();

      // 3. Benzersiz venue ID'leri topla (hem normal hem favori check-in'lerden)
      final venueIds = <String>{};

      // Normal check-in'ler
      for (var doc in checkInsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final venueId = data['venueId'] as String?;
          if (venueId != null) {
            venueIds.add(venueId);
          }
        }
      }

      // Favori mekanlardan gelen check-in'ler
      for (var doc in favoriteCheckInsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final venueId = data['venueId'] as String?;
          if (venueId != null) {
            venueIds.add(venueId);
          }
        }
      }

      if (venueIds.isEmpty) {
        return [];
      }

      // 4. BATCH: Tüm venue bilgilerini tek seferde çek (max 10 at a time for Firestore limit)
      final venuesList = venueIds.toList();
      final venuesData = <String, Map<String, dynamic>>{};

      // Firestore'da "in" query 10 item limit var, chunk'lara bölelim
      for (var i = 0; i < venuesList.length; i += 10) {
        final chunk = venuesList.skip(i).take(10).toList();
        final venuesSnapshot = await _firestore
            .collection('venues')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (var doc in venuesSnapshot.docs) {
          venuesData[doc.id] = doc.data();
        }
      }

      // 5. BATCH: Son 30 günün TÜM check-in'lerini tek query'de al
      final today = DateTime.now();
      final thirtyDaysAgo = today.subtract(const Duration(days: 30));

      final allCheckInsSnapshot = await _firestore
          .collection('check_ins')
          .where('checkInTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .get();

      // Venue ID'ye göre gruplayalım
      final checkInsByVenue = <String, List<Map<String, dynamic>>>{};
      for (var doc in allCheckInsSnapshot.docs) {
        final data = doc.data();
        final venueId = data['venueId'] as String?;
        if (venueId != null && venueIds.contains(venueId)) {
          checkInsByVenue.putIfAbsent(venueId, () => []).add(data);
        }
      }

      // 6. Her venue için ExploreVenue oluştur
      // Kullanıcı ve mayor bilgileri için hala tekil query gerekiyor
      final venues = <ExploreVenue>[];
      for (var venueId in venueIds) {
        try {
          final venueData = venuesData[venueId];
          if (venueData == null) continue;

          final checkIns = checkInsByVenue[venueId] ?? [];

          // Benzersiz kullanıcı sayısı
          final uniqueUserIds = checkIns
              .map((c) => c['userId'] as String?)
              .where((id) => id != null)
              .toSet();
          final totalCheckIns = uniqueUserIds.length;

          // Son check-in zamanı
          DateTime? lastCheckInTime;
          if (checkIns.isNotEmpty) {
            final timestamps = checkIns
                .map((c) => c['checkInTime'] as Timestamp?)
                .where((t) => t != null)
                .map((t) => t!.toDate())
                .toList();

            if (timestamps.isNotEmpty) {
              timestamps.sort((a, b) => b.compareTo(a));
              lastCheckInTime = timestamps.first;
            }
          }

          // Kullanıcıları ve mayor bilgisini getir (bu kısım hala gerekli)
          final recentUsers = await getCheckedInUsersForVenue(
            venueId: venueId,
            limit: 3,
          );

          // Mayor bilgisi
          CheckedInUserPreview? mayor;
          try {
            mayor = recentUsers.firstWhere((user) => user.isMayor);
          } catch (e) {
            mayor = null;
          }

          // Favori kontrolü
          bool isFavorite = false;
          try {
            final favoriteCheckIns = await _firestore
                .collection('favorite_venue_history')
                .where('userId', isEqualTo: userId)
                .where('venueId', isEqualTo: venueId)
                .where('isPermanent', isEqualTo: true)
                .limit(1)
                .get();

            isFavorite = favoriteCheckIns.docs.isNotEmpty;
          } catch (e) {
            // Favori kontrolü hatası göz ardı edilebilir
          }

          final venue = ExploreVenue(
            id: venueId,
            name: venueData['name'] ?? 'Unknown Venue',
            category: venueData['category'] ?? 'other',
            photoUrl: _getFirstPhoto(venueData),
            totalCheckIns: totalCheckIns,
            recentUsers: recentUsers,
            mayorName: mayor?.name,
            mayorPhotoUrl: mayor?.photoUrl,
            isUserMayor: mayor?.userId == userId,
            isFavorite: isFavorite,
            lastCheckInTime: lastCheckInTime ?? DateTime.now(),
            isSponsored: venueData['isSponsored'] ?? false,
            description: venueData['description'],
            latitude: venueData['latitude']?.toDouble(),
            longitude: venueData['longitude']?.toDouble(),
          );

          venues.add(venue);
        } catch (e) {
          continue;
        }
      }

      // 7. Sırala: Sponsor → Muhtar olduğum → Check-in sayısı → Tarih
      venues.sort((a, b) => a.compareTo(b));

      stopwatch.stop();

      return venues;
    } catch (e) {
      rethrow;
    }
  }

  /// Bir mekan için muhtarı belirler (daily_mayors koleksiyonundan)
  /// MAP PAGE İLE AYNI YÖNTEM: date field ile query yap
  Future<CheckedInUserPreview?> getMayorForVenue(String venueId) async {
    try {
      // MAP PAGE YÖNTEMİ: date field ile bugünün mayor'larını getir
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // date field ile query yap (document ID değil!)
      final mayorsSnapshot = await _firestore
          .collection('daily_mayors')
          .where('venueId', isEqualTo: venueId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      if (mayorsSnapshot.docs.isEmpty) {
        return null;
      }

      // En yüksek diamond'lı mayor'u seç
      DocumentSnapshot? bestMayorDoc;
      int highestDiamonds = -1;

      for (var doc in mayorsSnapshot.docs) {
        final data = doc.data();
        final diamonds = data['diamondsSpent'] ?? 0;

        if (diamonds > highestDiamonds) {
          highestDiamonds = diamonds;
          bestMayorDoc = doc;
        }
      }

      if (bestMayorDoc == null) {
        return null;
      }

      final mayorData = bestMayorDoc.data() as Map<String, dynamic>;
      final mayorUserId = mayorData['userId'] as String;
      final mayorType = mayorData['mayorType'] as String? ?? 'first_checkin';
      final diamondsSpent = mayorData['diamondsSpent'] ?? 0;

      // Kullanıcı bilgilerini getir
      final userDoc =
          await _firestore.collection('users').doc(mayorUserId).get();

      if (!userDoc.exists) {
        return null;
      }

      final userData = userDoc.data()!;

      final isDiamondMayor = mayorType == 'diamond';

      return CheckedInUserPreview(
        userId: mayorUserId,
        name: userData['name'] ?? 'User',
        photoUrl: _getFirstPhoto(userData),
        isMayor: true,
        isDiamondMayor: isDiamondMayor,
        checkInTime: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Bir mekanda check-in yapan kullanıcıları getirir (son 30 gün)
  Future<List<CheckedInUserPreview>> getCheckedInUsersForVenue({
    required String venueId,
    int limit = 3,
  }) async {
    try {
      // Son 30 günün check-in'lerini getir
      final today = DateTime.now();
      final thirtyDaysAgo = today.subtract(const Duration(days: 30));

      final checkInsSnapshot = await _firestore
          .collection('check_ins')
          .where('venueId', isEqualTo: venueId)
          .where('checkInTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .orderBy('checkInTime', descending: true)
          .limit(50)
          .get();

      if (checkInsSnapshot.docs.isEmpty) {
        return [];
      }

      // Benzersiz kullanıcı ID'lerini topla
      final userIds = <String>{};
      for (var doc in checkInsSnapshot.docs) {
        final userId = doc.data()['userId'] as String?;
        if (userId != null) {
          userIds.add(userId);
        }
      }

      // Muhtarı getir
      final mayor = await getMayorForVenue(venueId);
      final mayorId = mayor?.userId;

      // Kullanıcı bilgilerini getir
      final users = <CheckedInUserPreview>[];

      for (var userId in userIds.take(limit)) {
        try {
          final userDoc =
              await _firestore.collection('users').doc(userId).get();

          if (!userDoc.exists) continue;

          final userData = userDoc.data()!;
          final isMayor = userId == mayorId;

          // Bu kullanıcının son check-in zamanını bul
          final userCheckIns = checkInsSnapshot.docs
              .where((doc) => doc.data()['userId'] == userId)
              .toList();
          DateTime lastCheckIn = DateTime.now();
          if (userCheckIns.isNotEmpty) {
            final timestamp =
                userCheckIns.first.data()['checkInTime'] as Timestamp?;
            if (timestamp != null) {
              lastCheckIn = timestamp.toDate();
            }
          }

          users.add(CheckedInUserPreview(
            userId: userId,
            name: userData['name'] ?? 'User',
            photoUrl: _getFirstPhoto(userData),
            isMayor: isMayor,
            isDiamondMayor: isMayor && (mayor?.isDiamondMayor ?? false),
            checkInTime: lastCheckIn,
          ));
        } catch (e) {
          continue;
        }
      }

      // Muhtarı en başa al
      users.sort((a, b) {
        if (a.isMayor && !b.isMayor) return -1;
        if (!a.isMayor && b.isMayor) return 1;
        return b.checkInTime.compareTo(a.checkInTime);
      });

      return users;
    } catch (e) {
      return [];
    }
  }

  /// Venue detay sayfası için tam bilgileri getirir
  Future<VenueDetail?> getVenueDetail(String venueId) async {
    try {
      // 1. Venue bilgilerini getir
      final venueDoc = await _firestore.collection('venues').doc(venueId).get();

      if (!venueDoc.exists) {
        return null;
      }

      final venueData = venueDoc.data()!;

      // 2. Son 30 günün check-in'lerini getir
      final today = DateTime.now();
      final thirtyDaysAgo = today.subtract(const Duration(days: 30));

      final checkInsSnapshot = await _firestore
          .collection('check_ins')
          .where('venueId', isEqualTo: venueId)
          .where('checkInTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .orderBy('checkInTime', descending: true)
          .get();

      // 3. Benzersiz kullanıcı ID'leri ve check-in sayıları (son 30 gün)
      final userCheckInCounts = <String, int>{};
      final userLastCheckIns = <String, DateTime>{};

      for (var doc in checkInsSnapshot.docs) {
        final userId = doc.data()['userId'] as String?;
        final checkInTime = (doc.data()['checkInTime'] as Timestamp?)?.toDate();

        if (userId != null && checkInTime != null) {
          userCheckInCounts[userId] = (userCheckInCounts[userId] ?? 0) + 1;

          // En son check-in zamanını kaydet
          if (!userLastCheckIns.containsKey(userId) ||
              checkInTime.isAfter(userLastCheckIns[userId]!)) {
            userLastCheckIns[userId] = checkInTime;
          }
        }
      }

      // 4. Muhtarı belirle
      final mayor = await getMayorForVenue(venueId);

      // 5. Kullanıcı listesini oluştur
      final venueUsers = <VenueUser>[];
      for (var entry in userCheckInCounts.entries) {
        try {
          final userDoc =
              await _firestore.collection('users').doc(entry.key).get();

          if (!userDoc.exists) {
            continue;
          }

          final userData = userDoc.data()!;
          final isMayor = entry.key == mayor?.userId;

          venueUsers.add(VenueUser(
            userId: entry.key,
            name: userData['name'] ?? 'User',
            surname: userData['surname'],
            age: userData['age'] ?? 18,
            photoUrl: _getFirstPhoto(userData),
            photos: _getPhotos(userData),
            bio: userData['bio'],
            gender: userData['gender'],
            isPremium: userData['isPremium'] ?? false,
            isMayor: isMayor,
            isDiamondMayor: isMayor && (mayor?.isDiamondMayor ?? false),
            checkInCount: entry.value,
            lastCheckIn: userLastCheckIns[entry.key] ?? DateTime.now(),
          ));
        } catch (e) {
          continue;
        }
      }

      // Muhtar önce, sonra check-in sayısına göre sırala
      venueUsers.sort((a, b) {
        if (a.isMayor && !b.isMayor) return -1;
        if (!a.isMayor && b.isMayor) return 1;
        return b.checkInCount.compareTo(a.checkInCount);
      });

      // 6. VenueDetail oluştur
      final firstPhoto = _getFirstPhoto(venueData);
      final allPhotos = _getPhotos(venueData);

      return VenueDetail(
        id: venueId,
        name: venueData['name'] ?? 'Unknown Venue',
        category: venueData['category'] ?? 'other',
        photoUrl: firstPhoto,
        photos: allPhotos,
        rating: venueData['rating']?.toDouble(),
        vicinity: venueData['vicinity'],
        description: venueData['description'],
        formattedAddress: venueData['formattedAddress'],
        phoneNumber: venueData['phoneNumber'],
        website: venueData['website'],
        features: _getFeatures(venueData),
        checkedInUsers: venueUsers,
        totalCheckInCount: checkInsSnapshot.docs.length,
        mayorUserId: mayor?.userId,
        mayorName: mayor?.name,
        mayorPhotoUrl: mayor?.photoUrl,
        mayorCheckIns: mayor != null ? userCheckInCounts[mayor.userId] ?? 0 : 0,
        isDiamondMayor: mayor?.isDiamondMayor ?? false,
        isSponsored: venueData['isSponsored'] ?? false,
        sponsorLogoUrl: venueData['sponsorLogoUrl'],
        sponsorBadgeText: venueData['sponsorBadgeText'],
        sponsorDescription: venueData['sponsorDescription'],
        latitude: venueData['latitude']?.toDouble(),
        longitude: venueData['longitude']?.toDouble(),
      );
    } catch (e) {
      return null;
    }
  }

  /// İlk fotoğrafı getirir
  String? _getFirstPhoto(Map<String, dynamic> data) {
    if (data['photos'] != null && data['photos'] is List) {
      final photos = List<String>.from(data['photos']);
      if (photos.isNotEmpty) {
        return photos[0];
      }
    }
    return data['photoUrl'] as String?;
  }

  /// Tüm fotoğrafları getirir
  List<String> _getPhotos(Map<String, dynamic> data) {
    if (data['photos'] != null && data['photos'] is List) {
      return List<String>.from(data['photos']);
    }
    return [];
  }

  /// Features listesini getirir
  List<String> _getFeatures(Map<String, dynamic> data) {
    if (data['features'] != null && data['features'] is List) {
      return List<String>.from(data['features']);
    }
    // Varsayılan features (kategori bazlı)
    return VenueDetail.getDefaultFeatures(data['category'] ?? 'other');
  }
}
