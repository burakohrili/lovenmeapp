// lib/core/services/diamond_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum DiamondPackage {
  small,   // 10 💎
  medium,  // 50 💎  
  large,   // 100 💎
  mega,    // 250 💎
}

class DiamondPackageInfo {
  final DiamondPackage type;
  final int diamonds;
  final double price;
  final String title;
  final String description;
  final int bonusDiamonds;
  final bool isPopular;

  DiamondPackageInfo({
    required this.type,
    required this.diamonds,
    required this.price,
    required this.title,
    required this.description,
    this.bonusDiamonds = 0,
    this.isPopular = false,
  });

  int get totalDiamonds => diamonds + bonusDiamonds;
}

class MayorshipBid {
  final String userId;
  final String userName;
  final String? userPhoto;
  final int diamonds;
  final DateTime bidTime;
  final bool isPremium;

  MayorshipBid({
    required this.userId,
    required this.userName,
    this.userPhoto,
    required this.diamonds,
    required this.bidTime,
    this.isPremium = false,
  });

  factory MayorshipBid.fromFirestore(Map<String, dynamic> data) {
    return MayorshipBid(
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'İsimsiz',
      userPhoto: data['userPhoto'],
      diamonds: data['diamonds'] ?? 0,
      bidTime: (data['bidTime'] as Timestamp).toDate(),
      isPremium: data['isPremium'] ?? false,
    );
  }
}

class DiamondService {
  static final DiamondService _instance = DiamondService._internal();
  factory DiamondService() => _instance;
  DiamondService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Elmas paketleri
  List<DiamondPackageInfo> get diamondPackages => [
    DiamondPackageInfo(
      type: DiamondPackage.small,
      diamonds: 10,
      price: 9.99,
      title: '10 Elmas',
      description: 'Başlangıç paketi',
    ),
    DiamondPackageInfo(
      type: DiamondPackage.medium,
      diamonds: 50,
      price: 39.99,
      title: '50 Elmas',
      description: '+5 bonus elmas',
      bonusDiamonds: 5,
      isPopular: true,
    ),
    DiamondPackageInfo(
      type: DiamondPackage.large,
      diamonds: 100,
      price: 69.99,
      title: '100 Elmas',
      description: '+15 bonus elmas',
      bonusDiamonds: 15,
    ),
    DiamondPackageInfo(
      type: DiamondPackage.mega,
      diamonds: 250,
      price: 149.99,
      title: '250 Elmas',
      description: '+50 bonus elmas',
      bonusDiamonds: 50,
    ),
  ];

