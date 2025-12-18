import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:lovenme/core/models/payment_models.dart';
import 'package:lovenme/core/config/payment_config.dart';
import 'package:lovenme/presentation/widgets/payment/universal_payment_button.dart';
import 'package:lovenme/presentation/widgets/payment/quick_purchase_widget.dart';

/// Ödeme Manager'ı - In-App Purchase sistemi için yardımcı sınıf
class PaymentManager {
  
  /// Platform bilgisini döner
  static String get platformPaymentMethod => PaymentConfig.platformName;
  
  /// In-App Purchase ikonu
  static IconData get platformPaymentIcon {
    if (Platform.isAndroid) {
      return Icons.payment; // Google Play icon
    } else if (Platform.isIOS) {
      return Icons.storefront; // App Store icon  
    } else {
      return Icons.credit_card;
    }
  }

  /// Universal payment button - IAP öncelikli
  static Widget platformPayButton({
    required PaymentPackage package,
    required VoidCallback onPaymentSuccess,
    required ValueChanged<String> onPaymentError,
    VoidCallback? onPaymentStarted,
    double? width,
    double height = 56,
  }) {
    // UniversalPaymentButton kullan - IAP/Google Pay detection otomatik
    return SizedBox(
      width: width,
      height: height,
      child: UniversalPaymentButton(
        package: package,
        onPaymentSuccess: onPaymentSuccess,
        onPaymentError: onPaymentError,
        onPaymentStarted: onPaymentStarted,
        width: width,
        height: height,
      ),
    );
  }

  /// Standart ödeme butonu - Tam özellikli
  static Widget standardButton({
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
    String? customButtonText,
    double? width,
    double height = 56,
  }) {
    return UniversalPaymentButton(
      package: package,
      onPaymentSuccess: onPaymentSuccess,
      onPaymentError: onPaymentError,
      customButtonText: customButtonText,
      width: width,
      height: height,
    );
  }

  /// Kompakt ödeme butonu - Sadece buton
  static Widget compactButton({
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
    String? customButtonText,
    double? width,
    double height = 44,
  }) {
    return UniversalPaymentButton(
      package: package,
      onPaymentSuccess: onPaymentSuccess,
      onPaymentError: onPaymentError,
      customButtonText: customButtonText,
      width: width,
      height: height,
      compact: true,
    );
  }

  /// Hızlı satın alma - Navigation bar için
  static Widget quickPurchase({
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
    bool horizontal = true,
  }) {
    return QuickPurchaseWidget(
      package: package,
      onPaymentSuccess: onPaymentSuccess,
      onPaymentError: onPaymentError,
      horizontal: horizontal,
    );
  }

  /// Ultra kompakt - Badge tarzı
  static Widget ultraCompact({
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
  }) {
    return QuickPurchaseWidget(
      package: package,
      onPaymentSuccess: onPaymentSuccess,
      onPaymentError: onPaymentError,
      ultraCompact: true,
    );
  }

