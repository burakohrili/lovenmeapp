import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lovenme/core/models/payment_models.dart';
import 'package:lovenme/core/services/payment_service.dart';
import 'package:lovenme/core/helpers/payment_helper.dart';
import 'package:lovenme/presentation/widgets/payment/simple_payment_button.dart';
import 'package:lovenme/presentation/widgets/payment/google_pay_button.dart';
import 'package:lovenme/presentation/widgets/payment/iap_payment_button.dart'; // 🆕 IAP Button

/// Mödüler Ödeme Widget'ı
/// Tüm ekranlarda kullanılabilir, otomatik olarak mevcut ödeme yöntemlerini algılar
class UniversalPaymentButton extends StatefulWidget {
  /// Ödeme paketi bilgileri
  final PaymentPackage package;
  
  /// Ödeme başarılı olduğunda çağrılacak callback
  final VoidCallback? onPaymentSuccess;
  
  /// Ödeme hatası olduğunda çağrılacak callback
  final ValueChanged<String>? onPaymentError;
  
  /// Ödeme işlemi başladığında çağrılacak callback
  final VoidCallback? onPaymentStarted;
  
  /// Buton genişliği
  final double? width;
  
  /// Buton yüksekliği
  final double height;
  
  /// Widget başlığı (opsiyonel)
  final String? title;
  
  /// Fiyat gösterimi (varsayılan: true)
  final bool showPrice;
  
  /// Kompakt mod (sadece buton, başlık ve fiyat yok)
  final bool compact;
  
  /// Özel buton metni
  final String? customButtonText;

  const UniversalPaymentButton({
    super.key,
    required this.package,
    this.onPaymentSuccess,
    this.onPaymentError,
    this.onPaymentStarted,
    this.width,
    this.height = 56,
    this.title,
    this.showPrice = true,
    this.compact = false,
    this.customButtonText,
  });

  @override
  State<UniversalPaymentButton> createState() => _UniversalPaymentButtonState();
}

class _UniversalPaymentButtonState extends State<UniversalPaymentButton> {
  PaymentMethodAvailability? _paymentAvailability;

  @override
  void initState() {
    super.initState();
    _loadPaymentAvailability();
  }
  
  /// PaymentPackage'ı IAP internal product ID'ye çevir
  String? _getIAPProductId() {
    // Premium paketleri
    if (widget.package.type == PaymentType.premium) {
      switch (widget.package.duration.toLowerCase()) {
        case '1 hafta':
        case '7 gün':
        case 'weekly':
          return 'premium_weekly';
        case '1 ay':
        case '30 gün':
        case 'monthly':
          return 'premium_monthly';
        case '3 ay':
        case '90 gün':
        case 'quarterly':
          return 'premium_quarterly';
        default:
          return null;
      }
    }
    
    // Super Chat paketleri (PaymentType.superlike — Super Chat için kullanılıyor)
    if (widget.package.type == PaymentType.superlike) {
      switch (widget.package.amount) {
        case 3:
          return 'super_chats_3';  // ✅ super_likes → super_chats
        case 10:
          return 'super_chats_10';
        case 25:
          return 'super_chats_25';
        default:
          return null;
      }
    }
    
    // Elmas paketleri (PaymentType.diamond)
    if (widget.package.type == PaymentType.diamond) {
      switch (widget.package.diamonds ?? widget.package.amount) {
        case 10:
          return 'diamonds_10';
        case 50:
          return 'diamonds_50'; // ✅ Fiyat güncellendi: 249.99 TL
        case 100:
          return 'diamonds_100';
        case 250:
          return 'diamonds_250'; // ✨ YENİ: 250 elmas paketi
        case 500:
          return 'diamonds_500'; // ✨ YENİ: 500 elmas paketi
        default:
          return null;
      }
    }
    
    return null;
  }

  Future<void> _loadPaymentAvailability() async {
    final availability = await PaymentService.getPaymentMethodAvailability();
    if (mounted) {
      setState(() {
        _paymentAvailability = availability;
      });
    }
  }

  PaymentMethod _getPreferredPaymentMethod() {
    
    if (_paymentAvailability == null) {
      if (Platform.isAndroid) {
        return PaymentMethod.googlePay;
      } else {
        return PaymentMethod.creditCard;
      }
    }
    
    // Android için Google Pay kontrolü
    if (Platform.isAndroid && (_paymentAvailability?.googlePayAvailable ?? false)) {
      return PaymentMethod.googlePay;
    } else {
      return PaymentMethod.creditCard;
    }
  }

  

  Widget _buildPaymentButton() {
    // 🚀 YENİ: IAP Product ID'yi al
    final iapProductId = _getIAPProductId();
    
    if (iapProductId != null) {
      // IAP desteklenen ürün - direkt IAP button kullan (Google Pay yok)
      return IAPPaymentButton(
        key: ValueKey(iapProductId), // 🔧 Key ekledik - her product için fresh mount
        internalProductId: iapProductId,
        onPaymentSuccess: widget.onPaymentSuccess,
        onPaymentError: widget.onPaymentError,
        onPaymentStarted: widget.onPaymentStarted,
        width: widget.width,
        height: widget.height,
        customButtonText: widget.customButtonText ?? 'Satın Al', // Varsayılan buton metni
      );
    }
    
    // Fallback: Eski sistem (IAP desteklenmeyen ürünler için - sadece eski sistemde)
    final preferredMethod = _getPreferredPaymentMethod();
    
    switch (preferredMethod) {
      case PaymentMethod.googlePay:
        return CustomGooglePayButton(
          package: widget.package,
          onPaymentSuccess: widget.onPaymentSuccess,
          onPaymentError: widget.onPaymentError,
          onPaymentStarted: widget.onPaymentStarted,
          width: widget.width,
          height: widget.height,
        );
        
      case PaymentMethod.creditCard:
        // Basit ödeme button'u kullan - eski çalışan sistemle
        final purchaseItem = PaymentHelper.convertPackageToPurchaseItem(widget.package);
        
        return SimplePaymentButton(
          item: purchaseItem,
          onSuccess: widget.onPaymentSuccess,
          onError: widget.onPaymentError,
          customText: widget.customButtonText,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Her zaman compact mode kullan - overflow'u önlemek için
    return _buildPaymentButton();
  }
}
