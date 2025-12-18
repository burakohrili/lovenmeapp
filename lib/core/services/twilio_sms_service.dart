import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:twilio_flutter/twilio_flutter.dart';

class TwilioSmsService {
  // Twilio API bilgileri - Gerçek hesap bilgilerinizle değiştirin
  static const String _accountSid = 'AC63807c84acdf8f996e4cdb73810e29b0'; // ✅ Doğru
  static const String _authToken = '31e6ff7f1213244b2e635cce1a4cc8da';   // 🔴 Auth Token'ı Console'dan alın
  static const String _fromPhoneNumber = '+16103475875'; // +90XXXXXXXXXX formatında
  static const String _messagingServiceSid = 'MG551fea1bc1e13a8ce309788057216409'; // Türk Telekom Service SID
  
  static late TwilioFlutter _twilioFlutter;
  
  // OTP kodları için geçici saklama (production'da database/cache kullanın)
  static final Map<String, String> _otpStorage = {};
  static final Map<String, DateTime> _otpExpiry = {};
  
  /// Twilio servisini başlat
  static void initialize() {
    _twilioFlutter = TwilioFlutter(
      accountSid: _accountSid,
      authToken: _authToken,
      twilioNumber: _fromPhoneNumber,
    );
  }
  
  /// OTP kodu oluştur (6 haneli)
  static String _generateOTP() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }
  
  /// OTP SMS gönder
  static Future<bool> sendOtpSms({
    required String phoneNumber,
    String? customMessage,
  }) async {
    try {
      // OTP kodu oluştur
      final otpCode = _generateOTP();
      
      // Telefon numarasını temizle ve uluslararası formata çevir
      final cleanPhone = _formatPhoneNumber(phoneNumber);
      
      if (cleanPhone == null) {
        return false;
      }
      
      // OTP'yi sakla (5 dakika geçerli)
      _otpStorage[cleanPhone] = otpCode;
      _otpExpiry[cleanPhone] = DateTime.now().add(const Duration(minutes: 5));
      
      // SMS mesajı
      final message = customMessage?.replaceAll('{CODE}', otpCode) ??
          'Lovenme doğrulama kodunuz: $otpCode\n\nBu kodu kimseyle paylaşmayın.';
      
      
      // Twilio SMS API'sine istek gönder
      final success = await _sendSmsViaTwilio(
        toPhoneNumber: cleanPhone,
        message: message,
      );
      
      if (success) {
        return true;
      } else {
        // OTP'yi temizle hata durumunda
        _otpStorage.remove(cleanPhone);
        _otpExpiry.remove(cleanPhone);
        return false;
      }
      
    } catch (e) {
      return false;
    }
  }
  
  /// OTP kodunu doğrula
  static bool verifyOtp({
    required String phoneNumber,
    required String otpCode,
  }) {
    try {
      final cleanPhone = _formatPhoneNumber(phoneNumber);
      
      if (cleanPhone == null) {
        return false;
      }
      
      // DEBUG: Test bypass kodları - Geliştirme için
      if (otpCode == '123456' || otpCode == '000000' || otpCode == '111111') {
        return true;
      }
      
      // DEBUG: Gerçek OTP'yi konsola yazdır (test için)
      if (_otpStorage.containsKey(cleanPhone)) {
        final realOtp = _otpStorage[cleanPhone];
      }
      
      // OTP'nin var olup olmadığını kontrol et
      if (!_otpStorage.containsKey(cleanPhone)) {
        return false;
      }
      
      // Süre dolmuş mu kontrol et
      final expiry = _otpExpiry[cleanPhone];
      if (expiry == null || DateTime.now().isAfter(expiry)) {
        _otpStorage.remove(cleanPhone);
        _otpExpiry.remove(cleanPhone);
        return false;
      }
      
      // OTP kodunu kontrol et
      final storedOtp = _otpStorage[cleanPhone];
      if (storedOtp == otpCode) {
        // Doğrulama sonrası temizle
        _otpStorage.remove(cleanPhone);
        _otpExpiry.remove(cleanPhone);
        return true;
      } else {
        return false;
      }
      
    } catch (e) {
      return false;
    }
  }
  
  /// Twilio üzerinden SMS gönder
  static Future<bool> _sendSmsViaTwilio({
    required String toPhoneNumber,
    required String message,
  }) async {
    try {
      
      // Doğrudan HTTP API kullan (TwilioFlutter package'ı atlayalım)
      return await _sendSmsViaHttpApi(
        toPhoneNumber: toPhoneNumber,
        message: message,
      );
      
    } catch (e) {
      
      // Alternatif olarak HTTP API kullan
      return await _sendSmsViaHttpApi(
        toPhoneNumber: toPhoneNumber,
        message: message,
      );
    }
  }
  
  /// HTTP API ile SMS gönder (fallback)
  static Future<bool> _sendSmsViaHttpApi({
    required String toPhoneNumber,
    required String message,
  }) async {
    try {
      final url = Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$_accountSid/Messages.json');
      
      // Messaging Service kullanarak gönder (From yerine MessagingServiceSid)
      final body = {
        'To': toPhoneNumber,
        'Body': message,
        'MessagingServiceSid': _messagingServiceSid, // Türk Telekom Service kullan
      };
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_accountSid:$_authToken'))}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));
      
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final status = responseData['status'];
        
        if (status == 'queued' || status == 'sent' || status == 'delivered' || status == 'accepted') {
          return true;
        } else {
          return false;
        }
      } else {
        final errorData = json.decode(response.body);
        return false;
      }
      
    } catch (e) {
      return false;
    }
  }
  
  /// Telefon numarasını Twilio formatına çevir
  static String? _formatPhoneNumber(String phoneNumber) {
    try {
      // Tüm özel karakterleri temizle
      String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      
      // Eğer + ile başlamıyorsa, Türkiye kodu ekle
      if (!cleaned.startsWith('+')) {
        if (cleaned.startsWith('90')) {
          cleaned = '+$cleaned';
        } else if (cleaned.startsWith('0')) {
          cleaned = '+90${cleaned.substring(1)}';
        } else {
          cleaned = '+90$cleaned';
        }
      }
      
      // Minimum 10 haneli olmalı
      if (cleaned.length < 10) {
        return null;
      }
      
      return cleaned;
      
    } catch (e) {
      return null;
    }
  }
  
  /// Toplu SMS gönder (isteğe bağlı)
  static Future<bool> sendBulkSms({
    required List<String> phoneNumbers,
    required String message,
  }) async {
    try {
      int successCount = 0;
      
      for (String phone in phoneNumbers) {
        final formattedPhone = _formatPhoneNumber(phone);
        if (formattedPhone != null) {
          final success = await _sendSmsViaTwilio(
            toPhoneNumber: formattedPhone,
            message: message,
          );
          
          if (success) successCount++;
          
          // Rate limiting için kısa bekleme
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
      
      
      return successCount > 0;
      
    } catch (e) {
      return false;
    }
  }
  
  /// SMS geçmişini sorgula (Twilio API)
  static Future<List<Map<String, dynamic>>> getSmsHistory({
    String? toPhoneNumber,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    try {
      var url = 'https://api.twilio.com/2010-04-01/Accounts/$_accountSid/Messages.json?PageSize=$limit';
      
      if (toPhoneNumber != null) {
        final formatted = _formatPhoneNumber(toPhoneNumber);
        if (formatted != null) {
          url += '&To=$formatted';
        }
      }
      
      if (startDate != null) {
        url += '&DateSent>=${startDate.toIso8601String()}';
      }
      
      if (endDate != null) {
        url += '&DateSent<=${endDate.toIso8601String()}';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_accountSid:$_authToken'))}',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      } else {
        return [];
      }
      
    } catch (e) {
      return [];
    }
  }
  
  /// OTP durumunu kontrol et (test için)
  static String? getOtpStatus(String phoneNumber) {
    final cleanPhone = _formatPhoneNumber(phoneNumber);
    
    if (cleanPhone == null || !_otpStorage.containsKey(cleanPhone)) {
      return 'OTP bulunamadı';
    }
    
    final expiry = _otpExpiry[cleanPhone];
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      return 'OTP süresi dolmuş';
    }
    
    final remainingTime = expiry.difference(DateTime.now()).inSeconds;
    return 'OTP geçerli (${remainingTime}s kaldı): ${_otpStorage[cleanPhone]}';
  }
  
  /// Test amaçlı - OTP'yi temizle
  static void clearOtp(String phoneNumber) {
    final cleanPhone = _formatPhoneNumber(phoneNumber);
    if (cleanPhone != null) {
      _otpStorage.remove(cleanPhone);
      _otpExpiry.remove(cleanPhone);
    }
  }
  
  /// Twilio hesap bilgilerini kontrol et
  static Future<bool> validateTwilioCredentials() async {
    try {
      final url = Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$_accountSid.json');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_accountSid:$_authToken'))}',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return true;
      } else {
        return false;
      }
      
    } catch (e) {
      return false;
    }
  }
}
