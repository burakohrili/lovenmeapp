import 'package:lovenme/core/models/payment_models.dart';
import 'package:lovenme/core/services/payment_service.dart';

/// PaymentPackage'ı PurchaseItem'a dönüştürür
class PaymentHelper {
  static PurchaseItem convertPackageToPurchaseItem(PaymentPackage package) {
    // Tip belirleme
    PurchaseType type;
    Map<String, dynamic> benefits = {};
    
    if (package.id.contains('diamond')) {
      type = PurchaseType.superLikes; // Diamond'lar super like olarak geçiyor
      benefits = {
        'diamonds': package.amount,
      };
    } else if (package.id.contains('super_like')) {
      type = PurchaseType.superLikes;
      benefits = {
        'superLikes': package.amount, // Super like sayısı
      };
    } else if (package.id.contains('premium')) {
      type = PurchaseType.premium;
      final duration = _getPremiumDuration(package.id);
      benefits = {
        'duration': duration,
        'type': package.title.toLowerCase().contains('weekly') ? 'weekly' :
                package.title.toLowerCase().contains('monthly') ? 'monthly' :
                package.title.toLowerCase().contains('yearly') ? 'yearly' : 'weekly',
      };
    } else {
      type = PurchaseType.likes;
      benefits = {
        'likes': package.amount,
      };
    }

    return PurchaseItem(
      id: package.id,
      title: package.title,
      description: package.description,
      price: package.price,
      currency: 'TRY',
      type: type,
      benefits: benefits,
    );
  }

  static Map<String, dynamic> _getPremiumDuration(String packageId) {
    if (packageId.contains('weekly')) {
      return {'days': 7};
    } else if (packageId.contains('monthly')) {
      return {'days': 30};
    } else if (packageId.contains('yearly')) {
      return {'days': 365};
    }
    return {'days': 7}; // Default
  }
}
