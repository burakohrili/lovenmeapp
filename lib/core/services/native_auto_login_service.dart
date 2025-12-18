// lib/core/services/native_auto_login_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase/firebase_auth.dart';

class NativeAutoLoginService {
  // Native storage keys
  static const String _keyRememberMe = 'native_remember_me_v3';
  static const String _keyLastEmail = 'native_last_email_v3';
  static const String _keyLastPassword = 'native_last_password_v3'; // Encrypted
  static const String _keyAutoLoginEnabled = 'native_auto_login_enabled_v3';
  static const String _keyLastLoginTime = 'native_last_login_time_v3';

  final AuthService _authService = AuthService();

  // Basit şifreleme (XOR)
  String _encrypt(String text) {
    const key = 'lovenme2025';
    final encrypted = <int>[];
    for (int i = 0; i < text.length; i++) {
      encrypted.add(text.codeUnitAt(i) ^ key.codeUnitAt(i % key.length));
    }
    return base64Encode(encrypted);
  }

  String _decrypt(String encrypted) {
    try {
      const key = 'lovenme2025';
      final decoded = base64Decode(encrypted);
      final decrypted = StringBuffer();
      for (int i = 0; i < decoded.length; i++) {
        decrypted.writeCharCode(decoded[i] ^ key.codeUnitAt(i % key.length));
      }
      return decrypted.toString();
    } catch (e) {
      return '';
    }
  }