  // Kullanıcının elmas bakiyesini getir
  Future<int> getUserDiamondBalance(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return 0;
      
      final data = userDoc.data()!;
      return data['diamondBalance'] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // Elmas satın alma (Google Pay ile)
  Future<bool> purchaseDiamonds(DiamondPackageInfo package) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Kullanıcı giriş yapmamış');

      // Şimdilik simülasyon
      await Future.delayed(const Duration(seconds: 2));

      // Satın alma kaydını Firestore'a kaydet
      await _firestore.collection('diamond_purchases').add({
        'userId': user.uid,
        'packageType': package.type.toString(),
        'diamonds': package.diamonds,
        'bonusDiamonds': package.bonusDiamonds,
        'totalDiamonds': package.totalDiamonds,
        'price': package.price,
        'currency': 'TRY',
        'purchaseDate': FieldValue.serverTimestamp(),
        'paymentMethod': 'google_pay',
        'status': 'completed',
      });

      // Kullanıcının elmas bakiyesini güncelle
      await _firestore.collection('users').doc(user.uid).update({
        'diamondBalance': FieldValue.increment(package.totalDiamonds),
        'totalDiamondsEarned': FieldValue.increment(package.totalDiamonds),
        'lastDiamondPurchase': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // Mekana elmas yatır (muhtarlık için)
  Future<bool> bidForMayorship(String venueId, String venueName, int diamonds) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Kullanıcı giriş yapmamış');

      // Kullanıcının elmas bakiyesini kontrol et
      final currentBalance = await getUserDiamondBalance(user.uid);
      if (currentBalance < diamonds) {
        throw Exception('Yetersiz elmas bakiyesi');
      }

      // Kullanıcı bilgilerini al
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw Exception('Kullanıcı bulunamadı');

      final userData = userDoc.data()!;
      String userName = userData['name'] ?? 'İsimsiz';
      if (userData['surname'] != null && userData['surname'].toString().isNotEmpty) {
        userName = '$userName ${userData['surname'].toString()[0]}.';
      }

      String? userPhoto;
      if (userData['photos'] != null && userData['photos'] is List) {
        final photos = userData['photos'] as List;
        if (photos.isNotEmpty) {
          userPhoto = photos[0].toString();
        }
      }

      // Mevcut en yüksek teklifi kontrol et
      final currentMayorDoc = await _firestore
          .collection('venue_mayorships')
          .doc(venueId)
          .get();

      int currentHighestBid = 0;
      if (currentMayorDoc.exists) {
        currentHighestBid = currentMayorDoc.data()?['highestBid'] ?? 0;
      }

      // Yeni teklifin daha yüksek olması gerekiyor
      if (diamonds <= currentHighestBid) {
        throw Exception('Teklifiniz mevcut en yüksek tekliften ($currentHighestBid 💎) daha yüksek olmalıdır');
      }

      // Transaction ile güncelle
      await _firestore.runTransaction((transaction) async {
        // Kullanıcının elmasını düş
        transaction.update(
          _firestore.collection('users').doc(user.uid),
          {
            'diamondBalance': FieldValue.increment(-diamonds),
            'totalDiamondsSpent': FieldValue.increment(diamonds),
          },
        );

        // Muhtarlık teklifini güncelle
        transaction.set(
          _firestore.collection('venue_mayorships').doc(venueId),
          {
            'venueId': venueId,
            'venueName': venueName,
            'mayorUserId': user.uid,
            'mayorUserName': userName,
            'mayorUserPhoto': userPhoto,
            'highestBid': diamonds,
            'bidTime': FieldValue.serverTimestamp(),
            'isPremium': userData['isPremium'] ?? false,
            'expiresAt': _getMayorshipExpiryTime(),
            'isActive': true,
          },
        );

        // Teklif geçmişi
        transaction.set(
          _firestore.collection('mayorship_bids').doc(),
          {
            'venueId': venueId,
            'venueName': venueName,
            'userId': user.uid,
            'userName': userName,
            'userPhoto': userPhoto,
            'diamonds': diamonds,
            'bidTime': FieldValue.serverTimestamp(),
            'isPremium': userData['isPremium'] ?? false,
            'isWinning': true, // Şu anda kazanan teklif
          },
        );

        // Eski kazanan teklifi güncelle
        if (currentMayorDoc.exists) {
          final previousMayorId = currentMayorDoc.data()?['mayorUserId'];
          if (previousMayorId != null && previousMayorId != user.uid) {
            // Önceki kazanan teklifleri güncelle
            final previousBidsQuery = await _firestore
                .collection('mayorship_bids')
                .where('venueId', isEqualTo: venueId)
                .where('userId', isEqualTo: previousMayorId)
                .where('isWinning', isEqualTo: true)
                .get();
            
            for (var doc in previousBidsQuery.docs) {
              transaction.update(doc.reference, {'isWinning': false});
            }
          }
        }
      });

      return true;
    } catch (e) {
      rethrow;
    }
  }

  // Muhtarlık bitiş zamanını hesapla (mekana göre değişebilir)
  Timestamp _getMayorshipExpiryTime() {
    final now = DateTime.now();
    // Varsayılan: Ertesi gün sabah 6'ya kadar
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 6, 0);
    return Timestamp.fromDate(tomorrow);
  }

  // Mekanın mevcut muhtarlık durumunu getir
  Future<Map<String, dynamic>?> getVenueMayorship(String venueId) async {
    try {
      final mayorshipDoc = await _firestore
          .collection('venue_mayorships')
          .doc(venueId)
          .get();

      if (!mayorshipDoc.exists) return null;

      final data = mayorshipDoc.data()!;
      
      // Süre kontrolü
      final expiresAt = data['expiresAt'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        // Muhtarlık süresi dolmuş, temizle
        await _firestore.collection('venue_mayorships').doc(venueId).update({
          'isActive': false,
        });
        return null;
      }

      return data;
    } catch (e) {
      return null;
    }
  }

  // Mekanın teklif geçmişini getir
  Future<List<MayorshipBid>> getVenueBidHistory(String venueId) async {
    try {
      final bidsQuery = await _firestore
          .collection('mayorship_bids')
          .where('venueId', isEqualTo: venueId)
          .orderBy('bidTime', descending: true)
          .limit(10)
          .get();

      return bidsQuery.docs
          .map((doc) => MayorshipBid.fromFirestore(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Kullanıcının muhtarlık geçmişini getir
  Future<List<Map<String, dynamic>>> getUserMayorshipHistory(String userId) async {
    try {
      final mayorshipsQuery = await _firestore
          .collection('mayorship_bids')
          .where('userId', isEqualTo: userId)
          .orderBy('bidTime', descending: true)
          .limit(20)
          .get();

      return mayorshipsQuery.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Kullanıcının aktif muhtarlıklarını getir
  Future<List<Map<String, dynamic>>> getUserActiveMayorships(String userId) async {
    try {
      final now = Timestamp.now();
      final mayorshipsQuery = await _firestore
          .collection('venue_mayorships')
          .where('mayorUserId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .where('expiresAt', isGreaterThan: now)
          .get();

      return mayorshipsQuery.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Elmas harcama geçmişi
  Future<List<Map<String, dynamic>>> getDiamondSpendingHistory(String userId) async {
    try {
      final spendingQuery = await _firestore
          .collection('mayorship_bids')
          .where('userId', isEqualTo: userId)
          .orderBy('bidTime', descending: true)
          .limit(50)
          .get();

      return spendingQuery.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
        'type': 'mayorship_bid',
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
