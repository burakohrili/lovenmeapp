import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'dart:math' as math;
import '../../../core/theme/app_colors.dart';
import '../../../utils/image_picker_service.dart';
import 'profile_setup_step3_page.dart';
import 'user_profile_provider.dart';

class ProfileSetupStep2Page extends ConsumerStatefulWidget {
  const ProfileSetupStep2Page({super.key});

  @override
  ConsumerState<ProfileSetupStep2Page> createState() => _ProfileSetupStep2PageState();
}

class _ProfileSetupStep2PageState extends ConsumerState<ProfileSetupStep2Page> {
  List<File?> photoFiles = List.filled(6, null); // File objelerini tutar
  List<String?> photoPaths = List.filled(6, null); // Path'leri provider için
  int selectedPhotoCount = 0;
  final int minPhotos = 2;
  final int maxPhotos = 6;
  final ImagePicker _picker = ImagePicker();
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    // initState'te ref.read kullanıyoruz (ref.watch değil!)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingPhotos();
    });
  }

  void _loadExistingPhotos() {
    // Provider'dan mevcut fotoğrafları yükle (geri geldiğinde)
    final profile = ref.read(userProfileProvider);
    if (profile.localPhotoPaths.isNotEmpty) {
      setState(() {
        selectedPhotoCount = 0;
        for (int i = 0; i < profile.localPhotoPaths.length && i < 6; i++) {
          final path = profile.localPhotoPaths[i];
          final file = File(path);
          
          // Dosya gerçekten var mı kontrol et
          if (file.existsSync()) {
            photoPaths[i] = path;
            photoFiles[i] = file;
            selectedPhotoCount++;
          }
        }
      });
      
    }
  }

  Future<void> _pickFromCamera() async {
    if (selectedPhotoCount >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('En fazla $maxPhotos fotoğraf ekleyebilirsiniz'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      setState(() => isProcessing = true);
      
      // Kamera ile fotoğraf seç ve crop et
      final File? croppedImage = await ImagePickerService.pickAndCropImage(
        context: context,
        source: ImageSource.camera,
        aspectRatioPresets: [
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio3x2,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9,
        ],
      );
      
      if (croppedImage != null) {
        _addPhotoToList(croppedImage.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kamera açılamadı: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (selectedPhotoCount >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('En fazla $maxPhotos fotoğraf ekleyebilirsiniz'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      setState(() => isProcessing = true);
      
      // Galeri ile fotoğraf seç ve crop et
      final File? croppedImage = await ImagePickerService.pickGalleryImage(context);
      
      if (croppedImage != null) {
        _addPhotoToList(croppedImage.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Galeri açılamadı: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  void _addPhotoToList(String imagePath) {
    // Dosyanın gerçekten var olduğunu kontrol et
    final file = File(imagePath);
    if (!file.existsSync()) {
      return;
    }

    // İlk boş slotu bul
    for (int i = 0; i < photoFiles.length; i++) {
      if (photoFiles[i] == null) {
        setState(() {
          photoFiles[i] = file;
          photoPaths[i] = imagePath;
          selectedPhotoCount++;
        });
        
        break;
      }
    }
  }

  void _removePhoto(int index) {
    if (index < 0 || index >= photoFiles.length) return;
    
    setState(() {
      // Fotoğrafı sil
      photoFiles[index] = null;
      photoPaths[index] = null;
      selectedPhotoCount--;
      
      // Boşlukları kapat - diğer fotoğrafları kaydır
      for (int i = index; i < photoFiles.length - 1; i++) {
        photoFiles[i] = photoFiles[i + 1];
        photoPaths[i] = photoPaths[i + 1];
      }
      
      // Son slotu temizle
      photoFiles[photoFiles.length - 1] = null;
      photoPaths[photoPaths.length - 1] = null;
    });
    
  }

  void _handleNext() {
    if (selectedPhotoCount < minPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('En az $minPhotos fotoğraf eklemelisiniz'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Provider'a LOCAL dosya path'lerini kaydet
    final validPaths = photoPaths
        .where((p) => p != null)
        .cast<String>()
        .toList();
    
    // Path'lerin gerçekten var olduğunu kontrol et
    final existingPaths = validPaths.where((path) {
      return File(path).existsSync();
    }).toList();
    
    if (existingPaths.length < minPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bazı fotoğraflar bulunamadı. Lütfen tekrar ekleyin.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    
    // Provider'ı güncelle
    ref.read(userProfileProvider.notifier).updateLocalPhotoPaths(existingPaths);
    
    
    // Step 3'e geçiş
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileSetupStep3Page(),
      ),
    );
  }

  void _showPhotoSourceDialog() {
    if (selectedPhotoCount >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('En fazla $maxPhotos fotoğraf ekleyebilirsiniz'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
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
                'Fotoğraf Ekle',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                title: const Text('Kamera'),
                subtitle: const Text('Yeni bir fotoğraf çek'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.primary),
                title: const Text('Galeri'),
                subtitle: const Text('Galerideki fotoğraflardan seç'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhotoOptions(int index) {
    if (photoFiles[index] == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
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
                'Fotoğraf İşlemleri',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.visibility, color: AppColors.primary),
                title: const Text('Fotoğrafı Görüntüle'),
                onTap: () {
                  Navigator.pop(context);
                  _showPhotoPreview(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.change_circle, color: AppColors.primary),
                title: const Text('Değiştir'),
                subtitle: const Text('Başka bir fotoğraf seç'),
                onTap: () {
                  Navigator.pop(context);
                  _replacePhoto(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Sil', style: TextStyle(color: AppColors.error)),
                subtitle: const Text('Bu fotoğrafı kaldır'),
                onTap: () {
                  Navigator.pop(context);
                  _removePhoto(index);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhotoPreview(int index) {
    if (photoFiles[index] == null) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SafeArea(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  photoFiles[index]!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _replacePhoto(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Fotoğrafı Değiştir',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                title: const Text('Kamera'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image = await _picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 80,
                    maxWidth: 1080,
                    maxHeight: 1920,
                  );
                  if (image != null) {
                    setState(() {
                      photoFiles[index] = File(image.path);
                      photoPaths[index] = image.path;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.primary),
                title: const Text('Galeri'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image = await _picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 80,
                    maxWidth: 1080,
                    maxHeight: 1920,
                  );
                  if (image != null) {
                    setState(() {
                      photoFiles[index] = File(image.path);
                      photoPaths[index] = image.path;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSlot(int index) {
    final hasPhoto = photoFiles[index] != null;
    final isMainPhoto = index == 0;
    
    return GestureDetector(
      onTap: isProcessing 
          ? null 
          : () {
              if (hasPhoto) {
                _showPhotoOptions(index);
              } else {
                _showPhotoSourceDialog();
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: hasPhoto 
              ? AppColors.grey200 
              : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPhoto 
                ? AppColors.primary.withOpacity(0.5)
                : Colors.white.withOpacity(0.5),
            width: hasPhoto ? 2 : 1,
          ),
          boxShadow: hasPhoto 
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: hasPhoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  // Fotoğraf
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      photoFiles[index]!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: AppColors.grey200,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: AppColors.error,
                                size: 32,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Yüklenemedi',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                    ),
                  ),
                  
                  // Remove Button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _removePhoto(index),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close,
                          color: AppColors.error,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  
                  // Main Photo Badge
                  if (isMainPhoto)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Ana Fotoğraf',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isMainPhoto ? Icons.add_a_photo : Icons.add_photo_alternate,
                    size: isMainPhoto ? 40 : 32,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isMainPhoto ? 'Ana Fotoğraf' : 'Fotoğraf ${index + 1}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (isMainPhoto)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Zorunlu',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Safe area padding değerlerini al
    final safePadding = MediaQuery.of(context).padding;
    final bottomSafeArea = safePadding.bottom;
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryRegisterGradient,
          ),
        ),
        child: SafeArea(
          // Tüm kenarlar için safe area'yı aktif et
          top: true,
          bottom: true,
          left: true,
          right: true,
          child: SingleChildScrollView(
            // Safe area ile uyumlu padding
            padding: EdgeInsets.fromLTRB(
              24.0, // left
              24.0, // top
              24.0, // right  
              math.max(24.0, bottomSafeArea + 8.0), // bottom - safe area + extra
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                
                // Progress Indicator
                Row(
                  children: List.generate(7, (index) {
                    final isCompleted = index < 2;
                    final isCurrent = index == 1;
                    
                    return Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isCompleted || isCurrent
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (index < 6)
                            Expanded(
                              child: Container(
                                height: 2,
                                color: isCompleted && !isCurrent
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.3),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),
                
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'Fotoğraflarını Ekle',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  '2/7 - En az $minPhotos, en fazla $maxPhotos fotoğraf',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 32),
                
                // Photo Counter
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selectedPhotoCount >= minPhotos
                        ? Colors.green.withOpacity(0.3)
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selectedPhotoCount >= minPhotos
                          ? Colors.green
                          : Colors.white.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selectedPhotoCount >= minPhotos
                            ? Icons.check_circle
                            : Icons.photo_camera,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$selectedPhotoCount / $maxPhotos fotoğraf',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Photo Grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) => _buildPhotoSlot(index),
                ),
                
                const SizedBox(height: 32),
                
                // Info Cards
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.white.withOpacity(0.9),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'İlk fotoğrafın ana profil fotoğrafın olacak',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Colors.yellow.withOpacity(0.9),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'En iyi sonuçlar için yüzünün net göründüğü fotoğraflar seç',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            color: Colors.white.withOpacity(0.7),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Fotoğraflar son adımda yüklenecek',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Next Button
                ElevatedButton(
                  onPressed: selectedPhotoCount >= minPhotos && !isProcessing
                      ? _handleNext 
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedPhotoCount >= minPhotos 
                        ? Colors.white 
                        : Colors.white.withOpacity(0.3),
                    foregroundColor: selectedPhotoCount >= minPhotos 
                        ? AppColors.primary 
                        : Colors.white.withOpacity(0.7),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: selectedPhotoCount >= minPhotos ? 2 : 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isProcessing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      else ...[
                        Text(
                          selectedPhotoCount >= minPhotos 
                              ? 'Devam Et' 
                              : 'En az $minPhotos fotoğraf gerekli',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (selectedPhotoCount >= minPhotos) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward),
                        ],
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Back Button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Geri Dön',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}