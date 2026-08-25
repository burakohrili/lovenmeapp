// lib/core/services/premium_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/premium_models.dart';

class PremiumService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Premium abonelik satın al
  static Future<bool> purchasePremiumSubscription({
    required PremiumSubscriptionType type,
    required String transactionId,
  }) async {
    try {
      
      final user = _auth.currentUser;
      if (user == null) throw Exception('Kullanıcı oturumu bulunamadı');

      final now = DateTime.now();
      
      // Mevcut aktif premium aboneliği kontrol et
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      bool hasActivePremium = false;
      DateTime? currentPremiumEnd;
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        hasActivePremium = userData['isPremium'] ?? false;
        final premiumUntil = userData['premiumUntil'] as Timestamp?;
        currentPremiumEnd = premiumUntil?.toDate();
        
        // Premium süresini kontrol et
        if (hasActivePremium && currentPremiumEnd != null && currentPremiumEnd.isBefore(now)) {
          hasActivePremium = false; // Süresi dolmuş
        }
      }
      
      // Yeni premium'ın başlangıç ve bitiş tarihlerini hesapla
      DateTime subscriptionStartDate;
      DateTime subscriptionEndDate;
      bool isQueuedSubscription = false;
      
      if (hasActivePremium && currentPremiumEnd != null) {
        // Aktif premium var, yeni premium'ı kuyruğa al
        subscriptionStartDate = currentPremiumEnd; // Mevcut premium bitince başla
        subscriptionEndDate = _calculateEndDate(type, subscriptionStartDate);
        isQueuedSubscription = true;
      } else {
        // Aktif premium yok, hemen başlat
        subscriptionStartDate = now;
        subscriptionEndDate = _calculateEndDate(type, subscriptionStartDate);
      }
      

      // Premium subscription kaydı oluştur
      final subscriptionData = {
        'userId': user.uid,
        'type': type.name,
        'purchaseDate': Timestamp.fromDate(now), // Satın alma tarihi
        'startDate': Timestamp.fromDate(subscriptionStartDate), // Abonelik başlangıç tarihi
        'endDate': Timestamp.fromDate(subscriptionEndDate), // Abonelik bitiş tarihi
        'isActive': !isQueuedSubscription, // Kuyruktakiler aktif değil
        'isQueued': isQueuedSubscription, // Kuyruğa alındı mı?
        'autoRenew': true,
        'paymentMethod': 'google_play',
        'transactionId': transactionId,
        'createdAt': Timestamp.fromDate(now),
      };

      // Premium subscriptions collection'a ekle
      await _firestore.collection('premium_subscriptions').add(subscriptionData);

      // Sadece aktif premium ise user'ı güncelle (kuyruktakiler güncellenmez)
      if (!isQueuedSubscription) {
        await _firestore.collection('users').doc(user.uid).update({
          'isPremium': true,
          'premiumType': type.name, // Premium tipini kaydet (weekly/monthly/quarterly)
          'premiumUntil': Timestamp.fromDate(subscriptionEndDate),
          'dailyRewindsRemaining': 3, // 🔄 Premium'da günde 3 geri alma
          'dailyChatRequestsRemaining': 999, // Genişletilmiş bağlantı isteği
          'updatedAt': Timestamp.fromDate(now),
        });
      } else {
        // Kuyruktaki premium - güncelleme yok, aktifleşince Cloud Function halleder
        await _firestore.collection('users').doc(user.uid).update({
          'updatedAt': Timestamp.fromDate(now),
        });
      }

      if (isQueuedSubscription) {
      } else {
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Kullanıcının Premium durumunu kontrol et
  static Future<bool> isPremiumActive() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data()!;
      final isPremium = userData['isPremium'] ?? false;
      final premiumUntil = userData['premiumUntil'] as Timestamp?;

      if (!isPremium || premiumUntil == null) return false;

      final now = DateTime.now();
      final expiryDate = premiumUntil.toDate();


      // Premium süresi dolmuşsa false döndür ve durumu güncelle
      if (now.isAfter(expiryDate)) {
        await _expirePremiumSubscription();
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Premium durumunu kontrol et ve expire olanları iptal et
  static Future<void> checkAndUpdatePremiumStatus() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data()!;
      final isPremium = userData['isPremium'] ?? false;
      final premiumUntil = userData['premiumUntil'] as Timestamp?;

      if (isPremium && premiumUntil != null) {
        final now = DateTime.now();
        final expiryDate = premiumUntil.toDate();

        // Premium süresi dolmuşsa
        if (now.isAfter(expiryDate)) {
          await _expirePremiumSubscription();
        }
      }
    } catch (e) {
    }
  }

  /// Premium aboneliği iptal et (süresi dolduğunda)
  static Future<void> _expirePremiumSubscription() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'isPremium': false,
        'premiumType': null,
        'premiumUntil': null,
        'dailyRewindsRemaining': 0, // Günlük geri alma hakkı kaldırılır
        'dailyChatRequestsRemaining': 5, // 💬 Normal kullanıcı limitine döner
        // superChatsRemaining: unchanged - IAP paketler korunur
        'updatedAt': Timestamp.now(),
      });

      // Aktif subscription'ı deaktive et
      final subscriptions = await _firestore
          .collection('premium_subscriptions')
          .where('userId', isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in subscriptions.docs) {
        await doc.reference.update({
          'isActive': false,
          'expiredAt': Timestamp.now(),
        });
      }

    } catch (e) {
    }
  }

  /// Kullanıcının premium durumunu al
  static Future<PremiumStatus> getPremiumStatus() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return PremiumStatus(isPremium: false);
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        return PremiumStatus(isPremium: false);
      }

      final userData = userDoc.data()!;
      final isPremium = userData['isPremium'] ?? false;
      final premiumTypeString = userData['premiumType'] as String?;
      final premiumUntil = userData['premiumUntil'] as Timestamp?;
      final purchasedSuperChats = userData['superChatsRemaining'] ?? 0; // 💬 IAP ile satın alınan super chat'ler
      final dailyRewindsRemaining = userData['dailyRewindsRemaining'] ?? 0; // 🔄 Günlük geri alma

      // Premium type'ı enum'a çevir
      PremiumSubscriptionType? premiumType;
      if (premiumTypeString != null) {
        try {
          premiumType = PremiumSubscriptionType.values.firstWhere(
            (e) => e.name == premiumTypeString,
          );
        } catch (e) {
        }
      }

      return PremiumStatus(
        isPremium: isPremium,
        premiumType: premiumType,
        expiryDate: premiumUntil?.toDate(),
        superChatsRemaining: purchasedSuperChats, // 💬 IAP ile satın alınan super chat'ler
        rewindsRemaining: dailyRewindsRemaining, // 🔄 Günlük geri alma hakkı
      );
    } catch (e) {
      return PremiumStatus(isPremium: false);
    }
  }

  /// DEPRECATED: Super like sistemi kaldırıldı, Super Chat kullanın
  @Deprecated('Use canUseSuperChat() instead - Like system removed')
  static Future<bool> canUseSuperLike() async {
    return false;
  }

  /// Super chat kullanıp kullanamayacağını kontrol et (IAP paketlerinden)
  static Future<bool> canUseSuperChat() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;

      final superChatsRemaining = userDoc.data()?['superChatsRemaining'] ?? 0;
      return superChatsRemaining > 0;
    } catch (e) {
      return false;
    }
  }

  /// Geri alma kullanıp kullanamayacağını kontrol et
  static Future<bool> canUseRewind() async {
    try {
      final status = await getPremiumStatus();
      return status.isPremium && status.rewindsRemaining > 0;
    } catch (e) {
      return false;
    }
  }

  /// DEPRECATED: Super like sistemi kaldırıldı
  @Deprecated('Like system removed - use Super Chat with IAP')
  static Future<bool> useSuperLike() async {
    return false;
  }

  /// DEPRECATED: Super like integrity check - artık kullanılmıyor
  @Deprecated('Like system removed')
  static Future<bool> verifySuperLikeIntegrity() async {
    return true;
  }

  /// Geri alma kullan - ATOMIC TRANSACTION ile günlük limit kontrolü
  static Future<bool> useRewind() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return false;
      }

      final userRef = _firestore.collection('users').doc(user.uid);
      
      // 🔒 ATOMIC TRANSACTION - Race condition koruması
      return await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          return false;
        }

        final userData = userDoc.data()!;
        final isPremium = userData['isPremium'] ?? false;
        final dailyRewindsRemaining = userData['dailyRewindsRemaining'] ?? 0;

        // Premium kontrolü
        if (!isPremium) {
          return false;
        }

        // Günlük limit kontrolü
        if (dailyRewindsRemaining <= 0) {
          return false;
        }

        // 🔒 ATOMIC UPDATE - Kesin bir şekilde 1 azalt
        transaction.update(userRef, {
          'dailyRewindsRemaining': dailyRewindsRemaining - 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final remainingRewinds = dailyRewindsRemaining - 1;
        return true;
      });
    } catch (e) {
      return false;
    }
  }

  /// DEPRECATED: Super like debug - sistem kaldırıldı
  @Deprecated('Like system removed')
  static Future<void> debugSuperLikeSystem() async {
  }

  // Helper methods
  static DateTime _calculateEndDate(PremiumSubscriptionType type, DateTime start) {
    switch (type) {
      case PremiumSubscriptionType.weekly:
        return start.add(const Duration(days: 7));
      case PremiumSubscriptionType.monthly:
        return DateTime(start.year, start.month + 1, start.day);
      case PremiumSubscriptionType.quarterly:
        return DateTime(start.year, start.month + 3, start.day);
    }
  }

  /// Kullanıcının kuyrukta bekleyen premium aboneliklerini getir
  static Future<List<QueuedPremiumSubscription>> getQueuedSubscriptions() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final queuedSnapshot = await _firestore
          .collection('premium_subscriptions')
          .where('userId', isEqualTo: user.uid)
          .where('isQueued', isEqualTo: true)
          .orderBy('startDate', descending: false) // En yakın başlayacaklar önce
          .get();

      return queuedSnapshot.docs.map((doc) {
        final data = doc.data();
        return QueuedPremiumSubscription.fromMap(doc.id, data);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Tüm premium abonelikleri getir (aktif + kuyruk)
  static Future<List<PremiumSubscriptionInfo>> getAllSubscriptions() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final allSnapshot = await _firestore
          .collection('premium_subscriptions')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return allSnapshot.docs.map((doc) {
        final data = doc.data();
        return PremiumSubscriptionInfo.fromMap(doc.id, data);
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
