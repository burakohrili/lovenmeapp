// lib/widgets/custom_navigation_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/providers/unread_messages_provider.dart';

class CustomNavigationBar extends ConsumerWidget {
  final int currentIndex;
  final Function(int) onIndexChanged;
  
  const CustomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 📱 DEVICE COMPATIBILITY: Get bottom safe area for adaptation
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    
    // Get unread messages count for badge
    final unreadCount = ref.watch(unreadMessagesProvider);
    
    // 🔧 ADAPTIVE HEIGHT: Base height + safe area consideration
    // - Phones with home indicator (iPhone): ~34px bottom safe area
    // - Older Android with nav buttons: ~48px bottom safe area  
    // - Modern Android with gestures: ~16px bottom safe area
    const baseHeight = 65.0;
    final adaptiveHeight = bottomSafeArea > 20 ? baseHeight : baseHeight + 8;
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        // 🔧 SAFE AREA OPTIMIZATION: Only apply to bottom (let system handle home indicator)
        top: false, // Don't consume top safe area
        child: Container(
          height: adaptiveHeight, // 🔧 ADAPTIVE: Use calculated height
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Listem — "Gitmek İstediklerim" ve "Gittiklerim".
              // Eski "Keşfet" etiketi yanlıştı: o sayfa hiçbir şey keşfetmiyor,
              // zaten gidilmiş yerleri listeliyordu. Canlı keşif Harita'da.
              _buildNavItem(
                index: 0,
                icon: Icons.bookmark_border_rounded,
                activeIcon: Icons.bookmark_rounded,
                label: 'Listem',
              ),
              
              // Harita
              _buildNavItem(
                index: 1,
                icon: Icons.map_outlined,
                activeIcon: Icons.map,
                label: 'Harita',
              ),
              
              // Anasayfa/Akış (Ortada ve büyük)
              _buildCenterNavItem(
                index: 2,
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
              ),

              // Mesajlar (with notification badge)
              _buildNavItemWithBadge(
                index: 3,
                icon: Icons.message_outlined,
                activeIcon: Icons.message,
                label: 'Mesajlar',
                badgeCount: unreadCount,
              ),
              
              // Profil
              _buildNavItem(
                index: 4,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onIndexChanged(index),
      // 🎯 TOUCH TARGET OPTIMIZATION: Minimum 48x48 dokunma alanı sağla
      behavior: HitTestBehavior.opaque, // Boş alanlarda da dokunmayı algıla
      child: Container(
        // 📏 ENLARGED TOUCH AREA: Dokunma alanını büyüt
        width: 64, // Minimum touch target genişliği
        // 🔧 FLEXIBLE HEIGHT: Let container adapt to parent height
        constraints: const BoxConstraints(
          minHeight: 60, // Minimum height guarantee
          maxHeight: 80, // Maximum height limit
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // 🔧 OVERFLOW FIX: Use minimum space
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.primary : AppColors.grey400,
              size: 22, // Reduced from 24 to 22 for space optimization
            ),
            const SizedBox(height: 2), // Reduced from 4 to 2
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.grey400,
                fontSize: 10, // Reduced from 11 to 10
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center, // Center alignment
              overflow: TextOverflow.ellipsis, // Handle long text
              maxLines: 1, // Single line only
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isActive = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onIndexChanged(index),
      // 🎯 TOUCH TARGET OPTIMIZATION: Merkez buton için de dokunma optimizasyonu
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 64, // Diğer butonlarla consistent genişlik
        // 🔧 FLEXIBLE HEIGHT: Let container adapt to parent height
        constraints: const BoxConstraints(
          minHeight: 60, // Minimum height guarantee
          maxHeight: 80, // Maximum height limit
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: isActive 
                  ? const LinearGradient(
                      colors: AppColors.primaryGradient,
                    )
                  : null,
              color: !isActive ? AppColors.grey200 : null,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isActive ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ] : [],
            ),
            child: Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.white : AppColors.grey400,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItemWithBadge({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int badgeCount,
  }) {
    final isActive = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onIndexChanged(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 64,
        constraints: const BoxConstraints(
          minHeight: 60,
          maxHeight: 80,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? AppColors.primary : AppColors.grey400,
                  size: 22,
                ),
                // Badge
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      height: 16,
                      constraints: const BoxConstraints(minWidth: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53E3E), // Red color
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.white,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 9 ? '9+' : badgeCount.toString(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.grey400,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}