// lib/presentation/widgets/payment/iap_payment_button.dart

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/services/iap_service.dart';
import '../../../core/config/iap_config.dart';

/// In-App Purchase Universal Payment Button
/// Tüm IAP ödeme işlemlerini handle eden tek widget
class IAPPaymentButton extends StatefulWidget {
  /// Internal product ID (IAPConfig'deki key)
  final String internalProductId;
  
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
  
  /// Özel buton metni (yoksa product title kullanılır)
  final String? customButtonText;
  
  /// Loading state'i disable et
  final bool disableLoading;
  
  /// Buton stili
  final ButtonStyle? buttonStyle;

  const IAPPaymentButton({
    super.key,
    required this.internalProductId,
    this.onPaymentSuccess,
    this.onPaymentError,
    this.onPaymentStarted,
    this.width,
    this.height = 56,
    this.customButtonText,
    this.disableLoading = false,
    this.buttonStyle,
  });

  @override
  State<IAPPaymentButton> createState() => _IAPPaymentButtonState();
}

class _IAPPaymentButtonState extends State<IAPPaymentButton> {
  bool _isLoading = false;
  ProductDetails? _product;
  String _status = 'Yükleniyor...';
  bool _hasError = false; // Hata durumu tracking
  bool _isProcessingPayment = false; // 🛡️ UI Level spam protection

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    try {
      // Internal product ID'den App Store Connect ID'yi al
      final storeProductId = IAPConfig.productIds[widget.internalProductId];
      if (storeProductId == null) {
        throw Exception('Ürün ID bulunamadı: ${widget.internalProductId}');
      }

      // Product details'i yükle
      final ProductDetailsResponse response = await InAppPurchase.instance
          .queryProductDetails({storeProductId});

      if (response.error != null) {
        throw Exception('Ürün sorgusu hatası: ${response.error}');
      }

      if (response.productDetails.isEmpty) {
        throw Exception('Ürün bulunamadı: $storeProductId');
      }

      setState(() {
        _product = response.productDetails.first;
        _status = 'Hazır';
        _hasError = false; // Reset error state
      });


    } catch (e) {
      setState(() {
        _status = 'Hata: $e';
        _hasError = true; // Set error state
      });
    }
  }

  Future<void> _handlePurchase() async {
    // 🛡️ SPAM PROTECTION - UI seviyesinde double-check
    if (_product == null || _isLoading || _isProcessingPayment) {
      if (_isProcessingPayment) {
        return;
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _isProcessingPayment = true; // 🛡️ Spam koruması aktif
      _status = 'Satın alınıyor...';
      _hasError = false; // Reset error state when starting new purchase
    });

    widget.onPaymentStarted?.call();

    try {
      // 🆕 Callback'li purchase başlat
      final success = await IAPService().buyProduct(
        widget.internalProductId,
        onSuccess: () {
          // 🛡️ MOUNT CHECK: Widget dispose olduysa hiçbir UI işlem yapma
          if (!mounted) {
            return;
          }
          
          // Purchase başarılı - UI'ı güncelle
          setState(() {
            _status = 'Satın alma başarılı!';
            _isLoading = false;
            _isProcessingPayment = false; // 🛡️ Spam koruması reset
            _hasError = false; // Reset error state
          });
          
          // Success feedback göster
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Satın alma başarılı! 🎉'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          
          // 🛡️ MOUNT CHECK - Parent widget callback'i güvenli çağır
          if (widget.onPaymentSuccess != null) {
            widget.onPaymentSuccess!();
          }
        },
        onError: (errorMessage) {
          // 🛡️ MOUNT CHECK: Widget dispose olduysa hiçbir UI işlem yapma
          if (!mounted) {
            return;
          }
          
          // Purchase başarısız - UI'ı güncelle  
          setState(() {
            _status = 'Tekrar dene'; // 🆕 Retry için buton text
            _isLoading = false;
            _isProcessingPayment = false; // 🛡️ Spam koruması reset
            _hasError = true; // Error state set et
          });
          
          // Error feedback göster
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Tekrar Dene',
                textColor: Colors.white,
                onPressed: () {
                  // Retry purchase
                  _handlePurchase();
                },
              ),
            ),
          );
          
          // 🛡️ MOUNT CHECK - Parent widget callback'i güvenli çağır
          if (widget.onPaymentError != null) {
            widget.onPaymentError!(errorMessage);
          }
        },
      );
      
      if (success) {
        setState(() {
          _status = 'Satın alma işlemi başlatıldı...';
        });
        
        
      } else {
        throw Exception('Satın alma işlemi başlatılamadı');
      }

    } catch (e) {
      // 🛡️ MOUNT CHECK: Widget dispose olduysa hiçbir UI işlem yapma
      if (!mounted) {
        return;
      }
      
      setState(() {
        _status = 'Tekrar dene'; // 🆕 Retry için buton text
        _isLoading = false;
        _isProcessingPayment = false; // 🛡️ Spam koruması reset
        _hasError = true; // Error state set et
      });
      
      final errorMessage = 'Satın alma hatası: $e';
      
      // 🛡️ MOUNT CHECK - Parent widget callback'i güvenli çağır
      if (widget.onPaymentError != null) {
        widget.onPaymentError!(errorMessage);
      }
      
      // Error mesajını göster - mount check zaten var
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Tekrar Dene',
            textColor: Colors.white,
            onPressed: () {
              // Retry purchase
              _handlePurchase();
            },
          ),
        ),
      );
      
    }
  }

  String _getButtonText() {
    if (_product == null) {
      return _status;
    }
    
    // Error state'de retry buton text
    if (_hasError) {
      return 'Tekrar Dene - ${_product!.price}';
    }
    
    if (widget.customButtonText != null) {
      return '${widget.customButtonText} - ${_product!.price}';
    }
    
    // Premium subscription için spesifik text'ler
    if (widget.internalProductId.startsWith('premium_')) {
      switch (widget.internalProductId) {
        case 'premium_weekly':
          return 'Haftalık Premium - ${_product!.price}';
        case 'premium_monthly':
          return 'Aylık Premium - ${_product!.price}';
        case 'premium_quarterly':
          return '3 Aylık Premium - ${_product!.price}';
        default:
          return 'Premium Başlat - ${_product!.price}';
      }
    }
    
    // Super likes için özel text  
    if (widget.internalProductId.startsWith('super_likes_')) {
      return 'Satın Al - ${_product!.price}';
    }
    
    // Diamonds için özel text
    if (widget.internalProductId.startsWith('diamonds_')) {
      return 'Satın Al - ${_product!.price}';
    }
    
    // Default
    return '${_product!.title} - ${_product!.price}';
  }

  Color _getButtonColor() {
    if (_product == null) {
      return Colors.grey;
    }
    
    // Error state'de orange/retry rengi
    if (_hasError) {
      return Colors.orange;
    }
    
    // Premium için mor
    if (widget.internalProductId.startsWith('premium_')) {
      return Colors.purple;
    }
    
    // Super likes için altın
    if (widget.internalProductId.startsWith('super_likes_')) {
      return Colors.amber;
    }
    
    // Default
    return Theme.of(context).primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    // 🛡️ SPAM PROTECTION - Processing durumunda da disable et
    final isEnabled = _product != null && !_isLoading && !_isProcessingPayment;
    
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ElevatedButton(
        onPressed: isEnabled ? _handlePurchase : null,
        style: widget.buttonStyle ?? ElevatedButton.styleFrom(
          backgroundColor: _getButtonColor(),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading && !widget.disableLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                _getButtonText(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}
