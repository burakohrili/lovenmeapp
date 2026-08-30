// lib/presentation/pages/profile/profile_edit_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../../../core/theme/app_colors.dart';

import '../../../core/utils/loading_state_manager.dart';
import '../../../core/utils/form_validation_helper.dart';
import '../../../widgets/production_button.dart';
import '../../../utils/image_picker_service.dart';

class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final _loadingManager = LoadingStateManager();
  
  // Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  
  // Data
  List<String> photos = [];
  List<String> selectedHobbies = [];
  List<Map<String, dynamic>> favoriteVenues = [];
  List<Map<String, dynamic>> availableVenues = [];
  Set<String> favoriteVenueIds = {}; // Favori mekan ID'lerini tut
  
  // State variables
  bool isLoading = true;
  bool isSaving = false;
  Map<String, dynamic> userData = {};
  String selectedGender = '';
  
  // Hobi kategorileri - Kayıt sistemi ile senkronize
  String selectedHobbyCategory = 'Tümü';
  final Map<String, List<Map<String, dynamic>>> hobbyCategories = {
    'Tümü': [],
    'Spor': [
      {'name': 'Fitness', 'icon': Icons.fitness_center},
      {'name': 'Koşu', 'icon': Icons.directions_run},
      {'name': 'Yoga', 'icon': Icons.self_improvement},
      {'name': 'Yüzme', 'icon': Icons.pool},
      {'name': 'Basketbol', 'icon': Icons.sports_basketball},
      {'name': 'Futbol', 'icon': Icons.sports_soccer},
      {'name': 'Voleybol', 'icon': Icons.sports_volleyball},
      {'name': 'Tenis', 'icon': Icons.sports_tennis},
      {'name': 'Bisiklet', 'icon': Icons.directions_bike},
      {'name': 'Dans', 'icon': Icons.music_note},
    ],
    'Sanat': [
      {'name': 'Resim', 'icon': Icons.palette},
      {'name': 'Müzik', 'icon': Icons.music_note},
      {'name': 'Fotoğrafçılık', 'icon': Icons.camera_alt},
      {'name': 'Yazı Yazma', 'icon': Icons.edit},
      {'name': 'Sinema', 'icon': Icons.movie},
      {'name': 'Tiyatro', 'icon': Icons.theater_comedy},
    ],
    'Teknoloji': [
      {'name': 'Kodlama', 'icon': Icons.code},
      {'name': 'Gaming', 'icon': Icons.sports_esports},
      {'name': 'Robotik', 'icon': Icons.smart_toy},
      {'name': '3D Tasarım', 'icon': Icons.view_in_ar},
    ],
    'Doğa': [
      {'name': 'Kamp', 'icon': Icons.cabin},
      {'name': 'Doğa Yürüyüşü', 'icon': Icons.hiking},
      {'name': 'Balık Tutma', 'icon': Icons.set_meal},
      {'name': 'Botanik', 'icon': Icons.local_florist},
    ],
    'Sosyal': [
      {'name': 'Seyahat', 'icon': Icons.flight},
      {'name': 'Yemek', 'icon': Icons.restaurant},
      {'name': 'Kahve', 'icon': Icons.coffee},
      {'name': 'Konserler', 'icon': Icons.music_note},
    ],
    'Kültür': [
      {'name': 'Kitap', 'icon': Icons.menu_book},
      {'name': 'Tarih', 'icon': Icons.history_edu},
      {'name': 'Bilim', 'icon': Icons.science},
    ],
    'Yaratıcılık': [
      {'name': 'Tasarım', 'icon': Icons.design_services},
      {'name': 'Moda', 'icon': Icons.checkroom},
      {'name': 'Girişimcilik', 'icon': Icons.business},
    ],
  };
  
  final List<String> genderOptions = ['Erkek', 'Kadın', 'Diğer'];
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    // _loadAvailableHobbies(); // Artık gerek yok, hobbyCategories direkt tanımlı
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _loadingManager.dispose();
    FormValidationHelper.dispose();
    super.dispose();
  }
  
  // KULLANICI VERİLERİNİ YÜKLE
  Future<void> _loadUserData() async {
    try {
      setState(() => isLoading = true);
      
      final user = _auth.currentUser;
      if (user != null) {
        
        final doc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Veri yükleme zaman aşımına uğradı');
              },
            );
        
        if (doc.exists) {
          final data = doc.data()!;
          
          setState(() {
            userData = data;
            
            // Text field'ları doldur
            _nameController.text = data['name']?.toString() ?? '';
            _surnameController.text = data['surname']?.toString() ?? '';
            _ageController.text = data['age']?.toString() ?? '';
            
            // Cinsiyet
            selectedGender = data['gender']?.toString() ?? '';
            
            // Fotoğrafları yükle
            if (data['photos'] != null && data['photos'] is List) {
              photos = List<String>.from(data['photos']);
            }
            
            // Hobileri yükle
            if (data['hobbies'] != null && data['hobbies'] is List) {
              selectedHobbies = List<String>.from(data['hobbies']);
            }
            
            // Favori mekanları yükle - DÜZELTİLDİ
            favoriteVenues.clear();
            favoriteVenueIds.clear();
            
            if (data['favoriteVenueDetails'] != null && data['favoriteVenueDetails'] is List) {
              for (var item in data['favoriteVenueDetails']) {
                if (item is Map) {
                  final venue = Map<String, dynamic>.from(item);
                  final venueId = venue['place_id'] ?? venue['id'] ?? '';
                  
                  // Aynı ID'li mekan yoksa ekle
                  if (venueId.isNotEmpty && !favoriteVenueIds.contains(venueId)) {
                    favoriteVenues.add(venue);
                    favoriteVenueIds.add(venueId);
                  }
                }
              }
            }
            
            // Favori mekan ID listesini de yükle
            if (data['favoriteVenues'] != null && data['favoriteVenues'] is List) {
              final idList = List<String>.from(data['favoriteVenues']);
              favoriteVenueIds.addAll(idList);
            }
          });
          
          // Kullanılabilir mekanları yükle
          await _loadAvailableVenues();
        } else {
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veri yüklenemedi'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }
  
  // KULLANILABİLİR HOBİLERİ YÜKLE
  // Hobi kategorilerinden tüm hobileri al
  List<Map<String, dynamic>> getAllHobbies() {
    final allHobbies = <Map<String, dynamic>>[];
    for (var category in hobbyCategories.entries) {
      if (category.key != 'Tümü') {
        allHobbies.addAll(category.value);
      }
    }
    return allHobbies;
  }

  // Filtrelenmiş hobileri al
  List<Map<String, dynamic>> getFilteredHobbies() {
    return selectedHobbyCategory == 'Tümü' 
        ? getAllHobbies() 
        : hobbyCategories[selectedHobbyCategory] ?? [];
  }
  
  // KULLANILABİLİR MEKANLARI YÜKLE - DÜZELTİLDİ
  Future<void> _loadAvailableVenues() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      availableVenues.clear();
      Set<String> availableVenueIds = {};
      
      // Check-in yapılan mekanları al
      final checkInsSnapshot = await _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: user.uid)
          .get();
      
      
      for (var doc in checkInsSnapshot.docs) {
        final data = doc.data();
        final venueId = data['venueId']?.toString() ?? '';
        final venueName = data['venueName']?.toString() ?? 'Mekan';
        
        // Bu mekan daha önce eklenmemişse ve favori değilse
        if (venueId.isNotEmpty && 
            !availableVenueIds.contains(venueId) && 
            !favoriteVenueIds.contains(venueId)) {
          
          availableVenueIds.add(venueId);
          
          // Mekan bilgilerini oluştur
          final venueData = {
            'place_id': venueId,
            'name': venueName,
            'category': data['venueCategory'] ?? 'Mekan',
            'vicinity': data['venueAddress'] ?? '',
            'latitude': data['venueLocation']?['latitude'] ?? 0.0,
            'longitude': data['venueLocation']?['longitude'] ?? 0.0,
            'checkInCount': 1, // Bu kullanıcının check-in sayısı
            'lastCheckIn': data['checkInTime'],
          };
          
          availableVenues.add(venueData);
        }
      }
      
      // Tarihe göre sırala (en son check-in yapılan önce)
      availableVenues.sort((a, b) {
        final aTime = a['lastCheckIn'];
        final bTime = b['lastCheckIn'];
        if (aTime == null || bTime == null) return 0;
        if (aTime is Timestamp && bTime is Timestamp) {
          return bTime.compareTo(aTime);
        }
        return 0;
      });
      
      setState(() {});
      
    } catch (e) {
    }
  }
  
  // FOTOĞRAF SEÇ VE YÜKLE (CROP İLE)
  Future<void> _pickAndUploadPhoto() async {
    // Zaten yükleme yapılıyorsa işlemi engelle
    if (isSaving) return;
    
    try {
      setState(() => isSaving = true);
      
      // Kaynak seçimi dialog'u göster
      final ImageSource? source = await ImagePickerService.showImageSourceDialog(context);
      if (source == null) {
        setState(() => isSaving = false);
        return;
      }
      
      // Fotoğraf seç ve crop et (kaynak seçimi yapmadan)
      final File? croppedImage = await ImagePickerService.pickGalleryImage(context);
      
      // Kullanıcı resim seçmedi, crop yapmadı veya iptal etti
      if (croppedImage == null) {
        setState(() => isSaving = false);
        return;
      }
      
      final user = _auth.currentUser;
      if (user == null) {
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kullanıcı oturumu bulunamadı'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      
      // Dosya boyutu kontrolü (5MB limit)
      final fileSizeInBytes = await croppedImage.length();
      final fileSizeInMB = fileSizeInBytes / (1024 * 1024);
      
      if (fileSizeInMB > 5) {
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya boyutu 5MB\'dan küçük olmalı'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      
      // Storage'a yükle
      final fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('user_photos/$fileName');
      
      // Timeout ile upload task
      final uploadTask = ref.putFile(croppedImage);
      final snapshot = await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          uploadTask.cancel();
          throw Exception('Yükleme zaman aşımına uğradı');
        },
      );
      
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Mounted kontrolü
      if (!mounted) return;
      
      setState(() {
        photos.add(downloadUrl);
        isSaving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf yüklendi ✅'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 1),
        ),
      );
      
    } catch (e) {
      // Mounted kontrolü
      if (!mounted) return;
      
      setState(() => isSaving = false);
      
      String errorMessage = 'Fotoğraf yüklenemedi';
      if (e.toString().contains('timeout') || e.toString().contains('zaman aşımı')) {
        errorMessage = 'Yükleme zaman aşımına uğradı, tekrar deneyin';
      } else if (e.toString().contains('network') || e.toString().contains('internet')) {
        errorMessage = 'İnternet bağlantınızı kontrol edin';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
  
  // KAYNAK SEÇİMİ DIALOG'U
  Future<void> _showImageSourceDialog() async {
    if (isSaving) return;
    
    final ImageSource? source = await ImagePickerService.showImageSourceDialog(context);
    if (source == null) return;
    
    // Seçilen kaynağa göre fotoğraf seç ve crop et
    if (source == ImageSource.camera) {
      _pickImageFromCamera();
    } else {
      _pickAndUploadPhoto();
    }
  }
  
  // KAMERADAN FOTOĞRAF SEÇ VE YÜKLE
  Future<void> _pickImageFromCamera() async {
    if (isSaving) return;
    
    try {
      setState(() => isSaving = true);
      
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
      
      if (croppedImage == null) {
        setState(() => isSaving = false);
        return;
      }
      
      final user = _auth.currentUser;
      if (user == null) {
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kullanıcı oturumu bulunamadı'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      
      // Dosya boyutu kontrolü (5MB limit)
      final fileSizeInBytes = await croppedImage.length();
      final fileSizeInMB = fileSizeInBytes / (1024 * 1024);
      
      if (fileSizeInMB > 5) {
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya boyutu 5MB\'dan küçük olmalı'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      
      // Storage'a yükle
      final fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('user_photos/$fileName');
      
      final uploadTask = ref.putFile(croppedImage);
      final snapshot = await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          uploadTask.cancel();
          throw Exception('Yükleme zaman aşımına uğradı');
        },
      );
      
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      if (!mounted) return;
      
      setState(() {
        photos.add(downloadUrl);
        isSaving = false;
      });
      
      await _updateUserPhotos();
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf başarıyla eklendi!'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 1),
        ),
      );
      
    } catch (e) {
      if (!mounted) return;
      
      setState(() => isSaving = false);
      
      String errorMessage = 'Fotoğraf yüklenemedi';
      if (e.toString().contains('timeout') || e.toString().contains('zaman aşımı')) {
        errorMessage = 'Yükleme zaman aşımına uğradı, tekrar deneyin';
      } else if (e.toString().contains('network') || e.toString().contains('internet')) {
        errorMessage = 'İnternet bağlantınızı kontrol edin';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
  
  // FOTOĞRAFI SİL
  void _removePhoto(int index) {
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En az 1 fotoğraf olmalı'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    
    setState(() {
      photos.removeAt(index);
    });
  }
  
  // FOTOĞRAF DEĞİŞTİRME DIALOG'U
  Future<void> _showReplacePhotoDialog(int index) async {
    if (isSaving) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
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
                'Fotoğrafı Değiştir',
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
                    child: _buildReplaceOption(
                      context: context,
                      icon: Icons.camera_alt,
                      label: 'Kamera',
                      onTap: () {
                        Navigator.pop(context);
                        _replacePhotoFromCamera(index);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildReplaceOption(
                      context: context,
                      icon: Icons.photo_library,
                      label: 'Galeri',
                      onTap: () {
                        Navigator.pop(context);
                        _replacePhotoFromGallery(index);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _removePhoto(index);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Fotoğrafı Sil',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildReplaceOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
  
  // KAMERADAN FOTOĞRAF DEĞİŞTİR
  Future<void> _replacePhotoFromCamera(int index) async {
    if (isSaving) return;
    
    try {
      setState(() => isSaving = true);
      
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
      
      if (croppedImage == null) {
        setState(() => isSaving = false);
        return;
      }
      
      await _uploadAndReplacePhoto(index, croppedImage);
      
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fotoğraf değiştirilemedi: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
  
  // GALERİDEN FOTOĞRAF DEĞİŞTİR
  Future<void> _replacePhotoFromGallery(int index) async {
    if (isSaving) return;
    
    try {
      setState(() => isSaving = true);
      
      final File? croppedImage = await ImagePickerService.pickGalleryImage(context);
      
      if (croppedImage == null) {
        setState(() => isSaving = false);
        return;
      }
      
      await _uploadAndReplacePhoto(index, croppedImage);
      
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fotoğraf değiştirilemedi: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
  
  // FOTOĞRAFI YÜKLE VE DEĞİŞTİR
  Future<void> _uploadAndReplacePhoto(int index, File croppedImage) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'Kullanıcı oturumu bulunamadı';
    }
    
    // Dosya boyutu kontrolü
    final fileSizeInBytes = await croppedImage.length();
    final fileSizeInMB = fileSizeInBytes / (1024 * 1024);
    
    if (fileSizeInMB > 5) {
      throw 'Dosya boyutu 5MB\'dan küçük olmalı';
    }
    
    // Storage'a yükle
    final fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('user_photos/$fileName');
    
    final uploadTask = ref.putFile(croppedImage);
    final snapshot = await uploadTask.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        uploadTask.cancel();
        throw 'Yükleme zaman aşımına uğradı';
      },
    );
    
    final downloadUrl = await snapshot.ref.getDownloadURL();
    
    if (!mounted) return;
    
    setState(() {
      photos[index] = downloadUrl;
      isSaving = false;
    });
    
    await _updateUserPhotos();
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fotoğraf başarıyla değiştirildi!'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 1),
      ),
    );
  }
  
  // KULLANICI FOTOĞRAFLARINI GÜNCELLE
  Future<void> _updateUserPhotos() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'photos': photos,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
    }
  }
  
  // PROFİLİ KAYDET - LoadingStateManager ve FormValidationHelper ile güncellenmiş
  Future<void> _saveProfile() async {
    try {
      // Basic validation
      if (_nameController.text.trim().isEmpty) {
        throw 'İsim alanı boş olamaz';
      }
      
      // 18+ KAPISI: Bu ekranda HİÇ yaş doğrulaması yoktu. Kullanıcı kayıtta
      // 18 girip buradan saniyeler içinde 13 yapabiliyordu; yani üç ayrı
      // hukuki metinde verilen "18+" taahhüdü tek ekranda geçersiz
      // oluyordu. Apple 5.1.1 incelemesi tam olarak bunu test eder.
      if (_ageController.text.trim().isEmpty) {
        throw 'Yaş alanı boş olamaz';
      }

      final parsedAge = int.tryParse(_ageController.text.trim());
      if (parsedAge == null) {
        throw 'Yaş sayı olmalı';
      }
      if (parsedAge < 18 || parsedAge > 99) {
        throw 'Yaş 18-99 arasında olmalı';
      }

      // Cinsiyet artık zorunlu değil — kayıt akışında da opsiyonel.
      // (Eskiden burada zorunluydu ve iki akış çelişiyordu.)
      
      if (photos.isEmpty) {
        throw 'En az 1 fotoğraf eklemelisiniz';
      }
      

      await _loadingManager.executeOperation(
        'save_profile',
        () async {
          final user = _auth.currentUser;
          if (user == null) {
            throw 'Kullanıcı oturumu bulunamadı';
          }
          
          // Favori mekan ID listesini güncelle
          final venueIds = favoriteVenues
              .map((v) => v['place_id'] ?? v['id'] ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
          
          // Firestore'a kaydet
          await _firestore
              .collection('users')
              .doc(user.uid)
              .update({
            'name': _nameController.text.trim(),
            'surname': _surnameController.text.trim(),
            'age': int.parse(_ageController.text),
            'gender': selectedGender,
            'photos': photos,
            'hobbies': selectedHobbies,
            'favoriteVenues': venueIds,
            'favoriteVenueDetails': favoriteVenues,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Cache'i temizle
          await _clearProfileCache();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Profil başarıyla güncellendi'),
                backgroundColor: AppColors.success,
              ),
            );
            Navigator.of(context).pop();
          }
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Resim yüklenemedi. Lütfen tekrar deneyiniz.'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
      );
    } catch (e) {
      // Error already handled in executeOperation
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: AppColors.grey50,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text('Profili Düzenle', style: TextStyle(color: AppColors.white)),
          iconTheme: const IconThemeData(color: AppColors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: AppColors.grey50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Profili Düzenle', style: TextStyle(color: AppColors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _saveProfile,
              icon: const Icon(Icons.check, color: AppColors.white),
              tooltip: 'Kaydet',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FOTOĞRAFLAR
            _buildSectionTitle('Fotoğraflar (${photos.length}/6)'),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length + (photos.length < 6 ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == photos.length) {
                    // Fotoğraf ekleme butonu
                    return GestureDetector(
                      onTap: isSaving ? null : _showImageSourceDialog,
                      child: Container(
                        width: 100,
                        height: 120,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: AppColors.grey200,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, 
                              color: AppColors.primary, 
                              size: 32),
                            SizedBox(height: 8),
                            Text('Ekle',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  // Mevcut fotoğraflar
                  return GestureDetector(
                    onTap: () => _showReplacePhotoDialog(index),
                    child: Stack(
                      children: [
                      Container(
                        width: 100,
                        height: 120,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            photos[index],
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: AppColors.grey200,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: AppColors.grey200,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: AppColors.grey400,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // Silme butonu
                      if (photos.length > 1)
                        Positioned(
                          top: 4,
                          right: 16,
                          child: GestureDetector(
                            onTap: () => _removePhoto(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.error,
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
                                color: AppColors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      // Ana fotoğraf etiketi
                      if (index == 0)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ANA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 32),
            
            // KİŞİSEL BİLGİLER
            _buildSectionTitle('Kişisel Bilgiler'),
            const SizedBox(height: 16),
            
            // İsim - Basic validation ile
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'İsim *',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.white,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Soyisim
            TextField(
              controller: _surnameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Soyisim',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.white,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Yaş - Basic validation ile
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              maxLength: 2,
              decoration: InputDecoration(
                labelText: 'Yaş *',
                prefixIcon: const Icon(Icons.cake),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.white,
                counterText: '',
              ),
            ),
            
            const SizedBox(height: 32),
            
            // CİNSİYET
            _buildSectionTitle('Cinsiyet *'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: genderOptions.map((gender) {
                final isSelected = selectedGender == gender;
                return ChoiceChip(
                  label: Text(gender),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      selectedGender = selected ? gender : '';
                    });
                  },
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.white : AppColors.grey900,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: AppColors.grey200,
                );
              }).toList(),
            ),
            
            const SizedBox(height: 32),
            
            // HOBİLER
            _buildSectionTitle('Hobiler'),
            const SizedBox(height: 16),
            
            // Kategori seçici
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: hobbyCategories.keys.map((category) {
                  final isSelected = selectedHobbyCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(category),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          selectedHobbyCategory = category;
                        });
                      },
                      selectedColor: AppColors.primary,
                      checkmarkColor: AppColors.white,
                      backgroundColor: AppColors.grey200,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.white : AppColors.grey900,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Hobi listesi
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: getFilteredHobbies().map((hobbyData) {
                final hobbyName = hobbyData['name'] as String;
                final hobbyIcon = hobbyData['icon'] as IconData;
                final isSelected = selectedHobbies.contains(hobbyName);
                
                return FilterChip(
                  avatar: Icon(
                    hobbyIcon,
                    size: 18,
                    color: isSelected ? AppColors.white : AppColors.primary,
                  ),
                  label: Text(hobbyName),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected && selectedHobbies.length < 10) {
                        selectedHobbies.add(hobbyName);
                      } else if (!selected) {
                        selectedHobbies.remove(hobbyName);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Maksimum 10 hobi seçebilirsiniz'),
                            backgroundColor: AppColors.warning,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    });
                  },
                  selectedColor: AppColors.primary,
                  checkmarkColor: AppColors.white,
                  backgroundColor: AppColors.grey200,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.white : AppColors.grey900,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 32),
            
            // FAVORİ MEKANLAR
            _buildSectionTitle('Favori Mekanlar (${favoriteVenues.length}/5)'),
            const SizedBox(height: 8),
            const Text(
              'Check-in yaptığın mekanlardan seçebilirsin',
              style: TextStyle(
                color: AppColors.grey600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            
            // Seçili favori mekanlar
            if (favoriteVenues.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.grey300,
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Henüz favori mekan eklemedin',
                    style: TextStyle(color: AppColors.grey600),
                  ),
                ),
              )
            else
              ...favoriteVenues.map((venue) {
                final venueName = venue['name'] ?? 'Mekan';
                final venueCategory = venue['category'] ?? '';
                final venueId = venue['place_id'] ?? venue['id'] ?? '';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite, 
                        color: AppColors.success,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      venueName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: venueCategory.isNotEmpty 
                        ? Text(
                            venueCategory,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle,
                        color: AppColors.error,
                      ),
                      onPressed: () {
                        setState(() {
                          favoriteVenues.removeWhere((v) => 
                            (v['place_id'] ?? v['id']) == venueId
                          );
                          favoriteVenueIds.remove(venueId);
                        });
                        
                        // Mekanı tekrar kullanılabilir listeye ekle
                        _loadAvailableVenues();
                      },
                    ),
                  ),
                );
              }),
            
            const SizedBox(height: 16),
            
            // Mekan ekleme butonu
            if (favoriteVenues.length < 5)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: availableVenues.isEmpty ? null : _showVenueSelectionDialog,
                  icon: const Icon(Icons.add_location),
                  label: Text(
                    availableVenues.isEmpty 
                        ? 'Check-in yapılan mekan yok' 
                        : 'Favori Mekan Ekle (${availableVenues.length} mekan)',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                      color: availableVenues.isEmpty 
                          ? AppColors.grey400 
                          : AppColors.primary,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            
            const SizedBox(height: 32),
            
            // KAYDET BUTONU - ProductionButton ile güncellendi
            ProductionButton(
              text: 'Değişiklikleri Kaydet',
              onPressed: isSaving ? null : _saveProfile,
              isLoading: isSaving,
              width: double.infinity,
              height: 48,
            ),
            
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.grey900,
      ),
    );
  }
  
  // MEKAN SEÇME DİYALOGU - DÜZELTİLDİ
  void _showVenueSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Check-in Yaptığın Mekanlar'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: availableVenues.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off, 
                        size: 48, 
                        color: AppColors.grey400
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Henüz check-in yapmadınız',
                        style: TextStyle(color: AppColors.grey600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: availableVenues.length,
                  itemBuilder: (context, index) {
                    final venue = availableVenues[index];
                    final venueId = venue['place_id'] ?? venue['id'] ?? '';
                    final venueName = venue['name'] ?? 'Mekan';
                    final venueCategory = venue['category'] ?? '';
                    
                    // Bu mekan zaten favorilerde mi?
                    final isAlreadyFavorite = favoriteVenueIds.contains(venueId);
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          venueName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: venueCategory.isNotEmpty
                            ? Text(
                                venueCategory,
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                        trailing: isAlreadyFavorite
                            ? const Chip(
                                label: Text(
                                  'Favoride',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: AppColors.success,
                              )
                            : IconButton(
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: AppColors.primary,
                                ),
                                onPressed: () {
                                  if (favoriteVenues.length < 5) {
                                    setState(() {
                                      favoriteVenues.add(venue);
                                      favoriteVenueIds.add(venueId);
                                    });
                                    Navigator.pop(context);
                                    
                                    // Listeyi güncelle
                                    _loadAvailableVenues();
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('$venueName favorilere eklendi'),
                                        backgroundColor: AppColors.success,
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                              ),
                        onTap: isAlreadyFavorite
                            ? null
                            : () {
                                if (favoriteVenues.length < 5) {
                                  setState(() {
                                    favoriteVenues.add(venue);
                                    favoriteVenueIds.add(venueId);
                                  });
                                  Navigator.pop(context);
                                  
                                  // Listeyi güncelle
                                  _loadAvailableVenues();
                                  
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('$venueName favorilere eklendi'),
                                      backgroundColor: AppColors.success,
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  // Clear profile cache method
  Future<void> _clearProfileCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profile_cache_data');
      await prefs.remove('profile_cache_time');
    } catch (e) {
    }
  }
}