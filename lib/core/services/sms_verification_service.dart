import 'package:cloud_functions/cloud_functions.dart';

class SmsVerificationService {
  static final SmsVerificationService _instance = SmsVerificationService._internal();
  factory SmsVerificationService() => _instance;
  SmsVerificationService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// SMS doğrulama kodu gönder (reCAPTCHA bypass)
  Future<SmsVerificationResult> sendVerificationCode(
    String phoneNumber,
    String userName,
  ) async {
    try {

      final HttpsCallable callable = _functions.httpsCallable(
        'sendSmsVerification',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 30),
        ),
      );

      final result = await callable.call({
        'phoneNumber': phoneNumber,
        'userName': userName,
      });

      final data = result.data as Map<String, dynamic>;

      if (data['success'] == true) {
        
        return SmsVerificationResult(
          success: true,
          message: data['message'] ?? 'SMS kodu gönderildi',
          // Development için kodu al - production'da kaldırılacak
          developmentCode: data['developmentCode'],
        );
      } else {
        return SmsVerificationResult(
          success: false,
          error: data['error'] ?? 'SMS gönderilemedi',
        );
      }
    } catch (e) {
      return SmsVerificationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// SMS kodunu doğrula
  Future<SmsVerificationResult> verifyCode(
    String phoneNumber,
    String code,
  ) async {
    try {

      final HttpsCallable callable = _functions.httpsCallable(
        'verifySmsCode',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 30),
        ),
      );

      final result = await callable.call({
        'phoneNumber': phoneNumber,
        'code': code,
      });

      final data = result.data as Map<String, dynamic>;

      if (data['success'] == true) {
        
        return SmsVerificationResult(
          success: true,
          message: data['message'] ?? 'Telefon numarası doğrulandı',
          phoneNumber: data['phoneNumber'],
        );
      } else {
        return SmsVerificationResult(
          success: false,
          error: data['error'] ?? 'Doğrulama başarısız',
        );
      }
    } catch (e) {
      return SmsVerificationResult(
        success: false,
        error: e.toString(),
      );
    }
  }
}

class SmsVerificationResult {
  final bool success;
  final String? message;
  final String? error;
  final String? phoneNumber;
  final String? developmentCode; // Development için

  SmsVerificationResult({
    required this.success,
    this.message,
    this.error,
    this.phoneNumber,
    this.developmentCode,
  });

  @override
  String toString() {
    return 'SmsVerificationResult(success: $success, message: $message, error: $error)';
  }
}
