// lib/presentation/pages/explore_nearby/widgets/venue_card_widget.dart

import 'package:flutter/material.dart';
import '../models/explore_venue_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../profile/user_profile_page.dart';

class VenueCardWidget extends StatefulWidget {
  final ExploreVenue venue;
  final VoidCallback onTap;

  const VenueCardWidget({
    super.key,
    required this.venue,
    required this.onTap,
  });

  @override
  State<VenueCardWidget> createState() => _VenueCardWidgetState();
}

class _VenueCardWidgetState extends State<VenueCardWidget> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        transform: Matrix4.identity()..scale(_isPressed ? 0.97 : 1.0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Ana Kart
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                // Sponsor gradient border - Pembe tema
                gradient: widget.venue.isSponsored
                    ? LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primaryLight,
                          AppColors.secondary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: widget.venue.isSponsored ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.venue.isSponsored
                        ? AppColors.primary
                            .withOpacity(_isPressed ? 0.35 : 0.22)
                        : AppColors.primary
                            .withOpacity(_isPressed ? 0.15 : 0.08),
                    blurRadius: _isPressed ? 10 : 18,
                    offset: Offset(0, _isPressed ? 2 : 6),
                    spreadRadius: _isPressed ? -2 : 0,
                  ),
                  if (!_isPressed)
                    BoxShadow(
                      color: widget.venue.isSponsored
                          ? AppColors.primaryLight.withOpacity(0.1)
                          : Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                ],
              ),
              // İç padding için wrapper (gradient border effect)
              padding: EdgeInsets.all(widget.venue.isSponsored ? 2.5 : 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                      widget.venue.isSponsored ? 17.5 : 20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mekan Başlığı ve İkonu
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.venue.name,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildCategoryIcon(),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (widget.venue.description != null)
                                  Text(
                                    widget.venue.description!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Check-in Kullanıcıları ve Muhtar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          // Kullanıcı Avatarları (Max 3)
                          Expanded(
                            child: Row(
                              children: _buildUserAvatars(context),
                            ),
                          ),

                          // Check-in Sayısı ve Ok İkonu
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withOpacity(0.15),
                                      AppColors.primaryLight.withOpacity(0.10),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          AppColors.primary.withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.people_rounded,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${widget.venue.totalCheckIns}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Sağa ok ikonu - tıklanabilir olduğunu gösterir
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withOpacity(0.12),
                                      AppColors.primaryLight.withOpacity(0.08),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.2),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Sponsor Badge (Sol Üst Köşe - Border Dışında)
            if (widget.venue.isSponsored)
              Positioned(
                top: 0,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.secondary,
                        AppColors.primaryLight,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'SPONSOR',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ), // Stack kapanışı
      ), // AnimatedContainer kapanışı
    ); // GestureDetector kapanışı
  }

  List<Widget> _buildUserAvatars(BuildContext context) {
    // Muhtar ve diğer kullanıcıları ayır
    CheckedInUserPreview? mayor;
    List<CheckedInUserPreview> otherUsers = [];

    for (var user in widget.venue.recentUsers) {
      if (user.isMayor) {
        mayor = user;
      } else {
        otherUsers.add(user);
      }
    }

    List<Widget> avatars = [];

    // 1. Muhtar (varsa) - Daha büyük
    if (mayor != null) {
      avatars.add(_buildMayorAvatar(context, mayor));
      avatars.add(const SizedBox(width: 8));
    }

    // 2. Diğer kullanıcılar (max 2 tane)
    final displayUsers = otherUsers.take(2).toList();
    for (int i = 0; i < displayUsers.length; i++) {
      avatars.add(_buildUserAvatar(displayUsers[i]));
      if (i < displayUsers.length - 1) {
        avatars.add(const SizedBox(width: 8));
      }
    }

    // Eğer hiç kullanıcı yoksa
    if (avatars.isEmpty) {
      avatars.add(
        Text(
          'Henüz check-in yok',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return avatars;
  }

  Widget _buildMayorAvatar(BuildContext context, CheckedInUserPreview mayor) {
    // Elmas muhtar mı yoksa günün muhtarı mı?
    final isDiamond = mayor.isDiamondMayor;
    final borderColor =
        isDiamond ? const Color(0xFFFF69B4) : const Color(0xFFFFD700);
    final iconData = isDiamond ? Icons.diamond : Icons.emoji_events;

    return GestureDetector(
      onTap: () => _showUserProfile(context, mayor.userId),
      child: Stack(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: borderColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
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
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: borderColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
              child: Icon(
                iconData,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(CheckedInUserPreview user) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
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
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryIcon() {
    IconData icon;
    Color color;

    switch (widget.venue.category.toLowerCase()) {
      case 'cafe':
      case 'kafe':
        icon = Icons.coffee;
        color = const Color(0xFF8B4513);
        break;
      case 'restaurant':
      case 'restoran':
        icon = Icons.restaurant;
        color = const Color(0xFFFF6347);
        break;
      case 'bar':
        icon = Icons.local_bar;
        color = const Color(0xFF9C27B0);
        break;
      case 'cinema':
      case 'sinema':
        icon = Icons.movie;
        color = const Color(0xFF2196F3);
        break;
      case 'park':
        icon = Icons.park;
        color = const Color(0xFF4CAF50);
        break;
      case 'gym':
      case 'spor':
        icon = Icons.fitness_center;
        color = const Color(0xFFFF5722);
        break;
      default:
        icon = Icons.place;
        color = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Icon(
        icon,
        size: 22,
        color: color,
      ),
    );
  }

  /// Kullanıcı profilini göster (Bottom Sheet)
  void _showUserProfile(BuildContext context, String userId) {
    // Bu kullanıcı bu mekanda muhtar mı kontrol et
    CheckedInUserPreview? mayorUser;
    for (var user in widget.venue.recentUsers) {
      if (user.userId == userId && user.isMayor) {
        mayorUser = user;
        break;
      }
    }

    final isMayor = mayorUser != null;
    final isDiamondMayor = isMayor && (mayorUser.isDiamondMayor);

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
          mayorVenueName: isMayor ? widget.venue.name : null,
        ),
      ),
    );
  }
}
