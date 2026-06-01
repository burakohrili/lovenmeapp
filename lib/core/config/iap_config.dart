// lib/core/config/iap_config.dart

import 'dart:io' show Platform;

/// In-App Purchase Configuration
/// ✅ CROSS-PLATFORM: iOS (App Store) + Android (Google Play) Support
class IAPConfig {
  
  /// Debug mode - production'da false yapılacak
  static const bool debugMode = false;
  
  /// Test mode - production'da false yapılacak  
  static const bool testMode = false;
  
  /// Platform info for debugging
  static String get currentPlatform {
    if (Platform.isIOS) return 'iOS (App Store)';
    if (Platform.isAndroid) return 'Android (Google Play)';
    return 'Unknown Platform';
  }
  
  /// Test environment check
  static bool get isTestEnvironment => debugMode || testMode;
  static const List<Map<String, dynamic>> diamondPackages = [
    // ESKİ PAKETLER (Korunuyor)
    {
      'id': 'diamonds_10',
      'title': '10 Elmas',
      'description': 'Premium özellikler için',
      'quantity': 10,
      'originalPrice': 99.99,
      'pricePerUnit': 9.99,
      'isPopular': false,
    },
    {
      'id': 'diamonds_50',
      'title': '50 Elmas',
      'description': 'Premium özellikler için',
      'quantity': 50,
      'originalPrice': 299.99,
      'pricePerUnit': 5.99,
      'isPopular': false,
    },
    {
      'id': 'diamonds_100',
      'title': '100 Elmas',
      'description': 'Premium özellikler için',
      'quantity': 100,
      'originalPrice': 499.99,
      'pricePerUnit': 4.99,
      'isPopular': false,
    },
    
    // YENİ PAKETLER ✨
    {
      'id': 'diamonds_250',
      'title': 'Standart',
      'description': '250 Elmas - En çok tercih edilen',
      'quantity': 250,
      'originalPrice': 1199.99,
      'pricePerUnit': 4.79,
      'isPopular': true,
    },
    {
      'id': 'diamonds_500',
      'title': 'Efsane',
      'description': '500 Elmas - En avantajlı paket',
      'quantity': 500,
      'originalPrice': 1799.99,
      'pricePerUnit': 3.59,
      'discountPercent': 40,
      'isPopular': false,
    },
  ];

  /// App Store Connect / Google Play Console'da tanımlanan ürün ID'leri
  /// ✅ GÜNCELLENEN: iOS (App Store) ve Android (Google Play) için unified mapping
  static const Map<String, String> productIds = {
    // Premium Subscriptions (Auto-renewable) ✅ CROSS-PLATFORM CONFIRMED
    'premium_weekly': 'com.lovenme.premium.weekly',
    'premium_monthly': 'com.lovenme.premium.monthly', 
    'premium_quarterly': 'com.lovenme.premium.quarterly',
    
    // Diamonds - ESKİ PAKETLER (Korunuyor)
    'diamonds_10': 'com.lovenme.diamonds.tenpack',
    'diamonds_50': 'com.lovenme.diamonds.fiftypack',
    'diamonds_100': 'com.lovenme.diamonds.hundredpack',
    
    // Diamonds - YENİ PAKETLER ✨
    'diamonds_250': 'com.lovenme.diamonds.twfiftypack',
    'diamonds_500': 'com.lovenme.diamonds.fivehundredpack',
    
    // Super Likes (Consumable) - DEPRECATED: Like sistemi kaldırıldı
    // 'super_likes_3': 'com.lovenme.superlikes.threepack',
    // 'super_likes_10': 'com.lovenme.superlikes.tenpack', 
    // 'super_likes_25': 'com.lovenme.superlikes.twentyfivepack',
    
    // Super Chats (Consumable) ✅ CROSS-PLATFORM CONFIRMED
    'super_chats_3': 'com.lovenme.superchats.threepacks',
    'super_chats_10': 'com.lovenme.superchats.tenpacks',
    'super_chats_25': 'com.lovenme.superchats.twentyfivepacks',
  };

  /// Premium package info for UI
  static const List<Map<String, dynamic>> premiumPackages = [
    {
      'id': 'premium_weekly',
      'title': 'Premium Haftalık',
      'subtitle': 'Hızlı başlangıç için',
      'description': 'Sınırsız chat + özel özellikler',
      'duration': 7,
      'durationText': '7 Gün',
      'originalPrice': 95.99,
      'isPopular': false,
      'features': [
        'Sınırsız chat isteği',
        'Reklamsız deneyim',
        'Günde 3 geri alma hakkı',
        'Özel rozetler',
      ],
    },
    {
      'id': 'premium_monthly',
      'title': 'Premium Aylık',
      'subtitle': 'En popüler seçenek!',
      'description': 'Sınırsız özellikler',
      'duration': 30,
      'durationText': '1 Ay',
      'originalPrice': 359.99,
      'isPopular': true,
      'features': [
        'Sınırsız chat isteği',
        'Reklamsız deneyim',
        'Geçmiş check-in\'leri görüntüle',
        'Günde 3 geri alma hakkı',
        'Özel rozetler',
        'Öncelikli destek',
      ],
    },
    {
      'id': 'premium_quarterly',
      'title': 'Premium 3 Aylık',
      'subtitle': '%33 tasarruf!',
      'description': 'En avantajlı paket',
      'duration': 90,
      'durationText': '3 Ay',
      'originalPrice': 719.99,
      'discountPercent': 33,
      'isPopular': false,
      'features': [
        'Sınırsız chat isteği',
        'Reklamsız deneyim',
        'Geçmiş check-in\'leri görüntüle',
        'Mekanda check-in yapanları gör',
        'Günde 3 geri alma hakkı',
        'Özel rozetler',
        'Öncelikli destek',
        '%33 indirim',
      ],
    },
  ];

