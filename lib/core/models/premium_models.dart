// lib/core/models/premium_models.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum PremiumSubscriptionType {
  weekly,
  monthly,
  quarterly,
}

extension PremiumSubscriptionTypeExtension on PremiumSubscriptionType {
  String get name {
    switch (this) {
      case PremiumSubscriptionType.weekly:
        return 'weekly';
      case PremiumSubscriptionType.monthly:
        return 'monthly';
      case PremiumSubscriptionType.quarterly:
        return 'quarterly';
    }
  }

  String get displayName {
    switch (this) {
      case PremiumSubscriptionType.weekly:
        return 'Haftalık Premium';
      case PremiumSubscriptionType.monthly:
        return 'Aylık Premium';
      case PremiumSubscriptionType.quarterly:
        return '3 Aylık Premium';
    }
  }

  String get duration {
    switch (this) {
      case PremiumSubscriptionType.weekly:
        return '7 Gün';
      case PremiumSubscriptionType.monthly:
        return '1 Ay';
      case PremiumSubscriptionType.quarterly:
        return '3 Ay';
    }
  }

  double get price {
    switch (this) {
      case PremiumSubscriptionType.weekly:
        return 95.99;
      case PremiumSubscriptionType.monthly:
        return 359.99;
      case PremiumSubscriptionType.quarterly:
        return 719.99;
    }
  }

  int get superLikes {
    switch (this) {
      case PremiumSubscriptionType.weekly:
        return 3; // Tek seferlik 3 super like
      case PremiumSubscriptionType.monthly:
        return 10; // Tek seferlik 10 super like
      case PremiumSubscriptionType.quarterly:
        return 30; // Tek seferlik 30 super like
    }
  }

  String get description {
    switch (this) {
      case PremiumSubscriptionType.weekly:
        return 'Hızlı başlangıç için mükemmel';
      case PremiumSubscriptionType.monthly:
        return 'En popüler seçenek';
      case PremiumSubscriptionType.quarterly:
        return '%33 tasarruf! En avantajlı paket';
    }
  }

  List<String> get features {
    const baseFeatures = [
      'Sınırsız chat isteği',
      'Check-in yapanların profillerini gör',
      'Check-in yapmadan kişileri görebilme',
      'Geçmiş check-in\'leri görüntüle',
    ];

    switch (this) {
      case PremiumSubscriptionType.weekly:
        return [
          ...baseFeatures,
          '3 Süper Chat hakkı (Tek seferlik)',
        ];
      case PremiumSubscriptionType.monthly:
        return [
          ...baseFeatures,
          '10 Süper Chat hakkı (Tek seferlik)',
        //   'Öncelikli müşteri desteği',
        ];
      case PremiumSubscriptionType.quarterly:
        return [
          ...baseFeatures,
          '30 Süper Chat hakkı (Tek seferlik)',
        //   'Öncelikli müşteri desteği',
        ];
    }
  }
}

class PremiumStatus {
  final bool isPremium;
  final PremiumSubscriptionType? premiumType;
  final DateTime? expiryDate;
  final int superChatsRemaining; // 💬 IAP ile satın alınan super chat'ler
  final int rewindsRemaining;

  PremiumStatus({
    required this.isPremium,
    this.premiumType,
    this.expiryDate,
    this.superChatsRemaining = 0, // 💬 Super chat hakkı
    this.rewindsRemaining = 0,
  });

  bool get isExpired {
    if (!isPremium || expiryDate == null) return true;
    return DateTime.now().isAfter(expiryDate!);
  }

  int get dailyRewindsLimit {
    if (!isPremium) return 0; // Normal kullanıcı geri alma alamaz
    return 3; // Premium kullanıcı günde 3 geri alma
  }

  String get remainingTimeText {
    if (!isPremium || expiryDate == null) return '';
    
    final remaining = expiryDate!.difference(DateTime.now());
    if (remaining.inDays > 0) {
      return '${remaining.inDays} gün kaldı';
    } else if (remaining.inHours > 0) {
      return '${remaining.inHours} saat kaldı';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes} dakika kaldı';
    } else {
      return 'Süresi dolmuş';
    }
  }

  /// 🆕 Günlük chat request limiti
  int get dailyChatRequestsLimit {
    if (!isPremium) return 5; // Normal kullanıcı günde 5 chat
    return 999; // Premium kullanıcı sınırsız
  }
}

class PremiumPackage {
  final PremiumSubscriptionType type;
  final String title;
  final String subtitle;
  final double price;
  /// Store'dan gelen formatlanmış fiyat stringi (ör. "₺359,99").
  /// null ise widget kendi formatlar.
  final String? priceString;
  final double? originalPrice;
  final String duration;
  final List<String> features;
  final bool isRecommended;
  final bool isLaunchOffer;

