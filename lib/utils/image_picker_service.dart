import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/theme/app_colors.dart';

class ImagePickerService {
  static final ImagePicker _picker = ImagePicker();

  /// Cihazın safe area'sını hesapla
  static EdgeInsets _getSafeAreaPadding(BuildContext context) {
    return MediaQuery.of(context).padding;
  }

  /// Platform-specific crop ayarları
  static List<PlatformUiSettings> _getCropUiSettings(
    BuildContext context,
    List<CropAspectRatioPreset> aspectRatioPresets,
  ) {
    final safeArea = _getSafeAreaPadding(context);
    final screenSize = MediaQuery.of(context).size;
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;
    
    // 📱 DEVICE SAFE AREA CALCULATIONS
    final topPadding = safeArea.top;
    final bottomPadding = safeArea.bottom;
    final leftPadding = safeArea.left;
    final rightPadding = safeArea.right;
    
    // Safe area percentages for dynamic positioning
    final topPercent = topPadding / screenHeight;
    final bottomPercent = bottomPadding / screenHeight;
    final leftPercent = leftPadding / screenWidth;
    final rightPercent = rightPadding / screenWidth;
    
    
    return [
      AndroidUiSettings(
        toolbarTitle: 'Fotoğrafı Düzenle',
        toolbarColor: AppColors.primary,
        toolbarWidgetColor: AppColors.white,
        initAspectRatio: aspectRatioPresets.isNotEmpty ? aspectRatioPresets.first : CropAspectRatioPreset.original,
        lockAspectRatio: false,
        aspectRatioPresets: aspectRatioPresets,
        statusBarColor: AppColors.primary,
        backgroundColor: AppColors.black,
        activeControlsWidgetColor: AppColors.primary,
        dimmedLayerColor: AppColors.black.withOpacity(0.8),
        cropFrameColor: AppColors.primary,
        cropGridColor: AppColors.primary.withOpacity(0.5),
        cropFrameStrokeWidth: 2,
        cropGridStrokeWidth: 1,
        showCropGrid: true,
        hideBottomControls: false,
      ),
      IOSUiSettings(
        title: 'Fotoğrafı Düzenle',
        doneButtonTitle: 'Tamam',
        cancelButtonTitle: 'İptal',
        aspectRatioLockEnabled: false,
        resetAspectRatioEnabled: true,
        rotateButtonsHidden: false,
        rotateClockwiseButtonHidden: false,
        hidesNavigationBar: false, // 🔧 CHANGED: Don't hide navigation for better safe area handling
        aspectRatioPresets: aspectRatioPresets,
        minimumAspectRatio: 0.2,
        // 📱 DYNAMIC SAFE AREA POSITIONING
        // Crop area positioning with safe area awareness
        rectX: leftPercent + 0.05, // Safe area + padding
        rectY: topPercent + 0.08, // Safe area + toolbar space
        rectWidth: 0.9 - leftPercent - rightPercent, // Width minus safe areas
        rectHeight: 0.84 - topPercent - bottomPercent, // Height minus safe areas and controls
      ),
    ];
  }

  /// Fotoğraf seç ve crop et - Safe Area Enhanced
  static Future<File?> pickAndCropImage({
    required BuildContext context,
    ImageSource source = ImageSource.gallery,
    List<CropAspectRatioPreset> aspectRatioPresets = const [
      CropAspectRatioPreset.original,
      CropAspectRatioPreset.square,
      CropAspectRatioPreset.ratio3x2,
      CropAspectRatioPreset.ratio4x3,
      CropAspectRatioPreset.ratio16x9
    ],
  }) async {
    try {
      // İzin kontrolü
      final hasPermission = await _requestPermissions(source);
      if (!hasPermission) {
        return null;
      }


      // Fotoğraf seç
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (image == null) return null;

      // 📱 SAFE AREA ENHANCED CROP: Use wrapper function for better safe area handling
      return await _cropImageWithSafeArea(
        context: context,
        imagePath: image.path,
        aspectRatioPresets: aspectRatioPresets,
      );
    } catch (e) {
      return null;
    }
  }

