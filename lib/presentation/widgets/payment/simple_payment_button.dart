import 'package:flutter/material.dart';
import 'package:lovenme/core/services/payment_service.dart';
import 'package:lovenme/core/theme/app_colors.dart';

/// Basit ödeme button'u - eski çalışan sistemle
class SimplePaymentButton extends StatefulWidget {
  final PurchaseItem item;
  final VoidCallback? onSuccess;
  final ValueChanged<String>? onError;
  final String? customText;

  const SimplePaymentButton({
    super.key,
    required this.item,
    this.onSuccess,
    this.onError,
    this.customText,
  });

  @override
  State<SimplePaymentButton> createState() => _SimplePaymentButtonState();
}

class _SimplePaymentButtonState extends State<SimplePaymentButton> {
  bool _isLoading = false;

  Future<void> _handlePurchase() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final paymentService = PaymentService();
      final success = await paymentService.purchaseItem(widget.item);

      if (success && mounted) {
        // Başarı mesajı
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.item.title} başarıyla satın alındı!',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        widget.onSuccess?.call();
      } else {
        widget.onError?.call('Satın alma işlemi başarısız oldu');
      }
    } catch (e) {
      widget.onError?.call('Satın alma işlemi tamamlanamadı');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handlePurchase,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                widget.customText ?? 'Satın Al - ${widget.item.price.toStringAsFixed(2)} ${widget.item.currency}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
