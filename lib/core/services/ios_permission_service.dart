import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_colors.dart';

class IOSPermissionService {
  /// iOS'ta kalıcı olarak reddedilen izinleri handle et
  static Future<void> handleCameraPermissionIssue(BuildContext context) async {
    if (!Platform.isIOS) return;

    
    try {
      // Mevcut kamera izin durumunu kontrol et
      final cameraStatus = await Permission.camera.status;
      
      switch (cameraStatus) {
        case PermissionStatus.granted:
          _showSuccessMessage(context, 'Kamera izni aktif! ✅');
          break;
          
        case PermissionStatus.denied:
          await _requestCameraPermission(context);
          break;
          
        case PermissionStatus.permanentlyDenied:
          await _showPermanentlyDeniedDialog(context);
          break;
          
        case PermissionStatus.restricted:
          _showRestrictedMessage(context);
          break;
          
        default:
          await _requestCameraPermission(context);
      }
      
    } catch (e) {
      _showErrorMessage(context, 'İzin kontrolü başarısız: $e');
    }
  }

  /// Kamera iznini iste
  static Future<void> _requestCameraPermission(BuildContext context) async {
    final shouldRequest = await _showPermissionRequestDialog(context);
    
    if (!shouldRequest || !context.mounted) return;
    
    final result = await Permission.camera.request();
    
    switch (result) {
      case PermissionStatus.granted:
        _showSuccessMessage(context, 'Kamera izni başarıyla verildi! ✅');
        break;
      case PermissionStatus.permanentlyDenied:
        await _showPermanentlyDeniedDialog(context);
        break;
      default:
        _showErrorMessage(context, 'Kamera izni reddedildi');
    }
  }

  /// İzin isteme dialog'u
  static Future<bool> _showPermissionRequestDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: AppColors.primary, size: 28),
            SizedBox(width: 12),
            Text('Kamera İzni Gerekli'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LoveNMe\'de check-in fotoğrafları çekebilmek için kamera iznine ihtiyacımız var.',
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 16),
            Text(
              '📸 Check-in fotoğrafları\n📱 Profil fotoğrafı güncelleme\n💬 Sohbette fotoğraf paylaşma',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Şimdi Değil'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  /// Kalıcı reddedilme dialog'u
  static Future<void> _showPermanentlyDeniedDialog(BuildContext context) async {
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error, size: 28),
            SizedBox(width: 12),
            Text('İzin Sorunu'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Kamera izni kalıcı olarak reddedildi.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'İzni tekrar açmak için:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1️⃣ "Ayarları Aç" butonuna basın\n2️⃣ "Kamera" seçeneğini bulun\n3️⃣ Kamera iznini AÇIK yapın\n4️⃣ Uygulamaya geri dönün',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Ayarları Aç',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    
    if (shouldOpenSettings == true) {
      await openAppSettings();
    }
  }

  /// Başarı mesajı
  static void _showSuccessMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Hata mesajı
  static void _showErrorMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Kısıtlanmış erişim mesajı
  static void _showRestrictedMessage(BuildContext context) {
    _showErrorMessage(
      context,
      'Kamera erişimi kısıtlanmış. Ebeveyn kontrollerini kontrol edin.',
    );
  }

  /// App silip yeniden yükleme önerisi
  static Future<void> showAppReinstallSuggestion(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.refresh, color: AppColors.primary, size: 28),
            SizedBox(width: 12),
            Text('İzin Sıfırlama'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Eğer izin sorunu devam ediyorsa, uygulamayı silip yeniden yükleyebilirsiniz.',
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 16),
            Text(
              'Bu işlem tüm izinleri sıfırlar ve tekrar istenmesini sağlar.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
