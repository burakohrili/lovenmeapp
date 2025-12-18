// lib/core/services/auto_login_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase/firebase_auth.dart';

class AutoLoginService {
  static const String _keyRememberMe = 'remember_me_v2';
  static const String _keyLastEmail = 'last_email_v2';
  static const String _keyAutoLoginEnabled = 'auto_login_enabled_v2';
  static const String _keyLastLoginTime = 'last_login_time_v2';

  final AuthService _authService = AuthService();
  SharedPreferences? _prefs;

  // SharedPreferences instance'ını güvenli şekilde al
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // Remember me durumunu kaydet
  Future<void> setRememberMe(bool remember, {String? email}) async {
    try {
      final prefs = await _getPrefs();
      
      // Önce tüm auto-login verilerini temizle
      await prefs.remove(_keyRememberMe);
      await prefs.remove(_keyLastEmail);
      await prefs.remove(_keyAutoLoginEnabled);
      await prefs.remove(_keyLastLoginTime);
      
      if (kDebugMode) {
      }
      
      if (remember && email != null && email.isNotEmpty) {
        // Sırayla kaydet ve her birini kontrol et
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        
        final rememberSuccess = await prefs.setBool(_keyRememberMe, remember);
        await prefs.commit();
        
        final emailSuccess = await prefs.setString(_keyLastEmail, email);
        await prefs.commit();
        
        final enabledSuccess = await prefs.setBool(_keyAutoLoginEnabled, true);
        await prefs.commit();
        
        final timeSuccess = await prefs.setInt(_keyLastLoginTime, currentTime);
        await prefs.commit();
        
        if (kDebugMode) {
        }
        
        // Kayıt kontrolü yap
        await Future.delayed(const Duration(milliseconds: 100));
        final savedRemember = prefs.getBool(_keyRememberMe) ?? false;
        final savedEmail = prefs.getString(_keyLastEmail) ?? '';
        final savedEnabled = prefs.getBool(_keyAutoLoginEnabled) ?? false;
        final savedTime = prefs.getInt(_keyLastLoginTime) ?? 0;
        
        if (kDebugMode) {
        }
        
        // Release modunda da çalışsın diye kontrol
        if (!savedRemember || savedEmail != email || !savedEnabled || savedTime != currentTime) {
          if (kDebugMode) {
          }
          // Tekrar dene - güçlü şekilde
          await Future.delayed(const Duration(milliseconds: 200));
          await prefs.setBool(_keyRememberMe, remember);
          await prefs.setString(_keyLastEmail, email);
          await prefs.setBool(_keyAutoLoginEnabled, true);
          await prefs.setInt(_keyLastLoginTime, currentTime);
          await prefs.commit();
          
          // Son kontrol
          await Future.delayed(const Duration(milliseconds: 100));
          final finalCheck = prefs.getBool(_keyRememberMe) ?? false;
          if (kDebugMode) {
          }
        }
      } else {
        if (kDebugMode) {
        }
        await prefs.commit();
      }
      
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Auto-login durumunu kontrol et
  Future<bool> isAutoLoginEnabled() async {
    try {
      final prefs = await _getPrefs();
      
      // Verileri oku
      final rememberMe = prefs.getBool(_keyRememberMe) ?? false;
      final autoLoginEnabled = prefs.getBool(_keyAutoLoginEnabled) ?? false;
      final lastLoginTime = prefs.getInt(_keyLastLoginTime) ?? 0;
      final lastEmail = prefs.getString(_keyLastEmail) ?? '';
      
      if (kDebugMode) {
      }
      
      // Eğer remember me false ise veya email boşsa direkt false döndür
      if (!rememberMe || !autoLoginEnabled || lastEmail.isEmpty) {
        return false;
      }
      
      // 30 gün geçmişse auto-login'i devre dışı bırak
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final lastLogin = DateTime.fromMillisecondsSinceEpoch(lastLoginTime);
      
      if (lastLogin.isBefore(thirtyDaysAgo)) {
        if (kDebugMode) {
        }
        await clearAutoLoginData();
        return false;
      }
      
      final result = rememberMe && autoLoginEnabled;
      if (kDebugMode) {
      }
      return result;
      
    } catch (e) {
      if (kDebugMode) {
      }
      return false;
    }
  }

  // Kayıtlı email'i al
  Future<String?> getLastEmail() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_keyLastEmail);
    } catch (e) {
      if (kDebugMode) {
      }
      return null;
    }
  }

  // Auto-login verilerini temizle
  Future<void> clearAutoLoginData() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_keyRememberMe);
      await prefs.remove(_keyLastEmail);
      await prefs.remove(_keyAutoLoginEnabled);
      await prefs.remove(_keyLastLoginTime);
      await prefs.commit();
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Auto-login kontrolü yap
  Future<AutoLoginResult> checkAutoLogin() async {
    try {
      if (kDebugMode) {
      }
      
      // SharedPreferences durumunu kontrol et
      final prefs = await _getPrefs();
      final rememberMe = prefs.getBool(_keyRememberMe) ?? false;
      final autoLoginEnabled = prefs.getBool(_keyAutoLoginEnabled) ?? false;
      final lastEmail = prefs.getString(_keyLastEmail);
      
      if (kDebugMode) {
      }
      
      // Auto-login aktif mi?
      final isEnabled = await isAutoLoginEnabled();
      if (!isEnabled) {
        if (kDebugMode) {
        }
        return AutoLoginResult.disabled;
      }

      // Firebase'de kullanıcı var mı? (Direct Firebase kullan)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (kDebugMode) {
      }
      
      if (currentUser == null) {
        if (kDebugMode) {
        }
        await clearAutoLoginData();
        return AutoLoginResult.failed;
      }

      // Email doğrulanmış mı? (Release için devre dışı bırak)
      if (kDebugMode) {
      }
      // GEÇICI: Email verification kontrolünü atlat
      /*
      if (!currentUser.emailVerified) {
        return AutoLoginResult.emailNotVerified;
      }
      */

      // Kullanıcı verilerini kontrol et
      if (kDebugMode) {
      }
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
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

    } catch (e) {
      if (kDebugMode) {
      }
      return AutoLoginResult.failed;
    }
  }

  // Son giriş zamanını güncelle
  Future<void> _updateLastLoginTime() async {
    try {
      final prefs = await _getPrefs();
      await prefs.setInt(_keyLastLoginTime, DateTime.now().millisecondsSinceEpoch);
      await prefs.commit();
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Logout sırasında auto-login verilerini temizle
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

// Extension for easy checking
extension AutoLoginResultExtension on AutoLoginResult {
  bool get isSuccess => this == AutoLoginResult.success;
  bool get shouldNavigateToHome => this == AutoLoginResult.success;
  bool get shouldNavigateToLogin => this != AutoLoginResult.success;
}
