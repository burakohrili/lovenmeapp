// lib/presentation/pages/explore_nearby/venue_detail_page.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import 'models/venue_detail_model.dart';
import 'services/explore_nearby_service.dart';
import '../profile/user_profile_page.dart';

class VenueDetailPage extends ConsumerStatefulWidget {
  final String venueId;

  const VenueDetailPage({
    super.key,
    required this.venueId,
  });

  @override
  ConsumerState<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends ConsumerState<VenueDetailPage> {
  bool _isLoading = true;
  VenueDetail? _venueDetail;
  bool _isPremium = false;
  final _exploreService = ExploreNearbyService();

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _loadVenueDetail();
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists) {
        setState(() {
          _isPremium = userDoc.data()?['isPremium'] ?? false;
        });
      }
    } catch (e) {
      // Hata durumunda premium değil kabul et
      setState(() {
        _isPremium = false;
      });
    }
  }

  Future<void> _loadVenueDetail() async {
    setState(() => _isLoading = true);
    
    try {
      final venueDetail = await _exploreService.getVenueDetail(widget.venueId);
      
      setState(() {
        _venueDetail = venueDetail;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (_venueDetail == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('Venue not found'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVenueInfo(),
                _buildCheckedInUsers(),
                _buildFeaturesSection(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 250,
      pinned: true,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Builder(
              builder: (context) {
                final photoUrl = _venueDetail!.photoUrl ?? 'https://via.placeholder.com/400x200';
                
                return Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(
                        Icons.image_not_supported,
                        size: 50,
                        color: Colors.grey,
                      ),
                    );
                  },
                );
              },
            ),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueInfo() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _venueDetail!.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              _buildCategoryIcon(),
            ],
          ),
          if (_venueDetail!.description != null && _venueDetail!.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _venueDetail!.description!,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
          if (_venueDetail!.isSponsored) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    _venueDetail!.sponsorBadgeText ?? 'Sponsor',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckedInUsers() {
    // Muhtar ve diğer kullanıcıları ayır
    VenueUser? mayor;
    List<VenueUser> otherUsers = [];

    for (var user in _venueDetail!.checkedInUsers) {
      if (user.isMayor) {
        mayor = user;
      } else {
        otherUsers.add(user);
      }
    }

    // Görüntülenecek kullanıcılar (non-premium için muhtar + 2 kullanıcı = 3 kişi, premium için tümü)
    final displayUsers = _isPremium
        ? otherUsers
        : otherUsers.take(2).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Check-in Yapanlar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_venueDetail!.checkedInUsers.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Elmas Muhtar (varsa) - SADECE elmas muhtar gösterilecek
          if (mayor != null && mayor.isDiamondMayor) _buildMayorCard(mayor),

          // Diğer kullanıcılar - Liste şeklinde (ücretsiz muhtar dahil)
          ...displayUsers.map((user) => _buildUserListItem(user, isBlurred: false)),

          // Premium olmayan kullanıcılar için blurlu kartlar
          if (!_isPremium && otherUsers.length > 2)
            ...otherUsers.skip(2).take(3).map((user) => _buildUserListItem(user, isBlurred: true)),

          // Premium upgrade prompt - sadece non-premium ve daha fazla kullanıcı varsa göster
          if (!_isPremium && otherUsers.length > 2)
            _buildPremiumUpgradePrompt(otherUsers.length - 2),
        ],
      ),
    );
  }

  Widget _buildMayorCard(VenueUser mayor) {
    // Elmas muhtar mı yoksa günün muhtarı mı?
    final isDiamond = mayor.isDiamondMayor;
    
    return GestureDetector(
      onTap: () => _showUserProfile(mayor.userId),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDiamond
                ? [
                    const Color(0xFFFFF0F5),
                    const Color(0xFFFFE4EC),
                  ]
                : [
                    const Color(0xFFFFF9E6),
                    const Color(0xFFFFF3CC),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDiamond
                ? const Color(0xFFFF69B4)
                : const Color(0xFFFFD700),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDiamond
                      ? const Color(0xFFFF69B4)
                      : const Color(0xFFFFD700))
                  .withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDiamond
                          ? const Color(0xFFFF69B4)
                          : const Color(0xFFFFD700),
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: mayor.photoUrl != null
                        ? Image.network(
                            mayor.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildDefaultAvatar(mayor.name);
                            },
                          )
                        : _buildDefaultAvatar(mayor.name),
                  ),
                ),
                if (isDiamond)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF69B4),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.diamond,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // İsim ve bilgi
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Üst başlık
                  Row(
                    children: [
                      Icon(
                        isDiamond ? Icons.diamond : Icons.star,
                        size: 16,
                        color: isDiamond
                            ? const Color(0xFFFF69B4)
                            : const Color(0xFFFFA500),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDiamond ? 'ELMAS MUHTAR' : 'GÜNÜN MUHTARI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDiamond
                              ? const Color(0xFFFF69B4)
                              : const Color(0xFFFFA500),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // İsim
                  Text(
                    mayor.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Bilgi
                  Text(
                    isDiamond
                        ? 'Elmas muhtarı (Toplam ${mayor.checkInCount} 💎 harcandı)'
                        : 'İlk check-in muhtarı (Ücretsiz)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            // Profil butonu
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDiamond
                      ? const Color(0xFFFF69B4)
                      : const Color(0xFFFFD700),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.remove_red_eye,
                color: isDiamond
                    ? const Color(0xFFFF69B4)
                    : const Color(0xFFFFD700),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserListItem(VenueUser user, {bool isBlurred = false}) {
    return GestureDetector(
      onTap: isBlurred ? _showPremiumUpgradeDialog : () => _showUserProfile(user.userId),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            // Ana içerik
            Row(
              children: [
            // Avatar
            Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: user.photoUrl != null
                        ? Image.network(
                            user.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildDefaultAvatar(user.name);
                            },
                          )
                        : _buildDefaultAvatar(user.name),
                  ),
                ),
                if (user.isPremium)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.star,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // İsim ve bilgi
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${user.age}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${user.checkInCount} check-in',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
              size: 20,
            ),
          ],
            ),
            
            // Blur overlay (sadece isBlurred true ise)
            if (isBlurred)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      color: Colors.white.withOpacity(0.3),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock,
                              size: 24,
                              color: AppColors.primary.withOpacity(0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Premium',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary.withOpacity(0.8),
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
      ),
    );
  }

  // Premium upgrade dialog göster
  void _showPremiumUpgradeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.diamond, color: AppColors.primary, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Premium Gerekli',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Tüm kullanıcıları görüntülemek ve profillerine erişmek için Premium üyelik gereklidir.\n\nPremium ile sınırsız erişim kazanın!',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Premium satın alma sayfası açılacak...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Premium Al'),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumUpgradePrompt(int hiddenUsersCount) {
    return GestureDetector(
      onTap: _showPremiumUpgradeDialog,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.1),
              AppColors.secondary.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.diamond,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '+$hiddenUsersCount Kişiyi Daha Gör',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '(Premium)',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar(String name) {
    return Container(
      color: Colors.primaries[name.length % Colors.primaries.length],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Özellikler',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ...(_venueDetail!.features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildCategoryIcon() {
    IconData icon;
    Color color;

    switch (_venueDetail!.category.toLowerCase()) {
      case 'cinema':
      case 'sinema':
        icon = Icons.movie;
        color = const Color(0xFF2196F3);
        break;
      case 'cafe':
      case 'kafe':
        icon = Icons.coffee;
        color = const Color(0xFF8B4513);
        break;
      default:
        icon = Icons.place;
        color = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 24,
        color: color,
      ),
    );
  }

  /// Kullanıcı profilini göster (Bottom Sheet)
  void _showUserProfile(String userId) {
    // Bu kullanıcı bu mekanda muhtar mı kontrol et
    final user = _venueDetail?.checkedInUsers.firstWhere(
      (u) => u.userId == userId,
      orElse: () => _venueDetail!.checkedInUsers.first,
    );
    
    final isMayor = user?.isMayor ?? false;
    final isDiamondMayor = user?.isDiamondMayor ?? false;
    
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => UserProfilePage(
          userId: userId,
          showActions: true,
          isBottomSheet: true,
          isMayor: isMayor,
          isDiamondMayor: isDiamondMayor,
          mayorVenueName: isMayor ? _venueDetail?.name : null,
        ),
      ),
    );
  }
}
