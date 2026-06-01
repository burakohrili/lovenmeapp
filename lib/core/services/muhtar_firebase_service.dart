import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Muhtar sistemi için Firebase servis sınıfı
class MuhtarFirebaseService {
  static final MuhtarFirebaseService _instance =
      MuhtarFirebaseService._internal();
  factory MuhtarFirebaseService() => _instance;
  MuhtarFirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Kullanıcının elmas bakiyesini getir
  Future<int> getUserDiamondBalance() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 0;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return 0;

      final data = userDoc.data()!;
      // Hem diamonds hem de diamondBalance hem de diamondCount field'larını kontrol et
      final balance = data['diamonds'] ??
          data['diamondBalance'] ??
          data['diamondCount'] ??
          0;
      return balance;
    } catch (e) {
      return 0;
    }
  }

  /// Kullanıcının elmas bakiyesini güncelle
  Future<bool> updateUserDiamondBalance(int newBalance) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      await _firestore.collection('users').doc(user.uid).update({
        'diamonds': newBalance,
        'diamondCount': newBalance, // Backup field
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Kullanıcının elmas bakiyesine diamond ekle
  Future<bool> addUserDiamonds(int diamondAmount) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Önce mevcut bakiyeyi al
      final currentBalance = await getUserDiamondBalance();
      final newBalance = currentBalance + diamondAmount;

      // Firebase'de bakiyeyi güncelle
      await _firestore.collection('users').doc(user.uid).update({
        'diamonds': newBalance,
        'diamondCount': newBalance, // Backup field
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Diamond transaction log'u ekle
      await _firestore.collection('diamond_transactions').add({
        'userId': user.uid,
        'amount': diamondAmount,
        'type': 'purchase',
        'previousBalance': currentBalance,
        'newBalance': newBalance,
        'timestamp': FieldValue.serverTimestamp(),
        'method': 'google_pay', // veya credit_card
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Elmas satın alma işlemi
  Future<bool> purchaseDiamonds({
    required int amount,
    required double price,
    required String transactionId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final batch = _firestore.batch();

      // Diamond transaction kaydı oluştur (yeni koleksiyon yapısına göre)
      final transactionRef =
          _firestore.collection('diamond_transactions').doc();
      batch.set(transactionRef, {
        'userId': user.uid,
        'transactionType': 'purchase',
        'amount': amount,
        'description': '$amount elmas satın alındı',
        'createdAt': FieldValue.serverTimestamp(),
        'paymentMethod': 'Google Pay', // Platform-specific olacak
        'packageType': '${amount}_diamonds_${price.toInt()}TL',
        'relatedId': transactionId,
      });

      // Kullanıcının mevcut bakiyesini al ve güncelle
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final currentBalance =
          userDoc.exists ? (userDoc.data()!['diamonds'] ?? 0) : 0;

      batch.update(_firestore.collection('users').doc(user.uid), {
        'diamonds': currentBalance + amount,
        'diamondCount': currentBalance + amount,
        'totalDiamondsEarned': FieldValue.increment(amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mekânın mevcut muhtar bilgisini getir
  Future<Map<String, dynamic>?> getVenueMayor(String venueId) async {
    try {
      final mayorDoc =
          await _firestore.collection('venue_mayors').doc(venueId).get();

      if (!mayorDoc.exists) return null;

      final data = mayorDoc.data()!;

      // Kullanıcı bilgisini de getir
      final userDoc =
          await _firestore.collection('users').doc(data['userId']).get();

      if (!userDoc.exists) return null;

      final userData = userDoc.data()!;

      return {
        'userId': data['userId'],
        'userName': userData['displayName'] ?? 'Anonim',
        'userPhoto': userData['photoURL'],
        'bidAmount': data['bidAmount'],
        'becameMayorAt': data['becameMayorAt'],
        'totalBids': data['totalBids'] ?? 1,
      };
    } catch (e) {
      return null;
    }
  }

  /// Mekânın aktif tekliflerini getir
  Future<List<Map<String, dynamic>>> getVenueBids(String venueId) async {
    try {
      final bidsQuery = await _firestore
          .collection('mayor_bids')
          .where('venueId', isEqualTo: venueId)
          .orderBy('bidAmount', descending: true)
          .orderBy('bidTime', descending: true)
          .limit(10)
          .get();

      List<Map<String, dynamic>> bids = [];

      for (var bidDoc in bidsQuery.docs) {
        final bidData = bidDoc.data();

        // Kullanıcı bilgisini getir
        final userDoc =
            await _firestore.collection('users').doc(bidData['userId']).get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          bids.add({
            'bidId': bidDoc.id,
            'userId': bidData['userId'],
            'userName': userData['displayName'] ?? 'Anonim',
            'userPhoto': userData['photoURL'],
            'bidAmount': bidData['bidAmount'],
            'bidTime': bidData['bidTime'],
            'isActive': bidData['isActive'] ?? true,
          });
        }
      }

      return bids;
    } catch (e) {
      return [];
    }
  }

  /// Muhtar teklifini ver
  Future<bool> placeMayorBid({
    required String venueId,
    required String venueName,
    required int bidAmount,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Kullanıcının elmas bakiyesini kontrol et
      final currentBalance = await getUserDiamondBalance();
      if (currentBalance < bidAmount) {
        throw Exception('Yetersiz elmas bakiyesi');
      }

      final batch = _firestore.batch();

      // Teklif kaydı oluştur
      final bidRef = _firestore.collection('mayor_bids').doc();
      batch.set(bidRef, {
        'userId': user.uid,
        'venueId': venueId,
        'venueName': venueName,
        'bidAmount': bidAmount,
        'bidTime': FieldValue.serverTimestamp(),
        'isActive': true,
        'bidType': 'normal', // normal veya buyNow
      });

      // Kullanıcının elmas bakiyesini düş
      batch.update(_firestore.collection('users').doc(user.uid), {
        'diamonds': currentBalance - bidAmount,
        'diamondCount': currentBalance - bidAmount, // Backup field
        'totalDiamondsSpent': FieldValue.increment(bidAmount),
        'lastDiamondUpdate': FieldValue.serverTimestamp(),
      });

      // Mevcut en yüksek teklifi kontrol et ve gerekirse muhtar değiştir
      final currentMayor = await getVenueMayor(venueId);
      if (currentMayor == null || bidAmount > currentMayor['bidAmount']) {
        // Bu kullanıcıyı yeni muhtar yap
        batch.set(_firestore.collection('venue_mayors').doc(venueId), {
          'userId': user.uid,
          'venueId': venueId,
          'venueName': venueName,
          'bidAmount': bidAmount,
          'becameMayorAt': FieldValue.serverTimestamp(),
          'totalBids': (currentMayor?['totalBids'] ?? 0) + 1,
        });

        // Eski muhtarın elmaslarını iade et (varsa)
        if (currentMayor != null) {
          final oldMayorDoc = await _firestore
              .collection('users')
              .doc(currentMayor['userId'])
              .get();

          if (oldMayorDoc.exists) {
            final oldBalance = oldMayorDoc.data()!['diamonds'] ?? 0;
            batch.update(
                _firestore.collection('users').doc(currentMayor['userId']), {
              'diamonds': oldBalance + currentMayor['bidAmount'],
              'diamondCount':
                  oldBalance + currentMayor['bidAmount'], // Backup field
            });
          }
        }
      }

      await batch.commit();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Buy Now işlemi (anında muhtar olma)
  Future<bool> buyNowMayor({
    required String venueId,
    required String venueName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Mevcut en yüksek teklifi al
      final currentMayor = await getVenueMayor(venueId);
      final currentHighestBid = currentMayor?['bidAmount'] ?? 0;
      final buyNowAmount = currentHighestBid * 2;

      // Kullanıcının elmas bakiyesini kontrol et
      final currentBalance = await getUserDiamondBalance();
      if (currentBalance < buyNowAmount) {
        throw Exception('Yetersiz elmas bakiyesi');
      }

      final batch = _firestore.batch();

      // Buy Now kaydı oluştur
      final bidRef = _firestore.collection('mayor_bids').doc();
      batch.set(bidRef, {
        'userId': user.uid,
        'venueId': venueId,
        'venueName': venueName,
        'bidAmount': buyNowAmount,
        'bidTime': FieldValue.serverTimestamp(),
        'isActive': true,
        'bidType': 'buyNow',
        'originalBidAmount': currentHighestBid,
      });

      // Kullanıcının elmas bakiyesini düş
      batch.update(_firestore.collection('users').doc(user.uid), {
        'diamonds': currentBalance - buyNowAmount,
        'diamondCount': currentBalance - buyNowAmount, // Backup field
        'totalDiamondsSpent': FieldValue.increment(buyNowAmount),
        'lastDiamondUpdate': FieldValue.serverTimestamp(),
      });

      // Bu kullanıcıyı muhtar yap
      batch.set(_firestore.collection('venue_mayors').doc(venueId), {
        'userId': user.uid,
        'venueId': venueId,
        'venueName': venueName,
        'bidAmount': buyNowAmount,
        'becameMayorAt': FieldValue.serverTimestamp(),
        'totalBids': (currentMayor?['totalBids'] ?? 0) + 1,
        'isBuyNow': true,
      });

      // Eski muhtarın elmaslarını iade et (varsa)
      if (currentMayor != null) {
        final oldMayorDoc = await _firestore
            .collection('users')
            .doc(currentMayor['userId'])
            .get();

        if (oldMayorDoc.exists) {
          final oldBalance = oldMayorDoc.data()!['diamonds'] ?? 0;
          batch.update(
              _firestore.collection('users').doc(currentMayor['userId']), {
            'diamonds': oldBalance + currentMayor['bidAmount'],
            'diamondCount':
                oldBalance + currentMayor['bidAmount'], // Backup field
          });
        }
      }

      await batch.commit();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Kullanıcının muhtar olduğu mekânları getir
  Future<List<Map<String, dynamic>>> getUserMayorVenues() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final mayorsQuery = await _firestore
          .collection('venue_mayors')
          .where('userId', isEqualTo: user.uid)
          .orderBy('becameMayorAt', descending: true)
          .get();

      return mayorsQuery.docs.map((doc) {
        final data = doc.data();
        return {
          'venueId': doc.id,
          'venueName': data['venueName'],
          'bidAmount': data['bidAmount'],
          'becameMayorAt': data['becameMayorAt'],
          'totalBids': data['totalBids'] ?? 1,
          'isBuyNow': data['isBuyNow'] ?? false,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Mekân muhtar durumunu real-time dinle
  Stream<Map<String, dynamic>?> listenToVenueMayor(String venueId) {
    return _firestore
        .collection('venue_mayors')
        .doc(venueId)
        .snapshots()
        .asyncMap((snapshot) async {
      if (!snapshot.exists) return null;

      final data = snapshot.data()!;

      // Kullanıcı bilgisini getir
      final userDoc =
          await _firestore.collection('users').doc(data['userId']).get();

      if (!userDoc.exists) return null;

      final userData = userDoc.data()!;

      return {
        'userId': data['userId'],
        'userName': userData['displayName'] ?? 'Anonim',
        'userPhoto': userData['photoURL'],
        'bidAmount': data['bidAmount'],
        'becameMayorAt': data['becameMayorAt'],
        'totalBids': data['totalBids'] ?? 1,
        'isBuyNow': data['isBuyNow'] ?? false,
      };
    });
  }

  /// Kullanıcının elmas bakiyesini real-time dinle
  Stream<int> listenToUserDiamondBalance() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(0);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 0;
      final data = snapshot.data()!;
      // Hem diamonds hem de diamondBalance hem de diamondCount field'larını kontrol et
      final balance = data['diamonds'] ??
          data['diamondBalance'] ??
          data['diamondCount'] ??
          0;
      return balance;
    });
  }

  /// Kullanıcının duplicate mayor kayıtlarını temizle
  Future<void> cleanupDuplicateMayorEntries() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Bugünkü tarihi al
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Kullanıcının bugünkü tüm mayor kayıtlarını al
      final mayorQuery = await _firestore
          .collection('daily_mayors')
          .where('userId', isEqualTo: user.uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      // Venue ID'ye göre grupla ve duplicate'leri bul
      final Map<String, List<QueryDocumentSnapshot>> venueGroups = {};

      for (final doc in mayorQuery.docs) {
        final venueId = doc.data()['venueId'] as String?;
        if (venueId != null) {
          venueGroups.putIfAbsent(venueId, () => []).add(doc);
        }
      }

      // Her venue için duplicate'leri temizle
      for (final entry in venueGroups.entries) {
        final venueId = entry.key;
        final docs = entry.value;

        if (docs.length > 1) {
          // En son kaydı bul (en yüksek diamond'a sahip olan veya en son oluşturulan)
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final aDiamonds = aData['diamondsSpent'] ?? 0;
            final bDiamonds = bData['diamondsSpent'] ?? 0;

            // Önce diamond sayısına göre sırala
            if (aDiamonds != bDiamonds) {
              return bDiamonds.compareTo(aDiamonds);
            }

            // Diamond sayısı aynıysa timestamp'e göre sırala
            final aTime = aData['assignedAt'] ?? aData['createdAt'];
            final bTime = bData['assignedAt'] ?? bData['createdAt'];

            if (aTime != null && bTime != null) {
              return (bTime as Timestamp).compareTo(aTime as Timestamp);
            }

            return 0;
          });

          // İlk kaydı sakla, geri kalanını sil
          final keepDoc = docs.first;
          final deleteCount = docs.length - 1;

          for (int i = 1; i < docs.length; i++) {
            await docs[i].reference.delete();
          }
        }
      }
    } catch (e) {}
  }
}