  // Remember me durumunu kaydet - ŞİFREYLE BİRLİKTE
  Future<void> setRememberMe(bool remember, {String? email, String? password}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (kDebugMode) {
      }

      if (remember && email != null && password != null && email.isNotEmpty && password.isNotEmpty) {
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        final encryptedPassword = _encrypt(password);
        
        // iOS için daha güvenilir kaydetme
        bool success = false;
        int attempts = 0;
        
        while (!success && attempts < 3) {
          attempts++;
          
          try {
            // Her bir değeri ayrı ayrı kaydet
            await prefs.setBool(_keyRememberMe, true);
            await prefs.setString(_keyLastEmail, email);
            await prefs.setString(_keyLastPassword, encryptedPassword);
            await prefs.setBool(_keyAutoLoginEnabled, true);
            await prefs.setInt(_keyLastLoginTime, currentTime);
            
            // iOS için commit zorla
            if (defaultTargetPlatform == TargetPlatform.iOS) {
              await prefs.commit();
              // iOS'ta ekstra bekleme
              await Future.delayed(const Duration(milliseconds: 200));
            }
            
            // Doğrulama yap
            final verification = prefs.getBool(_keyRememberMe) ?? false;
            final emailVerification = prefs.getString(_keyLastEmail) ?? '';
            
            if (verification && emailVerification == email) {
              success = true;
              if (kDebugMode) {
              }
            } else {
              if (kDebugMode) {
              }
              await Future.delayed(const Duration(milliseconds: 300));
            }
            
          } catch (e) {
            if (kDebugMode) {
            }
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        
        if (!success) {
          if (kDebugMode) {
          }
        }
        
      } else {
        await clearAutoLoginData();
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Auto-login durumunu kontrol et
  Future<bool> isAutoLoginEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final rememberMe = prefs.getBool(_keyRememberMe) ?? false;
      final autoLoginEnabled = prefs.getBool(_keyAutoLoginEnabled) ?? false;
      final lastEmail = prefs.getString(_keyLastEmail) ?? '';
      final lastPassword = prefs.getString(_keyLastPassword) ?? '';
      final lastLoginTimeStr = prefs.getInt(_keyLastLoginTime) ?? 0;
      
      if (kDebugMode) {
      }

      // Veriler var mı?
      if (!rememberMe || !autoLoginEnabled || lastEmail.isEmpty || lastPassword.isEmpty) {
        return false;
      }

      // 30 gün kontrolü
      if (lastLoginTimeStr > 0) {
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        final lastLogin = DateTime.fromMillisecondsSinceEpoch(lastLoginTimeStr);
        
        if (lastLogin.isBefore(thirtyDaysAgo)) {
          if (kDebugMode) {
          }
          await clearAutoLoginData();
          return false;
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
      }
      return false;
    }
  }

  // Oturum kapatma için otomatik giriş bilgilerini temizle
  Future<void> clearRememberMe() async {
    await clearAutoLoginData();
  }

  // Auto-login verilerini temizle
  Future<void> clearAutoLoginData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // iOS için daha güvenilir temizleme
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS'ta ayrı ayrı sil
        await prefs.remove(_keyRememberMe);
        await prefs.remove(_keyLastEmail);
        await prefs.remove(_keyLastPassword);
        await prefs.remove(_keyAutoLoginEnabled);
        await prefs.remove(_keyLastLoginTime);
        await prefs.commit();
        
        // iOS'ta ekstra bekleme ve doğrulama
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Temizlendiğini doğrula
        final stillExists = prefs.getBool(_keyRememberMe);
        if (stillExists != null) {
          // Hala varsa clear ile tümünü sil
          await prefs.clear();
          await prefs.commit();
        }
      } else {
        // Android için normal temizleme
        await prefs.remove(_keyRememberMe);
        await prefs.remove(_keyLastEmail);
        await prefs.remove(_keyLastPassword);
        await prefs.remove(_keyAutoLoginEnabled);
        await prefs.remove(_keyLastLoginTime);
        await prefs.commit();
      }
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Auto-login kontrolü yap - ŞİFREYLE BİRLİKTE GİRİŞ YAP
  Future<AutoLoginResult> checkAutoLogin() async {
    try {
      if (kDebugMode) {
      }

      // Auto-login aktif mi?
      final isEnabled = await isAutoLoginEnabled();
      if (!isEnabled) {
        if (kDebugMode) {
        }
        return AutoLoginResult.disabled;
      }

      // Kayıtlı bilgileri al
      final prefs = await SharedPreferences.getInstance();
      final lastEmail = prefs.getString(_keyLastEmail) ?? '';
      final encryptedPassword = prefs.getString(_keyLastPassword) ?? '';
      
      if (lastEmail.isEmpty || encryptedPassword.isEmpty) {
        if (kDebugMode) {
        }
        await clearAutoLoginData();
        return AutoLoginResult.failed;
      }

      // Şifreyi çöz
      final password = _decrypt(encryptedPassword);
      if (password.isEmpty) {
        if (kDebugMode) {
        }
        await clearAutoLoginData();
        return AutoLoginResult.failed;
      }

      if (kDebugMode) {
      }

      // Firebase'e giriş yap
      try {
        final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: lastEmail,
          password: password,
        );

        if (userCredential.user == null) {
          if (kDebugMode) {
          }
          await clearAutoLoginData();
          return AutoLoginResult.failed;
        }

        // Kullanıcı verilerini kontrol et
        if (kDebugMode) {
        }
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();

        if (!userDoc.exists) {
          if (kDebugMode) {
          }
          await clearAutoLoginData();
          return AutoLoginResult.failed;
        }

        if (kDebugMode) {
        }
        
        // Son giriş zamanını güncelle
        await _updateLastLoginTime();
        
        return AutoLoginResult.success;

      } on FirebaseAuthException catch (e) {
        if (kDebugMode) {
        }
        
        // Eğer şifre yanlış ise auto-login'i temizle
        if (e.code == 'wrong-password' || e.code == 'user-not-found') {
          await clearAutoLoginData();
        }
        
        return AutoLoginResult.failed;
      }

    } catch (e) {
      if (kDebugMode) {
      }
      return AutoLoginResult.failed;
    }
  }

  // Son giriş zamanını güncelle
  Future<void> _updateLastLoginTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_keyLastLoginTime, currentTime);
      await prefs.commit();
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Kayıtlı email'i al
  Future<String?> getLastEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastEmail);
    } catch (e) {
      return null;
    }
  }

  // Logout işlemi
  Future<void> handleLogout() async {
    await clearAutoLoginData();
    if (kDebugMode) {
    }
  }
}

enum AutoLoginResult {
  success,
  failed,
  disabled,
  emailNotVerified,
}
