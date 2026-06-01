import 'dart:io' show Platform;

/// Platform-specific payment configuration
class PaymentConfig {
  
  /// Test için minimal fiyat döndür
  static double getTestPrice(double originalPrice) {
    if (Platform.isIOS) {
      return 0.01; // iOS'ta hep 1 kuruş
    }
    return originalPrice; // Android'de normal fiyat
  }
  
  /// Test modunda Google Pay configuration (Gerçek test arayüzü için)
  static String getGooglePayTestConfiguration({
    required double price,
    String currencyCode = "TRY",
    String countryCode = "TR",
  }) {
    return '''
{
  "provider": "google_pay",
  "data": {
    "environment": "TEST",
    "apiVersion": 2,
    "apiVersionMinor": 0,
    "allowedPaymentMethods": [
      {
        "type": "CARD",
        "parameters": {
          "allowedAuthMethods": ["PAN_ONLY", "CRYPTOGRAM_3DS"],
          "allowedCardNetworks": ["MASTERCARD", "VISA"],
          "billingAddressRequired": false,
          "billingAddressParameters": {
            "format": "MIN"
          }
        },
        "tokenizationSpecification": {
          "type": "PAYMENT_GATEWAY",
          "parameters": {
            "gateway": "cybersource",
            "gatewayMerchantId": "test_merchant_id"
          }
        }
      }
    ],
    "merchantInfo": {
      "merchantId": "01234567890123456789",
      "merchantName": "MyDateApp Test"
    },
    "transactionInfo": {
      "totalPriceStatus": "FINAL",
      "totalPrice": "${price.toStringAsFixed(2)}",
      "currencyCode": "$currencyCode",
      "countryCode": "$countryCode"
    }
  }
}
''';
  }

  /// Backward compatibility için eski static configuration
  static const String googlePayTestConfiguration = '''
{
  "provider": "google_pay",
  "data": {
    "environment": "TEST",
    "apiVersion": 2,
    "apiVersionMinor": 0,
    "allowedPaymentMethods": [
      {
        "type": "CARD",
        "parameters": {
          "allowedAuthMethods": ["PAN_ONLY", "CRYPTOGRAM_3DS"],
          "allowedCardNetworks": ["MASTERCARD", "VISA"],
          "billingAddressRequired": false,
          "billingAddressParameters": {
            "format": "MIN"
          }
        },
        "tokenizationSpecification": {
          "type": "PAYMENT_GATEWAY",
          "parameters": {
            "gateway": "cybersource",
            "gatewayMerchantId": "test_merchant_id"
          }
        }
      }
    ],
    "merchantInfo": {
      "merchantId": "01234567890123456789",
      "merchantName": "MyDateApp Test"
    },
    "transactionInfo": {
      "totalPriceStatus": "FINAL",
      "totalPrice": "1.00",
      "currencyCode": "TRY",
      "countryCode": "TR"
    }
  }
}
''';

  /// Production modunda Google Pay configuration
  static String getGooglePayProductionConfiguration({
    required double price,
    required String merchantId,
    required String gatewayMerchantId,
    required String gateway, // "stripe", "iyzico", "cybersource", etc.
    String currencyCode = "TRY",
    String countryCode = "TR",
  }) {
    return '''
{
  "provider": "google_pay",
  "data": {
    "environment": "PRODUCTION",
    "apiVersion": 2,
    "apiVersionMinor": 0,
    "allowedPaymentMethods": [
      {
        "type": "CARD",
        "parameters": {
          "allowedAuthMethods": ["PAN_ONLY", "CRYPTOGRAM_3DS"],
          "allowedCardNetworks": ["MASTERCARD", "VISA"],
          "billingAddressRequired": false,
          "billingAddressParameters": {
            "format": "MIN"
          }
        },
        "tokenizationSpecification": {
          "type": "PAYMENT_GATEWAY",
          "parameters": {
            "gateway": "$gateway",
            "gatewayMerchantId": "$gatewayMerchantId"
          }
        }
      }
    ],
    "merchantInfo": {
      "merchantId": "$merchantId",
      "merchantName": "MyDateApp"
    },
    "transactionInfo": {
      "totalPriceStatus": "FINAL",
      "totalPrice": "${price.toStringAsFixed(2)}",
      "currencyCode": "$currencyCode",
      "countryCode": "$countryCode"
    }
  }
}
''';
  }

  /// Production modunda kullanılacak (Merchant ID aldıktan sonra) - Backward compatibility
  static const String googlePayProductionConfiguration = '''
{
  "provider": "google_pay",
  "data": {
    "environment": "PRODUCTION",
    "apiVersion": 2,
    "apiVersionMinor": 0,
    "allowedPaymentMethods": [
      {
        "type": "CARD",
        "parameters": {
          "allowedAuthMethods": ["PAN_ONLY", "CRYPTOGRAM_3DS"],
          "allowedCardNetworks": ["MASTERCARD", "VISA"]
        },
        "tokenizationSpecification": {
          "type": "PAYMENT_GATEWAY",
          "parameters": {
            "gateway": "GERÇEK_GATEWAY_ADI",
            "gatewayMerchantId": "GERÇEK_MERCHANT_ID"
          }
        }
      }
    ],
    "merchantInfo": {
      "merchantId": "GERÇEK_GOOGLE_PAY_MERCHANT_ID",
      "merchantName": "MyDateApp"
    }
  }
}
''';

  /// Platform ve environment'a göre configuration döner
  static String getPaymentConfiguration({bool isProduction = false}) {
    if (Platform.isAndroid) {
      return isProduction ? googlePayProductionConfiguration : googlePayTestConfiguration;
    } else {
      return googlePayTestConfiguration; // iOS için artık Google Pay kullanıyoruz
    }
  }

  /// Platform adını döner
  static String get platformName {
    if (Platform.isAndroid) {
      return 'Google Pay';
    } else if (Platform.isIOS) {
      return 'Kart ile Ödeme';
    } else {
      return 'Kart ile Ödeme';
    }
  }

  /// Test modunda mı?
  static bool get isTestMode => false; // ✅ Production: false

  /// Desteklenen ödeme paketleri
  static const List<Map<String, dynamic>> diamondPackages = [
    {
      'diamonds': 10,
      'price': 74.99, // ✅ iap_service.dart ile senkronize
      'currency': 'TRY',
      'packageId': '10_diamonds_74_99',
      'title': '10 Elmas',
      'description': 'Muhtar teklifleri için',
    },
    {
      'diamonds': 50,
      'price': 249.99, // ✅ iap_service.dart ile senkronize
      'currency': 'TRY',
      'packageId': '50_diamonds_249_99',
      'title': '50 Elmas',
      'description': 'Büyük muhtar savaşları için',
    },
  ];
}
