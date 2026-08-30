// lib/core/services/native_auto_login_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// "Beni hatırla" / otomatik giriş.
///
/// GÜVENLİK — bu dosya 30.08.2026'da baştan yazıldı:
/// Eskiden kullanıcının **şifresi**, kaynak kodda sabit duran `'lovenme2025'`
/// anahtarıyla XOR'lanıp base64'lenerek SharedPreferences'a yazılıyordu
/// (iOS'ta `Library/Preferences/*.plist`, Android'de `shared_prefs/*.xml`) ve
/// 30 gün orada duruyordu. Sabit anahtarlı XOR şifreleme değildir; cihaza
/// erişen biri saniyeler içinde düz şifreyi elde ederdi. Bu hem App Store
/// incelemesinde savunulamaz hem KVKK Md. 12 / GDPR Md. 32 açısından ihlaldi.
///
/// Doğru çözüm şifreyi daha iyi saklamak değil, **hiç saklamamak**:
/// Firebase Auth mobil SDK'sı oturumu zaten kalıcı tutar; uygulama yeniden
/// açıldığında `FirebaseAuth.instance.currentUser` doludur. Bu servis artık
/// yalnızca "kullanıcı otomatik girişi istedi mi" tercihini ve e-posta
/// ön-doldurma bilgisini tutuyor.
class NativeAutoLoginService {
  static const String _keyRememberMe = 'native_remember_me_v3';
  static const String _keyLastEmail = 'native_last_email_v3';
  static const String _keyAutoLoginEnabled = 'native_auto_login_enabled_v3';
  static const String _keyLastLoginTime = 'native_last_login_time_v3';

  /// Artık YAZILMAYAN, yalnızca temizlenen eski anahtarlar.
  /// `_keyLegacyPassword` eski sürümlerde şifre taşıyordu; kurulu cihazlarda
  /// kalmasın diye her fırsatta siliniyor.
  static const String _keyLegacyPassword = 'native_last_password_v3';
  static const List<String> _legacyV2Keys = [
    'auto_login_enabled_v2',
    'remember_me_v2',
    'last_email_v2',
    'last_password_v2',
    'last_login_time_v2',
  ];

  /// Otomatik girişin geçerli sayıldığı süre.
  static const Duration _maxSessionAge = Duration(days: 30);

  /// Eski sürümlerden kalan kimlik bilgilerini cihazdan siler.
  static Future<void> purgeLegacyCredentials(SharedPreferences prefs) async {
    if (prefs.containsKey(_keyLegacyPassword)) {
      await prefs.remove(_keyLegacyPassword);
    }
    for (final key in _legacyV2Keys) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    }
  }

  /// "Beni hatırla" tercihini kaydeder.
  ///
  /// [password] parametresi çağıranları bozmamak için duruyor ama
  /// **bilerek yok sayılıyor** — hiçbir yere yazılmıyor.
  Future<void> setRememberMe(
    bool remember, {
    String? email,
    String? password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await purgeLegacyCredentials(prefs);

      if (remember && email != null && email.isNotEmpty) {
        await prefs.setBool(_keyRememberMe, true);
        await prefs.setString(_keyLastEmail, email);
        await prefs.setBool(_keyAutoLoginEnabled, true);
        await prefs.setInt(
            _keyLastLoginTime, DateTime.now().millisecondsSinceEpoch);
      } else {
        await clearAutoLoginData();
      }
    } catch (_) {
      // Tercih yazılamazsa kullanıcı yalnızca tekrar giriş yapar.
    }
  }

  Future<bool> isAutoLoginEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_keyAutoLoginEnabled) ?? false)) return false;

      final lastLogin = prefs.getInt(_keyLastLoginTime);
      if (lastLogin == null) return false;

      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastLogin));
      return age <= _maxSessionAge;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearRememberMe() => clearAutoLoginData();

  /// Tercihleri temizler ve oturumu kapatır.
  ///
  /// Eski `_v2` anahtarları da burada siliniyor: ayarlar ekranındaki çıkış
  /// yalnızca onları temizliyor, canlı `_v3` anahtarlarına dokunmuyordu — bu
  /// yüzden kullanıcı çıkış yaptıktan sonra bir sonraki açılışta sessizce
  /// geri giriş yapmış oluyordu.
  Future<void> clearAutoLoginData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await purgeLegacyCredentials(prefs);
      await prefs.remove(_keyRememberMe);
      await prefs.remove(_keyLastEmail);
      await prefs.remove(_keyAutoLoginEnabled);
      await prefs.remove(_keyLastLoginTime);
    } catch (_) {
      // yutulsa bile aşağıdaki signOut çalışmalı
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  /// Açılışta oturumun devam edip etmediğini belirler.
  ///
  /// Artık şifreyle yeniden giriş YAPILMIYOR; Firebase'in kendi kalıcı
  /// oturumu okunuyor.
  Future<AutoLoginResult> checkAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await purgeLegacyCredentials(prefs);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return AutoLoginResult.disabled;
      }

      // Kullanıcı açıkça "beni hatırla" demediyse oturumu sürdürme.
      if (!await isAutoLoginEnabled()) {
        await clearAutoLoginData();
        return AutoLoginResult.disabled;
      }

      // Hesap silinmiş olabilir.
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        await clearAutoLoginData();
        return AutoLoginResult.failed;
      }

      await prefs.setInt(
          _keyLastLoginTime, DateTime.now().millisecondsSinceEpoch);
      return AutoLoginResult.success;
    } on FirebaseAuthException catch (_) {
      await clearAutoLoginData();
      return AutoLoginResult.failed;
    } catch (_) {
      return AutoLoginResult.failed;
    }
  }

  Future<String?> getLastEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastEmail);
    } catch (_) {
      return null;
    }
  }

  /// Çıkış: hem tercihleri hem oturumu temizler.
  Future<void> handleLogout() => clearAutoLoginData();
}

enum AutoLoginResult {
  success,
  failed,
  disabled,
  emailNotVerified,
}
