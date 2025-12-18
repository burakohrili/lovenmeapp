import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NetGsmSmsService {
  static const String _baseUrl = 'https://api.netgsm.com.tr';
  
  // NetGSM credentials - gerçek değerler
  static const String _userCode = '2323323097'; // NetGSM kullanıcı kodu
  static const String _password = 'R5.64673'; // NetGSM şifresi (yeni şifre)
  static const String _smsHeader = '2323323097'; // SMS başlığı (kullanıcı kodunu kullan)
  
  static final Map<String, String> _otpCodes = {}; // Geçici OTP saklama

  /// OTP kodu oluştur ve gönder
  static Future<bool> sendOtpSms(
    String phoneNumber, {
    String? customMessage,
  }) async {
    try {
      // OTP kodu oluştur (6 haneli)
      final otpCode = _generateOtpCode();
      
      // Telefon numarasını temizle (+ işaretini kaldır)
      final cleanPhoneNumber = phoneNumber.replaceAll('+', '');
      
      // OTP kodunu geçici olarak sakla
      _otpCodes[cleanPhoneNumber] = otpCode;
      
      // SMS mesajını hazırla
      final message = customMessage?.replaceAll('{CODE}', otpCode) ??
          'Lovenme doğrulama kodunuz: $otpCode\n\nBu kodu kimseyle paylaşmayın.';


      // NetGSM API'sine GET isteği ile gönder (GitHub OTP repo formatı)
      // GitHub: https://github.com/netgsm1/otp
      const baseUrl = '$_baseUrl/sms/send/get/';
      final params = [
        'usercode=$_userCode',
        'password=${Uri.encodeComponent(_password)}',
        'gsmno=$cleanPhoneNumber',
        'message=${Uri.encodeComponent(message)}',
        'msgheader=$_smsHeader',
      ];
      
      final fullUrl = '$baseUrl?${params.join('&')}';
      final url = Uri.parse(fullUrl);


      final response = await http.get(url);


      if (response.statusCode == 200) {
        final responseBody = response.body.trim();
        
        // NetGSM başarı kodları: 00, 01, 02
        if (responseBody.startsWith('00') || 
            responseBody.startsWith('01') || 
            responseBody.startsWith('02')) {
          return true;
        } else {
          // Hata kodlarını detaylandır
          final errorMessage = _getNetGsmErrorMessage(responseBody);
          return false;
        }
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// OTP kodunu doğrula
  static bool verifyOtpCode(String phoneNumber, String enteredCode) {
    try {
      final cleanPhoneNumber = phoneNumber.replaceAll('+', '');
      final storedCode = _otpCodes[cleanPhoneNumber];
      

      if (storedCode != null && storedCode == enteredCode) {
        // Başarılı doğrulama sonrası kodu sil
        _otpCodes.remove(cleanPhoneNumber);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// 6 haneli rastgele OTP kodu oluştur
  static String _generateOtpCode() {
    final random = Random();
    final code = (100000 + random.nextInt(900000)).toString();
    return code;
  }

  /// Saklanan OTP kodlarını temizle (güvenlik için)
  static void clearOtpCodes() {
    _otpCodes.clear();
  }

  /// Development için - saklanan OTP kodlarını görüntüle
  static Map<String, String> getStoredOtpCodes() {
    if (kDebugMode) {
      return Map.from(_otpCodes);
    }
    return {};
  }
  /// NetGSM hata kodlarını açıkla
  static String _getNetGsmErrorMessage(String errorCode) {
    switch (errorCode.trim()) {
      case '20':
        return 'Mesaj metninde hata var';
      case '30':
        return 'Geçersiz kullanıcı adı, şifre veya kullanıcı yetkisi yok';
      case '40':
        return 'Mesaj başlığı (header) sisteme tanımlı değil';
      case '50':
        return 'Abone bulunamadı';
      case '51':
        return 'Numara hatalı';
      case '60':
        return 'Kota aşıldı';
      case '70':
        return 'Mesaj başlığı (header) onaylı değil';
      case '80':
        return 'Mesaj gönderilemedi';
      case '85':
        return 'Geçersiz tarih formatı';
      case '100':
        return 'Sistem hatası';
      case '101':
        return 'Sistem hatası';
      default:
        return 'Bilinmeyen hata kodu: $errorCode';
    }
  }
}

/// NetGSM SMS sonuç sınıfı
class NetGsmSmsResult {
  final bool success;
  final String? message;
  final String? error;
  final String? otpCode; // Development için

  NetGsmSmsResult({
    required this.success,
    this.message,
    this.error,
    this.otpCode,
  });
}
