// lib/core/services/secure_auto_login_service.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase/firebase_auth.dart';

class SecureAutoLoginService {
  static const String _keyRememberMe = 'secure_remember_me';
  static const String _keyLastEmail = 'secure_last_email';
  static const String _keyAutoLoginEnabled = 'secure_auto_login_enabled';
  static const String _keyLastLoginTime = 'secure_last_login_time';

  // Secure Storage instance
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      preferencesKeyPrefix: 'lovenme_',
      sharedPreferencesName: 'lovenme_secure_prefs',
    ),
  );

  final AuthService _authService = AuthService();
  Database? _database;

  // Database'i başlat
  Future<Database> _getDatabase() async {
    if (_database != null) return _database!;
    
    final dbPath = await getDatabasesPath();
    final dbFile = path.join(dbPath, 'lovenme_autologin.db');
    
    _database = await openDatabase(
      dbFile,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE auto_login(id INTEGER PRIMARY KEY, key TEXT, value TEXT)',
        );
      },
    );
    
    return _database!;
  }

  // Güvenli veri kaydetme (3 yöntem birden)
  Future<void> _saveSecureData(String key, String value) async {
    try {
      // 1. Secure Storage
      await _secureStorage.write(key: key, value: value);
      
      // 2. SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backup_$key', value);
      await prefs.commit();
      
      // 3. SQLite Database
      final db = await _getDatabase();
      await db.insert(
        'auto_login',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Güvenli veri okuma (3 yöntemden ilk bulunanı kullan)
  Future<String?> _readSecureData(String key) async {
    try {
      // 1. Önce Secure Storage'dan dene
      String? value = await _secureStorage.read(key: key);
      if (value != null && value.isNotEmpty) {
        if (kDebugMode) {
        }
        return value;
      }

      // 2. SharedPreferences'dan dene
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getString('backup_$key');
      if (value != null && value.isNotEmpty) {
        if (kDebugMode) {
        }
        // Bulduğumuz veriyi tekrar secure storage'a kaydet
        await _secureStorage.write(key: key, value: value);
        return value;
      }

      // 3. SQLite'dan dene
      final db = await _getDatabase();
      final result = await db.query(
        'auto_login',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        value = result.first['value'] as String?;
        if (value != null && value.isNotEmpty) {
          if (kDebugMode) {
          }
          // Bulduğumuz veriyi tekrar secure storage'a kaydet
          await _secureStorage.write(key: key, value: value);
          return value;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
      }
      return null;
    }
  }

  // Güvenli veri silme (3 yöntemden de sil)
  Future<void> _deleteSecureData(String key) async {
    try {
      // 1. Secure Storage
      await _secureStorage.delete(key: key);
      
      // 2. SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('backup_$key');
      await prefs.commit();
      
      // 3. SQLite
      final db = await _getDatabase();
      await db.delete('auto_login', where: 'key = ?', whereArgs: [key]);
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Remember me durumunu kaydet
  Future<void> setRememberMe(bool remember, {String? email}) async {
    try {
      if (kDebugMode) {
      }

      if (remember && email != null && email.isNotEmpty) {
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        
        await _saveSecureData(_keyRememberMe, 'true');
        await _saveSecureData(_keyLastEmail, email);
        await _saveSecureData(_keyAutoLoginEnabled, 'true');
        await _saveSecureData(_keyLastLoginTime, currentTime.toString());
        
        if (kDebugMode) {
        }
        
        // Doğrulama yap
        await Future.delayed(const Duration(milliseconds: 100));
        final verification = await _readSecureData(_keyRememberMe);
        if (kDebugMode) {
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
      final rememberMe = await _readSecureData(_keyRememberMe);
      final autoLoginEnabled = await _readSecureData(_keyAutoLoginEnabled);
      final lastEmail = await _readSecureData(_keyLastEmail);
      final lastLoginTimeStr = await _readSecureData(_keyLastLoginTime);
      
      if (kDebugMode) {
      }

      // Veriler var mı?
      if (rememberMe != 'true' || autoLoginEnabled != 'true' || lastEmail == null || lastEmail.isEmpty) {
        return false;
      }

      // 30 gün kontrolü
      if (lastLoginTimeStr != null) {
        final lastLoginTime = int.tryParse(lastLoginTimeStr) ?? 0;
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        final lastLogin = DateTime.fromMillisecondsSinceEpoch(lastLoginTime);
        
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

  // Auto-login verilerini temizle
  Future<void> clearAutoLoginData() async {
    try {
      await _deleteSecureData(_keyRememberMe);
      await _deleteSecureData(_keyLastEmail);
      await _deleteSecureData(_keyAutoLoginEnabled);
      await _deleteSecureData(_keyLastLoginTime);
      
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

      // Auto-login aktif mi?
      final isEnabled = await isAutoLoginEnabled();
      if (!isEnabled) {
        if (kDebugMode) {
        }
        return AutoLoginResult.disabled;
      }

      // Firebase'de kullanıcı var mı?
      final currentUser = FirebaseAuth.instance.currentUser;
      if (kDebugMode) {
      }
      
      if (currentUser == null) {
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
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      await _saveSecureData(_keyLastLoginTime, currentTime.toString());
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // Kayıtlı email'i al
  Future<String?> getLastEmail() async {
    return await _readSecureData(_keyLastEmail);
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
