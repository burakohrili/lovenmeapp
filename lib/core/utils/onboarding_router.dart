// lib/core/utils/onboarding_router.dart

import 'package:flutter/widgets.dart';

import '../../presentation/pages/onboarding/profile_setup_step1_page.dart';
import '../../presentation/pages/onboarding/profile_setup_step2_page.dart';
import '../../presentation/pages/onboarding/profile_setup_step3_page.dart';
import '../../presentation/pages/onboarding/profile_setup_step4_page.dart';
import '../../presentation/pages/onboarding/profile_setup_step5_page.dart';
import '../../presentation/pages/onboarding/profile_setup_step6_page.dart';
import '../../presentation/pages/onboarding/profile_setup_step7_page.dart';

/// Yarım kalmış bir profilin hangi adımdan devam edeceğini belirler.
///
/// NEDEN PAYLAŞILAN BİR YERDE:
/// Bu mantık yalnızca splash ekranında vardı. Giriş ekranı ise profili eksik
/// olan HERKESİ koşulsuz Adım 1'e gönderiyordu (`pushAndRemoveUntil`). Yani
/// Adım 6'da (SMS doğrulama) takılan bir kullanıcı, uygulamayı kapatıp
/// yeniden giriş yaptığında yedi ekranın tamamını baştan yürümek zorunda
/// kalıyordu — SMS gelmiyorsa da kalıcı olarak kilitleniyordu.
class OnboardingRouter {
  const OnboardingRouter._();

  /// Kullanıcı dokümanına bakıp devam edilecek adımı döndürür.
  static Widget resumePage(Map<String, dynamic> userData) {
    final String? name = userData['name'] as String?;
    final int? age = userData['age'] as int?;
    final List? photos = userData['photos'] as List?;
    final int? localPhotoCount = userData['localPhotoCount'] as int?;
    final List? hobbies = userData['hobbies'] as List?;
    final List? favoriteVenues = userData['favoriteVenues'] as List?;
    final bool isEmailVerified = userData['isEmailVerified'] ?? false;
    final bool isPhoneVerified = userData['isPhoneVerified'] ?? false;

    if (name == null || name.isEmpty || age == null) {
      return const ProfileSetupStep1Page();
    }

    if (photos == null || photos.length < 2) {
      // Fotoğraflar seçilmiş ama henüz yüklenmemişse ileri geç.
      if (localPhotoCount != null && localPhotoCount >= 2) {
        return const ProfileSetupStep3Page();
      }
      return const ProfileSetupStep2Page();
    }

    // Hobiler artık zorunlu değil; yalnızca hiç dokunulmamışsa o adıma dön.
    if (hobbies == null) {
      return const ProfileSetupStep3Page();
    }

    if (favoriteVenues == null || favoriteVenues.length < 3) {
      return const ProfileSetupStep4Page();
    }

    if (!isEmailVerified) {
      return const ProfileSetupStep5Page();
    }

    if (!isPhoneVerified) {
      return const ProfileSetupStep6Page();
    }

    return const ProfileSetupStep7Page();
  }
}
