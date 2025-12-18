import 'package:flutter/material.dart';
import 'package:lovenme/core/models/payment_models.dart';
import 'package:lovenme/core/theme/app_colors.dart';

class CustomGooglePayButton extends StatefulWidget {
  final PaymentPackage package;
  final VoidCallback? onPaymentSuccess;
  final ValueChanged<String>? onPaymentError;
  final VoidCallback? onPaymentStarted;
  final double? width;
  final double height;

  const CustomGooglePayButton({
    super.key,
    required this.package,
    this.onPaymentSuccess,
    this.onPaymentError,
    this.onPaymentStarted,
    this.width,
    this.height = 56,
  });

  @override
  State<CustomGooglePayButton> createState() => _CustomGooglePayButtonState();
}

class _CustomGooglePayButtonState extends State<CustomGooglePayButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return _buildFallbackButton();
  }

  Widget _buildFallbackButton() {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleFallbackPayment,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Satın Al - ${widget.package.price.toStringAsFixed(2)} TL',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _handleFallbackPayment() async {
    setState(() {
      _isLoading = true;
    });

    widget.onPaymentStarted?.call();

    try {
      await Future.delayed(const Duration(seconds: 2));
      widget.onPaymentSuccess?.call();
    } catch (e) {
      widget.onPaymentError?.call('Ödeme işlemi tamamlanamadı');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