  PremiumPackage({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.price,
    this.priceString,
    this.originalPrice,
    required this.duration,
    required this.features,
    this.isRecommended = false,
    this.isLaunchOffer = false,
  });

  factory PremiumPackage.fromType(PremiumSubscriptionType type) {
    return PremiumPackage(
      type: type,
      title: type.displayName,
      subtitle: type.description,
      price: type.price,
      originalPrice: type == PremiumSubscriptionType.quarterly ? 1079.97 : null,
      duration: type.duration,
      features: type.features,
      isRecommended: type == PremiumSubscriptionType.monthly,
      isLaunchOffer: type == PremiumSubscriptionType.quarterly,
    );
  }
}

class PremiumTransaction {
  final String id;
  final String userId;
  final PremiumSubscriptionType type;
  final double amount;
  final String transactionId;
  final DateTime purchaseDate;
  final DateTime expiryDate;
  final bool isActive;

  PremiumTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.transactionId,
    required this.purchaseDate,
    required this.expiryDate,
    required this.isActive,
  });

  factory PremiumTransaction.fromMap(String id, Map<String, dynamic> data) {
    return PremiumTransaction(
      id: id,
      userId: data['userId'] ?? '',
      type: PremiumSubscriptionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => PremiumSubscriptionType.monthly,
      ),
      amount: (data['amount'] ?? 0.0).toDouble(),
      transactionId: data['transactionId'] ?? '',
      purchaseDate: (data['startDate'] as Timestamp).toDate(),
      expiryDate: (data['endDate'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? false,
    );
  }
}

class QueuedPremiumSubscription {
  final String id;
  final String userId;
  final PremiumSubscriptionType type;
  final DateTime purchaseDate;
  final DateTime startDate;
  final DateTime endDate;
  final bool isQueued;

  QueuedPremiumSubscription({
    required this.id,
    required this.userId,
    required this.type,
    required this.purchaseDate,
    required this.startDate,
    required this.endDate,
    required this.isQueued,
  });

  factory QueuedPremiumSubscription.fromMap(String id, Map<String, dynamic> data) {
    return QueuedPremiumSubscription(
      id: id,
      userId: data['userId'] ?? '',
      type: PremiumSubscriptionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => PremiumSubscriptionType.monthly,
      ),
      purchaseDate: data['purchaseDate'] != null 
          ? (data['purchaseDate'] as Timestamp).toDate() 
          : DateTime.now(),
      startDate: data['startDate'] != null 
          ? (data['startDate'] as Timestamp).toDate() 
          : DateTime.now(),
      endDate: data['endDate'] != null 
          ? (data['endDate'] as Timestamp).toDate() 
          : DateTime.now(),
      isQueued: data['isQueued'] ?? false,
    );
  }

  String get statusText {
    if (DateTime.now().isBefore(startDate)) {
      final diff = startDate.difference(DateTime.now());
      if (diff.inDays > 0) {
        return '${diff.inDays} gün sonra başlayacak';
      } else if (diff.inHours > 0) {
        return '${diff.inHours} saat sonra başlayacak';
      } else {
        return 'Yakında başlayacak';
      }
    }
    return 'Aktif edilecek';
  }
}

class PremiumSubscriptionInfo {
  final String id;
  final String userId;
  final PremiumSubscriptionType type;
  final DateTime purchaseDate;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final bool isQueued;
  final String? transactionId;

  PremiumSubscriptionInfo({
    required this.id,
    required this.userId,
    required this.type,
    required this.purchaseDate,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.isQueued,
    this.transactionId,
  });

  factory PremiumSubscriptionInfo.fromMap(String id, Map<String, dynamic> data) {
    return PremiumSubscriptionInfo(
      id: id,
      userId: data['userId'] ?? '',
      type: PremiumSubscriptionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => PremiumSubscriptionType.monthly,
      ),
      purchaseDate: data['purchaseDate'] != null 
          ? (data['purchaseDate'] as Timestamp).toDate() 
          : DateTime.now(),
      startDate: data['startDate'] != null 
          ? (data['startDate'] as Timestamp).toDate() 
          : DateTime.now(),
      endDate: data['endDate'] != null 
          ? (data['endDate'] as Timestamp).toDate() 
          : DateTime.now(),
      isActive: data['isActive'] ?? false,
      isQueued: data['isQueued'] ?? false,
      transactionId: data['transactionId'],
    );
  }

  String get statusText {
    if (isActive) {
      return 'Aktif';
    } else if (isQueued) {
      return 'Kuyrukta';
    } else {
      return 'Tamamlandı';
    }
  }

  Color get statusColor {
    if (isActive) {
      return Colors.green;
    } else if (isQueued) {
      return Colors.orange;
    } else {
      return Colors.grey;
    }
  }
}
