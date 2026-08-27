// lib/presentation/pages/profile/profile_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/photo_viewer.dart';
import '../../../core/services/native_auto_login_service.dart'; // Otomatik giriş servisi eklendi
import '../../../utils/image_picker_service.dart';
import '../map/services/venue_service.dart'; // Venue service eklendi
import '../auth/login_page.dart';
import 'profile_edit_page.dart';
import 'profile_settings_page.dart';
import '../../widgets/premium/premium_subscription_widget.dart';
import '../../../core/services/premium_service.dart';
import '../../../widgets/super_chat_purchase_sheet.dart';
import '../../../core/config/iap_config.dart'; // IAP Config import
import '../../../core/services/iap_service.dart'; // IAP Service import
// Production Components - Profile sayfası için

import '../../../core/utils/loading_state_manager.dart';
import '../../../core/utils/form_validation_helper.dart';
// Diamond Purchase Components

import '../../../core/models/payment_models.dart';
import '../../../core/services/muhtar_firebase_service.dart';
import '../../widgets/payment/universal_payment_button.dart';
import '../../widgets/venue_progress_section.dart';
// Payment pages removed - using only muhtar system now

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final NativeAutoLoginService _autoLoginService = NativeAutoLoginService(); // Otomatik giriş servisi eklendi
  final MuhtarFirebaseService _muhtarService = MuhtarFirebaseService(); // Elmas servisi
  
  // Production Components
  late final LoadingStateManager _loadingManager;
  
  // Diamond balance
  int _userDiamondBalance = 0;
  StreamSubscription<int>? _diamondBalanceSubscription;

  // IAP fiyatları — Google Play / App Store'dan çekilen gerçek fiyatlar
  Map<String, String> _iapPrices = {};
  /// Store'da aktif olan ürün key'leri — aktif değilse kart gizlenir
  Set<String> _iapAvailableKeys = {};
  bool _iapProductsLoaded = false; // Yükleme tamamlandı mı?
  final IAPService _iapService = IAPService();
  
  Stream<DocumentSnapshot>? userStream;
  bool isUploadingPhoto = false;
  
  // CACHE DEĞİŞKENLERİ
  Map<String, dynamic>? _cachedUserData;
  DateTime? _lastCacheUpdate;
  bool _isLoadingFromCache = true;
  bool _isStreamInitialized = false; // Stream'in sadece bir kez başlatılması için
  static const Duration _cacheExpiry = Duration(minutes: 5); // 5 dakikaya düşürüldü
  
  @override
  void initState() {
    super.initState();
    _loadingManager = LoadingStateManager();
    final user = FirebaseAuth.instance.currentUser;
    WidgetsBinding.instance.addObserver(this);
    _loadInitialDiamondBalance(); // Elmas bakiyesini yükle
    _startDiamondBalanceListener(); // Elmas listener'ını başlat
    _muhtarService.cleanupDuplicateMayorEntries(); // Duplicate mayor kayıtlarını temizle
    _loadIAPPrices(); // Google Play / App Store fiyatlarını yükle
    _loadCachedProfile().then((_) {
      // Cache yüklendikten sonra stream'i başlat
      _initUserStream();
    });
  }
  
  @override
  void dispose() {
    _diamondBalanceSubscription?.cancel();
    _loadingManager.dispose();
    FormValidationHelper.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama ön plana geldiğinde cache'i kontrol et
    if (state == AppLifecycleState.resumed) {
      _checkAndRefreshCache();
    }
  }
  
  // Cache'i kontrol et ve gerekirse yenile
  Future<void> _checkAndRefreshCache() async {
    if (_lastCacheUpdate != null) {
      final difference = DateTime.now().difference(_lastCacheUpdate!);
      if (difference.inMinutes > 5) {
        // Cache 5 dakikadan eskiyse temizle
        // Stream otomatik olarak yeni veriyi getirecek
        await _clearProfileCache();
      }
    }
  }
  
  // CACHE'DEN PROFİL YÜKLE
  Future<void> _loadCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Cache zamanını kontrol et
      final lastUpdate = prefs.getInt('profile_cache_time');
      if (lastUpdate != null) {
        _lastCacheUpdate = DateTime.fromMillisecondsSinceEpoch(lastUpdate);
        
        // Cache hala geçerliyse yükle (5 dakika)
        if (DateTime.now().difference(_lastCacheUpdate!).inMinutes < 5) {
          final cachedData = prefs.getString('profile_cache_data');
          if (cachedData != null && mounted) {
            setState(() {
              _cachedUserData = json.decode(cachedData);
              _isLoadingFromCache = false;
            });
            return;
          }
        } else {
          // Cache eskiyse temizle
          await prefs.remove('profile_cache_data');
          await prefs.remove('profile_cache_time');
        }
      }
      
      if (mounted) {
        setState(() {
          _isLoadingFromCache = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFromCache = false;
        });
      }
    }
  }
  
  // CACHE'E PROFİL KAYDET
  Future<void> _saveProfileToCache(Map<String, dynamic> userData) async {
    try {
      // Önce mevcut cache ile karşılaştır
      if (_cachedUserData != null) {
        // Basit bir kontrol: eğer isim ve yaş aynıysa büyük ihtimalle aynı veridir
        if (_cachedUserData!['name'] == userData['name'] &&
            _cachedUserData!['age'] == userData['age'] &&
            _cachedUserData!['surname'] == userData['surname']) {
          return; // Aynı veri, güncelleme yapma
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // Timestamp'leri string'e çevir (JSON uyumlu hale getir)
      final cacheData = Map<String, dynamic>.from(userData);
      
      // TÜM Firestore Timestamp'lerini kontrol et ve çevir
      cacheData.forEach((key, value) {
        if (value is Timestamp) {
          cacheData[key] = value.toDate().toIso8601String();
        } else if (value is DateTime) {
          cacheData[key] = value.toIso8601String();
        } else if (value is Map) {
          // İç içe Map'lerdeki Timestamp'leri de çevir
          final innerMap = Map<String, dynamic>.from(value);
          innerMap.forEach((innerKey, innerValue) {
            if (innerValue is Timestamp) {
              innerMap[innerKey] = innerValue.toDate().toIso8601String();
            } else if (innerValue is DateTime) {
              innerMap[innerKey] = innerValue.toIso8601String();
            }
          });
          cacheData[key] = innerMap;
        } else if (value is List) {
          // List içindeki Map'lerdeki Timestamp'leri çevir
          final newList = [];
          for (var item in value) {
            if (item is Map) {
              final itemMap = Map<String, dynamic>.from(item);
              itemMap.forEach((itemKey, itemValue) {
                if (itemValue is Timestamp) {
                  itemMap[itemKey] = itemValue.toDate().toIso8601String();
                } else if (itemValue is DateTime) {
                  itemMap[itemKey] = itemValue.toIso8601String();
                }
              });
              newList.add(itemMap);
            } else if (item is Timestamp) {
              newList.add(item.toDate().toIso8601String());
            } else if (item is DateTime) {
              newList.add(item.toIso8601String());
            } else {
              newList.add(item);
            }
          }
          cacheData[key] = newList;
        }
      });
      
      // Olası tüm Timestamp alanlarını tekrar kontrol et
      final fieldsToCheck = [
        'createdAt', 'lastLogin', 'premiumStartDate', 'premiumEndDate',
        'lastCheckInDate', 'emailVerifiedAt', 'phoneVerifiedAt',
        'lastUpdated', 'birthDate'
      ];
      
      for (String field in fieldsToCheck) {
        if (cacheData[field] != null) {
          if (cacheData[field] is Timestamp) {
            cacheData[field] = (cacheData[field] as Timestamp).toDate().toIso8601String();
          } else if (cacheData[field] is DateTime) {
            cacheData[field] = (cacheData[field] as DateTime).toIso8601String();
          }
        }
      }
      
      // JSON string oluştur ve kaydet
      final jsonString = json.encode(cacheData);
      await prefs.setString('profile_cache_data', jsonString);
      await prefs.setInt('profile_cache_time', DateTime.now().millisecondsSinceEpoch);
      
      // Cache değişkenlerini güncelle (setState OLMADAN!)
      _cachedUserData = cacheData;
      _lastCacheUpdate = DateTime.now();
      
    } catch (e) {
      _cachedUserData = null;
      _lastCacheUpdate = null;
    }
  }
  
  // CACHE TEMİZLE (Profil güncellendiğinde kullanılacak)
  Future<void> _clearProfileCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profile_cache_data');
      await prefs.remove('profile_cache_time');
      
      // setState sadece widget mounted ise çağrılmalı
      if (mounted) {
        setState(() {
          _cachedUserData = null;
          _lastCacheUpdate = null;
        });
      }
      
    } catch (e) {
    }
  }
  
  // MANUEL YENİLEME
  Future<void> _refreshProfile() async {
    await _clearProfileCache();
    
    // Stream'i yeniden başlat
    setState(() {
      _isStreamInitialized = false;
      userStream = null;
    });
    
    _initUserStream();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profil yenilendi'),
        duration: Duration(seconds: 1),
        backgroundColor: AppColors.success,
      ),
    );
  }
  
  void _initUserStream() {
    // Stream zaten başlatıldıysa tekrar başlatma
    if (_isStreamInitialized) return;
    
    try {
      final user = _auth.currentUser;
      if (user != null) {
        userStream = _firestore
            .collection('users')
            .doc(user.uid)
            .snapshots();
        _isStreamInitialized = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        });
      }
    } catch (e) {
    }
  }
  
  Future<void> _logout() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
      
      // Çıkış yaparken cache'i temizle
      await _clearProfileCache();
      
      // Map page cache'ini de temizle
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_venues');
      await prefs.remove('cache_update_time');
      
      // 🔑 ÖNEMLİ: Otomatik giriş bilgilerini temizle
      await _autoLoginService.clearRememberMe();
      
      await _auth.signOut();
      
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      Navigator.pop(context);
    }
  }
  
  Future<void> _upgradeToPremium() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: PremiumSubscriptionWidget(
            onPurchaseSuccess: (type) async {
              Navigator.pop(context);
              
              // Premium durumunu kontrol et
            final premiumStatus = await PremiumService.getPremiumStatus();
            final isExtension = premiumStatus.isPremium;
            
            String message = isExtension 
              ? '🎉 Premium süreniz uzatıldı!'
              : '🎉 Premium satın alındı!';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.green,
              ),
            );
            // Cache'i temizle ve sayfayı yenile
            _refreshProfile();
          },
          onError: (error) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Resim yüklenemedi. Lütfen tekrar deneyiniz.'),
                backgroundColor: Colors.red,
              ),
            );
          },
          ),
        ),
      ),
    );
  }
  
  Future<void> _buySuperChats() async {
    await showSuperChatPurchaseSheet(
      context,
      onPurchaseSuccess: () {
        _refreshProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Öne çıkan istek satın alındı!'),
            backgroundColor: AppColors.success,
          ),
        );
      },
    );
  }
  
  // ELMAS SATIN ALMA - Bottom sheet'i göster
  Future<void> _buyDiamonds() async {
    await _showPurchaseDiamondsBottomSheet();
  }
  
  // Güvenli String listesi dönüşümü
  List<String> _safeStringList(dynamic data) {
    if (data == null) return <String>[];
    if (data is List) {
      List<String> result = [];
      for (var item in data) {
        if (item != null) {
          result.add(item.toString());
        }
      }
      return result;
    }
    return <String>[];
  }
  
  // Güvenli Map listesi dönüşümü
  List<Map<String, dynamic>> _safeMapList(dynamic data) {
    if (data == null) return <Map<String, dynamic>>[];
    if (data is List) {
      List<Map<String, dynamic>> result = [];
      for (var item in data) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    }
    return <Map<String, dynamic>>[];
  }
  
  // Sadece geçerli URL'leri filtrele
  List<String> _filterValidPhotos(dynamic data) {
    if (data == null) return <String>[];
    if (data is List) {
      List<String> result = [];
      for (var item in data) {
        if (item != null) {
          String url = item.toString();
          if (url.startsWith('http://') || url.startsWith('https://')) {
            result.add(url);
          }
        }
      }
      return result;
    }
    return <String>[];
  }

  // Profil fotoğrafı değiştirme fonksiyonu
  Future<void> _changeProfilePhoto() async {
    try {
      // Kaynak seçimi dialog'u göster
      final ImageSource? source = await ImagePickerService.showImageSourceDialog(context);
      if (source == null) return;
      
      // Profil fotoğrafı için kare crop
      final File? croppedImage = await ImagePickerService.pickProfileImage(context);
      if (croppedImage == null) return;
      
      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text(
                  'Fotoğraf yükleniyor...',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      );
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.pop(context); // Loading dialog'u kapat
        return;
      }
      
      // Firebase Storage'a yükle
      final fileName = '${user.uid}_profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('user_photos/$fileName');
      final uploadTask = ref.putFile(croppedImage);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Firestore'da güncelle - mevcut fotoğrafların ilkini değiştir
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userData = await userDoc.get();
      List<String> currentPhotos = [];
      
      if (userData.exists && userData.data()?['photos'] != null) {
        currentPhotos = List<String>.from(userData.data()?['photos'] ?? []);
      }
      
      // İlk fotoğrafı değiştir veya ekle
      if (currentPhotos.isEmpty) {
        currentPhotos.add(downloadUrl);
      } else {
        currentPhotos[0] = downloadUrl;
      }
      
      await userDoc.update({'photos': currentPhotos});
      
      Navigator.pop(context); // Loading dialog'u kapat
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil fotoğrafı güncellendi'),
          backgroundColor: AppColors.success,
        ),
      );
      
    } catch (e) {
      Navigator.pop(context); // Loading dialog'u kapat
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf yüklenemedi. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Her zaman StreamBuilder kullan
    return StreamBuilder<DocumentSnapshot>(
      stream: userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _cachedUserData == null) {
          return Scaffold(
            backgroundColor: AppColors.grey50,
            body: _buildLoadingSkeleton(),
          );
        }
        
        if (snapshot.hasError) {
          // Hata olsa bile cache varsa onu göster
          if (_cachedUserData != null) {
            return _buildProfileUI(_cachedUserData!);
          }
          return Scaffold(
            backgroundColor: AppColors.grey50,
            body: _buildErrorState(),
          );
        }
        
        if (!snapshot.hasData || !snapshot.data!.exists) {
          // Veri yoksa ama cache varsa onu göster
          if (_cachedUserData != null) {
            return _buildProfileUI(_cachedUserData!);
          }
          return Scaffold(
            backgroundColor: AppColors.grey50,
            body: _buildErrorState(),
          );
        }
        
        final userData = snapshot.data!.data() as Map<String, dynamic>;
        
        // Yeni veriyi cache'e kaydet - Build tamamlandıktan sonra
        // Sadece veri gerçekten varsa ve değiştiyse kaydedecek
        Future.microtask(() => _saveProfileToCache(userData));
        
        return _buildProfileUI(userData);
      },
    );
  }
  
  // PROFİL UI'INI OLUŞTUR
  Widget _buildProfileUI(Map<String, dynamic> userData) {
    // Verileri güvenli şekilde çıkar
    final String name = userData['name']?.toString() ?? 'İsimsiz';
    final String surname = userData['surname']?.toString() ?? '';
    final int age = userData['age'] ?? 18;
    final String gender = userData['gender']?.toString() ?? '';
    final bool isPremium = userData['isPremium'] ?? false;
    
    // Listeler - güvenli dönüşüm
    final List<String> photos = _filterValidPhotos(userData['photos']);
    final List<String> hobbies = _safeStringList(userData['hobbies']);
    final List<String> favoriteVenues = _safeStringList(userData['favoriteVenues']);
    final List<Map<String, dynamic>> favoriteVenueDetails = _safeMapList(userData['favoriteVenueDetails']);
    
    // Premium istatistikler
    final Map<String, dynamic>? mostVisitedVenue = userData['mostVisitedVenue'] as Map<String, dynamic>?;
    final int sameVenueCount = userData['sameVenueCount'] ?? 0;
    
    return Scaffold(
      backgroundColor: AppColors.grey50,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Profilim',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Check-in History butonu
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CheckInHistoryPage(),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.location_history, 
                          color: AppColors.primary,
                          size: 26,
                        ),
                        tooltip: 'Check-in Geçmişi',
                      ),
                      // Edit butonu
                      IconButton(
                        onPressed: () async {
                          // Edit sayfasına git
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileEditPage(),
                            ),
                          );
                          
                          // Edit sayfasından dönünce cache'i temizle
                          // Stream otomatik olarak yeni veriyi alacak
                          if (result == true || result == null) {
                            await _clearProfileCache();
                          }
                        },
                        icon: const Icon(
                          Icons.edit, 
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                      // Settings butonu
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileSettingsPage(),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.settings, 
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshProfile,
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              // AD SOYAD YAŞ VE BADGE'LER
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // İsim ve Premium Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // İsim
                        Flexible(
                          child: Text(
                            '$name $surname',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.grey900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Premium Badge
                        if (isPremium)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: AppColors.premiumGradient,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.warning.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  color: AppColors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'PREMIUM',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Yaş, Cinsiyet ve Elmas Bakiyesi
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Yaş ve Cinsiyet
                        Text(
                          '$age yaşında${gender.isNotEmpty ? ' • $gender' : ''}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: AppColors.grey600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // Elmas Bakiyesi
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.diamond,
                                color: AppColors.primary,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_userDiamondBalance',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Muhtar Badge'leri
                    _buildMayorBadges(),
                  ],
                ),
              ),

              // Keşif ilerlemesi: seri, seviye, rozetler (bireysel ilerleme)
              const VenueProgressSection(),

              // 1. FOTOĞRAF
              if (photos.isNotEmpty)
                _buildPhotoCard(photos[0], 0, userData),
              
              // HOBİLER
              if (hobbies.isNotEmpty)
                _buildHobbiesSection(hobbies),
              
              // 2. FOTOĞRAF
              if (photos.length > 1)
                _buildPhotoCard(photos[1], 1, userData),
              
              // FAVORİ MEKANLAR
              if (favoriteVenueDetails.isNotEmpty)
                _buildFavoriteVenuesSection(favoriteVenues, favoriteVenueDetails)
              else if (favoriteVenues.isNotEmpty)
                _buildSimpleFavoriteVenuesSection(favoriteVenues),
              
              // 3. FOTOĞRAF
              if (photos.length > 2)
                _buildPhotoCard(photos[2], 2, userData),
              
              // SON CHECK-IN MEKANLARI
              _buildRecentCheckInsSection(),
              
              // PREMIUM REKLAMI VEYA PREMIUM İSTATİSTİKLER
              if (!isPremium)
                _buildPremiumUpgradeSection()
              else
                _buildPremiumStatsSection(mostVisitedVenue, sameVenueCount),
              
              // SUPER LIKE VE DIAMOND BUTONLARI
              const SizedBox(height: 16),
              _buildPurchaseButtonsSection(),
              
              // 4. FOTOĞRAF
              if (photos.length > 3)
                _buildPhotoCard(photos[3], 3, userData),
              
              // 5. FOTOĞRAF
              if (photos.length > 4)
                _buildPhotoCard(photos[4], 4, userData),
              
              // 6. FOTOĞRAF
              if (photos.length > 5)
                _buildPhotoCard(photos[5], 5, userData),
              
              // ÇIKIŞ YAP
              _buildLogoutSection(),
              
              const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // FOTOĞRAF KART - CachedImage KULLANMIYOR!
  Widget _buildPhotoCard(String photoUrl, int index, Map<String, dynamic> userData) {
    return GestureDetector(
      onTap: () {
        // Tüm fotoğrafları topla - Firebase'den direkt string URL'ler geliyor
        final allPhotos = userData['photos'] as List<dynamic>? ?? [];
        final photoUrls = allPhotos.map((photo) {
          // Eğer photo bir Map ise 'url' field'ını al, değilse direkt string olarak kullan
          if (photo is Map<String, dynamic>) {
            return photo['url'] as String;
          } else {
            return photo as String;
          }
        }).toList();
        
        showPhotoViewer(
          context,
          imageUrls: photoUrls,
          initialIndex: index,
          heroTag: 'profile_photo_$index',
        );
      },
      child: Hero(
        tag: 'profile_photo_$index',
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          height: 400,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cached Image display with better performance
                CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 400,
                  alignment: Alignment.center,
                  placeholder: (context, url) => Container(
                    color: AppColors.grey200,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.grey200,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image,
                          size: 50,
                          color: AppColors.grey400,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Fotoğraf yüklenemedi',
                          style: TextStyle(color: AppColors.grey600),
                        ),
                      ],
                    ),
                  ),
                  // Cache configuration
                  cacheManager: CacheManager(
                    Config(
                      'profilePhotos',
                      stalePeriod: const Duration(days: 7), // 7 gün cache
                      maxNrOfCacheObjects: 100, // Max 100 fotoğraf cache
                    ),
                  ),
                ),
                // Gradient overlay
                Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.black.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Fotoğraf numarası
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Fotoğraf ${index + 1}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ], // Stack children listesi burada kapanıyor
        ), // Stack burada kapanıyor
      ), // ClipRRect burada kapanıyor
    ), // Container burada kapanıyor
  ), // Hero burada kapanıyor
); // GestureDetector burada kapanıyor
  }
  
  // HOBİLER BÖLÜMÜ
  Widget _buildHobbiesSection(List<String> hobbies) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.interests,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Hobilerim',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.grey900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: hobbies.map((hobby) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.8),
                      AppColors.primaryLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hobby,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  // FAVORİ MEKANLAR (Detaylı)
  Widget _buildFavoriteVenuesSection(
    List<String> venues,
    List<Map<String, dynamic>> venueDetails,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.favorite_border,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Favori Mekanlarım',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.grey900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: venueDetails.asMap().entries.map((entry) {
              final venue = entry.value;
              final index = entry.key;
              final String venueName = venue['name']?.toString() ?? 
                  (index < venues.length ? venues[index] : 'Mekan');
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.1),
                      AppColors.secondary.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.coffee,
                      color: AppColors.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        venueName,
                        style: const TextStyle(
                          color: AppColors.grey900,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  // FAVORİ MEKANLAR (Basit - sadece ID'ler varsa)
  Widget _buildSimpleFavoriteVenuesSection(List<String> venues) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.favorite_border,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Favori Mekanlarım',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.grey900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${venues.length} favori mekan seçildi',
            style: const TextStyle(
              color: AppColors.grey600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  // PREMIUM UPGRADE
  Widget _buildPremiumUpgradeSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.premiumGradient,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.warning.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _upgradeToPremium,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.star, color: AppColors.white, size: 48),
                const SizedBox(height: 16),
                const Text(
                  '🚀 Premium\'a Geç',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Yeni özellikler ve ayrıcalıklar',
                  style: TextStyle(
                    color: AppColors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Text(
                    'Hemen Başla',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // SUPER LIKE VE DIAMOND BUTONLARI
  Widget _buildPurchaseButtonsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Super Like Butonu
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.blue, Color(0xFF00BFFF)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _buySuperChats,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.chat_bubble, color: Colors.white, size: 32),
                        const SizedBox(height: 8),
                        const Text(
                          'Öne Çıkan İstek',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Satın Al',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Diamond Butonu
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purple, Color(0xFF9C27B0)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _buyDiamonds,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.diamond, color: Colors.white, size: 32),
                        const SizedBox(height: 8),
                        const Text(
                          'Elmas',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Satın Al',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // PREMIUM İSTATİSTİKLER
  Widget _buildPremiumStatsSection(
    Map<String, dynamic>? mostVisitedVenue,
    int sameVenueCount,
  ) {
    return Column(
      children: [
        // Premium Durum ve Süre Uzatma Kartı
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppColors.premiumGradient,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.warning.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star, color: AppColors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'PREMIUM ÜYE',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Premium Bitiş Tarihi ve Toplam Süre
              FutureBuilder<dynamic>(
                future: PremiumService.getPremiumStatus(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data.isPremium) {
                    final expiryDate = snapshot.data.expiryDate;
                    if (expiryDate != null) {
                      final now = DateTime.now();
                      final difference = expiryDate.difference(now);
                      
                      String remainingText = '';
                      if (difference.inDays > 0) {
                        remainingText = '${difference.inDays} gün kaldı';
                      } else if (difference.inHours > 0) {
                        remainingText = '${difference.inHours} saat kaldı';
                      } else if (difference.inMinutes > 0) {
                        remainingText = '${difference.inMinutes} dakika kaldı';
                      } else {
                        remainingText = 'Yakında sona eriyor';
                      }
                      
                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '⏰ $remainingText',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Premium süreniz ${expiryDate.day}/${expiryDate.month}/${expiryDate.year} tarihinde sona eriyor',
                                  style: TextStyle(
                                    color: AppColors.white.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Süreyi Uzat Butonu
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _upgradeToPremium,
                              borderRadius: BorderRadius.circular(25),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      color: AppColors.warning,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Süreyi Uzat',
                                      style: TextStyle(
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  }
                  
                  // Premium değilse veya data yoksa loading göster
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Premium durumu yükleniyor...',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
              
              // Premium Kuyruk ve Toplam Süre Bilgileri
              const SizedBox(height: 16),
              FutureBuilder<List<dynamic>>(
                future: Future.wait([
                  PremiumService.getAllSubscriptions(),
                  PremiumService.getQueuedSubscriptions(),
                ]),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final allSubscriptions = snapshot.data![0] as List<dynamic>;
                    final queuedSubscriptions = snapshot.data![1] as List<dynamic>;
                    
                    if (allSubscriptions.isNotEmpty || queuedSubscriptions.isNotEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            // Toplam Premium Süre
                            if (allSubscriptions.isNotEmpty) ...[
                              Row(
                                children: [
                                  const Icon(Icons.schedule, color: AppColors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Toplam ${allSubscriptions.length} premium satın alımınız var',
                                    style: TextStyle(
                                      color: AppColors.white.withOpacity(0.9),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            
                            // Kuyruk Bilgisi
                            if (queuedSubscriptions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.queue, color: AppColors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${queuedSubscriptions.length} premium kuyruğunuzda bekliyor',
                                    style: TextStyle(
                                      color: AppColors.white.withOpacity(0.9),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              
                              // Sonraki premium'un başlayacağı tarih
                              if (queuedSubscriptions.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.event, color: AppColors.white, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Sonraki premium: ${queuedSubscriptions.first.startDate.day}/${queuedSubscriptions.first.startDate.month}/${queuedSubscriptions.first.startDate.year}',
                                        style: TextStyle(
                                          color: AppColors.white.withOpacity(0.8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ],
                        ),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        
        // Premium İstatistikleri
        if (mostVisitedVenue != null || sameVenueCount > 0)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.premiumGradient,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.warning.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Premium İstatistikler',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
          
                // En çok gittiği mekan
                if (mostVisitedVenue != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '🏆 EN ÇOK GİTTİĞİN MEKAN',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mostVisitedVenue['name']?.toString() ?? 'Henüz check-in yok',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${mostVisitedVenue['count'] ?? 0} kez check-in',
                          style: TextStyle(
                            color: AppColors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
  
  // SON CHECK-IN MEKANLARI BÖLÜMÜ
  Widget _buildRecentCheckInsSection() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    
    return RecentCheckInsWidget(userId: user.uid);
  }
  
  // ÇIKIŞ YAP
  Widget _buildLogoutSection() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: OutlinedButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Oturumu Kapat'),
              content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _logout();
                  },
                  child: const Text(
                    'Oturumu Kapat',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout),
            SizedBox(width: 8),
            Text(
              'Oturumu Kapat',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // LOADING SKELETON
  Widget _buildLoadingSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(height: 120, color: Colors.white),
            const SizedBox(height: 10),
            Container(height: 400, margin: const EdgeInsets.all(20), color: Colors.white),
            Container(height: 150, margin: const EdgeInsets.all(20), color: Colors.white),
            Container(height: 400, margin: const EdgeInsets.all(20), color: Colors.white),
          ],
        ),
      ),
    );
  }
  
  // ERROR STATE
  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          SizedBox(height: 16),
          // const Text(
          //   'Profil yüklenemedi',
          //   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          // ),
          SizedBox(height: 16),
          // ElevatedButton(
          //   onPressed: () async {
          //     await _clearProfileCache();
          //     setState(() {
          //       _isStreamInitialized = false;
          //       userStream = null;
          //     });
          //     _initUserStream();
          //   },
          //   style: ElevatedButton.styleFrom(
          //     backgroundColor: AppColors.primary,
          //   ),
          //   child: const Text('Tekrar Dene'),
          // ),
        ],
      ),
    );
  }

  /// İlk elmas bakiyesini yükle (stream başlamadan önce)
  Future<void> _loadInitialDiamondBalance() async {
    try {
      final balance = await _muhtarService.getUserDiamondBalance();
      if (mounted) {
        setState(() {
          _userDiamondBalance = balance;
        });
      }
    } catch (e) {
    }
  }

  /// Google Play / App Store'dan gerçek ürün fiyatlarını çek
  Future<void> _loadIAPPrices() async {
    // IAP initialize edilmemişse bekle (max 5 sn)
    for (int i = 0; i < 10; i++) {
      if (_iapService.products.isNotEmpty) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    final prices = _iapService.getAllPriceStrings();
    // Hangi ürünler store'da aktif?
    final availableKeys = _iapService.getAvailablePackageKeys('diamonds_')
      ..addAll(_iapService.getAvailablePackageKeys('super_chats_'))
      ..addAll(_iapService.getAvailablePackageKeys('premium_'));
    if (mounted) {
      setState(() {
        _iapPrices = prices;
        _iapAvailableKeys = availableKeys;
        _iapProductsLoaded = true;
      });
    }
  }

  /// Elmas bakiye listener'ını başlat
  void _startDiamondBalanceListener() {
    _diamondBalanceSubscription?.cancel();
    _diamondBalanceSubscription = _muhtarService.listenToUserDiamondBalance().listen(
      (balance) {
        if (mounted) {
          setState(() {
            _userDiamondBalance = balance;
          });
        }
      },
      onError: (error) {
      },
    );
  }

  /// Google Pay elmas satın alma başarılı olduğunda çağrılır
  void _onDiamondPurchaseSuccess(int diamonds) async {
    try {
      // Kullanıcıya elmasi ekle
      await _muhtarService.addUserDiamonds(diamonds);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Tebrikler! 🎉',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '$diamonds elmas başarıyla hesabınıza eklendi!',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hata',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Elmas satın alma işlemi tamamlanamadı',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  /// Google Pay elmas satın alma hatası durumunda çağrılır
  void _onDiamondPurchaseError(String errorMessage) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.payment, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ödeme Hatası',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Direkt IAP ile elmas satın al (Google Pay yok)
  Future<void> _purchaseDiamondsDirectly(int quantity, double price, {BuildContext? sheetContext}) async {
    // Product ID mapping
    String? productId;
    switch (quantity) {
      case 10:
        productId = 'diamonds_10';
        break;
      case 50:
        productId = 'diamonds_50';
        break;
      case 100:
        productId = 'diamonds_100';
        break;
      case 250:
        productId = 'diamonds_250';
        break;
      case 500:
        productId = 'diamonds_500';
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geçersiz elmas paketi'),
            backgroundColor: Colors.red,
          ),
        );
        return;
    }

    try {
      // Bottom sheet'in kapalı olup olmadığını takip et
      bool bottomSheetClosed = false;

      final success = await IAPService().buyProduct(
        productId,
        onSuccess: () {
          if (!mounted) return;
          
          // Bakiyeyi yenile
          _loadInitialDiamondBalance();
          
          // Bottom sheet hâlâ açıksa kapat (sheetContext ile — profil sayfasını kapatma!)
          if (!bottomSheetClosed) {
            bottomSheetClosed = true;
            try { 
              if (sheetContext != null && Navigator.of(sheetContext).canPop()) {
                Navigator.of(sheetContext).pop();
              }
            } catch (_) {}
          }
          
          // Başarı mesajı (profil page context'i ile)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('$quantity Elmas satın alındı! 💎'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          
        },
        onError: (error) {
          if (!mounted) return;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Satın alma hatası: $error'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          
        },
        onPendingTimeout: () {
          // Ödeme hâlâ beklemede — bottom sheet'i kapat (sheetContext ile!), profil sayfası açık kalsın
          if (!mounted) return;
          if (!bottomSheetClosed) {
            bottomSheetClosed = true;
            try {
              if (sheetContext != null && Navigator.of(sheetContext).canPop()) {
                Navigator.of(sheetContext).pop();
              }
            } catch (_) {}
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏳ Ödeme onay bekliyor. Onaylandığında elmaslarınız otomatik eklenecek.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        },
      );
      
    } catch (e) {
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Satın alma hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Elmas satın alma bottom sheet'ini göster
  Future<void> _showPurchaseDiamondsBottomSheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              top: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.diamond, color: Colors.orange, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Elmas Satın Al',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Mevcut Bakiye: $_userDiamondBalance 💎',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    // Hızlı satın alma seçenekleri
                    _buildDiamondPurchaseOptions(sheetContext: context),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  /// Elmas satın alma seçenekleri widget'ı - Horizontal scroll ile map page tasarımı
  Widget _buildDiamondPurchaseOptions({BuildContext? sheetContext}) {
    // IAPConfig'den elmas paketlerini al; store'da aktif olmayanları filtrele
    final allPackages = IAPConfig.diamondPackages;
    // _iapProductsLoaded false iken tüm paketleri göster (yükleniyor state'i)
    final packages = _iapProductsLoaded
        ? allPackages
            .where((p) => _iapAvailableKeys.contains(p['id']))
            .toList()
        : allPackages;
    
    // Icon ve renk ayarları
    final icons = ['⚡', '🏆', '💎', '🌟', '👑', '🔥'];
    final colors = [
      AppColors.primary,
      AppColors.secondary,
      AppColors.accent,
      Colors.purple,
      Colors.orange,
      Colors.deepPurple,
    ];
    
    if (packages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(
          'Şu anda satın alınabilir elmas paketi bulunmuyor.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    return SizedBox(
      height: 240, // Sabit yükseklik
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            for (int i = 0; i < packages.length; i++) ...[
              _buildDiamondPackageCard(
                title: '${icons[i % icons.length]} ${packages[i]['title']}',
                diamonds: packages[i]['quantity'],
                price: packages[i]['originalPrice'],
                priceString: _iapPrices[packages[i]['id']],
                description: packages[i]['description'],
                color: colors[i % colors.length],
                gradientIntensity: 0.1 + (i * 0.1),
                onTap: () => _purchaseDiamondsDirectly(
                  packages[i]['quantity'],
                  packages[i]['originalPrice'],
                  sheetContext: sheetContext,
                ),
                isPopular: packages[i]['isPopular'] ?? false,
              ),
              if (i < packages.length - 1) const SizedBox(width: 16),
            ],
            const SizedBox(width: 20), // Sağ padding
          ],
        ),
      ),
    );
  }

  /// Map sayfasından alınan Google Pay aktif widget'ı
  void _showUniversalPaymentWidget(int diamonds, double price) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                '💎 $diamonds Elmas Satın Al',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              
              // Price info
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$diamonds Elmas',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          '₺${price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.diamond, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Mevcut Bakiye: $_userDiamondBalance 💎',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Universal Payment Button - Cross-platform support
              SizedBox(
                width: double.infinity,
                height: 50,
                child: UniversalPaymentButton(
                  package: PaymentPackage(
                    id: 'diamond_$diamonds',
                    title: '$diamonds Elmas',
                    description: '$diamonds adet elmas satın al',
                    amount: diamonds,
                    price: price,
                    originalPrice: price,
                    discountPercentage: 0,
                    duration: "permanent",
                    type: PaymentType.diamond, // Elmas için doğru type
                    isPopular: diamonds == 50, // 50 elmas popüler yap
                    features: ['$diamonds Elmas'],
                  ),
                  onPaymentSuccess: () {
                    _onDiamondPurchaseSuccess(diamonds);
                    Navigator.pop(context); // Bottom sheet'i kapat
                  },
                  onPaymentError: (error) {
                    _onDiamondPurchaseError('Elmas satın alma işlemi tamamlanamadı');
                  },
                  onPaymentStarted: () {
                  },
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

  /// Elmas paketi kartı oluştur - Map sayfasından alınan tasarım
  Widget _buildDiamondPackageCard({
    required String title,
    required int diamonds,
    required double price,
    String? priceString,
    required String description,
    required Color color,
    required VoidCallback onTap,
    double gradientIntensity = 0.1,
    bool isPopular = false,
  }) {
    return Stack(
      children: [
        Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.8), // Daha koyu arka plan
                color.withOpacity(0.6)  // Daha koyu gradient
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPopular ? Colors.amber : color.withOpacity(0.8),
              width: isPopular ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, isPopular ? 24 : 18, 18, 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$diamonds 💎',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 2.0,
                                  color: Colors.black26,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            priceString ?? '₺${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 2.0,
                                  color: Colors.black26,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Google Pay Button
                  Container(
                    width: double.infinity,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart,
                              color: color,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Satın Al',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Popular Badge
        if (isPopular)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Text(
                '🏆 POPÜLER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  /// Muhtar Badge'lerini oluştur
  Widget _buildMayorBadges() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getUserMayorVenues(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Muhtar bilgileri yükleniyor...',
                  style: TextStyle(
                    color: AppColors.grey600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }
        
        final mayorVenues = snapshot.data ?? [];
        
        if (mayorVenues.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.grey300),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.location_city_outlined,
                  color: AppColors.grey500,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Henüz hiçbir mekanın muhtarı değilsiniz',
                    style: TextStyle(
                      color: AppColors.grey600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...mayorVenues.asMap().entries.map((entry) {
              final index = entry.key;
              final venue = entry.value;
              final venueName = venue['name'] as String;
              final venueType = venue['type'] as String;
              final diamonds = venue['diamonds'] as int;
              final isDiamond = venueType == 'diamond';
              
              return Column(
                children: [
                  if (index > 0) const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDiamond ? [
                          AppColors.primary.withOpacity(0.1),
                          AppColors.primary.withOpacity(0.05),
                        ] : [
                          AppColors.warning.withOpacity(0.1),
                          AppColors.warning.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDiamond 
                          ? AppColors.primary.withOpacity(0.3)
                          : AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Sol taraf - Venue adı
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                isDiamond ? Icons.diamond : Icons.emoji_events,
                                color: isDiamond ? AppColors.primary : AppColors.warning,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  venueName,
                                  style: TextStyle(
                                    color: isDiamond ? AppColors.primary : AppColors.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Sağ taraf - Mayor tipi
                        Text(
                          isDiamond ? '- elmas muhtar' : '- ücretsiz muhtar',
                          style: TextStyle(
                            color: isDiamond ? AppColors.primary : AppColors.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        );
      },
    );
  }
  
  /// Kullanıcının muhtar olduğu mekanları getir
  Future<List<Map<String, dynamic>>> _getUserMayorVenues() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];
      
      // Bugünkü tarihi al
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Daily mayors collection'ından kullanıcının muhtarlıklarını al
      final mayorQuery = await FirebaseFirestore.instance
          .collection('daily_mayors')
          .where('userId', isEqualTo: user.uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      // VenueService instance'ı oluştur
      final venueService = VenueService();
      final mayorVenues = <Map<String, dynamic>>[];
      final processedVenueIds = <String>{};

      for (final doc in mayorQuery.docs) {
        final data = doc.data();
        final venueId = data['venueId'] as String?;
        final mayorType = data['mayorType'] as String? ?? 'first_checkin';
        final diamonds = data['diamondsSpent'] ?? 0;
        
        // Duplicate kontrolü
        if (venueId == null || processedVenueIds.contains(venueId)) {
          continue;
        }
        processedVenueIds.add(venueId);
        
        // Venue name'i venueId'den al
        final venueName = await venueService.getVenueNameById(venueId);
        
        // Debug için mayor type ve diamond bilgisi ekle
        if (mayorType == 'diamond') {
          mayorVenues.add({
            'name': venueName,
            'type': 'diamond',
            'diamonds': diamonds,
          });
        } else {
          mayorVenues.add({
            'name': venueName,
            'type': 'free',
            'diamonds': 0,
          });
        }
      }
      
      return mayorVenues;
    } catch (error) {
      return [];
    }
  }
}

// CheckInHistoryPage implementation
enum CheckInFilter {
  all,
  lastWeek,
  lastMonth,
}

class CheckInHistoryPage extends ConsumerStatefulWidget {
  const CheckInHistoryPage({super.key});

  @override
  ConsumerState<CheckInHistoryPage> createState() => _CheckInHistoryPageState();
}

class _CheckInHistoryPageState extends ConsumerState<CheckInHistoryPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  List<CheckInHistoryItem> _checkIns = [];
  bool _isLoading = true;
  bool _isPremium = false;
  String? _error;
  CheckInFilter _selectedFilter = CheckInFilter.all;
  
  @override
  void initState() {
    super.initState();
    _initializeDateFormatting();
    _checkPremiumStatus();
    _loadCheckInHistory();
  }

  Future<void> _checkPremiumStatus() async {
    final isPremium = await PremiumService.isPremiumActive();
    setState(() {
      _isPremium = isPremium;
    });
  }

  Future<void> _initializeDateFormatting() async {
    try {
      await initializeDateFormatting('tr_TR', null);
    } catch (e) {
    }
  }

  Future<void> _loadCheckInHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı girişi yapılmamış');
      }


      // En basit query - sadece userId ile filtrele ve tarih sıralı getir
      final snapshot = await FirebaseFirestore.instance
          .collection('check_ins')
          .where('userId', isEqualTo: user.uid)
          .orderBy('checkInTime', descending: true) // En yeni en üstte
          .limit(100) // Performans için limit
          .get();
      
      
      List<CheckInHistoryItem> allCheckIns = [];
      
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          
          // Güvenli veri dönüşümü
          final checkIn = CheckInHistoryItem.fromFirestore(data, doc.id);
          allCheckIns.add(checkIn);
        } catch (e) {
        }
      }

      // Firestore'dan zaten sıralı geldiği için client-side sıralama gereksiz
      // allCheckIns.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

      // Filtreleme uygula
      if (_selectedFilter != CheckInFilter.all) {
        DateTime cutoffDate;
        if (_selectedFilter == CheckInFilter.lastWeek) {
          cutoffDate = DateTime.now().subtract(const Duration(days: 7));
        } else {
          cutoffDate = DateTime.now().subtract(const Duration(days: 30));
        }
        allCheckIns = allCheckIns.where((checkIn) => 
          checkIn.checkInTime.isAfter(cutoffDate)
        ).toList();
      }

      // Maksimum 50 sonuç
      final checkIns = allCheckIns.take(50).toList();

      setState(() {
        _checkIns = checkIns;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _error = 'Check-in geçmişi yüklenemedi. Lütfen tekrar deneyiniz.';
        _isLoading = false;
      });
    }
  }

  String _getFilterText() {
    switch (_selectedFilter) {
      case CheckInFilter.lastWeek:
        return 'Bu Hafta';
      case CheckInFilter.lastMonth:
        return 'Bu Ay';
      default:
        return 'Tümü';
    }
  }

  int _getThisMonthCount() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    return _checkIns.where((checkIn) => checkIn.checkInTime.isAfter(thisMonth)).length;
  }

  int _getFavoriteCount() {
    // Premium özellik: favorilere eklenen check-in'lar (şimdilik random)
    return (_checkIns.length * 0.3).round(); 
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.warning, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.warning,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showFilterMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Süre Filtresi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),
            ),
            _buildFilterOption(CheckInFilter.all, 'Tümü', Icons.list),
            _buildFilterOption(CheckInFilter.lastWeek, 'Bu Hafta', Icons.calendar_today),
            _buildFilterOption(CheckInFilter.lastMonth, 'Bu Ay', Icons.calendar_month),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(CheckInFilter value, String text, IconData icon) {
    final isSelected = _selectedFilter == value;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.primary : AppColors.grey600,
      ),
      title: Text(
        text,
        style: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        Navigator.pop(context);
        if (_selectedFilter != value) {
          setState(() => _selectedFilter = value);
          _loadCheckInHistory();
        }
      },
    );
  }

  void _showPremiumSubscriptionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const PremiumSubscriptionWidget(),
    ).then((result) {
      if (result == true) {
        // Premium satın alındıysa sayfayı yenile
        _checkPremiumStatus();
        _loadCheckInHistory();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Premium olmayan kullanıcılar için Premium upgrade göster
    if (!_isPremium) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          title: const Text(
            'Check-in Geçmişi',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.premiumGradient),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.warning.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, color: Colors.white, size: 64),
                const SizedBox(height: 20),
                const Text(
                  '🌟 Premium Özellik',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Check-in geçmişinizi görmek için Premium üyeliğe geçin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    _showPremiumSubscriptionSheet(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    'Premium\'a Geç',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Header bölümü - Foursquare benzeri
                SliverAppBar(
                  expandedHeight: 200.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: AppColors.white,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          // Stats kartları
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    '${_checkIns.length}',
                                    'Check-ins',
                                    Icons.location_on,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildStatCard(
                                    _getMostVisitedCategory(),
                                    'En Çok Gidilen',
                                    Icons.category,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Timeline başlığı
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      'Zaman Çizelgesi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

                // Check-in Listesi
                _checkIns.isEmpty
                    ? SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Henüz check-in geçmişin yok',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final checkIn = _checkIns[index];
                            return _buildTimelineCheckInCard(checkIn, index);
                          },
                          childCount: _checkIns.length,
                        ),
                      ),
              ],
            ),
    );
  }




  Widget _buildStatCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppColors.primary.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.primary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _getMostVisitedCategory() {
    if (_checkIns.isEmpty) return 'Henüz Yok';
    
    final categoryCount = <String, int>{};
    for (final checkIn in _checkIns) {
      final category = _getEffectiveCategory(checkIn);
      if (category.isNotEmpty && category != 'other') {
        categoryCount[category] = (categoryCount[category] ?? 0) + 1;
      }
    }
    
    if (categoryCount.isEmpty) return 'Çeşitli';
    
    final mostVisited = categoryCount.entries.reduce(
      (a, b) => a.value > b.value ? a : b
    );
    
    // Kategori adlarını Türkçe'ye çevir
    switch (mostVisited.key) {
      case 'restaurant':
        return 'Restoran';
      case 'cafe':
        return 'Kafe';
      case 'pastane':
        return 'Pastane';
      case 'shop':
        return 'Mağaza';
      case 'bar':
        return 'Bar';
      case 'park':
        return 'Park';
      case 'gym':
        return 'Spor Salonu';
      case 'hospital':
        return 'Hastane';
      default:
        return 'Çeşitli';
    }
  }

  // int _getCategoriesCount() {
  //   final categories = <String>{};
  //   for (final checkIn in _checkIns) {
  //     final category = checkIn.category;
  //     if (category.isNotEmpty) {
  //       categories.add(category);
  //     }
  //   }
  //   return categories.length;
  // }

  Widget _buildTimelineCheckInCard(CheckInHistoryItem checkIn, int index) {
    // Tarihe göre gruplama
    String timeLabel = 'Bugün';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkInDate = DateTime(checkIn.checkInTime.year, checkIn.checkInTime.month, checkIn.checkInTime.day);
    final daysDifference = today.difference(checkInDate).inDays;
    
    if (daysDifference == 0) {
      timeLabel = 'Bugün';
    } else if (daysDifference == 1) {
      timeLabel = 'Dün';
    } else if (daysDifference <= 7) {
      // Türkçe gün isimleri
      final weekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
      timeLabel = weekdays[checkIn.checkInTime.weekday - 1];
    } else {
      timeLabel = DateFormat('d MMM yyyy', 'tr_TR').format(checkIn.checkInTime);
    }

    // Önceki öğe ile aynı gün mü kontrol et
    bool showDateHeader = true;
    if (index > 0) {
      final prevCheckIn = _checkIns[index - 1];
      final prevCheckInDate = DateTime(prevCheckIn.checkInTime.year, prevCheckIn.checkInTime.month, prevCheckIn.checkInTime.day);
      final prevDaysDifference = today.difference(prevCheckInDate).inDays;
      
      String prevTimeLabel = 'Bugün';
      if (prevDaysDifference == 0) {
        prevTimeLabel = 'Bugün';
      } else if (prevDaysDifference == 1) {
        prevTimeLabel = 'Dün';
      } else if (prevDaysDifference <= 7) {
        final weekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
        prevTimeLabel = weekdays[prevCheckIn.checkInTime.weekday - 1];
      } else {
        prevTimeLabel = DateFormat('d MMM yyyy', 'tr_TR').format(prevCheckIn.checkInTime);
      }
      showDateHeader = timeLabel != prevTimeLabel;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tarih başlığı
        if (showDateHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 16, 16, 8),
            child: Text(
              timeLabel,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),

        // Timeline öğesi
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline çizgisi ve icon
              SizedBox(
                width: 60,
                child: Column(
                  children: [
                    // Timeline line üst
                    if (index > 0)
                      Container(
                        width: 2,
                        height: 20,
                        color: _getCategoryColor(_checkIns[index - 1]).withOpacity(0.5),
                      ),
                    
                    // Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(checkIn),
                        shape: _getCategoryShape(checkIn),
                        borderRadius: _getCategoryShape(checkIn) == BoxShape.rectangle 
                            ? BorderRadius.circular(8) 
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: _getCategoryColor(checkIn).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        _getVenueIcon(checkIn),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    
                    // Timeline line alt
                    if (index < _checkIns.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: _getCategoryColor(checkIn).withOpacity(0.5),
                        ),
                      ),
                  ],
                ),
              ),

              // İçerik kartı
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 16, bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.primary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Venue adı ve zaman
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  checkIn.locationName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  checkIn.address,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: Colors.grey[500],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('HH:mm').format(checkIn.checkInTime),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (checkIn.fromFavorite)
                            const Icon(
                              Icons.favorite,
                              color: Colors.red,
                              size: 20,
                            ),
                        ],
                      ),

                      // Etkileşim bilgileri
                      if (checkIn.likes > 0 || checkIn.comments > 0) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (checkIn.likes > 0) ...[
                              const Icon(
                                Icons.favorite,
                                size: 16,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                checkIn.likes.toString(),
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (checkIn.comments > 0) ...[
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                checkIn.comments.toString(),
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getVenueIcon(CheckInHistoryItem checkIn) {
    final category = _getEffectiveCategory(checkIn);
    
    if (category.contains('restaurant') || category.contains('food') || category.contains('döner') || category.contains('kebap') || category.contains('pide')) {
      return Icons.restaurant;
    } else if (category.contains('coffee') || category.contains('cafe') || category.contains('kahve') || category.contains('kafe')) {
      return Icons.local_cafe;
    } else if (category.contains('shop') || category.contains('store') || category.contains('market')) {
      return Icons.shopping_bag;
    } else if (category.contains('park') || category.contains('outdoor')) {
      return Icons.park;
    } else if (category.contains('gym') || category.contains('fitness')) {
      return Icons.fitness_center;
    } else if (category.contains('pastane') || category.contains('tatlı') || category.contains('waffle')) {
      return Icons.cake;
    } else if (category.contains('bar') || category.contains('pub')) {
      return Icons.local_bar;
    } else if (category.contains('hospital') || category.contains('health')) {
      return Icons.local_hospital;
    } else {
      return Icons.place;
    }
  }

  // Kategori bazında renk döndürür
  Color _getCategoryColor(CheckInHistoryItem checkIn) {
    final category = _getEffectiveCategory(checkIn);
    
    if (category.contains('restaurant') || category.contains('food') || category.contains('döner') || category.contains('kebap') || category.contains('pide')) {
      return AppColors.error; // Kırmızı ton
    } else if (category.contains('coffee') || category.contains('cafe') || category.contains('kahve') || category.contains('kafe')) {
      return AppColors.secondary; // Kahverengi ton
    } else if (category.contains('shop') || category.contains('store') || category.contains('market')) {
      return AppColors.accent; // Mor ton
    } else if (category.contains('park') || category.contains('outdoor')) {
      return AppColors.success; // Yeşil ton
    } else if (category.contains('gym') || category.contains('fitness')) {
      return AppColors.primary; // Mavi ton
    } else if (category.contains('bar') || category.contains('pub')) {
      return AppColors.warning; // Sarı/amber ton
    } else if (category.contains('hospital') || category.contains('health')) {
      return AppColors.info; // Teal ton
    } else if (category.contains('gas') || category.contains('petrol')) {
      return AppColors.primary.withOpacity(0.8); // Koyu mavi
    } else if (category.contains('pastane') || category.contains('tatlı') || category.contains('waffle')) {
      return AppColors.accent.withOpacity(0.7); // Pembe ton
    } else {
      return AppColors.secondary.withOpacity(0.6); // Default renk
    }
  }

  // Kategori bazında şekil döndürür
  BoxShape _getCategoryShape(CheckInHistoryItem checkIn) {
    final category = _getEffectiveCategory(checkIn);
    
    // Özel kategoriler için kare şekil
    if (category.contains('shop') || category.contains('store') || category.contains('market')) {
      return BoxShape.rectangle;
    } else if (category.contains('hospital') || category.contains('health')) {
      return BoxShape.rectangle;
    } else if (category.contains('pastane') || category.contains('tatlı') || category.contains('waffle')) {
      return BoxShape.rectangle;
    } else {
      return BoxShape.circle; // Default daire
    }
  }

  // Etkili kategori - venue name'den tahmin et
  String _getEffectiveCategory(CheckInHistoryItem checkIn) {
    String category = checkIn.category.toLowerCase();
    
    // Eğer kategori boş ise venue name'den tahmin et
    if (category.isEmpty) {
      final venueName = checkIn.locationName.toLowerCase();
      
      if (venueName.contains('coffee') || venueName.contains('cafe') || venueName.contains('kafe') || venueName.contains('kahve')) {
        category = 'cafe';
      } else if (venueName.contains('restaurant') || venueName.contains('döner') || venueName.contains('kebap') || venueName.contains('pide') || venueName.contains('çorba') || venueName.contains('pizza') || venueName.contains('burger') || venueName.contains('lokanta') || venueName.contains('yemek')) {
        category = 'restaurant';
      } else if (venueName.contains('pastane') || venueName.contains('tatlı') || venueName.contains('waffle') || venueName.contains('profiterol')) {
        category = 'pastane';
      } else if (venueName.contains('market') || venueName.contains('shop') || venueName.contains('mağaza')) {
        category = 'shop';
      } else if (venueName.contains('bar') || venueName.contains('pub')) {
        category = 'bar';
      } else if (venueName.contains('hospital') || venueName.contains('hastane') || venueName.contains('sağlık')) {
        category = 'hospital';
      } else if (venueName.contains('park')) {
        category = 'park';
      } else if (venueName.contains('gym') || venueName.contains('fitness') || venueName.contains('spor')) {
        category = 'gym';
      } else {
      }
    } else {
    }
    
    return category;
  }
}

class CheckInHistoryItem {
  final String id;
  final String userId;
  final String locationName;
  final String address;
  final DateTime checkInTime;
  final GeoPoint coordinates;
  final String venueCategory;
  final int totalCheckIns;
  final String venueId;
  final int points;
  final bool fromFavorite;
  final int likes;
  final int comments;

  CheckInHistoryItem({
    required this.id,
    required this.userId,
    required this.locationName,
    required this.address,
    required this.checkInTime,
    required this.coordinates,
    required this.venueId,
    this.venueCategory = '',
    this.totalCheckIns = 1,
    this.points = 0,
    this.fromFavorite = false,
    this.likes = 0,
    this.comments = 0,
  });

  // Helper getter for category property
  String get category => venueCategory;

  factory CheckInHistoryItem.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime checkInTime;
    try {
      if (data['checkInTime'] is Timestamp) {
        checkInTime = (data['checkInTime'] as Timestamp).toDate();
      } else {
        checkInTime = DateTime.now();
      }
    } catch (e) {
      checkInTime = DateTime.now();
    }

    GeoPoint coordinates;
    try {
      if (data['coordinates'] != null) {
        final coords = data['coordinates'];
        if (coords is GeoPoint) {
          coordinates = coords;
        } else if (coords is Map) {
          coordinates = GeoPoint(
            coords['latitude'] ?? 0.0,
            coords['longitude'] ?? 0.0,
          );
        } else {
          coordinates = const GeoPoint(0.0, 0.0);
        }
      } else {
        coordinates = const GeoPoint(0.0, 0.0);
      }
    } catch (e) {
      coordinates = const GeoPoint(0.0, 0.0);
    }

    return CheckInHistoryItem(
      id: id,
      userId: data['userId'] ?? '',
      locationName: data['locationName'] ?? data['venueName'] ?? 'Bilinmeyen Lokasyon',
      address: data['address'] ?? data['venueAddress'] ?? '',
      checkInTime: checkInTime,
      coordinates: coordinates,
      venueId: data['venueId'] ?? '',
      venueCategory: data['venueCategory'] ?? data['category'] ?? '',
      totalCheckIns: data['totalCheckIns'] ?? 1,
      points: data['points'] ?? 0,
      fromFavorite: data['fromFavorite'] ?? false,
      likes: data['likes'] ?? 0,
      comments: data['comments'] ?? 0,
    );
  }

  factory CheckInHistoryItem.fromMap(Map<String, dynamic> data) {
    return CheckInHistoryItem.fromFirestore(data, data['id'] ?? '');
  }

  String getFormattedTime() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkInDate = DateTime(checkInTime.year, checkInTime.month, checkInTime.day);
    final daysDifference = today.difference(checkInDate).inDays;

    if (daysDifference == 0) {
      return DateFormat('HH:mm').format(checkInTime);
    } else if (daysDifference == 1) {
      return 'Dün ${DateFormat('HH:mm').format(checkInTime)}';
    } else if (daysDifference < 7) {
      return '$daysDifference gün önce';
    } else if (daysDifference < 30) {
      final weeks = (daysDifference / 7).floor();
      return '$weeks hafta önce';
    } else {
      return DateFormat('dd.MM.yyyy').format(checkInTime);
    }
  }

  IconData getCategoryIcon() {
    final category = venueCategory.toLowerCase();
    if (category.contains('cafe') || category.contains('coffee')) {
      return Icons.coffee;
    } else if (category.contains('restaurant') || category.contains('food')) {
      return Icons.restaurant;
    } else if (category.contains('bar') || category.contains('pub')) {
      return Icons.local_bar;
    } else if (category.contains('gym') || category.contains('fitness')) {
      return Icons.fitness_center;
    } else if (category.contains('shop') || category.contains('store')) {
      return Icons.shopping_bag;
    } else if (category.contains('park')) {
      return Icons.park;
    } else if (category.contains('hospital') || category.contains('health')) {
      return Icons.local_hospital;
    } else if (category.contains('gas') || category.contains('petrol')) {
      return Icons.local_gas_station;
    } else {
      return Icons.location_on;
    }
  }

  // ELMAS YÖNETİMİ METODları
  
  // Bu method'lar artık _ProfilePageState class'ının içinde tanımlı
}

// SON CHECK-IN MEKANLARI WIDGET
class RecentCheckInsWidget extends StatelessWidget {
  final String userId;

  const RecentCheckInsWidget({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_history,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Son 24 Saatteki Check-in\'ler', // ✅ Başlık güncellendi
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.grey900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('check_ins')
                .where('userId', isEqualTo: userId)
                .orderBy('checkInTime', descending: true)
                .limit(5)
                .snapshots(),
            builder: (context, snapshot) {
              // Debug: Stream durumu
              
              if (snapshot.hasError) {
              }
              
              if (snapshot.hasData) {
                for (int i = 0; i < snapshot.data!.docs.length; i++) {
                  final doc = snapshot.data!.docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final fromFavorite = data['fromFavorite'] ?? false;
                }
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingState();
              }

              if (snapshot.hasError) {
                return _buildErrorState();
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState();
              }

              final checkIns = snapshot.data!.docs
                  .map((doc) => {
                        'id': doc.id,
                        ...doc.data() as Map<String, dynamic>,
                      })
                  .toList();

              return Column(
                children: checkIns.map((checkIn) {
                  return _buildCheckInItem(checkIn);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: List.generate(3, (index) => 
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Shimmer.fromColors(
                baseColor: AppColors.grey200,
                highlightColor: AppColors.grey100,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Shimmer.fromColors(
                      baseColor: AppColors.grey200,
                      highlightColor: AppColors.grey100,
                      child: Container(
                        width: double.infinity,
                        height: 16,
                        color: AppColors.grey200,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Shimmer.fromColors(
                      baseColor: AppColors.grey200,
                      highlightColor: AppColors.grey100,
                      child: Container(
                        width: 100,
                        height: 12,
                        color: AppColors.grey200,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error),
          SizedBox(width: 8),
          Text(
            'Check-in geçmişi yüklenemedi',
            style: TextStyle(color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Row(
        children: [
          Icon(Icons.location_off, color: AppColors.grey400),
          SizedBox(width: 8),
          Text(
            'Henüz check-in yapılmamış',
            style: TextStyle(color: AppColors.grey600),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInItem(Map<String, dynamic> checkIn) {
    final venueName = checkIn['venueName'] ?? 'Bilinmeyen Mekan';
    final venueCategory = checkIn['venueCategory'] ?? '';
    final checkInTime = (checkIn['checkInTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.05),
            AppColors.secondary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.1),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _getCategoryIcon(venueCategory),
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venueName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.grey900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 14,
                      color: AppColors.grey500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getTimeAgo(checkInTime),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.grey600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('cafe') || cat.contains('coffee')) {
      return Icons.coffee;
    } else if (cat.contains('restaurant') || cat.contains('food')) {
      return Icons.restaurant;
    } else if (cat.contains('bar') || cat.contains('pub')) {
      return Icons.local_bar;
    } else if (cat.contains('gym') || cat.contains('fitness')) {
      return Icons.fitness_center;
    } else if (cat.contains('shop') || cat.contains('store')) {
      return Icons.shopping_bag;
    } else if (cat.contains('park')) {
      return Icons.park;
    } else {
      return Icons.location_on;
    }
  }

  String _getTimeAgo(DateTime checkInTime) {
    final now = DateTime.now();
    final difference = now.difference(checkInTime);

    if (difference.inDays == 0) {
      if (difference.inHours > 0) {
        return '${difference.inHours} saat önce';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} dakika önce';
      } else {
        return 'Şimdi';
      }
    } else if (difference.inDays == 1) {
      return 'Dün';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks hafta önce';
    } else {
      return DateFormat('dd.MM.yyyy').format(checkInTime);
    }
  }
}
