// lib/core/models/payment_models.dart

enum PaymentType {
  muhtar, // Sadece muhtar sistemi
  premium, // Premium abonelik sistemi
  diamond, // Elmas satın alma
  superlike, // Süper like satın alma
}

enum PaymentMethod {
  googlePay,
  creditCard,
}

class PaymentPackage {
  final String id;
  final PaymentType type;
  final String title;
  final String? name; // For backward compatibility
  final int amount;
  final int? diamonds; // For diamond packages
  final double price;
  final double originalPrice;
  final double discountPercentage;
  final String description;
  final String duration;
  final bool isPopular;
  final bool isRecommended;
  final List<String> features;

  PaymentPackage({
    required this.id,
    required this.type,
    required this.title,
    this.name,
    required this.amount,
    this.diamonds,
    required this.price,
    required this.originalPrice,
    this.discountPercentage = 0,
    required this.description,
    required this.duration,
    this.isPopular = false,
    this.isRecommended = false,
    this.features = const [],
  });

  double get perUnitPrice => price / amount;
  bool get hasDiscount => discountPercentage > 0;
}

class PaymentResult {
  final bool success;
  final String? transactionId;
  final String? errorMessage;
  final PaymentPackage? package;

  PaymentResult({
    required this.success,
    this.transactionId,
    this.errorMessage,
    this.package,
  });
}

class PaymentMethodAvailability {
  final bool googlePayAvailable;
  final bool creditCardAvailable;

  PaymentMethodAvailability({
    required this.googlePayAvailable,
    required this.creditCardAvailable,
  });
}