  /// Floating Action Button tarzı
  static Widget floatingPurchase({
    required BuildContext context,
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
  }) {
    return FloatingActionButton.extended(
      onPressed: () => showPaymentDialog(
        context: context,
        package: package,
        onPaymentSuccess: onPaymentSuccess,
        onPaymentError: onPaymentError,
        title: 'Hızlı Satın Al',
      ),
      backgroundColor: _getPackageColor(package.type),
      icon: Icon(_getPackageIcon(package.type)),
      label: Text(
        '₺${package.price.toStringAsFixed(0)}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Bottom Sheet ödeme paneli
  static void showPaymentBottomSheet({
    required BuildContext context,
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
    String? title,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1a1a2e),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            UniversalPaymentButton(
              package: package,
              onPaymentSuccess: () {
                Navigator.of(context).pop();
                onPaymentSuccess?.call();
              },
              onPaymentError: onPaymentError,
              title: title,
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog ödeme paneli
  static void showPaymentDialog({
    required BuildContext context,
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
    String? title,
  }) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              UniversalPaymentButton(
                package: package,
                onPaymentSuccess: () {
                  Navigator.of(context).pop();
                  onPaymentSuccess?.call();
                },
                onPaymentError: onPaymentError,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Snackbar ile hızlı satın alma
  static void showQuickPurchaseSnackbar({
    required BuildContext context,
    required PaymentPackage package,
    VoidCallback? onPaymentSuccess,
    ValueChanged<String>? onPaymentError,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: QuickPurchaseWidget(
          package: package,
          onPaymentSuccess: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            onPaymentSuccess?.call();
          },
          onPaymentError: onPaymentError,
          horizontal: true,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Predefined paketler - Sadece Muhtar Elmas Paketleri
  static List<PaymentPackage> get muhtarPackages => [
    PaymentPackage(
      id: 'muhtar_starter',
      type: PaymentType.muhtar,
      title: 'Muhtar Başlangıç',
      amount: 10,
      description: '10 elmas ile muhtar ol + özel ayrıcalıklar',
      price: 79.99,
      originalPrice: 79.99,
      duration: 'Kalıcı',
      features: [
        '10 elmas',
        'Mekân sayfasında en üst sırada',
        'Haritada altın taç',
        'Muhtarla Tanış butonu',
        'Muhtar etiketi',
        'Hızlı DM erişimi',
      ],
    ),
    PaymentPackage(
      id: 'muhtar_standard',
      type: PaymentType.muhtar,
      title: 'Muhtar Standart',
      amount: 50,
      description: '50 elmas ile güçlü muhtar ol',
      price: 299.99,
      originalPrice: 299.99,
      duration: 'Kalıcı',
      isRecommended: true,
      features: [
        '50 elmas',
        'Mekân sayfasında en üst sırada',
        'Haritada altın taç',
        'Muhtarla Tanış butonu',
        'Muhtar etiketi',
        'Hızlı DM erişimi',
        'Özel muhtar çerçevesi',
        'Premium gösterim',
      ],
    ),
    PaymentPackage(
      id: 'muhtar_efsane',
      type: PaymentType.muhtar,
      title: 'Muhtar Efsane',
      amount: 100,
      description: '100 elmas ile efsanevi muhtar ol',
      price: 499.99,
      originalPrice: 499.99,
      duration: 'Kalıcı',
      isPopular: true,
      features: [
        '100 elmas',
        'Mekân sayfasında en üst sırada',
        'Haritada efsanevi altın taç',
        'Muhtarla Tanış butonu',
        'Efsane muhtar etiketi',
        'Hızlı DM erişimi',
        'Özel efsane çerçevesi',
        'Premium gösterim',
        'Özel animasyonlar',
        'VIP müşteri desteği',
      ],
    ),
  ];

  // Helper methods
  static Color _getPackageColor(PaymentType type) {
    switch (type) {
      case PaymentType.muhtar:
        return const Color(0xFFFF6B35); // Orange/Red
      case PaymentType.premium:
        return const Color(0xFF6B35FF); // Purple
      case PaymentType.diamond:
        return const Color(0xFF00BCD4); // Cyan for diamond
      case PaymentType.superlike:
        return const Color(0xFFE91E63); // Pink for super like
    }
  }

  static IconData _getPackageIcon(PaymentType type) {
    switch (type) {
      case PaymentType.muhtar:
        return Icons.account_balance; // Muhtar ikonu
      case PaymentType.premium:
        return Icons.star; // Premium ikonu
      case PaymentType.diamond:
        return Icons.diamond; // Elmas ikonu
      case PaymentType.superlike:
        return Icons.favorite; // Süper like ikonu
    }
  }

  /// Direkt Google Pay çağır (custom button için)
  static Future<bool> directGooglePay({
    required int diamondAmount,
    required double price,
    required Function(int) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      if (Platform.isAndroid) {
        try {
          // Google Pay widget'ı oluştur ve test modunda simüle et
          await Future.delayed(const Duration(seconds: 1));
          onSuccess(diamondAmount);
          return true;
          
        } catch (e) {
          onError('Google Pay hatası: $e');
          return false;
        }

      } else {
        onError('Sadece Android destekleniyor');
        return false;
      }
    } catch (e) {
      onError('Ödeme hatası: $e');
      return false;
    }
  }
}
