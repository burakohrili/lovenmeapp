// lib/core/services/iap_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _isPurchaseInProgress = false; // 🆕 Spam koruması
  final List<PurchaseDetails> _purchases = [];
  
  // 🛡️ Purchase deduplication - aynı purchase'ın birden fazla işlenmesini önler
  final Set<String> _processedPurchases = <String>{};

  // UI Callback sistemi
  VoidCallback? _onPurchaseSuccess;
  ValueChanged<String>? _onPurchaseError;
  String? _currentPurchaseProductId;
  Timer? _purchaseTimeout; // 🛡️ Purchase timeout protection
  
  // Restore purchases counter
  int _restoredItemsCount = 0;

    // ✅ UPDATED: App Store Connect'teki tüm mevcut ürünler
  static const Map<String, String> _productIds = {
    // Premium Subscriptions ✅
    'premium_weekly': 'com.lovenme.premium.weekly',
    'premium_monthly': 'com.lovenme.premium.monthly',
    'premium_quarterly': 'com.lovenme.premium.quarterly',
    
    // Diamonds - ESKİ PAKETLER ✅
    'diamonds_10': 'com.lovenme.diamonds.tenpack',
    'diamonds_50': 'com.lovenme.diamonds.fiftypack',
    'diamonds_100': 'com.lovenme.diamonds.hundredpack',
    
    // Diamonds - YENİ PAKETLER ✨
    'diamonds_250': 'com.lovenme.diamonds.twfiftypack',
    'diamonds_500': 'com.lovenme.diamonds.fivehundredpack',
    
    // Super Chats 💬 Chat Request System
    'super_chats_3': 'com.lovenme.superchats.threepacks',
    'super_chats_10': 'com.lovenme.superchats.tenpacks',
    'super_chats_25': 'com.lovenme.superchats.twentyfivepacks',
  };

  // Product Details
  Map<String, Map<String, dynamic>> get productInfo => {
    'premium_weekly': {
      'title': 'Premium Haftalık',
      'description': 'Sınırsız chat isteği, özel özellikler',
      'price': 99.99,
      'duration': '7 gün',
      'features': [
        'Sınırsız chat isteği',
        'Check-in yapanların profillerini gör',
        'Check-in yapmadan kişileri görebilme',
        'Geçmiş check-in\'leri görüntüle',
        '3 Süper Chat hakkı (Tek seferlik)'
      ],
    },
    'premium_monthly': {
      'title': 'Premium Aylık',
      'description': 'En popüler seçenek! Sınırsız özellikler',
      'price': 299.99,
      'duration': '30 gün',
      'features': [
        'Sınırsız chat isteği',
        'Check-in yapanların profillerini gör',
        'Check-in yapmadan kişileri görebilme',
        'Geçmiş check-in\'leri görüntüle',
        '10 Süper Chat hakkı (Tek seferlik)'
      ],
    },
    'premium_quarterly': {
      'title': 'Premium 3 Aylık',
      'description': '%44 tasarruf! Lansman özel fiyatı',
      'price': 499.99,
      'duration': '90 gün',
      'features': [
        'Sınırsız chat isteği',
        'Check-in yapanların profillerini gör',
        'Check-in yapmadan kişileri görebilme',
        'Geçmiş check-in\'leri görüntüle',
        '30 Süper Chat hakkı (Tek seferlik)'
      ],
    },
    
    // Diamonds - ESKİ PAKETLER ✅
    'diamonds_10': {
      'title': '10 Elmas',
      'description': 'Premium özellikler için elmas',
      'price': 74.99, // ✅ Fiyat güncellendi: 79.99 → 74.99
      'quantity': 10,
    },
    'diamonds_50': {
      'title': '50 Elmas',
      'description': 'Premium özellikler için elmas',
      'price': 249.99, // ✅ Fiyat güncellendi: 299.99 → 249.99
      'quantity': 50,
    },
    'diamonds_100': {
      'title': '100 Elmas',
      'description': 'Premium özellikler için elmas',
      'price': 499.99,
      'quantity': 100,
    },
    
    // Diamonds - YENİ PAKETLER ✨
    'diamonds_250': {
      'title': 'Standart - 250 Elmas',
      'description': 'En çok tercih edilen elmas paketi',
      'price': 999.99,
      'quantity': 250,
    },
    'diamonds_500': {
      'title': 'Efsane - 500 Elmas',
      'description': 'En avantajlı elmas paketi',
      'price': 1499.99,
      'quantity': 500,
    },
    
    // Super Chats 💬 Chat Request System
    'super_chats_3': {
      'title': '3 Super Chat',
      'description': 'Özel mesajla öne çık ve fark yarat',
      'price': 74.99,
      'quantity': 3,
      'features': [
        '3 adet Super Chat hakkı',
        '20 karakterlik özel mesaj',
        'Anında dikkat çek',
        'Match şansını artır'
      ],
    },
    'super_chats_10': {
      'title': '10 Super Chat',
      'description': 'Daha fazla bağlantı için ideal paket',
      'price': 219.99,
      'quantity': 10,
      'features': [
        '10 adet Super Chat hakkı',
        '20 karakterlik özel mesaj',
        'Daha fazla match fırsatı',
        'En popüler paket'
      ],
    },
    'super_chats_25': {
      'title': '25 Super Chat',
      'description': 'Maximum etki için en büyük paket',
      'price': 499.99,
      'quantity': 25,
      'features': [
        '25 adet Super Chat hakkı',
        '20 karakterlik özel mesaj',
        'Sınırsız bağlantı imkanı',
        'En avantajlı fiyat'
      ],
    },
  };

  // Getters
  bool get isAvailable => _isAvailable;
  bool get purchasePending => _purchasePending;
  List<ProductDetails> get products => _products;
  List<PurchaseDetails> get purchases => _purchases;

  /// Initialize In-App Purchase
  Future<void> initialize() async {
    
    try {
      final available = await _inAppPurchase.isAvailable();
      if (!available) {
        _isAvailable = false;
        return;
      }

      _isAvailable = true;

      // Platform-specific setup
      if (Platform.isIOS) {
        final InAppPurchaseStoreKitPlatformAddition iosAddition =
            _inAppPurchase.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
        await iosAddition.setDelegate(IAPPaymentQueueDelegate());
      } else if (Platform.isAndroid) {
        // Android-specific setup
        await _setupAndroidSpecific();
      }

      // Listen to purchase updates
      _subscription = _inAppPurchase.purchaseStream.listen(
        _handlePurchaseUpdates,
        onDone: () => _subscription.cancel(),
        onError: (error) {
        },
      );

      // Clear any pending transactions FIRST (Real device için kritik)
      await _clearPendingTransactions();
      
      // 🛡️ DEDUPLICATION: Service restart'ta processed purchases'ı temizle
      final oldCount = _processedPurchases.length;
      _processedPurchases.clear();

      // Load products
      await _loadProducts();
      
      // Restore purchases - only for iOS and only for subscriptions (AFTER clearing)
      if (Platform.isIOS) {
        await _restorePurchases();
      }

    } catch (e) {
      _isAvailable = false;
    }
  }

  /// Load products from store
  Future<void> _loadProducts() async {
    try {
      final Set<String> productIds = _productIds.values.toSet();

      final ProductDetailsResponse response = 
          await _inAppPurchase.queryProductDetails(productIds);

      if (response.error != null) {
        return;
      }

      _products = response.productDetails;
      
      for (final product in _products) {
      }

      if (response.notFoundIDs.isNotEmpty) {
      }
    } catch (e) {
    }
  }

  /// Restore purchases (for subscriptions) - PUBLIC METHOD for Guideline 3.1.1
  /// Returns the number of items restored
  Future<int> restorePurchases() async {
    try {
      
      // iOS için restore purchases
      if (Platform.isIOS) {
        // Restore edilen ürün sayısını takip et
        _restoredItemsCount = 0;
        await _inAppPurchase.restorePurchases();
        
        // Stream'den gelen restore işlemlerinin tamamlanması için kısa bir bekleme
        await Future.delayed(const Duration(milliseconds: 1500));
        
        return _restoredItemsCount;
      } else {
        return 0;
      }
    } catch (e) {
      rethrow; // Hatayı UI'a bildir
    }
  }

  /// Restore purchases (for subscriptions) - INTERNAL
  Future<void> _restorePurchases() async {
    try {
      
      // iOS için restore purchases
      if (Platform.isIOS) {
        await _inAppPurchase.restorePurchases();
      } else {
      }
    } catch (e) {
      // Restore hatası önemli değil, devam et
    }
  }

  /// Android-specific setup for In-App Purchases
  Future<void> _setupAndroidSpecific() async {
    try {
      
      // Android'de pending purchases'ları temizle (kritik)
      await _clearAndroidPendingPurchases();
      
    } catch (e) {
      // Bu hata kritik değil, devam et
    }
  }

  /// Clear pending purchases specifically for Android
  Future<void> _clearAndroidPendingPurchases() async {
    try {
      
      // Android'de pending purchase'ları otomatik handle et
      await _inAppPurchase.restorePurchases();
      
      // Mevcut pending transactions kontrol et
      
    } catch (e) {
    }
  }

  /// Clear pending transactions (for duplicate issue resolution)
  Future<void> _clearPendingTransactions() async {
    try {
      
      if (Platform.isIOS) {
        // iOS'ta pending transactions'ları otomatik temizle
        // Mevcut pending transactions'ları al ve complete et
        final transactions = await SKPaymentQueueWrapper().transactions();
        for (final transaction in transactions) {
          if (transaction.transactionState == SKPaymentTransactionStateWrapper.failed ||
              transaction.transactionState == SKPaymentTransactionStateWrapper.purchasing) {
            await SKPaymentQueueWrapper().finishTransaction(transaction);
          }
        }
        
      }
    } catch (e) {
      // Bu hata kritik değil, devam et
    }
  }

  /// Handle purchase updates
  void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
      } else {
        _purchasePending = false;
        _isPurchaseInProgress = false; // 🛡️ Purchase tamamlandı - spam koruması reset
        
        if (purchaseDetails.status == PurchaseStatus.error) {
          _handlePurchaseError(purchaseDetails);
        } else if (purchaseDetails.status == PurchaseStatus.purchased) {
          _handlePurchaseSuccess(purchaseDetails);
        } else if (purchaseDetails.status == PurchaseStatus.restored) {
          _handlePurchaseRestore(purchaseDetails);
        } else if (purchaseDetails.status == PurchaseStatus.canceled) {
          
          // 🆕 UI Canceled Callback çağır - ALWAYS call reset callbacks
          _onPurchaseError?.call('Satın alma iptal edildi');
          _resetCallbacks();
        }
      }

      // Complete the purchase - SADECE başarılı veya restored purchases için
      if (purchaseDetails.pendingCompletePurchase && 
          (purchaseDetails.status == PurchaseStatus.purchased || 
           purchaseDetails.status == PurchaseStatus.restored)) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  /// Handle successful purchase
  Future<void> _handlePurchaseSuccess(PurchaseDetails purchaseDetails) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // 🛡️ DEDUPLICATION: Purchase ID ile duplikasyon kontrolü
      final purchaseKey = '${purchaseDetails.purchaseID}_${purchaseDetails.productID}';
      if (_processedPurchases.contains(purchaseKey)) {
        return;
      }

      // Purchase'ı processed listesine ekle
      _processedPurchases.add(purchaseKey);


      // 🚨 ATOMIC: Apply benefits (otomatik rollback ile)
      await _applyPurchaseBenefits(user.uid, purchaseDetails);

      // 🚨 ATOMIC: Record purchase (benefits başarılıysa kaydet)
      await _recordPurchase(user.uid, purchaseDetails);

      
      // Verify the benefits were applied
      await _verifyBenefitsApplied(user.uid, purchaseDetails.productID);
      
      // 🆕 UI Callback çağır
      if (_currentPurchaseProductId == purchaseDetails.productID) {
        _onPurchaseSuccess?.call();
        _resetCallbacks();
      }
      
    } catch (e) {
      
      // 🚨 CRITICAL ERROR: Para çekildi ama benefit uygulanamadı
      // Bu durumda user'a özel mesaj ver ve support'a yönlendir
      
      // 🆕 UI Error Callback çağır
      if (_currentPurchaseProductId == purchaseDetails.productID) {
        final criticalError = 'Satın alma tamamlandı ancak hesabınıza yansıtılamadı. '
                              'Lütfen müşteri hizmetleriyle iletişime geçin. '
                              'İşlem ID: ${purchaseDetails.purchaseID}';
        _onPurchaseError?.call(criticalError);
        _resetCallbacks();
      }
      
      // 🚨 Log critical error for monitoring
      await _logCriticalError(purchaseDetails, e);
      
      // 🛡️ DEDUPLICATION: Error durumunda purchase'ı processed listesinden çıkar
      final purchaseKey = '${purchaseDetails.purchaseID}_${purchaseDetails.productID}';
      _processedPurchases.remove(purchaseKey);
    }
  }

  /// Handle restored purchase (iOS) - RESTORE BENEFITS ✅
  Future<void> _handlePurchaseRestore(PurchaseDetails purchaseDetails) async {
    try {
      
      final user = _auth.currentUser;
      if (user == null) {
        return;
      }

      // ✅ RESTORE: Check if subscription is still active and restore benefits
      final isActive = await _checkSubscriptionActive(purchaseDetails);
      
      if (isActive) {
        
        // Determine subscription type from productId
        if (purchaseDetails.productID.contains('premium')) {
          // Premium subscription restore
          await _restorePremiumSubscription(user.uid, purchaseDetails);
          _restoredItemsCount++; // Restore edilen ürün sayısını artır
        } else {
          // Other product types (Super Chat, Diamonds, etc.)
          await _restoreConsumableProduct(user.uid, purchaseDetails);
          _restoredItemsCount++; // Restore edilen ürün sayısını artır
        }
        
      } else {
      }
      
    } catch (e) {
      // Restore hatası kritik değil, sessizce devam et
    }
  }

  /// Check if restored subscription is still active
  Future<bool> _checkSubscriptionActive(PurchaseDetails purchaseDetails) async {
    try {
      // For iOS, check with App Store receipt validation
      // For now, we'll check Firestore premium status
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;

      final data = userDoc.data()!;
      final isPremium = data['isPremium'] ?? false;
      
      // ✅ FIXED: Use premiumUntil instead of premiumExpiryDate (consistent with codebase)
      final expiryDate = data['premiumUntil'] as Timestamp?;

      if (!isPremium || expiryDate == null) return false;

      // Check if not expired
      final isNotExpired = expiryDate.toDate().isAfter(DateTime.now());
      return isNotExpired;
    } catch (e) {
      return false;
    }
  }

  /// Restore premium subscription benefits
  /// ⚠️ IMPORTANT: Restore does NOT add new time, only verifies existing subscription
  Future<void> _restorePremiumSubscription(String userId, PurchaseDetails purchaseDetails) async {
    try {
      // 🔍 Get current user premium status
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw 'User document not found';
      }

      // ✅ CRITICAL: Restore only updates sync fields, does NOT change expiry date
      // The expiry date should already be set from original purchase
      // We're just confirming the subscription is still active
      await _firestore.collection('users').doc(userId).update({
        'isPremium': true, // Confirm premium status
        'premiumRestoredAt': FieldValue.serverTimestamp(), // Log restore time
        'lastPremiumRestoreProductId': purchaseDetails.productID, // Track product
        // ⚠️ IMPORTANT: premiumUntil is NOT modified here
        // It keeps the original expiry date from the actual purchase
      });

    } catch (e) {
      rethrow;
    }
  }

  /// Restore consumable products (Super Chats, Diamonds)
  /// ⚠️ IMPORTANT: Each purchase can only be restored once per user (duplicate prevention)
  Future<void> _restoreConsumableProduct(String userId, PurchaseDetails purchaseDetails) async {
    try {
      
      // ✅ DUPLICATE PREVENTION: Check if already restored to prevent duplicates
      final existingRestore = await _firestore
          .collection('restored_purchases')
          .where('userId', isEqualTo: userId)
          .where('purchaseId', isEqualTo: purchaseDetails.purchaseID)
          .limit(1)
          .get();

      if (existingRestore.docs.isNotEmpty) {
        return; // ❌ 2nd restore attempt blocked
      }


      // Add benefits based on product type
      if (purchaseDetails.productID.contains('superchat')) {
        final quantity = _getProductQuantity(purchaseDetails.productID);
        await _firestore.collection('users').doc(userId).update({
          'superChatsRemaining': FieldValue.increment(quantity),
        });
      } else if (purchaseDetails.productID.contains('diamond')) {
        final quantity = _getProductQuantity(purchaseDetails.productID);
        await _firestore.collection('users').doc(userId).update({
          'diamonds': FieldValue.increment(quantity),
        });
      }

      // Log restore to prevent duplicates
      await _firestore.collection('restored_purchases').add({
        'userId': userId,
        'purchaseId': purchaseDetails.purchaseID,
        'productId': purchaseDetails.productID,
        'restoredAt': FieldValue.serverTimestamp(),
      });

    } catch (e) {
      rethrow;
    }
  }

  /// Get product quantity from product ID
  int _getProductQuantity(String productId) {
    // Önce internal product ID'sini bul
    String? internalId;
    for (final entry in _productIds.entries) {
      if (entry.value == productId) {
        internalId = entry.key;
        break;
      }
    }
    
    // productInfo'dan quantity'yi al
    if (internalId != null && productInfo.containsKey(internalId)) {
      final info = productInfo[internalId];
      if (info != null && info.containsKey('quantity')) {
        return info['quantity'] as int;
      }
    }
    
    // Fallback: product ID'den parse et
    final parts = productId.split('_');
    if (parts.length >= 2) {
      return int.tryParse(parts.last) ?? 1;
    }
    return 1;
  }

  /// Verify that benefits were actually applied
  Future<void> _verifyBenefitsApplied(String userId, String productId) async {
    try {
      
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        
        if (productId.contains('premium')) {
          final isPremium = data['isPremium'] ?? false;
          final premiumUntil = data['premiumUntil'] as Timestamp?;
        } else if (productId.contains('diamonds') || productId.contains('diamond')) {
          // Diamond balans alanı uygulamada 'balance' olarak tutuluyor; eski alanı da fallback olarak kontrol et
          final balance = data['balance'] ?? data['diamonds'] ?? 0;
        } else if (productId.contains('superchats') || productId.contains('super_chat')) {
          // Satın alınan super chat'ler 'superChatsRemaining' alanında birikir
          final purchased = data['superChatsRemaining'] ?? 0;
          
          // 🛡️ Type safety check
          final safePurchased = (purchased is double) ? purchased.toInt() : purchased as int;
          
          // 🔍 Additional integrity check
          if (safePurchased < 0) {
          }
        }
      } else {
      }
    } catch (e) {
    }
  }

  /// Handle purchase error
  void _handlePurchaseError(PurchaseDetails purchaseDetails) {
    final error = purchaseDetails.error;
    
    // 🛡️ CRITICAL: ALWAYS reset loading states first, regardless of error type
    _purchasePending = false;
    _isPurchaseInProgress = false;
    
    // iOS specific error handling - Güvenli casting
    if (Platform.isIOS && error?.details != null) {
      try {
        final details = error!.details;
        if (details is Map) {
          final detailsMap = Map<String, dynamic>.from(details);
          if (detailsMap.containsKey('NSLocalizedDescription')) {
          }
          if (detailsMap.containsKey('NSUnderlyingError')) {
          }
        }
      } catch (e) {
      }
    }
    
    // Android specific error handling 
    if (Platform.isAndroid && error?.details != null) {
      try {
        final details = error!.details.toString();
        
        if (details.contains('BillingResponse.developerError') || error.code == 'purchase_error') {
          
          // Kullanıcıya daha anlaşılır mesaj
          if (_currentPurchaseProductId == purchaseDetails.productID) {
            const friendlyMessage = 'Debug modu hatası: Release build gerekli veya Play Console test gerekli. '
                                  'Detaylar için debug log\'a bakın.';
            _onPurchaseError?.call(friendlyMessage);
            _resetCallbacks();
          }
          return;
        }
      } catch (e) {
      }
    }
    
    // Specific error code handling
    if (error?.code == 'purchase_error') {
    }
    
    // 🆕 UI Error Callback çağır - ALWAYS call this for ANY error
    String errorMessage = 'Satın alma başarısız';
    if (error?.code == 'user_cancelled') {
      errorMessage = 'Satın alma iptal edildi';
    } else if (error?.message != null) {
      errorMessage = 'Hata: ${error!.message}';
    }

    // 🤖 Android özel: billingUnavailable için net mesaj
    if (Platform.isAndroid) {
      final msg = (error?.message ?? '').toLowerCase();
      if (msg.contains('billingUnavailable') || msg.contains('billing_unavailable')) {
        errorMessage = 'Google Play faturalandırma servis geçici olarak kullanılamıyor. Lütfen birkaç dakika sonra tekrar deneyin.';
      } else if (msg.contains('itemAlreadyOwned') || msg.contains('item_already_owned')) {
        errorMessage = 'Bu ürün zaten satın alınmış. Premium özellikleriniz aktif olmalı.';
      } else if (msg.contains('developer_error') ||
          msg.contains('responsecode: 5') ||
          msg.contains('billingresponsecode: 5')) {
        errorMessage = 'Google Play ödeme yapılandırması uygun değil. Uygulamayı Play kapalı test bağlantısından yükleyin, tester hesabınızla giriş yapın ve Play Store önbelleğini temizleyip tekrar deneyin.';
      }
    }
    
    _onPurchaseError?.call(errorMessage);
    _resetCallbacks();
  }

  /// Reset UI callbacks
  void _resetCallbacks() {
    _onPurchaseSuccess = null;
    _onPurchaseError = null;
    _currentPurchaseProductId = null;
    _isPurchaseInProgress = false; // 🛡️ Spam koruması da reset
    _cancelPurchaseTimeout(); // 🛡️ Timeout cancel
  }

  /// 🛡️ Purchase timeout başlat
  void _startPurchaseTimeout() {
    _cancelPurchaseTimeout(); // Önceki timeout'u iptal et
    
    _purchaseTimeout = Timer(const Duration(seconds: 30), () { // ✅ OPTIMIZED: 45 → 30 saniye
      if (_isPurchaseInProgress) {
        
        // Force reset all states
        _purchasePending = false;
        _isPurchaseInProgress = false;
        
        // 🛡️ DEDUPLICATION: Timeout durumunda processed purchases'ı temizle
        final oldCount = _processedPurchases.length;
        _processedPurchases.clear();
        
        const errorMessage = 'Satın alma zaman aşımına uğradı. Lütfen tekrar deneyin.';
        _onPurchaseError?.call(errorMessage);
        _resetCallbacks();
      }
    });
    
  }

  /// 🛡️ Purchase timeout iptal et
  void _cancelPurchaseTimeout() {
    _purchaseTimeout?.cancel();
    _purchaseTimeout = null;
  }

  /// Apply purchase benefits to user account - ATOMIC TRANSACTION
  Future<void> _applyPurchaseBenefits(String userId, PurchaseDetails purchaseDetails) async {
    final productId = purchaseDetails.productID;
    final userRef = _firestore.collection('users').doc(userId);

    // Find internal product ID
    String? internalProductId;
    for (final entry in _productIds.entries) {
      if (entry.value == productId) {
        internalProductId = entry.key;
        break;
      }
    }

    if (internalProductId == null) {
      throw Exception('Unknown product ID: $productId');
    }

    
    // Android premium özel debug
    if (Platform.isAndroid && internalProductId.startsWith('premium_')) {
    }

    // 🚨 ATOMIC TRANSACTION - All benefits applied together or none
    try {
      await _firestore.runTransaction((transaction) async {
        // İlk önce user document'ini oku
        final userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          throw Exception('User document not found: $userId');
        }

        final userData = userDoc.data()!;
        Map<String, dynamic> updates = {};

        // Product tipine göre benefit'leri hazırla
        switch (internalProductId!) {
          case 'premium_weekly':
            _preparePremiumUpdates(updates, userData, 'weekly', 7, 3); // 3 süper chat
            break;
          case 'premium_monthly':
            _preparePremiumUpdates(updates, userData, 'monthly', 30, 10); // 10 süper chat
            break;
          case 'premium_quarterly':
            _preparePremiumUpdates(updates, userData, 'quarterly', 90, 30); // 30 süper chat
            break;
          case 'super_chats_3': // 💬 Super Chat IAP
            _prepareSuperChatUpdates(updates, userData, 3);
            break;
          case 'super_chats_10': // 💬 NEW: Super Chat IAP
            _prepareSuperChatUpdates(updates, userData, 10);
            break;
          case 'super_chats_25': // 💬 NEW: Super Chat IAP
            _prepareSuperChatUpdates(updates, userData, 25);
            break;
          // 💎 Elmas Paketleri - ESKİ
          case 'diamonds_10':
            _prepareDiamondUpdates(updates, userData, 10);
            break;
          case 'diamonds_50':
            _prepareDiamondUpdates(updates, userData, 50);
            break;
          case 'diamonds_100':
            _prepareDiamondUpdates(updates, userData, 100);
            break;
          // 💎 Elmas Paketleri - YENİ
          case 'diamonds_250':
            _prepareDiamondUpdates(updates, userData, 250);
            break;
          case 'diamonds_500':
            _prepareDiamondUpdates(updates, userData, 500);
            break;
          default:
            throw Exception('Unsupported product: $internalProductId');
        }

        // Android premium özel debug
        if (Platform.isAndroid && internalProductId.startsWith('premium_')) {
        }

        // 🔥 ATOMIC UPDATE - Tek transaction'da tüm değişiklikler
        for (final entry in updates.entries) {
          if (entry.value is FieldValue) {
          } else {
          }
        }
        
        transaction.update(userRef, updates);
        
        
        // Android premium özel debug
        if (Platform.isAndroid && internalProductId.startsWith('premium_')) {
        }
      });

      
      // Android premium özel success debug
      if (Platform.isAndroid && internalProductId.startsWith('premium_')) {
      }
      
    } catch (e) {
      
      // Android premium özel error debug
      if (Platform.isAndroid && internalProductId.startsWith('premium_')) {
      }
      
      // Transaction otomatik olarak rollback oldu
      throw Exception('Benefits application failed: $e');
    }
  }

  /// Prepare premium benefits for atomic transaction
  void _preparePremiumUpdates(Map<String, dynamic> updates, Map<String, dynamic> userData, String type, int days, int superChatCount) {
    final now = DateTime.now();
    final expiryDate = now.add(Duration(days: days));

    updates.addAll({
      'isPremium': true,
      'premiumType': type,
      'premiumUntil': Timestamp.fromDate(expiryDate),
      'dailyChatRequestsRemaining': 999, // Sınırsız chat request
      'superChatsRemaining': FieldValue.increment(superChatCount), // 💬 Süper Chat hakkı (tek seferlik)
      'updatedAt': FieldValue.serverTimestamp(),
    });

  }

  /// 💬 Prepare Super Chat benefits for atomic transaction - Chat Request System
  void _prepareSuperChatUpdates(Map<String, dynamic> updates, Map<String, dynamic> userData, int count) {
    
    updates.addAll({
      'superChatsRemaining': FieldValue.increment(count), // 💬 Satın alınan super chat'ler
      'lastSuperChatPurchase': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

  }

  /// Prepare diamond benefits for atomic transaction
  void _prepareDiamondUpdates(Map<String, dynamic> updates, Map<String, dynamic> userData, int count) {
    updates.addAll({
      'balance': FieldValue.increment(count), // 💎 Elmas bakiyesi
      'updatedAt': FieldValue.serverTimestamp(),
    });

  }

  /// Log critical error for monitoring
  Future<void> _logCriticalError(PurchaseDetails purchaseDetails, dynamic error) async {
    try {
      await _firestore.collection('critical_errors').add({
        'type': 'iap_benefit_application_failed',
        'productId': purchaseDetails.productID,
        'purchaseId': purchaseDetails.purchaseID,
        'transactionDate': purchaseDetails.transactionDate,
        'userId': _auth.currentUser?.uid,
        'error': error.toString(),
        'timestamp': FieldValue.serverTimestamp(),
        'platform': Platform.isIOS ? 'ios' : 'android',
        'needsManualReview': true,
      });
      
    } catch (e) {
      // En azından console'da görelim
    }
  }

  /// Record purchase in Firestore
  Future<void> _recordPurchase(String userId, PurchaseDetails purchaseDetails) async {
    await _firestore.collection('purchases').add({
      'userId': userId,
      'productId': purchaseDetails.productID,
      'purchaseId': purchaseDetails.purchaseID,
      'transactionDate': purchaseDetails.transactionDate != null
          ? Timestamp.fromMillisecondsSinceEpoch(
              int.parse(purchaseDetails.transactionDate!))
          : FieldValue.serverTimestamp(),
      'source': Platform.isIOS ? 'ios_appstore' : 'android_playstore',
      'status': 'completed',
      'verificationData': purchaseDetails.verificationData.source,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Buy product
  Future<bool> buyProduct(
    String internalProductId, {
    VoidCallback? onSuccess,
    ValueChanged<String>? onError,
  }) async {
    // 🛡️ SPAM KORUMASI - Zaten bir işlem devam ediyorsa engelle
    if (_isPurchaseInProgress) {
      onError?.call('Zaten bir satın alma işlemi devam ediyor. Lütfen bekleyin.');
      return false;
    }

    // ⚙️ On-demand availability re-check (özellikle test sırasında initialize geç geldiyse)
    if (!_isAvailable) {
      try {
        final nowAvailable = await _inAppPurchase.isAvailable();
        _isAvailable = nowAvailable;
        if (nowAvailable) {
          if (_products.isEmpty) {
            await _loadProducts();
          }
        } else {
          onError?.call('In-App Purchase mevcut değil');
          return false;
        }
      } catch (e) {
        onError?.call('In-App Purchase mevcut değil');
        return false;
      }
    }

    if (_purchasePending) {
      onError?.call('Zaten bekleyen bir satın alma var');
      return false;
    }

    final storeProductId = _productIds[internalProductId];
    if (storeProductId == null) {
      onError?.call('Geçersiz ürün ID');
      return false;
    }

    ProductDetails? productDetails = _products
        .where((product) => product.id == storeProductId)
        .firstOrNull;

    // 🔎 On-demand fetch: initialize erken/başarısız olduysa tek ürün detayını çekmeyi dene
    if (productDetails == null) {
      try {
        final resp = await _inAppPurchase.queryProductDetails({storeProductId});
        if (resp.productDetails.isNotEmpty) {
          productDetails = resp.productDetails.first;
          // Cache’e ekle
          _products = {..._products, productDetails}.toList();
        } else {
          onError?.call('Ürün bulunamadı');
          return false;
        }
      } catch (e) {
        onError?.call('Ürün bilgisi alınamadı');
        return false;
      }
    }

    try {
      // 🛡️ Purchase işlemini başlat - spam koruması aktif
      _isPurchaseInProgress = true;
      
      // 🛡️ Purchase timeout başlat (30 saniye)
      _startPurchaseTimeout();
      
      // 🆕 Real device için pending transactions'ları temizle
      await _clearPendingTransactions();
      
      // 🆕 UI Callback'leri set et
      _onPurchaseSuccess = onSuccess;
      _onPurchaseError = onError;
      _currentPurchaseProductId = storeProductId;
      
      _purchasePending = true;
      
      // Subscription veya consumable product kontrolü
      bool isSubscription = internalProductId.startsWith('premium_');

      if (isSubscription) {

        // Android: Google Play için özel param kullan (plugin mevcut base plan seçimini handle eder)
        if (Platform.isAndroid) {
          final gpParam = GooglePlayPurchaseParam(
            productDetails: productDetails,
          );
          await _inAppPurchase.buyNonConsumable(purchaseParam: gpParam);
        } else {
          // iOS veya non-GP detaylarında standart param ile devam et
          final purchaseParam = PurchaseParam(productDetails: productDetails);
          await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
        }
      } else {
        final purchaseParam = PurchaseParam(productDetails: productDetails);
        await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
      }

      return true;
    } catch (e) {
      _purchasePending = false;
      _isPurchaseInProgress = false; // 🛡️ Spam koruması reset
      _resetCallbacks();
      
      // Specific error handling for real device issues
      final errorString = e.toString().toLowerCase();
      
      if (errorString.contains('storekit_duplicate_product_object') || 
          errorString.contains('duplicate')) {
        
        // Clear pending transactions otomatik olarak
        await _clearPendingTransactions();
        
        // User'a bilgi ver ama error olarak değil, info olarak
        onError?.call('Satın alma işlemi devam ediyor. Lütfen bekleyin.');
        return false; // UI'da retry göster
      }
      
      if (errorString.contains('payment_not_available') || 
          errorString.contains('store_kit_error')) {
        onError?.call('Ödeme sistemi geçici olarak kullanılamıyor. Lütfen tekrar deneyin.');
        return false;
      }
      
      if (errorString.contains('user_cancelled') || 
          errorString.contains('cancelled')) {
        onError?.call('Satın alma iptal edildi');
        return false;
      }
      
      // Generic error
      onError?.call('Satın alma başlatılamadı: $e');
      return false;
    }
  }

  /// Get product by internal ID
  ProductDetails? getProduct(String internalProductId) {
    final storeProductId = _productIds[internalProductId];
    if (storeProductId == null) return null;

    return _products.where((product) => product.id == storeProductId).firstOrNull;
  }

  /// Check if user has active premium
  Future<bool> hasActivePremium() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;

      final data = userDoc.data()!;
      final isPremium = data['isPremium'] ?? false;

      if (!isPremium) return false;

      final premiumUntil = data['premiumUntil'] as Timestamp?;
      if (premiumUntil == null) return false;

      return premiumUntil.toDate().isAfter(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  /// Android premium debug method - Call this after a purchase to diagnose issues
  Future<void> debugAndroidPremiumStatus() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) {
        return;
      }


      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        return;
      }

      final data = userDoc.data()!;
      
      // Premium fields
      final isPremium = data['isPremium'];
      final premiumType = data['premiumType'];
      final premiumUntil = data['premiumUntil'];
      final purchasedSuperLikes = data['purchasedSuperLikes'];
      final dailyLikesRemaining = data['dailyLikesRemaining'];
      final rewindsRemaining = data['rewindsRemaining'];
      final balance = data['balance'] ?? data['diamonds'] ?? 0;

      if (premiumUntil is Timestamp) {
      }

      // Check active premium status
      final isActivePremium = await hasActivePremium();

      if (isPremium == true && premiumUntil is Timestamp && premiumUntil.toDate().isAfter(DateTime.now())) {
      } else {
      }

      // Check recent purchases
      final purchasesQuery = await _firestore
          .collection('purchases')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      if (purchasesQuery.docs.isNotEmpty) {
        for (final doc in purchasesQuery.docs) {
          final purchaseData = doc.data();
        }
      } else {
      }

      // Check for critical errors
      final errorsQuery = await _firestore
          .collection('critical_errors')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(3)
          .get();
      
      if (errorsQuery.docs.isNotEmpty) {
        for (final doc in errorsQuery.docs) {
          final errorData = doc.data();
        }
      } else {
      }

    } catch (e) {
    }
  }

  /// Emergency fix for failed purchases - manually apply benefits
  Future<void> emergencyFixPurchase({
    required String productId,
    required String purchaseId,
    bool simulateOnly = false, // 🆕 Simulation mode
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return;
      }


      if (simulateOnly) {
        await Future.delayed(const Duration(milliseconds: 500)); // Simulate processing time
        return;
      }

      // Find internal product ID
      String? internalProductId;
      for (final entry in _productIds.entries) {
        if (entry.value == productId) {
          internalProductId = entry.key;
          break;
        }
      }

      if (internalProductId == null) {
        return;
      }

      // Apply benefits manually
      final userRef = _firestore.collection('users').doc(user.uid);
      
      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          throw Exception('User document not found');
        }

        final userData = userDoc.data()!;
        Map<String, dynamic> updates = {};

        // Apply benefits based on product type
        switch (internalProductId!) {
          case 'premium_weekly':
            _preparePremiumUpdates(updates, userData, 'weekly', 7, 3); // 3 süper chat
            break;
          case 'premium_monthly':
            _preparePremiumUpdates(updates, userData, 'monthly', 30, 10); // 10 süper chat
            break;
          case 'premium_quarterly':
            _preparePremiumUpdates(updates, userData, 'quarterly', 90, 30); // 30 süper chat
            break;
          case 'diamonds_10':
            _prepareDiamondUpdates(updates, userData, 10);
            break;
          case 'diamonds_50':
            _prepareDiamondUpdates(updates, userData, 50);
            break;
          case 'diamonds_100':
            _prepareDiamondUpdates(updates, userData, 100);
            break;
        }

        // Add emergency fix flag
        updates['emergencyFixed'] = true;
        updates['emergencyFixDate'] = FieldValue.serverTimestamp();
        updates['emergencyFixPurchaseId'] = purchaseId;

        transaction.update(userRef, updates);
      });

      
      // Log the emergency fix
      await _firestore.collection('emergency_fixes').add({
        'userId': user.uid,
        'productId': productId,
        'purchaseId': purchaseId,
        'internalProductId': internalProductId,
        'fixedAt': FieldValue.serverTimestamp(),
        'platform': 'android',
      });

    } catch (e) {
    }
  }
  
  /// Debug fonksiyonu: Google Play'deki aktif subscription'ları iptal eder
  static Future<void> cancelAllActiveSubscriptions() async {
    try {
      
      // Android'de aktif subscription'ları bul ve iptal et
      if (Platform.isAndroid) {
        // Pending purchases'ları aktifleştir
        InAppPurchaseAndroidPlatformAddition.enablePendingPurchases();
        
        // Mevcut satın almaları kontrol et
        await InAppPurchase.instance.restorePurchases();
        
        // Purchase stream'den aktif subscription'ları bulup iptal ederiz
        
      } else if (Platform.isIOS) {
        // iOS için StoreKit restoration
        try {
          // iOS'ta subscription'ları manuel olarak iptal edemeyiz
          // Kullanıcı App Store'dan iptal etmeli
          
        } catch (e) {
        }
      }
      
    } catch (e) {
    }
  }
  
  /// 💬 Purchase Super Chats - Chat Request System
  /// 
  /// Atomic transaction ile Super Chat satın alma
  /// Double-spending korumalı ve güvenli
  Future<bool> purchaseSuperChats(
    String internalProductId, {
    VoidCallback? onSuccess,
    ValueChanged<String>? onError,
  }) async {
    
    // Ürün ID kontrolü
    if (!internalProductId.startsWith('super_chats_')) {
      onError?.call('Geçersiz ürün');
      return false;
    }
    
    // Miktarı al
    final info = productInfo[internalProductId];
    if (info == null) {
      onError?.call('Ürün bilgisi bulunamadı');
      return false;
    }
    
    final quantity = info['quantity'] as int?;
    if (quantity == null || quantity <= 0) {
      onError?.call('Geçersiz miktar');
      return false;
    }
    
    // IAP satın almayı başlat
    // ✅ Benefit ekleme işini _applyPurchaseBenefits yapacak (buyProduct içinde otomatik çağrılır)
    // ❌ Burada manuel Firestore güncellemesi YAPILMAMALI (2 katı olmasın diye!)
    final purchaseResult = await buyProduct(
      internalProductId,
      onSuccess: onSuccess,
      onError: onError,
    );
    
    return purchaseResult;
  }

  /// Dispose
  void dispose() {
    _subscription.cancel();
    _cancelPurchaseTimeout(); // 🛡️ Timeout cleanup
    
    // 🛡️ DEDUPLICATION: App kapanırken processed purchases'ı temizle
    final oldCount = _processedPurchases.length;
    _processedPurchases.clear();
  }
}

/// iOS Payment Queue Delegate
class IAPPaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
      SKPaymentTransactionWrapper transaction, SKStorefrontWrapper storefront) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return false;
  }
}
