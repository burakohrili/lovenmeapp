import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_colors.dart';

class PermissionService {
  /// iOS için home page'de kamera iznini iste
  static Future<void> requestEssentialPermissions(BuildContext context) async {
    if (!Platform.isIOS) {
      return;
    }

    
    try {
      // iOS versiyonunu kontrol et
      final iosVersion = Platform.operatingSystemVersion;
      
      // Kamera iznini kontrol et
      final cameraStatus = await Permission.camera.status;

      // iOS 17+ için photo library limited access kontrolü
      if (iosVersion.contains('17.') || iosVersion.contains('18.')) {
        final photosStatus = await Permission.photos.status;
      }

      if (cameraStatus == PermissionStatus.denied) {
        
        // Kullanıcıya neden kamera iznine ihtiyaç duyduğumuzu açıkla
        final shouldRequest = await _showPermissionExplanationDialog(context);
        
        if (shouldRequest && context.mounted) {
          
          // İlk olarak kamera iznini iste
          final result = await Permission.camera.request();
          
          // Eğer hala denied ise tekrar dene (iOS bazen böyle davranır)
          if (result == PermissionStatus.denied) {
            final retryResult = await Permission.camera.request();
            
            if (retryResult == PermissionStatus.granted) {
              _showPermissionSuccessMessage(context);
            } else if (retryResult == PermissionStatus.permanentlyDenied) {
              await _showPermanentlyDeniedDialog(context, ['Kamera']);
            }
          } else if (result == PermissionStatus.granted) {
            _showPermissionSuccessMessage(context);
          } else if (result == PermissionStatus.permanentlyDenied) {
            await _showPermanentlyDeniedDialog(context, ['Kamera']);
          } else {
          }
        } else {
        }
      } else if (cameraStatus == PermissionStatus.granted) {
      } else if (cameraStatus == PermissionStatus.permanentlyDenied) {
        await _showPermanentlyDeniedDialog(context, ['Kamera']);
      } else {
      }

    } catch (e) {
    }
  }

  /// Kullanıcıya neden kamera iznine ihtiyaç duyduğumuzu açıklayan dialog
  static Future<bool> _showPermissionExplanationDialog(BuildContext context) async {
    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.camera_alt, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Text(
                'Kamera İzni',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: const Text(
            'Profil fotoğrafı eklemek ve fotoğraf paylaşmak için kamera iznine ihtiyacımız var.\n\n'
            'Bu izin olmadan bazı özellikler çalışmayabilir.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                'Şimdi Değil',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  /// İzin verildiği zaman başarı mesajı göster
  static void _showPermissionSuccessMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text(
              '✅ Kamera izni verildi!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// Kalıcı olarak reddedilen izinler için özel dialog
  static Future<void> _showPermanentlyDeniedDialog(
    BuildContext context, 
    List<String> deniedPermissions
  ) async {
    if (!context.mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.settings, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Text(
                'İzin Ayarları',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aşağıdaki izinler kalıcı olarak reddedilmiş:',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ...deniedPermissions.map((permission) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.block, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      permission,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              const Text(
                'Bu izinleri etkinleştirmek için:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. "Ayarlara Git" butonuna tıklayın\n'
                '2. İzinler bölümünü bulun\n'
                '3. Gerekli izinleri açın\n'
                '4. Uygulamaya geri dönün',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Daha Sonra',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text(
                'Ayarlara Git',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Camera permission kontrolü
  static Future<bool> isCameraPermissionGranted() async {
    final status = await Permission.camera.status;
    return status == PermissionStatus.granted;
  }

  /// Photo library permission kontrolü
  static Future<bool> isPhotosPermissionGranted() async {
    final status = await Permission.photos.status;
    return status == PermissionStatus.granted;
  }

  /// Camera permission iste (manuel)
  static Future<PermissionStatus> requestCameraPermission() async {
    return await Permission.camera.request();
  }

  /// Photo library permission iste (manuel)
  static Future<PermissionStatus> requestPhotosPermission() async {
    return await Permission.photos.request();
  }

  /// iOS 14+ Limited Photos Access kontrolü
  static Future<bool> isPhotosLimitedAccess() async {
    if (!Platform.isIOS) return false;
    
    final status = await Permission.photos.status;
    return status == PermissionStatus.limited;
  }

  /// iOS 14+ Limited Photos için ayarlara yönlendirme
  static Future<void> openPhotosSettings() async {
    if (Platform.isIOS) {
      await openAppSettings();
    }
  }
}
