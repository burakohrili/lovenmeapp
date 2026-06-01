// lib/core/services/payment_service.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/payment_models.dart';

enum PremiumPackage {
  monthly,
  threeMonths,
  sixMonths,
}

enum PurchaseType {
  premium,
  likes, // DEPRECATED
  superLikes, // DEPRECATED  
  superChats, // YENİ: Chat Request sistemi
  mayorshipBoost,
}

class PurchaseItem {
  final String id;
  final String title;
  final String description;
  final double price;
  final String currency;
  final PurchaseType type;
  final Map<String, dynamic> benefits;

  PurchaseItem({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.currency,
    required this.type,
    required this.benefits,
  });
}

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Premium paketleri
  List<PurchaseItem> get premiumPackages => [
    PurchaseItem(
      id: 'premium_monthly',
      title: 'Premium Aylık',
      description: 'Sınırsız chat + özel özellikler',
      price: 49.99,
      currency: 'TRY',
      type: PurchaseType.premium,
      benefits: {
        'unlimitedChats': true,
        'premiumVisibility': true,
        'rewind': true,
        'noAds': true,
        'duration': 30,
      },
    ),
    PurchaseItem(
      id: 'premium_3months',
      title: 'Premium 3 Aylık',
      description: '3 aylık premium üyelik (%20 indirim)',
      price: 119.99,
      currency: 'TRY',
      type: PurchaseType.premium,
      benefits: {
        'unlimitedChats': true,
        'premiumVisibility': true,
        'rewind': true,
        'noAds': true,
        'duration': 90,
      },
    ),
    PurchaseItem(
      id: 'premium_6months',
      title: 'Premium 6 Aylık',
      description: '6 aylık premium üyelik (%35 indirim)',
      price: 194.99,
      currency: 'TRY',
      type: PurchaseType.premium,
      benefits: {
        'unlimitedChats': true,
        'premiumVisibility': true,
        'rewind': true,
        'noAds': true,
        'duration': 180,
      },
    ),
  ];

  // Super Chat paketleri - YENİ
  List<PurchaseItem> get superChatPackages => [
    PurchaseItem(
      id: 'super_chats_3',
      title: '3 Super Chat',
      description: '3 super chat hakkı',
      price: 89.99,
      currency: 'TRY',
      type: PurchaseType.superChats,
      benefits: {'superChats': 3},
    ),
    PurchaseItem(
      id: 'super_chats_10',
      title: '10 Super Chat',
      description: '10 super chat hakkı',
      price: 264.99,
      currency: 'TRY',
      type: PurchaseType.superChats,
      benefits: {'superChats': 10},
    ),
    PurchaseItem(
      id: 'super_chats_25',
      title: '25 Super Chat',
      description: '25 super chat hakkı',
      price: 599.99,
      currency: 'TRY',
      type: PurchaseType.superChats,
      benefits: {'superChats': 25},
    ),
  ];

  // Like paketleri - DEPRECATED
  @Deprecated('Use superChatPackages instead')
  List<PurchaseItem> get likePackages => [];

  // Super like paketleri - DEPRECATED
  @Deprecated('Use superChatPackages instead')
  List<PurchaseItem> get superLikePackages => [];

  // Muhtarlık boost paketleri
  List<PurchaseItem> get mayorshipBoostPackages => [
    PurchaseItem(
      id: 'mayorship_1day',
      title: '1 Günlük Muhtarlık Boost',
      description: 'Mekanda muhtarlık için ekstra puan',
      price: 14.99,
      currency: 'TRY',
      type: PurchaseType.mayorshipBoost,
      benefits: {
        'boostMultiplier': 2.0,
        'duration': 1,
        'priorityDisplay': true,
      },
    ),
    PurchaseItem(
      id: 'mayorship_3days',
      title: '3 Günlük Muhtarlık Boost',
      description: '3 gün muhtarlık boost (%30 indirim)',
      price: 29.99,
      currency: 'TRY',
      type: PurchaseType.mayorshipBoost,
      benefits: {
        'boostMultiplier': 2.5,
        'duration': 3,
        'priorityDisplay': true,
      },
    ),
    PurchaseItem(
      id: 'mayorship_week',
      title: '1 Haftalık Muhtarlık Boost',
      description: '1 hafta muhtarlık boost (%50 indirim)',
      price: 49.99,
      currency: 'TRY',
      type: PurchaseType.mayorshipBoost,
      benefits: {
        'boostMultiplier': 3.0,
        'duration': 7,
        'priorityDisplay': true,
      },
    ),
  ];

  // Satın alma işlemi simülasyonu (gerçek ödeme sistemi entegre edilecek)
  Future<bool> purchaseItem(PurchaseItem item) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Kullanıcı giriş yapmamış');

      // Gerçek ödeme işlemi burada yapılacak
      // Şimdilik simülasyon
      await Future.delayed(const Duration(seconds: 2));

      // Satın alma kaydını Firebase'e kaydet
      await _recordPurchase(user.uid, item);

      // Kullanıcının hesabını güncelle
      await _applyPurchaseBenefits(user.uid, item);

      return true;
    } catch (e) {
      return false;
    }
  }

  // Satın alma kaydını Firestore'a kaydet
  Future<void> _recordPurchase(String userId, PurchaseItem item) async {
    await _firestore.collection('purchases').add({
      'userId': userId,
      'itemId': item.id,
      'productId': item.id,
      'title': item.title,
      'price': item.price,
      'currency': item.currency,
      'type': item.type.toString(),
      'benefits': item.benefits,
      'purchaseDate': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'completed',
    });
  }

  // Satın alma faydalarını kullanıcı hesabına uygula
  Future<void> _applyPurchaseBenefits(String userId, PurchaseItem item) async {
    final userRef = _firestore.collection('users').doc(userId);
    
    switch (item.type) {
      case PurchaseType.premium:
        await _applyPremiumBenefits(userRef, item);
        break;
      case PurchaseType.likes:
        await _applyLikeBenefits(userRef, item);
        break;
      case PurchaseType.superLikes:
        await _applySuperLikeBenefits(userRef, item);
        break;
      case PurchaseType.superChats:
        await _applySuperChatBenefits(userRef, item);
        break;
      case PurchaseType.mayorshipBoost:
        await _applyMayorshipBoost(userRef, item);
        break;
    }
  }

  Future<void> _applyPremiumBenefits(DocumentReference userRef, PurchaseItem item) async {
    final duration = item.benefits['duration'] as int;
    final expiryDate = DateTime.now().add(Duration(days: duration));

    await userRef.update({
      'isPremium': true,
      'premiumUntil': Timestamp.fromDate(expiryDate), // ✅ Doğru field adı (premiumExpiryDate değil)
      'dailyRewindsRemaining': 3,
      'dailyChatRequestsRemaining': 999,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
  }

  Future<void> _applyLikeBenefits(DocumentReference userRef, PurchaseItem item) async {
    // DEPRECATED: Like sistemi kaldırıldı
  }

  Future<void> _applySuperLikeBenefits(DocumentReference userRef, PurchaseItem item) async {
    // DEPRECATED: Super Like sistemi kaldırıldı, IAP Service kullanılıyor
  }

  Future<void> _applySuperChatBenefits(DocumentReference userRef, PurchaseItem item) async {
    // 💬 YENİ: Super Chat sistemi - IAP Service atomic transaction kullanıyor
  }

  Future<void> _applyMayorshipBoost(DocumentReference userRef, PurchaseItem item) async {
    final duration = item.benefits['duration'] as int;
    final expiryDate = DateTime.now().add(Duration(days: duration));

    await userRef.update({
      'mayorshipBoost': {
        'isActive': true,
        'multiplier': item.benefits['boostMultiplier'],
        'expiryDate': Timestamp.fromDate(expiryDate),
        'priorityDisplay': item.benefits['priorityDisplay'],
      }
    });
  }

  // Premium durumunu kontrol et
  Future<bool> checkPremiumStatus(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return false;

      final data = userDoc.data()!;
      final isPremium = data['isPremium'] ?? false;
      
      if (!isPremium) return false;

      // Premium süresini kontrol et
      final expiryDate = data['premiumUntil'] as Timestamp?; // ✅ Doğru field adı
      if (expiryDate != null && expiryDate.toDate().isBefore(DateTime.now())) {
        await _firestore.collection('users').doc(userId).update({
          'isPremium': false,
          'dailyChatRequestsRemaining': 5,
        });
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // Muhtarlık boost durumunu kontrol et
  Future<Map<String, dynamic>?> checkMayorshipBoost(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return null;

      final data = userDoc.data()!;
      final boost = data['mayorshipBoost'] as Map<String, dynamic>?;
      
      if (boost == null || !(boost['isActive'] ?? false)) return null;

      final expiryDate = boost['expiryDate'] as Timestamp?;
      if (expiryDate != null && expiryDate.toDate().isBefore(DateTime.now())) {
        await _firestore.collection('users').doc(userId).update({
          'mayorshipBoost.isActive': false,
        });
        return null;
      }

      return boost;
    } catch (e) {
      return null;
    }
  }

  // Kullanıcının satın alma geçmişini getir
  Future<List<Map<String, dynamic>>> getPurchaseHistory(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('purchases')
          .where('userId', isEqualTo: userId)
          .orderBy('purchaseDate', descending: true)
          .get();

      return querySnapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Ödeme yöntemlerinin mevcut olup olmadığını kontrol et
  static Future<PaymentMethodAvailability> getPaymentMethodAvailability() async {
    try {
      bool googlePayAvailable = false;
      
      if (Platform.isAndroid) {
        googlePayAvailable = Platform.isAndroid;
      }
      
      return PaymentMethodAvailability(
        googlePayAvailable: googlePayAvailable,
        creditCardAvailable: true,
      );
    } catch (e) {
      return PaymentMethodAvailability(
        googlePayAvailable: false,
        creditCardAvailable: true,
      );
    }
  }

  // Tercih edilen ödeme yöntemini al
  static PaymentMethod getPreferredPaymentMethod() {
    if (Platform.isAndroid) {
      return PaymentMethod.googlePay;
    } else {
      return PaymentMethod.creditCard;
    }
  }

  // Fiyatı formatla
  static String formatPrice(double price) {
    return '₺${price.toStringAsFixed(2)}';
  }

  // İndirim yüzdesini formatla
  static String formatDiscountPercentage(double percentage) {
    return '%${percentage.toInt()} İndirim';
  }

  // Google Pay ile ödeme işle
  static Future<PaymentResult> processGooglePayPayment(dynamic package) async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      
      return PaymentResult(
        success: true,
        transactionId: 'gp_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      return PaymentResult(
        success: false,
        errorMessage: 'Google Pay hatası: $e',
      );
    }
  }

  // Kredi kartı ile ödeme işle
  static Future<PaymentResult> processCreditCardPayment(dynamic package) async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      
      return PaymentResult(
        success: true,
        transactionId: 'cc_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      return PaymentResult(
        success: false,
        errorMessage: 'Kredi kartı ödeme hatası: $e',
      );
    }
  }
}
