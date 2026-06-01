import 'package:flutter/material.dart';
import 'package:lovenme/core/models/payment_models.dart';
import 'package:lovenme/core/theme/app_colors.dart';
import 'package:lovenme/presentation/widgets/payment/universal_payment_button.dart';

/// Hızlı Satın Alma Widget'ı
/// Kompakt tasarım, navigation bar'larda ve küçük alanlarda kullanım için
class QuickPurchaseWidget extends StatelessWidget {
  /// Ödeme paketi
  final PaymentPackage package;

  /// Ödeme başarılı callback
  final VoidCallback? onPaymentSuccess;

  /// Ödeme hatası callback
  final ValueChanged<String>? onPaymentError;

  /// Kompakt mod (sadece fiyat ve buton)
  final bool ultraCompact;

  /// Yatay layout
  final bool horizontal;

  const QuickPurchaseWidget({
    super.key,
    required this.package,
    this.onPaymentSuccess,
    this.onPaymentError,
    this.ultraCompact = false,
    this.horizontal = true,
  });

  @override
  Widget build(BuildContext context) {
    if (ultraCompact) {
      return _buildUltraCompactVersion(context);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primaryLight,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getPackageIcon(),
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            package.priceString ?? '${package.price.toStringAsFixed(0)} ₺',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _showPurchaseDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'AL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUltraCompactVersion(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPurchaseDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          package.priceString ?? '₺${package.price.toStringAsFixed(0)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  IconData _getPackageIcon() {
    switch (package.type) {
      case PaymentType.muhtar:
        return Icons.account_balance;
      case PaymentType.premium:
        return Icons.star;
      case PaymentType.diamond:
        return Icons.diamond;
      case PaymentType.superlike:
        return Icons.favorite;
    }
  }

  void _showPurchaseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _getPackageIcon(),
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      package.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
              Text(
                package.description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (package.features.isNotEmpty) ...[
                ...package.features.take(3).map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Toplam:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (package.hasDiscount) ...[
                        Text(
                          '₺${package.originalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        package.priceString ?? '₺${package.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              UniversalPaymentButton(
                package: package,
                onPaymentSuccess: () {
                  Navigator.of(context).pop();
                  onPaymentSuccess?.call();
                },
                onPaymentError: onPaymentError,
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
