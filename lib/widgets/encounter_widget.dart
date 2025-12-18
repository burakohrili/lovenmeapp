// lib/widgets/encounter_widget.dart

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/services/encounter_service.dart';

class EncounterWidget extends StatefulWidget {
  final String currentUserId;
  final String otherUserId;
  final String currentUserPhoto;
  final String otherUserPhoto;
  // External like state control
  final bool? externalIsLiked;
  final bool? externalIsSuperLiked;
  final VoidCallback? onExternalLike;
  final VoidCallback? onExternalSuperLike;

  const EncounterWidget({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    required this.currentUserPhoto,
    required this.otherUserPhoto,
    // External controls
    this.externalIsLiked,
    this.externalIsSuperLiked,
    this.onExternalLike,
    this.onExternalSuperLike,
  });

  @override
  State<EncounterWidget> createState() => _EncounterWidgetState();
}

class _EncounterWidgetState extends State<EncounterWidget>
    with SingleTickerProviderStateMixin {
  EncounterData? _encounterData;
  bool _isLoading = true;
  bool _isPremium = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadEncounterData();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
  }

  Future<void> _loadEncounterData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Premium kontrolü
      final isPremium = await EncounterService.isCurrentUserPremium();
      
      if (!isPremium) {
        setState(() {
          _isPremium = false;
          _isLoading = false;
        });
        return;
      }

      // Encounter verilerini al
      final encounterData = await EncounterService.getTopEncounter(
        widget.currentUserId,
        widget.otherUserId,
      );

      setState(() {
        _isPremium = true;
        _encounterData = encounterData;
        _isLoading = false;
      });

      // Animasyonu başlat
      if (_encounterData != null) {
        _animationController.forward();
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (!_isPremium) {
      return _buildPremiumRequiredWidget();
    }

    if (_encounterData == null) {
      return _buildNoEncounterWidget();
    }

    return _buildEncounterWidget();
  }

  Widget _buildLoadingWidget() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/images/feed_post_background.png'),
          fit: BoxFit.cover,
          opacity: 0.1,
        ),
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildIntersectingAvatars(true),
          const SizedBox(height: 16),
          Column(
            children: [
              Container(
                height: 16,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 12,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumRequiredWidget() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber[100]!, Colors.orange[100]!],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        children: [
          Icon(
            Icons.diamond,
            color: Colors.amber[700],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Karşılaşma geçmişi için Premium üyelik gerekli',
              style: TextStyle(
                color: Colors.amber[800],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoEncounterWidget() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/images/feed_post_background.png'),
          fit: BoxFit.cover,
          opacity: 0.3,
        ),
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          _buildIntersectingAvatars(false),
          const SizedBox(width: 16),
          Text(
            'Henüz aynı mekanda karşılaşmadınız',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEncounterWidget() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                image: const DecorationImage(
                  image: AssetImage('assets/images/feed_post_background.png'),
                  fit: BoxFit.cover,
                  opacity: 0.35,
                ),
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.05),
                    AppColors.secondary.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Üstte kesişen profil fotoğrafları
                  _buildIntersectingAvatars(false),
                  const SizedBox(height: 16),
                  
                  // Altta encounter bilgileri
                  Column(
                    children: [
                      // Karşılaşma sayısı - button gibi
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_encounterData!.encounterCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'kez',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_encounterData!.venueName}\'da',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        child: Text(
                          'karşılaştınız',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.grey[400],
                            decorationThickness: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntersectingAvatars(bool isLoading) {
    return SizedBox(
      width: 132, // 110 * 1.2 = 132
      height: 94, // 84 + 10 (aşağıya indirme için)
      child: Stack(
        children: [
          // Sol avatar (mevcut kullanıcı) - sola yatık
          Positioned(
            left: 0,
            top: 10, // Biraz aşağıya indirdik
            child: Transform.rotate(
              angle: -0.2, // 0.2 radyan sola yatık
              child: Container(
                width: 72, // 60 * 1.2 = 72
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18), // 72 * 0.25 = 18 (tam daire yerine)
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14), // Border'ın içi için
                  child: widget.currentUserPhoto.isNotEmpty
                      ? Image.network(
                          widget.currentUserPhoto,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 72,
                              height: 72,
                              color: isLoading 
                                  ? Colors.grey[300] 
                                  : AppColors.primaryLight.withOpacity(0.3),
                              child: Icon(
                                Icons.person,
                                color: isLoading ? Colors.grey[500] : AppColors.primary,
                                size: 36, // 28 * 1.2 ≈ 34
                              ),
                            );
                          },
                        )
                      : Container(
                          width: 72,
                          height: 72,
                          color: isLoading 
                              ? Colors.grey[300] 
                              : AppColors.primaryLight.withOpacity(0.3),
                          child: Icon(
                            Icons.person,
                            color: isLoading ? Colors.grey[500] : AppColors.primary,
                            size: 36,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // Sağ avatar (diğer kullanıcı) - sağa yatık
          Positioned(
            right: 0,
            top: 20, // Biraz aşağıya indirdik
            child: Transform.rotate(
              angle: 0.2, // 0.2 radyan sağa yatık
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: widget.otherUserPhoto.isNotEmpty
                      ? Image.network(
                          widget.otherUserPhoto,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 72,
                              height: 72,
                              color: isLoading 
                                  ? Colors.grey[300] 
                                  : AppColors.primaryLight.withOpacity(0.3),
                              child: Icon(
                                Icons.person,
                                color: isLoading ? Colors.grey[500] : AppColors.primary,
                                size: 36,
                              ),
                            );
                          },
                        )
                      : Container(
                          width: 72,
                          height: 72,
                          color: isLoading 
                              ? Colors.grey[300] 
                              : AppColors.primaryLight.withOpacity(0.3),
                          child: Icon(
                            Icons.person,
                            color: isLoading ? Colors.grey[500] : AppColors.primary,
                            size: 36,
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
}
