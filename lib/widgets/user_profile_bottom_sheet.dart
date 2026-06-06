// lib/widgets/user_profile_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/theme/app_colors.dart';
import '../core/services/chat_request_service.dart';
import 'chat_request_modal.dart';

class UserProfileBottomSheet extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userPhoto;
  final bool isMayor;
  final String? mayorVenueName;
  final bool canMessage; // 🔄 YENİ: Mesaj atılabilirlik kontrolü

  const UserProfileBottomSheet({
    super.key,
    required this.userId,
    required this.userName,
    this.userPhoto,
    this.isMayor = false,
    this.mayorVenueName,
    this.canMessage = false, // 🔄 YENİ: Varsayılan false
  });

  @override
  State<UserProfileBottomSheet> createState() => _UserProfileBottomSheetState();
}

class _UserProfileBottomSheetState extends State<UserProfileBottomSheet>
    with TickerProviderStateMixin {
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  bool _isCurrentUser = false;
  bool _hasSentRequest = false; // Chat isteği gönderildi mi
  bool _isCheckingRequest = true; // Chat isteği kontrolü loading durumu
  
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
    _checkIfCurrentUser();
    _loadUserData();
    _checkChatRequestStatus(); // Chat isteği durumunu kontrol et
    _initAnimations();
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

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        userData = doc.data();
        
        // 🔄 YENİ: Venue details eksikse resolve et
        await _resolveMissingVenueDetails();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 🔧 Eksik venue detaylarını resolve et
  Future<void> _resolveMissingVenueDetails() async {
    if (userData == null) return;
    
    final List<String> favoriteVenues = _safeStringList(userData!['favoriteVenues']);
    final List<Map<String, dynamic>> favoriteVenueDetails = _safeMapList(userData!['favoriteVenueDetails']);
    
    // Eğer venue details eksikse veya venue sayısından azsa
    if (favoriteVenues.isNotEmpty && 
        (favoriteVenueDetails.isEmpty || favoriteVenueDetails.length < favoriteVenues.length)) {
      
      
      // Check-in geçmişinden venue isimlerini bul
      final resolvedDetails = await _resolveVenueNamesFromCheckIns(favoriteVenues);
      
      if (resolvedDetails.isNotEmpty) {
        // userData'yı güncelle (sadece local state, Firestore'a yazmıyoruz)
        userData!['favoriteVenueDetails'] = resolvedDetails;
      }
    }
  }

  /// 📍 Check-in geçmişinden venue isimlerini çözümle
  Future<List<Map<String, dynamic>>> _resolveVenueNamesFromCheckIns(List<String> venueIds) async {
    final List<Map<String, dynamic>> resolvedDetails = [];
    
    try {
      // Check-in koleksiyonundan bu venue'lar için en son kayıtları al
      for (String venueId in venueIds) {
        if (venueId.isEmpty) continue;
        
        final checkInQuery = await FirebaseFirestore.instance
            .collection('check_ins')
            .where('venueId', isEqualTo: venueId)
            .orderBy('checkInTime', descending: true)
            .limit(1)
            .get();
        
        if (checkInQuery.docs.isNotEmpty) {
          final checkInData = checkInQuery.docs.first.data();
          final venueName = checkInData['venueName'] ?? checkInData['locationName'] ?? 'Favori Mekan';
          
          resolvedDetails.add({
            'place_id': venueId,
            'id': venueId,
            'name': venueName,
            'category': checkInData['venueCategory'] ?? '',
            'vicinity': checkInData['venueAddress'] ?? '',
            'latitude': checkInData['venueLocation']?['latitude'] ?? 0.0,
            'longitude': checkInData['venueLocation']?['longitude'] ?? 0.0,
            'rating': 0.0,
          });
          
        } else {
          // Check-in bulunamadı, basic entry ekle
          resolvedDetails.add({
            'place_id': venueId,
            'id': venueId,
            'name': 'Favori Mekan',
            'category': '',
            'vicinity': '',
            'latitude': 0.0,
            'longitude': 0.0,
            'rating': 0.0,
          });
          
        }
      }
    } catch (e) {
    }
    
    return resolvedDetails;
  }

  /// 💬 Normal Chat İsteği Gönder
  Future<void> _sendChatRequest() async {
    final result = await showChatRequestModal(
      context: context,
      targetUserId: widget.userId,
      targetUserName: widget.userName,
      isSuperChat: false,
      onSuccess: () {
        setState(() {
          _hasSentRequest = true;
        });
      },
    );
    
    if (result == true && mounted) {
      // İstek gönderildi, state'i güncelle
      await _checkChatRequestStatus();
    }
  }

  /// ⭐ Süper Chat İsteği Gönder
  Future<void> _sendSuperChatRequest() async {
    final result = await showChatRequestModal(
      context: context,
      targetUserId: widget.userId,
      targetUserName: widget.userName,
      isSuperChat: true,
      onSuccess: () {
        setState(() {
          _hasSentRequest = true;
        });
      },
    );
    
    if (result == true && mounted) {
      // İstek gönderildi, state'i güncelle
      await _checkChatRequestStatus();
    }
  }

  Future<void> _sendMessage() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Mesaj gönderme dialog'u göster
      final messageController = TextEditingController();
      
      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mesaj Gönder'),
          content: TextField(
            controller: messageController,
            decoration: const InputDecoration(
              hintText: 'Mesajınızı yazın...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Gönder'),
            ),
          ],
        ),
      ) ?? false;

      if (shouldSend && messageController.text.trim().isNotEmpty) {
        await FirebaseFirestore.instance.collection('messages').add({
          'senderId': currentUserId,
          'receiverId': widget.userId,
          'message': messageController.text.trim(),
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mesaj gönderildi! 💬'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
    }
  }

  // Güvenli liste dönüşüm fonksiyonları
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

  // FOTOĞRAF KART
  Widget _buildPhotoCard(String photoUrl, int index) {
    return Container(
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
            Image.network(
              photoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: AppColors.grey200,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
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
                );
              },
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
                      AppColors.transparent,
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
    );
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
          const Text(
            '🎯 Hobileri',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.grey900,
            ),
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
          const Text(
            '📍 Favori Mekanları',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.grey900,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: venueDetails.asMap().entries.map((entry) {
              final venue = entry.value;
              final index = entry.key;
              
              // � DEBUG: Venue verilerini logla
              
              // 🔄 DÜZELTME: Venue ID yerine düzgün name göster
              String venueName = 'Favori Mekan'; // Default fallback
              
              // 1. venue['name'] var mı?
              if (venue['name'] != null && venue['name'].toString().isNotEmpty) {
                venueName = venue['name'].toString();
              }
              // 2. venue['place_name'] var mı? (bazı kayıtlarda böyle olabilir)
              else if (venue['place_name'] != null && venue['place_name'].toString().isNotEmpty) {
                venueName = venue['place_name'].toString();
              }
              // 3. venue['vicinity'] var mı? (konum bilgisi)
              else if (venue['vicinity'] != null && venue['vicinity'].toString().isNotEmpty) {
                venueName = venue['vicinity'].toString();
              }
              // 4. Son çare: "Favori Mekan #X" yaz (ID yazmasın!)
              else {
                venueName = 'Favori Mekan ${index + 1}';
              }
              
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: AppColors.success.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.coffee,
                      color: AppColors.success,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
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

  // FAVORİ MEKANLAR (Basit)
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
          const Text(
            '📍 Favori Mekanları',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.grey900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.location_on,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${venues.length} favori mekan seçili',
                style: const TextStyle(
                  color: AppColors.grey600,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Mekan detayları yükleniyor...',
            style: TextStyle(
              color: AppColors.grey500,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: _buildProfileContent(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (userData == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Text(
            'Kullanıcı bulunamadı',
            style: TextStyle(
              color: AppColors.grey600,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    // Verileri güvenli şekilde çıkar
    final String name = userData!['name']?.toString() ?? 'İsimsiz';
    final String surname = userData!['surname']?.toString() ?? '';
    final int age = userData!['age'] ?? 18;
    final String gender = userData!['gender']?.toString() ?? '';
    final bool isPremium = userData!['isPremium'] ?? false;
    
    // Listeler - güvenli dönüşüm
    final List<String> photos = _filterValidPhotos(userData!['photos']);
    final List<String> hobbies = _safeStringList(userData!['hobbies']);
    final List<String> favoriteVenues = _safeStringList(userData!['favoriteVenues']);
    final List<Map<String, dynamic>> favoriteVenueDetails = _safeMapList(userData!['favoriteVenueDetails']);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // AD SOYAD YAŞ VE BADGE'LER - Profil sayfası tasarımı
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
              
              // Yaş ve cinsiyet
              Text(
                '$age yaşında${gender.isNotEmpty ? ' • $gender' : ''}',
                style: const TextStyle(
                  fontSize: 18,
                  color: AppColors.grey600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Badge'ler - MUHTAR badge'i
              if (widget.isMayor)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: AppColors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.mayorVenueName != null 
                            ? '${widget.mayorVenueName} MUHTARI' 
                            : 'MUHTAR',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // 1. FOTOĞRAF
        if (photos.isNotEmpty)
          _buildPhotoCard(photos[0], 0),

        // HOBİLER
        if (hobbies.isNotEmpty)
          _buildHobbiesSection(hobbies),

        // 2. FOTOĞRAF
        if (photos.length > 1)
          _buildPhotoCard(photos[1], 1),

        // FAVORİ MEKANLAR
        if (favoriteVenueDetails.isNotEmpty)
          _buildFavoriteVenuesSection(favoriteVenues, favoriteVenueDetails)
        else if (favoriteVenues.isNotEmpty)
          _buildSimpleFavoriteVenuesSection(favoriteVenues),

        // 3. FOTOĞRAF
        if (photos.length > 2)
          _buildPhotoCard(photos[2], 2),

        // 4. FOTOĞRAF
        if (photos.length > 3)
          _buildPhotoCard(photos[3], 3),

        // 5. FOTOĞRAF
        if (photos.length > 4)
          _buildPhotoCard(photos[4], 4),

        // 6. FOTOĞRAF
        if (photos.length > 5)
          _buildPhotoCard(photos[5], 5),

        // Action Buttons - Alt kısımda sabit (sadece başkasıysa)
        if (!_isCurrentUser) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: _isCheckingRequest
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _hasSentRequest ? null : _sendChatRequest,
                          icon: Icon(
                            _hasSentRequest ? Icons.check_circle : Icons.chat_bubble_outline,
                            color: _hasSentRequest ? AppColors.grey400 : AppColors.white,
                          ),
                          label: Text(
                            _hasSentRequest ? 'İstek Gönderildi' : 'Mesaj İsteği',
                            style: TextStyle(
                              color: _hasSentRequest ? AppColors.grey400 : AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _hasSentRequest ? AppColors.grey200 : AppColors.secondary,
                            foregroundColor: _hasSentRequest ? AppColors.grey400 : AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: _hasSentRequest ? 0 : 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _hasSentRequest ? null : _sendSuperChatRequest,
                          icon: Icon(
                            _hasSentRequest ? Icons.check_circle : Icons.stars,
                            color: _hasSentRequest ? AppColors.grey400 : AppColors.white,
                          ),
                          label: Text(
                            _hasSentRequest ? 'İstek Gönderildi' : 'Süper Mesaj ⭐',
                            style: TextStyle(
                              color: _hasSentRequest ? AppColors.grey400 : AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _hasSentRequest ? AppColors.grey200 : AppColors.primary,
                            foregroundColor: _hasSentRequest ? AppColors.grey400 : AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: _hasSentRequest ? 0 : 2,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          
          // 💬 MESAJ BUTONU (sadece muhtar ile mesajlaşma için)
          if (widget.canMessage && !_isCurrentUser) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton.icon(
                onPressed: _sendMessage,
                icon: const Icon(Icons.message, color: AppColors.white),
                label: const Text(
                  'Muhtara Mesaj Gönder',
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
              ),
            ),
          ],
        ],

        const SizedBox(height: 20),
      ],
    ),
    
    // Normal Beğeni Animasyonu
    if (_showLikeAnimation && _likeAnimationController != null)
      Positioned(
        left: 0,
        right: 0,
        bottom: 160, // Beğeni butonlarının biraz üstünde
        child: AnimatedBuilder(
          animation: _likeAnimationController!,
          builder: (context, child) {
            return Opacity(
              opacity: _likeOpacityAnimation!.value,
              child: Center(
                child: Transform.scale(
                  scale: _likeScaleAnimation!.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.error.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_add,
                          color: AppColors.white,
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'İstek Gönderildi!',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    
    // Süper Beğeni Animasyonu
    if (_showSuperLikeAnimation && _superLikeAnimationController != null)
      Positioned(
        left: 0,
        right: 0,
        bottom: 160, // Beğeni butonlarının biraz üstünde
        child: AnimatedBuilder(
          animation: _superLikeAnimationController!,
          builder: (context, child) {
            return Opacity(
              opacity: _superLikeOpacityAnimation!.value,
              child: Center(
                child: Transform.scale(
                  scale: _superLikeScaleAnimation!.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryLight, AppColors.primary],
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 25,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          color: AppColors.white,
                          size: 32,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'SÜPER!',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(
                          Icons.star,
                          color: AppColors.white,
                          size: 32,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
  ],
    );
  }
}

// Helper function to show the bottom sheet
void showUserProfileBottomSheet(
  BuildContext context, {
  required String userId,
  required String userName,
  String? userPhoto,
  bool isMayor = false,
  String? mayorVenueName,
  bool canMessage = false, // 🔄 YENİ: Mesaj atılabilirlik kontrolü
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => UserProfileBottomSheet(
      userId: userId,
      userName: userName,
      userPhoto: userPhoto,
      isMayor: isMayor,
      mayorVenueName: mayorVenueName,
      canMessage: canMessage, // 🔄 YENİ: Mesaj parametresi
    ),
  );
}


