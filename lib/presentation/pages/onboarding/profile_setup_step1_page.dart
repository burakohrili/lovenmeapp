import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import 'profile_setup_step2_page.dart';
import 'user_profile_provider.dart';

class ProfileSetupStep1Page extends ConsumerStatefulWidget {
  const ProfileSetupStep1Page({super.key});

  @override
  ConsumerState<ProfileSetupStep1Page> createState() => _ProfileSetupStep1PageState();
}

class _ProfileSetupStep1PageState extends ConsumerState<ProfileSetupStep1Page> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _surnameController;
  late final TextEditingController _ageController;
  String? _selectedGender; // YENİ - Cinsiyet seçimi
  
  @override
  void initState() {
    super.initState();
    
    // 🔥 YENİ: Firebase'den profil verilerini yükle
    _loadProfileFromFirebase();
    
    final profile = ref.read(userProfileProvider);
    
    _nameController = TextEditingController(text: profile.name ?? '');
    _surnameController = TextEditingController(text: profile.surname ?? '');
    _ageController = TextEditingController(
      text: profile.age != null && profile.age! > 0 
          ? profile.age.toString() 
          : ''
    );
    _selectedGender = profile.gender; // YENİ - Mevcut cinsiyeti al
  }
  
  // 🔥 YENİ: Firebase'den profil verilerini provider'a yükle
  Future<void> _loadProfileFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        
        // Provider'ı Firebase verileriyle güncelle
        final notifier = ref.read(userProfileProvider.notifier);
        
        // Temel bilgiler
        if (data['name'] != null && data['surname'] != null && data['age'] != null) {
          notifier.updateBasicInfo(
            name: data['name'],
            surname: data['surname'],
            age: data['age'],
            gender: data['gender'],
          );
        }
        
        // Hobiler
        if (data['hobbies'] != null) {
          notifier.updateHobbies(List<String>.from(data['hobbies']));
        }
        
        // Fotoğraflar (Firebase Storage URL'leri)
        if (data['photos'] != null) {
          notifier.updatePhotos(List<String>.from(data['photos']));
        }
        
        // Favori mekanlar
        if (data['favoriteVenues'] != null) {
          notifier.updateFavoriteVenues(List<String>.from(data['favoriteVenues']));
        }
        
        if (data['favoriteVenueDetails'] != null) {
          final venueDetails = (data['favoriteVenueDetails'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          notifier.updateFavoriteVenueDetails(venueDetails);
        }
        
        // Email & Phone
        if (data['email'] != null) {
          notifier.updateEmail(data['email']);
        }
        
        if (data['phone'] != null) {
          notifier.updatePhone(data['phone']);
        }
        
        // Doğrulama durumları
        if (data['isEmailVerified'] == true) {
          notifier.setEmailVerified(true);
        }
        
        if (data['isPhoneVerified'] == true) {
          notifier.setPhoneVerified(true);
        }
      }
    } catch (e) {
      // Hata olsa bile devam et
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'İsim gerekli';
    }
    if (value.length < 2) {
      return 'İsim en az 2 karakter olmalı';
    }
    return null;
  }

  String? _validateSurname(String? value) {
    if (value == null || value.isEmpty) {
      return 'Soyisim gerekli';
    }
    if (value.length < 2) {
      return 'Soyisim en az 2 karakter olmalı';
    }
    return null;
  }

  String? _validateAge(String? value) {
    if (value == null || value.isEmpty) {
      return 'Yaş gerekli';
    }
    final age = int.tryParse(value);
    if (age == null) {
      return 'Geçerli bir yaş giriniz';
    }
    if (age < 18 || age > 99) {
      return 'Yaş 18-99 arasında olmalı';
    }
    return null;
  }

  String? _validateGender() {
    if (_selectedGender == null || _selectedGender!.isEmpty) {
      return 'Cinsiyet seçimi gerekli';
    }
    return null;
  }

  void _handleNext() {
    // Cinsiyet opsiyonel (Apple 4.3 uyumu)

    if (_formKey.currentState!.validate()) {
      // Provider'a bilgileri kaydet - CİNSİYET OPSİYONEL
      ref.read(userProfileProvider.notifier).updateBasicInfo(
        name: _nameController.text,
        surname: _surnameController.text,
        age: int.parse(_ageController.text),
        gender: _selectedGender,
      );
      
      // 🔥 YENİ: Firebase'e hemen kaydet (uygulama kapanırsa veri kaybolmasın)
      _saveToFirestore();
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProfileSetupStep2Page(),
        ),
      );
    }
  }
  
  // 🔥 YENİ: Firestore'a otomatik kayıt
  Future<void> _saveToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'name': _nameController.text,
        'surname': _surnameController.text,
        'age': int.parse(_ageController.text),
        'gender': _selectedGender,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Hata olsa bile devam et (ağ sorunu olabilir)
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final hasExistingData = profile.name != null && 
                           profile.name!.isNotEmpty && 
                           profile.surname != null && 
                           profile.surname!.isNotEmpty;
    
    return Scaffold(
      backgroundColor: AppColors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryRegisterGradient,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  
                  // Progress Indicator
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: AppColors.white.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: AppColors.white.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Title
                  Text(
                    hasExistingData 
                        ? 'Bilgilerini Tamamla' 
                        : 'Kendini Tanıt',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    hasExistingData
                        ? '1/7 - Eksik bilgileri tamamla'
                        : '1/7 - Temel bilgilerini girelim',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.white.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Avatar Placeholder
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.white.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _selectedGender == 'Kadın' 
                            ? Icons.face_3
                            : _selectedGender == 'Erkek'
                                ? Icons.face
                                : Icons.person,
                        size: 60,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Hoş geldin mesajı
                  if (hasExistingData) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Hoş geldin ${profile.name}!',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  
                  // Name Field
                  Container(
                    decoration: BoxDecoration(
                      color: hasExistingData 
                          ? AppColors.white.withOpacity(0.5) 
                          : AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextFormField(
                      controller: _nameController,
                      validator: _validateName,
                      enabled: !hasExistingData,
                      textCapitalization: TextCapitalization.words,
                      scrollPadding: const EdgeInsets.only(bottom: 100),
                      style: const TextStyle(color: AppColors.grey800),
                      decoration: const InputDecoration(
                        labelText: 'İsim',
                        hintText: 'Adınızı giriniz',
                        prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                        contentPadding: EdgeInsets.only(bottom: 12.0),
                        prefixIcon: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                          child: Icon(Icons.person_outline, color: AppColors.primary),
                        ),
                        border: InputBorder.none,
                        floatingLabelStyle: TextStyle(
                          color: AppColors.grey600,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        errorStyle: TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Surname Field
                  Container(
                    decoration: BoxDecoration(
                      color: hasExistingData 
                          ? AppColors.white.withOpacity(0.5) 
                          : AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextFormField(
                      controller: _surnameController,
                      validator: _validateSurname,
                      enabled: !hasExistingData,
                      textCapitalization: TextCapitalization.words,
                      scrollPadding: const EdgeInsets.only(bottom: 100),
                      style: const TextStyle(color: AppColors.grey800),
                      decoration: const InputDecoration(
                        labelText: 'Soyisim',
                        hintText: 'Soyadınızı giriniz',
                        prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                        contentPadding: EdgeInsets.only(bottom: 12.0),
                        prefixIcon: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                          child: Icon(Icons.person, color: AppColors.primary),
                        ),
                        border: InputBorder.none,
                        floatingLabelStyle: TextStyle(
                          color: AppColors.grey600,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        errorStyle: TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Age Field
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextFormField(
                      controller: _ageController,
                      validator: _validateAge,
                      keyboardType: TextInputType.number,
                      autofocus: hasExistingData,
                      style: const TextStyle(color: AppColors.grey800),
                      decoration: const InputDecoration(
                        labelText: 'Yaş',
                        hintText: 'Yaşınızı giriniz',
                        prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                        contentPadding: EdgeInsets.only(bottom: 12.0),
                        prefixIcon: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                          child: Icon(Icons.cake_outlined, color: AppColors.primary),
                        ),
                        border: InputBorder.none,
                        floatingLabelStyle: TextStyle(
                          color: AppColors.grey600,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        errorStyle: TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // YENİ - CİNSİYET SEÇİMİ
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.white.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.wc,
                              color: AppColors.white.withOpacity(0.8),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Cinsiyet',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedGender = 'Erkek';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _selectedGender == 'Erkek'
                                        ? AppColors.white.withOpacity(0.3)
                                        : AppColors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _selectedGender == 'Erkek'
                                          ? AppColors.white
                                          : AppColors.white.withOpacity(0.3),
                                      width: _selectedGender == 'Erkek' ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.male,
                                        color: _selectedGender == 'Erkek'
                                            ? AppColors.white
                                            : AppColors.white.withOpacity(0.6),
                                        size: 30,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Erkek',
                                        style: TextStyle(
                                          color: _selectedGender == 'Erkek'
                                              ? AppColors.white
                                              : AppColors.white.withOpacity(0.6),
                                          fontWeight: _selectedGender == 'Erkek'
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedGender = 'Kadın';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _selectedGender == 'Kadın'
                                        ? AppColors.white.withOpacity(0.3)
                                        : AppColors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _selectedGender == 'Kadın'
                                          ? AppColors.white
                                          : AppColors.white.withOpacity(0.3),
                                      width: _selectedGender == 'Kadın' ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.female,
                                        color: _selectedGender == 'Kadın'
                                            ? AppColors.white
                                            : AppColors.white.withOpacity(0.6),
                                        size: 30,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Kadın',
                                        style: TextStyle(
                                          color: _selectedGender == 'Kadın'
                                              ? AppColors.white
                                              : AppColors.white.withOpacity(0.6),
                                          fontWeight: _selectedGender == 'Kadın'
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedGender = 'Diğer';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _selectedGender == 'Diğer'
                                        ? AppColors.white.withOpacity(0.3)
                                        : AppColors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _selectedGender == 'Diğer'
                                          ? AppColors.white
                                          : AppColors.white.withOpacity(0.3),
                                      width: _selectedGender == 'Diğer' ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.transgender,
                                        color: _selectedGender == 'Diğer'
                                            ? AppColors.white
                                            : AppColors.white.withOpacity(0.6),
                                        size: 30,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Diğer',
                                        style: TextStyle(
                                          color: _selectedGender == 'Diğer'
                                              ? AppColors.white
                                              : AppColors.white.withOpacity(0.6),
                                          fontWeight: _selectedGender == 'Diğer'
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Next Button
                  ElevatedButton(
                    onPressed: _handleNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonWhite,
                      foregroundColor: AppColors.buttonWhiteText,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'İleri',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}