  /// Super Chat packages for UI ✅ YENİ: Chat Request Sistemi
  static const List<Map<String, dynamic>> superChatPackages = [
    {
      'id': 'super_chats_3',
      'title': '3 Super Chat',
      'description': 'Özel mesaj ile fark yarat',
      'quantity': 3,
      'originalPrice': 89.99,
      'pricePerUnit': 29.99,
      'isPopular': false,
      'features': [
        '20 karakterlik özel mesaj',
        '5 hızlı mesaj seçeneği',
        'Anında ilgi çek',
      ],
    },
    {
      'id': 'super_chats_10',
      'title': '10 Super Chat',
      'description': 'Daha fazla eşleşme için ideal',
      'quantity': 10,
      'originalPrice': 264.99,
      'pricePerUnit': 26.49,
      'isPopular': true,
      'features': [
        '20 karakterlik özel mesaj',
        '5 hızlı mesaj seçeneği',
        'Anında ilgi çek',
        'En popüler paket',
      ],
    },
    {
      'id': 'super_chats_25',
      'title': '25 Super Chat',
      'description': 'Maximum etki için',
      'quantity': 25,
      'originalPrice': 599.99,
      'pricePerUnit': 23.99,
      'discountPercent': 20,
      'isPopular': false,
      'features': [
        '20 karakterlik özel mesaj',
        '5 hızlı mesaj seçeneği',
        'Anında ilgi çek',
        '%20 indirim',
      ],
    },
  ];
  
  /// Super Like packages - DEPRECATED: Like sistemi kaldırıldı
  @Deprecated('Use superChatPackages instead')
  static const List<Map<String, dynamic>> superLikePackages = [];

  /// Boost packages for UI
  static const List<Map<String, dynamic>> boostPackages = [
    {
      'id': 'boost_1day',
      'title': '1 Günlük Boost',
      'description': 'Mekanda daha görünür ol',
      'duration': 1,
      'durationText': '24 Saat',
      'originalPrice': 14.99,
      'isPopular': false,
    },
    {
      'id': 'boost_3days',
      'title': '3 Günlük Boost',
      'description': '3 gün boost (%30 indirim)',
      'duration': 3,
      'durationText': '3 Gün',
      'originalPrice': 29.99,
      'discountPercent': 30,
      'isPopular': true,
    },
    {
      'id': 'boost_week',
      'title': '1 Haftalık Boost',
      'description': '1 hafta boost (%50 indirim)',
      'duration': 7,
      'durationText': '1 Hafta',
      'originalPrice': 49.99,
      'discountPercent': 50,
      'isPopular': false,
    },
  ];

  /// Get package info by ID
  static Map<String, dynamic>? getPackageInfo(String packageId) {
    // Premium packages
    for (final package in premiumPackages) {
      if (package['id'] == packageId) return package;
    }
    
    // Super Like packages
    for (final package in superLikePackages) {
      if (package['id'] == packageId) return package;
    }
    
    // Diamond packages
    for (final package in diamondPackages) {
      if (package['id'] == packageId) return package;
    }
    
    // Boost packages
    for (final package in boostPackages) {
      if (package['id'] == packageId) return package;
    }
    
    return null;
  }

  /// Get all subscription product IDs
  static Set<String> get subscriptionProductIds => {
    productIds['premium_weekly']!,
    productIds['premium_monthly']!,
    productIds['premium_quarterly']!,
  };

  /// Get all consumable product IDs
  static Set<String> get consumableProductIds => {
    // Diamonds ✅
    productIds['diamonds_10']!,
    productIds['diamonds_50']!,
    productIds['diamonds_100']!,
    productIds['diamonds_250']!,
    productIds['diamonds_500']!,
    // Super Chats ✅
    productIds['super_chats_3']!,
    productIds['super_chats_10']!,
    productIds['super_chats_25']!,
    // super_likes_* KALDIRILDI — kaldırılanları buraya ekleme, null crash olur
  };

  /// Get all product IDs
  static Set<String> get allProductIds => {
    ...subscriptionProductIds,
    ...consumableProductIds,
  };

  /// ✅ CROSS-PLATFORM HELPERS
  
  /// Platform-specific test product validation
  static bool isValidProductId(String productId) {
    return allProductIds.contains(productId);
  }
  
  /// Get platform-specific store info
  static Map<String, String> getPlatformStoreInfo() {
    return {
      'platform': currentPlatform,
      'store': Platform.isIOS ? 'App Store Connect' : 'Google Play Console',
      'environment': isTestEnvironment ? 'Sandbox/Test' : 'Production',
      'total_products': '${allProductIds.length}',
      'subscriptions': '${subscriptionProductIds.length}',
      'consumables': '${consumableProductIds.length}',
    };
  }
}
