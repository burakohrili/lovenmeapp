// lib/presentation/pages/profile/user_profile_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/gamification_service.dart';
import '../../../core/services/chat_request_service.dart';
import '../../../core/services/premium_service.dart';
import '../../../widgets/photo_viewer.dart';
import '../map/services/venue_service.dart';
import '../../../widgets/encounter_widget.dart';
import '../../widgets/premium/premium_subscription_widget.dart';
import '../../../widgets/chat_request_modal.dart';
import '../safety/community_guidelines_page.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;
  final Map<String, dynamic>? userData;
  final bool showActions; // Encounter widget, şikayet, blok butonları için
  final bool isBottomSheet; // Bottom sheet olarak gösterilip gösterilmeyeceği
  final bool isMayor; // Muhtar olduğu bilgisi
  final bool isDiamondMayor; // Elmas muhtar mı yoksa ücretsiz muhtar mı?
  final String? mayorVenueName; // Muhtar olduğu mekan adı
  // External like state control
  final bool? externalHasSentRequest;
  final VoidCallback? onExternalChatRequest;
  final VoidCallback? onExternalSuperChatRequest;

  const UserProfilePage({
    super.key,
    required this.userId,
    this.userData,
    this.showActions = true, // Default olarak true
    this.isBottomSheet = false, // Default olarak false
    this.isMayor = false, // Default olarak false
    this.isDiamondMayor = false, // Default olarak false (ücretsiz muhtar)
    this.mayorVenueName, // Opsiyonel
    // External chat request controls
    this.externalHasSentRequest,
    this.onExternalChatRequest,
    this.onExternalSuperChatRequest,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> 
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  List<Map<String, dynamic>> _userMayorVenues = [];
  List<String> _allPhotos = [];
  List<String> _currentUserHobbies = []; // Current user'ın hobilerini saklar

  // Chat Request state'leri
  bool _hasSentRequest = false;
  bool _isCheckingRequest = true;
  bool _isCurrentUser = false;
  
  // Animasyon controller'ları
  AnimationController? _likeAnimationController;
  AnimationController? _superLikeAnimationController;
  Animation<double>? _likeScaleAnimation;
  Animation<double>? _likeOpacityAnimation;
  Animation<double>? _superLikeScaleAnimation;
  Animation<double>? _superLikeOpacityAnimation;
  
  bool _showLikeAnimation = false;
  bool _showSuperLikeAnimation = false;

  @override
  void initState() {
    super.initState();
    
    // External chat request state varsa kullan
    if (widget.externalHasSentRequest != null) {
      _hasSentRequest = widget.externalHasSentRequest!;
      _isCheckingRequest = false; // External state varsa loading'i kapat
    }
    
    _checkIfCurrentUser();
    _loadUserProfile();
    _loadUserMayorVenues();
    if (widget.isBottomSheet) {
      // External states varsa chat request status kontrolünü atla
      if (widget.externalHasSentRequest == null) {
        _checkChatRequestStatus();
      }
      _initAnimations();
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      if (widget.userData != null) {
        setState(() {
          _userProfile = widget.userData;
          _isLoading = false;
          _extractPhotos();
        });
        // Widget userData varsa bile current user limitlerini al
        await _loadCurrentUserLimits();
        return;
      }

      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      if (userDoc.exists) {
        setState(() {
          _userProfile = userDoc.data();
          _isLoading = false;
          _extractPhotos();
        });
        // Current user limitlerini al
        await _loadCurrentUserLimits();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // CURRENT USER VERİLERİNİ YÜKLEYİN (hobbies için)
  Future<void> _loadCurrentUserLimits() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null || _isCurrentUser) {
        return;
      }

      // Current user'ın hobilerini al
      final currentUserDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (currentUserDoc.exists) {
        final userData = currentUserDoc.data()!;
        setState(() {
          _currentUserHobbies = List<String>.from(userData['hobbies'] ?? []);
        });
      }
    } catch (e) {
    }
  }

  // Venue ID'lerinden gerçek venue isimlerini çek
  Future<List<String>> _resolveVenueNames(List<String> venueIds) async {
    if (venueIds.isEmpty) return [];
    
    try {
      final resolvedNames = <String>[];
      
      for (String venueId in venueIds) {
        try {
          // Check-in koleksiyonundan bu venue için bir check-in bul
          final checkInQuery = await FirebaseFirestore.instance
              .collection('check_ins')
              .where('venueId', isEqualTo: venueId)
              .limit(1)
              .get();
          
          if (checkInQuery.docs.isNotEmpty) {
            final checkInData = checkInQuery.docs.first.data();
            final venueName = checkInData['venueName'] as String?;
            
            if (venueName != null && venueName.isNotEmpty) {
              resolvedNames.add(venueName);
            } else {
              resolvedNames.add('Favori Mekan');
            }
          } else {
            resolvedNames.add('Favori Mekan');
          }
        } catch (e) {
          resolvedNames.add('Favori Mekan');
        }
      }
      
      return resolvedNames;
    } catch (e) {
      // Fallback: Her venue için "Favori Mekan" döndür
      return venueIds.map((id) => 'Favori Mekan').toList();
    }
  }

  // REMOVED: No longer needed with chat request system

  void _extractPhotos() {
    if (_userProfile != null) {
      final photos = _userProfile!['photos'] as List<dynamic>? ?? [];
      _allPhotos = photos.map((photo) => photo.toString()).where((url) => 
        url.startsWith('http://') || url.startsWith('https://')).toList();
    }
  }

  Future<void> _loadUserMayorVenues() async {
    try {
      // TÜM mayor kayıtlarını getir (sadece bugün değil!)
      // Kullanıcının muhtar olduğu tüm mekanları gösterelim
      final mayorQuery = await _firestore
          .collection('daily_mayors')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('date', descending: true)
          .get();

      
      final venueService = VenueService();
      final mayorVenues = <Map<String, dynamic>>[];
      
      // Her venue için en yüksek diamond'lı mayor kaydını sakla
      final bestMayorByVenue = <String, Map<String, dynamic>>{};

      for (final doc in mayorQuery.docs) {
        final data = doc.data();
        final venueId = data['venueId'] as String?;
        final mayorType = data['mayorType'] as String? ?? 'first_checkin';
        final diamonds = data['diamondsSpent'] ?? 0;
        // final date = data['date'] as Timestamp?; // Unused variable
        
        
        if (venueId == null) {
          continue;
        }
        
        // Bu venue için daha önce kaydedilmiş bir mayor var mı?
        if (bestMayorByVenue.containsKey(venueId)) {
          final existingDiamonds = bestMayorByVenue[venueId]!['diamonds'] as int;
          
          // Yeni kayıt daha fazla diamond'a sahipse, güncelle
          if (diamonds > existingDiamonds) {
            bestMayorByVenue[venueId] = {
              'venueId': venueId,
              'mayorType': mayorType,
              'diamonds': diamonds,
            };
          } else {
          }
        } else {
          // İlk kez görülen venue
          bestMayorByVenue[venueId] = {
            'venueId': venueId,
            'mayorType': mayorType,
            'diamonds': diamonds,
          };
        }
      }
      
      // En iyi mayor kayıtlarından venue listesini oluştur
      for (final mayorData in bestMayorByVenue.values) {
        final venueId = mayorData['venueId'] as String;
        final mayorType = mayorData['mayorType'] as String;
        final diamonds = mayorData['diamonds'] as int;
        
        final venueName = await venueService.getVenueNameById(venueId);
        
        mayorVenues.add({
          'name': venueName,
          'type': mayorType == 'diamond' ? 'diamond' : 'free',
          'diamonds': diamonds,
        });
      }
      
      
      setState(() {
        _userMayorVenues = mayorVenues;
      });
    } catch (e) {
    }
  }

  // LIKE VE SUPER LIKE İŞLEMLERİ
  void _checkIfCurrentUser() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _isCurrentUser = currentUserId == widget.userId;
  }

  Future<void> _checkChatRequestStatus() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null || _isCurrentUser) {
        setState(() {
          _isCheckingRequest = false;
        });
        return;
      }

      // Chat isteği gönderilmiş mi kontrol et
      final hasSent = await ChatRequestService.hasSentRequest(widget.userId);
      
      // Zaten eşleşmiş mi kontrol et
      final alreadyMatched = await ChatRequestService.areAlreadyMatched(widget.userId);
      

      setState(() {
        _hasSentRequest = hasSent || alreadyMatched;
        _isCheckingRequest = false;
      });
    } catch (e) {
      setState(() {
        _isCheckingRequest = false;
      });
    }
  }

  void _initAnimations() {
    // Normal beğeni animasyonu
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _likeScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _likeAnimationController!,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    ));
    
    _likeOpacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _likeAnimationController!,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    ));

    // Süper beğeni animasyonu
    _superLikeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _superLikeScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _superLikeAnimationController!,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    ));
    
    _superLikeOpacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _superLikeAnimationController!,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    ));

    // Animasyon tamamlandığında temizle
    _likeAnimationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _showLikeAnimation = false;
        });
        _likeAnimationController!.reset();
      }
    });

    _superLikeAnimationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _showSuperLikeAnimation = false;
        });
        _superLikeAnimationController!.reset();
      }
    });
  }

  @override
  void dispose() {
    _likeAnimationController?.dispose();
    _superLikeAnimationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isBottomSheet) {
      // Bottom sheet mode - Scaffold olmadan döndür
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _userProfile?['name'] ?? 'Profil',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      // Elmas Muhtar badge'i (SADECE elmas muhtar ise)
                      if (widget.isMayor && widget.isDiamondMayor && widget.mayorVenueName != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity, // Full genişlik
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryDark],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.diamond,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'ELMAS MUHTAR',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.mayorVenueName!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2, // 2 satıra çıkarttık
                              ),
                            ],
                          ),
                        ),
                      ],
                      // LIKE BUTONLARI (eğer bottom sheet mode ise ve başka kullanıcı ise)
                      if (widget.isBottomSheet && !_isCurrentUser) ...[
                        const SizedBox(height: 12),
                        _buildCompactLikeButtons(),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading ? _buildLoadingSkeleton() : _buildProfileContent(),
                ),
              ],
            ),

            // GLOBAL LIKE ANIMATIONS - Bottom sheet'te de tüm alanı kaplasın
            if (_showLikeAnimation)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _likeAnimationController!,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _likeOpacityAnimation!.value,
                      child: Transform.scale(
                        scale: _likeScaleAnimation!.value,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.pink.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.place,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            if (_showSuperLikeAnimation)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _superLikeAnimationController!,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _superLikeOpacityAnimation!.value,
                      child: Transform.scale(
                        scale: _superLikeScaleAnimation!.value,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.purple[400]!, Colors.blue[400]!],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    }
    
    // Normal mode - Scaffold ile döndür
    return Scaffold(
      backgroundColor: AppColors.grey50,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header - profile_page.dart'tan tam kopya
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
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: AppColors.primary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          _userProfile?['name'] ?? 'Profil',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48), // Balance for back button
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading ? _buildLoadingSkeleton() : _buildProfileContent(),
                ),
              ],
            ),

            // GLOBAL LIKE ANIMATIONS - Tüm ekranı kaplasın
            if (_showLikeAnimation)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _likeAnimationController!,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _likeOpacityAnimation!.value,
                      child: Transform.scale(
                        scale: _likeScaleAnimation!.value,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.pink.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.place,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            if (_showSuperLikeAnimation)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _superLikeAnimationController!,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _superLikeOpacityAnimation!.value,
                      child: Transform.scale(
                        scale: _superLikeScaleAnimation!.value,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.purple[400]!, Colors.blue[400]!],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Shimmer.fromColors(
      baseColor: AppColors.grey300,
      highlightColor: AppColors.grey100,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(height: 120, color: AppColors.white),
            const SizedBox(height: 10),
            Container(height: 400, margin: const EdgeInsets.all(20), color: AppColors.white),
            Container(height: 150, margin: const EdgeInsets.all(20), color: AppColors.white),
            Container(height: 400, margin: const EdgeInsets.all(20), color: AppColors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          const Text(
            'Profil yüklenemedi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Geri Dön'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    if (_userProfile == null) {
      return _buildErrorState();
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AD SOYAD YAŞ VE BADGE'LER - profile_page.dart ile aynı stil
          _buildNameAgeSection(),
          
          // İLK FOTOĞRAF
          if (_allPhotos.isNotEmpty) _buildPhotoCard(_allPhotos[0], 0),
          
          // HOBİLER
          _buildHobbiesSection(),
          
          // İKİNCİ FOTOĞRAF
          if (_allPhotos.length > 1) _buildPhotoCard(_allPhotos[1], 1),
          
          // FAVORİ MEKANLAR
          _buildFavoriteVenuesSection(),
          
          // ÜÇÜNCÜ FOTOĞRAF
          if (_allPhotos.length > 2) _buildPhotoCard(_allPhotos[2], 2),
          
          // SON CHECK-IN MEKANLARI
          _buildRecentCheckInsSection(),
          
          // PREMIUM REKLAMI (kullanıcı premium değilse)
          _buildPremiumUpgradeSection(),
          
          // DÖRDÜNCÜ FOTOĞRAF
          if (_allPhotos.length > 3) _buildPhotoCard(_allPhotos[3], 3),
          
          // BEŞİNCİ FOTOĞRAF
          if (_allPhotos.length > 4) _buildPhotoCard(_allPhotos[4], 4),
          
          // ALTINCI FOTOĞRAF
          if (_allPhotos.length > 5) _buildPhotoCard(_allPhotos[5], 5),
          
          // ENCOUNTER WIDGET (eğer showActions true ise)
          if (widget.showActions) _buildEncounterWidget(),
          
          // AKSIYON BUTONLARI (şikayet, blok - sadece normal mode)
          if (widget.showActions && !widget.isBottomSheet) _buildActionButtons(),
          
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // AD SOYAD YAŞ VE BADGE'LER - profile_page.dart ile aynı
  Widget _buildNameAgeSection() {
    final String name = _userProfile?['name']?.toString() ?? 'İsimsiz';
    final String surname = _userProfile?['surname']?.toString() ?? '';
    final int age = _userProfile?['age'] ?? 18;
    final String gender = _userProfile?['gender']?.toString() ?? '';
    final bool isPremium = _userProfile?['isPremium'] ?? false;

    return Container(
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
          
          // Kimlik demografiye değil, gezip keşfedilene dayanıyor.
          // Yaş/cinsiyet verisi korunuyor, sadece gösterilmiyor.
          Text(
            GamificationService.levelTitle(GamificationService.levelFor(
                (_userProfile?['totalCheckIns'] as num?)?.toInt() ?? 0)),
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.grey600,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Muhtar Badge'leri
          _buildMayorBadges(),
        ],
      ),
    );
  }

  // MUHTAR BADGE'LERİ - profile_page.dart ile aynı stil
  Widget _buildMayorBadges() {
    if (_userMayorVenues.isEmpty) {
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
                'Henüz hiçbir mekanın muhtarı değil',
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
        ..._userMayorVenues.asMap().entries.map((entry) {
          final index = entry.key;
          final venue = entry.value;
          final venueName = venue['name'] as String;
          final venueType = venue['type'] as String;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Venue adı
                    Row(
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
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    // Mayor tipi
                    Text(
                      isDiamond ? 'Elmas Muhtar' : 'Ücretsiz Muhtar',
                      style: TextStyle(
                        color: isDiamond ? AppColors.primary.withOpacity(0.7) : AppColors.warning.withOpacity(0.7),
                        fontSize: 11,
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
  }
  // FOTOĞRAF KART - profile_page.dart ile aynı
  Widget _buildPhotoCard(String photoUrl, int index) {
    return GestureDetector(
      onTap: () {
        showPhotoViewer(
          context,
          imageUrls: _allPhotos,
          initialIndex: index,
          heroTag: 'user_photo_$index',
        );
      },
      child: Hero(
        tag: 'user_photo_$index',
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
                      'userPhotos',
                      stalePeriod: const Duration(days: 7), // 7 gün cache
                      maxNrOfCacheObjects: 200, // Max 200 fotoğraf cache
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // HOBİLER BÖLÜMÜ - ortak hobi kontrolü ile
  Widget _buildHobbiesSection() {
    final hobbies = _userProfile?['hobbies'] as List<dynamic>? ?? [];
    
    if (hobbies.isEmpty) {
      return const SizedBox.shrink();
    }

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
                'Hobileri',
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
              final hobbyStr = hobby.toString();
              final isCommonHobby = _currentUserHobbies.contains(hobbyStr);
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isCommonHobby ? AppColors.white : null,
                  gradient: isCommonHobby ? null : LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.8),
                      AppColors.primaryLight,
                    ],
                  ),
                  border: isCommonHobby ? Border.all(
                    color: Colors.pink,
                    width: 2,
                  ) : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hobbyStr,
                  style: TextStyle(
                    color: isCommonHobby ? AppColors.primary : AppColors.white,
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
  // FAVORİ MEKANLAR - profile_page.dart ile aynı stil
  Widget _buildFavoriteVenuesSection() {
    final favoriteVenues = _userProfile?['favoriteVenues'] as List<dynamic>? ?? [];
    final favoriteVenueDetails = _userProfile?['favoriteVenueDetails'] as List<dynamic>? ?? [];

    if (favoriteVenues.isEmpty && favoriteVenueDetails.isEmpty) {
      return const SizedBox.shrink();
    }

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
                'Favori Mekanları',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.grey900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Detaylı venue bilgileri varsa onları göster
          if (favoriteVenueDetails.isNotEmpty)
            Column(
              children: favoriteVenueDetails.asMap().entries.map((entry) {
                final venue = entry.value;
                final index = entry.key;
                
                // 🔄 YENİ SİSTEM: Venue name resolve logic
                String venueName = 'Favori Mekan'; // Default fallback
                
                // 1. venue['name'] var mı?
                if (venue['name'] != null && venue['name'].toString().isNotEmpty) {
                  venueName = venue['name'].toString();
                }
                // 2. venue['place_name'] var mı?
                else if (venue['place_name'] != null && venue['place_name'].toString().isNotEmpty) {
                  venueName = venue['place_name'].toString();
                }
                // 3. venue['vicinity'] var mı?
                else if (venue['vicinity'] != null && venue['vicinity'].toString().isNotEmpty) {
                  venueName = venue['vicinity'].toString();
                }
                // 4. Son çare: "Favori Mekan #X" 
                else {
                  venueName = 'Favori Mekan ${index + 1}';
                }
                
                return Container(
                  width: double.infinity,
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
                        child: const Icon(
                          Icons.location_on,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          venueName,
                          style: const TextStyle(
                            color: AppColors.grey900,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else if (favoriteVenues.isNotEmpty)
            // 🔄 YENİ: Venue ID'lerini resolve et
            FutureBuilder<List<String>>(
              future: _resolveVenueNames(favoriteVenues.cast<String>()),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  );
                }
                
                final venueNames = snapshot.data ?? favoriteVenues.map((v) => 'Favori Mekan').toList();
                
                return Column(
                  children: venueNames.asMap().entries.map((entry) {
                    final venueName = entry.value.toString();
                    
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              venueName,
                              style: const TextStyle(
                                color: AppColors.grey900,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            )
          else
            // Basit venue sayısı
            Text(
              '${favoriteVenues.length} favori mekan seçildi',
              style: const TextStyle(
                color: AppColors.grey600,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  // SON CHECK-IN MEKANLARI
  Widget _buildRecentCheckInsSection() {
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
                'Son 24 Saatteki Check-in\'leri',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.grey900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRecentCheckInsList(),
        ],
      ),
    );
  }

  Widget _buildRecentCheckInsList() {
    // 24 saat öncesini hesapla
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));
    
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: widget.userId)
          .where('checkInTime', isGreaterThan: Timestamp.fromDate(twentyFourHoursAgo)) // 🔄 24 saatlik filtre
          .orderBy('checkInTime', descending: true) // En yeni önce
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildCheckInsLoadingState();
        }

        if (snapshot.hasError) {
          return _buildCheckInsErrorState();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildCheckInsEmptyState();
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
    );
  }

  Widget _buildCheckInsLoadingState() {
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

  Widget _buildCheckInsErrorState() {
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

  Widget _buildCheckInsEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Row(
        children: [
          Icon(Icons.location_off, color: AppColors.grey400),
          SizedBox(width: 8),
          Text(
            'Son 24 saatte check-in yapılmamış',
            style: TextStyle(color: AppColors.grey600),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInItem(Map<String, dynamic> checkIn) {
    final venueName = checkIn['venueName'] ?? checkIn['locationName'] ?? 'Bilinmeyen Mekan';
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

  // PREMIUM UPGRADE - profile_page.dart ile aynı
  Widget _buildPremiumUpgradeSection() {
    final isPremium = _userProfile?['isPremium'] ?? false;
    
    if (isPremium) {
      return const SizedBox.shrink(); // Premium kullanıcılar için gösterme
    }

    // Profili görüntüleyen kullanıcının premium durumunu kontrol et
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(currentUser.uid).get(),
      builder: (context, snapshot) {
        // Default olarak non-premium davran
        bool isCurrentUserPremium = false;
        
        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          isCurrentUserPremium = userData?['isPremium'] ?? false;
        }

        return _buildPremiumCard(isCurrentUserPremium);
      },
    );
  }

  Widget _buildPremiumCard(bool isCurrentUserPremium) {
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
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => SafeArea( // 🔧 SAFE AREA: User profile premium bottom sheet wrapper
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: PremiumSubscriptionWidget(
                    onPurchaseSuccess: (type) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🎉 Premium satın alındı!'),
                          backgroundColor: Colors.green,
                        ),
                      );
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
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.star, color: AppColors.white, size: 48),
                const SizedBox(height: 16),
                Text(
                  isCurrentUserPremium ? ' Premium\'u Devam Ettir' : '🚀 Premium\'a Geç',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isCurrentUserPremium 
                    ? 'Premium avantajlarını kaybetme'
                    : 'Yeni özellikler ve ayrıcalıklar',
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
                  child: Text(
                    isCurrentUserPremium ? 'Süreyi Uzat' : 'Hemen Başla',
                    style: const TextStyle(
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

  // ENCOUNTER WIDGET
  Widget _buildEncounterWidget() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _userProfile == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(currentUser.uid).get(),
      builder: (context, snapshot) {
        String currentUserPhoto = '';
        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final photos = userData['photos'] as List<dynamic>? ?? [];
          currentUserPhoto = photos.isNotEmpty ? photos[0].toString() : '';
        }

        final otherUserPhoto = _allPhotos.isNotEmpty ? _allPhotos[0] : '';

        return EncounterWidget(
          currentUserId: currentUser.uid,
          otherUserId: widget.userId,
          currentUserPhoto: currentUserPhoto,
          otherUserPhoto: otherUserPhoto,
        );
      },
    );
  }

  // AKSIYON BUTONLARI
  Widget _buildActionButtons() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showReportDialog(),
              icon: const Icon(Icons.flag, size: 18),
              label: const Text('Şikayet Et'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning.withOpacity(0.1),
                foregroundColor: AppColors.warning,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: AppColors.warning.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showBlockDialog(),
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Engelle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error.withOpacity(0.1),
                foregroundColor: AppColors.error,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: AppColors.error.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Şikayet Et'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_userProfile?['name'] ?? 'Bu kullanıcı'}yı neden şikayet ediyorsunuz?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ...['Sahte Profil', 'Taciz/Rahatsız Etme', 'Uygunsuz İçerik', 'Spam/Bot'].map(
              (reason) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    reason,
                    style: const TextStyle(fontSize: 14),
                  ),
                  leading: Icon(
                    _getReportReasonIcon(reason),
                    color: AppColors.error,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.grey300),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _reportUser(reason);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CommunityGuidelinesPage(),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text(
                  'Topluluk Kuralları',
                  style: TextStyle(color: Colors.blue.shade600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  IconData _getReportReasonIcon(String reason) {
    switch (reason) {
      case 'Sahte Profil':
        return Icons.person_off;
      case 'Taciz/Rahatsız Etme':
        return Icons.warning;
      case 'Uygunsuz İçerik':
        return Icons.block;
      case 'Spam/Bot':
        return Icons.smart_toy;
      default:
        return Icons.flag;
    }
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Engelle'),
        content: const Text('Bu kullanıcıyı engellemek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _blockUser();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Engelle'),
          ),
        ],
      ),
    );
  }

  Future<void> _reportUser(String reason) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await _firestore.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedUserId': widget.userId,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'user_report',
        'status': 'pending', // Admin incelemesi için
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$reason nedeniyle şikayet edildi. İnceleyeceğiz.'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şikayet gönderilemedi. Lütfen tekrar deneyin.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _blockUser() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('blocked_users')
          .doc(widget.userId)
          .set({
        'blockedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kullanıcı engellendi'),
            backgroundColor: AppColors.error,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
    }
  }

  // KOMPAKT LIKE VE SÜPER LIKE BUTONLARI (Header için)
  Widget _buildCompactLikeButtons() {
    if (_isCheckingRequest) {
      return const SizedBox(
        height: 50,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      child: Row(
        children: [
          // NORMAL SOHBET İSTEĞİ BUTONU
          Expanded(
            child: GestureDetector(
              onTap: _hasSentRequest
                ? null 
                : () async {
                    
                    // External callback varsa onu kullan, yoksa internal method'u çağır
                    if (widget.onExternalChatRequest != null) {
                      widget.onExternalChatRequest!();
                    } else {
                      await _sendChatRequest();
                    }
                  },
              child: Container(
                height: 48,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: _hasSentRequest 
                    ? Colors.grey[200]
                    : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hasSentRequest 
                      ? Colors.grey[300]!
                      : AppColors.primary.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: _hasSentRequest ? null : [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _hasSentRequest ? Icons.check_circle_outline : Icons.chat_bubble_outline,
                      color: _hasSentRequest ? Colors.grey[600] : AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hasSentRequest ? 'Gönderildi' : 'Mesaj Gönder',
                      style: TextStyle(
                        color: _hasSentRequest ? Colors.grey[600] : AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // SÜPER SOHBET İSTEĞİ BUTONU
          Expanded(
            child: GestureDetector(
              onTap: _hasSentRequest
                ? null 
                : () async {
                    
                    // External callback varsa onu kullan, yoksa internal method'u çağır
                    if (widget.onExternalSuperChatRequest != null) {
                      widget.onExternalSuperChatRequest!();
                    } else {
                      await _sendSuperChatRequest();
                    }
                  },
              child: Container(
                height: 48,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  gradient: _hasSentRequest 
                    ? null
                    : const LinearGradient(
                        colors: [
                          Color(0xFFFF6B9D),
                          Color(0xFFC239B8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                  color: _hasSentRequest ? Colors.grey[200] : null,
                  borderRadius: BorderRadius.circular(12),
                  border: _hasSentRequest ? Border.all(
                    color: Colors.grey[300]!,
                    width: 1.5,
                  ) : null,
                  boxShadow: _hasSentRequest ? null : [
                    BoxShadow(
                      color: const Color(0xFFC239B8).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _hasSentRequest ? Icons.check_circle_outline : Icons.stars_rounded,
                      color: _hasSentRequest ? Colors.grey[600] : Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hasSentRequest ? 'Gönderildi' : 'Öne Çıkan',
                      style: TextStyle(
                        color: _hasSentRequest ? Colors.grey[600] : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Normal sohbet isteği gönder
  Future<void> _sendChatRequest() async {
    // 🛡️ Günlük limit kontrolü (Premium değilse)
    final premiumStatus = await PremiumService.getPremiumStatus();
    
    if (!premiumStatus.isPremium) {
      // Premium değilse günlük limit kontrol et
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final userData = userDoc.data();
        final dailyChatRequestsRemaining = userData?['dailyChatRequestsRemaining'] ?? 0;
        
        if (dailyChatRequestsRemaining <= 0) {
          if (!mounted) return;
          
          // Dialog ile uyarı göster (Bottom sheet üstünde görünür)
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Günlük Limitiniz Doldu',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: const Text(
                'Günlük bağlantı isteği limitiniz doldu.\n\nPremium üyelik ile daha fazla bağlantı isteği gönderebilirsiniz.',
                style: TextStyle(fontSize: 15),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          );
          return;
        }
      }
    }
    
    final userName = _userProfile?['name'] ?? 'Kullanıcı';
    final result = await showChatRequestModal(
      context: context,
      targetUserId: widget.userId,
      targetUserName: userName,
      isSuperChat: false,
    );
    if (result == true) {
      setState(() {
        _hasSentRequest = true;
      });
    }
  }

  // Öne çıkan bağlantı isteği gönder
  Future<void> _sendSuperChatRequest() async {
    // 🛡️ Öne çıkan istek hakkı kontrolü
    final premiumStatus = await PremiumService.getPremiumStatus();
    
    if (premiumStatus.superChatsRemaining <= 0) {
      if (!mounted) return;
      
      // Dialog ile uyarı göster (Bottom sheet üstünde görünür)
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Öne Çıkan İstek Hakkınız Yok',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Öne çıkan istek hakkınız kalmadı.\n\nPremium üyelik satın alarak öne çıkan istek hakkı kazanabilirsiniz.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }
    
    final userName = _userProfile?['name'] ?? 'Kullanıcı';
    final result = await showChatRequestModal(
      context: context,
      targetUserId: widget.userId,
      targetUserName: userName,
      isSuperChat: true,
    );
    if (result == true) {
      setState(() {
        _hasSentRequest = true;
      });
    }
  }

}