  /// 📱 SAFE AREA ENHANCED CROP: Enhanced cropping with safe area consideration
  static Future<File?> _cropImageWithSafeArea({
    required BuildContext context,
    required String imagePath,
    required List<CropAspectRatioPreset> aspectRatioPresets,
  }) async {
    try {
      
      // Get device safe area info for logging
      final safeArea = _getSafeAreaPadding(context);
      final screenSize = MediaQuery.of(context).size;
      
      // Crop işlemi with enhanced settings
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: _getCropUiSettings(context, aspectRatioPresets),
      );

      if (croppedFile != null) {
        return File(croppedFile.path);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Settings'e yönlendirme dialog'u göster - iOS için geliştirilmiş
  static Future<void> showPermissionDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Kamera İzni Gerekli'),
          ],
        ),
        content: const Text(
          'Check-in fotoğrafı çekebilmek için kamera iznini açmanız gerekiyor.\n\n'
          'iOS Ayarlar > Gizlilik ve Güvenlik > Kamera > LoveNMe bölümünden '
          'kamera iznini etkinleştirin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Ayarlara Git'),
          ),
        ],
      ),
    );
  }

  /// Profil fotoğrafı için özel crop (kare format) - Safe Area Enhanced
  static Future<File?> pickProfileImage(BuildContext context) {
    return pickAndCropImage(
      context: context,
      aspectRatioPresets: [CropAspectRatioPreset.square],
    );
  }

  /// Check-in fotoğrafı için özel crop (kamera + square format) - Safe Area Enhanced
  static Future<File?> pickCheckInImage(BuildContext context) {
    return pickAndCropImage(
      context: context,
      source: ImageSource.camera,
      aspectRatioPresets: [
        CropAspectRatioPreset.square,
        CropAspectRatioPreset.original,
        CropAspectRatioPreset.ratio4x3,
      ],
    );
  }

  /// Galeri fotoğrafları için özel crop (serbest format) - Safe Area Enhanced  
  static Future<File?> pickGalleryImage(BuildContext context) {
    return pickAndCropImage(
      context: context,
      aspectRatioPresets: [
        CropAspectRatioPreset.original,
        CropAspectRatioPreset.square,
        CropAspectRatioPreset.ratio3x2,
        CropAspectRatioPreset.ratio4x3,
        CropAspectRatioPreset.ratio16x9,
      ],
    );
  }

  /// İzin kontrolü ve detaylı hata yönetimi - iOS için geliştirilmiş
  static Future<bool> _requestPermissions(ImageSource source) async {
    if (source == ImageSource.camera) {
      
      final status = await Permission.camera.status;
      
      if (status == PermissionStatus.denied) {
        final result = await Permission.camera.request();
        
        if (result == PermissionStatus.granted) {
          return true;
        } else {
          // iOS-specific permission denied handling
          if (Platform.isIOS) {
          }
          // Permission request sonucunu da kaydet
          return false;
        }
      } else if (status == PermissionStatus.permanentlyDenied) {
        return false;
      } else if (status == PermissionStatus.granted) {
        return true;
      } else if (status == PermissionStatus.restricted) {
        return false;
      } else {
        final result = await Permission.camera.request();
        return result == PermissionStatus.granted;
      }
    } else {
      if (Platform.isAndroid) {
        await Permission.storage.request();
        await Permission.photos.request();
      } else if (Platform.isIOS) {
        final status = await Permission.photos.status;
        if (status != PermissionStatus.granted) {
          final result = await Permission.photos.request();
          if (result != PermissionStatus.granted) {
          }
          return result == PermissionStatus.granted;
        }
      }
      return true;
    }
  }

  /// Kaynak seçimi dialog'u - Safe Area Enhanced
  static Future<ImageSource?> showImageSourceDialog(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true, // 🔧 SAFE AREA: Allow proper safe area handling
      builder: (context) {
        return SafeArea( // 🔧 SAFE AREA: Wrap with SafeArea
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Fotoğraf Seç',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildSourceOption(
                        context: context,
                        icon: Icons.camera_alt,
                        label: 'Kamera',
                        source: ImageSource.camera,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSourceOption(
                        context: context,
                        icon: Icons.photo_library,
                        label: 'Galeri',
                        source: ImageSource.gallery,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildSourceOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: AppColors.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
