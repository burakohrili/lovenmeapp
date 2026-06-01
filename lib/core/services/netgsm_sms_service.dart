import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class NetGsmSmsService {
  // OTP gönderimi artık Cloud Function üzerinden yapılır
  // NetGSM credentials server-side'da güvende

  /// OTP kodu oluştur ve gönder (Cloud Function üzerinden)
  static Future<bool> sendOtpSms(
    String phoneNumber, {
    String? customMessage,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('sendOtpSms');
      
      final result = await callable.call<Map<String, dynamic>>({
        'phoneNumber': phoneNumber,
      });

      final data = result.data;
      return data['success'] == true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ OTP SMS hatası: $e');
      }
      return false;
    }
  }

  /// OTP kodunu doğrula (Cloud Function üzerinden — server-side doğrulama)
  static Future<bool> verifyOtpCode(String phoneNumber, String enteredCode) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('verifyOtpSms');
      
      final result = await callable.call<Map<String, dynamic>>({
        'phoneNumber': phoneNumber,
        'otpCode': enteredCode,
      });

      final data = result.data;
      return data['success'] == true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ OTP doğrulama hatası: $e');
      }
      return false;
    }
  }
}
