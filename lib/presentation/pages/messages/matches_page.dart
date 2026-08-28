// lib/presentation/pages/messages/matches_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/notification_provider.dart';
import 'providers/firebase_chat_provider.dart';
import 'chat_detail_page.dart';
import '../home/home_page.dart';
import '../notifications/notifications_page.dart';

class MatchesPage extends ConsumerWidget {
  const MatchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(firebaseChatProvider);

    final newMatches = chatState.newMatches;
    final activeChats = chatState.activeChats;
    int index = 3; // Mesajlar sekmesi varsayılan olarak seçili

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
                          Icons.chat_bubble,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Mesajlar',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  // Bildirim ikonu
                  Consumer(
                    builder: (context, ref, child) {
                      final notificationState = ref.watch(notificationProvider);
                      final unreadCount = notificationState.unreadCount;

                      return Stack(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.notifications_outlined,
                              color: AppColors.primary,
                              size: 26,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const NotificationsPage(),
                                ),
                              );
                            },
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: chatState.matches.isEmpty
                  ? _buildEmptyState(context)
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Yeni Eşleşmeler Bölümü
                          if (newMatches.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Mekan Bağlantıların',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${newMatches.length} YENİ',
                                      style: const TextStyle(
                                        color: AppColors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Yeni eşleşmeler horizontal scroll
                            SizedBox(
                              height: 140,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: newMatches.length,
                                itemBuilder: (context, index) {
                                  final match = newMatches[index];
                                  return _buildNewMatchCard(
                                      context, ref, match);
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          const SizedBox(height: 26),
                          // Sohbetler Bölümü
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Sohbetler',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  '${activeChats.length} sohbet',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.grey600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),

                          // Sohbet listesi
                          if (activeChats.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 80,
                                      color: AppColors.grey300,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Henüz mesajlaşma yok',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: AppColors.grey600,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Bağlantılarınla sohbete başla!',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.grey400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 20),
                              itemCount: activeChats.length,
                              itemBuilder: (context, index) {
                                final match = activeChats[index];
                                return _buildChatItem(context, ref, match);
                              },
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),

      // BOTTOM NAVIGATION BAR
      // bottomNavigationBar: Container(
      //   decoration: BoxDecoration(
      //     color: AppColors.white,
      //     boxShadow: [
      //       BoxShadow(
      //         color: AppColors.black.withOpacity(0.1),
      //         blurRadius: 20,
      //         offset: const Offset(0, -5),
      //       ),
      //     ],
      //   ),
      //   child: SafeArea(
      //     child: Container(
      //       height: 65,
      //       padding: const EdgeInsets.symmetric(horizontal: 20),
      //       child: Row(
      //         mainAxisAlignment: MainAxisAlignment.spaceAround,
      //         children: [
      //           // Keşfet
      //           _buildNavItem(
      //             context: context,
      //             index: 0,
      //             icon: Icons.explore_outlined,
      //             activeIcon: Icons.explore,
      //             label: 'Keşfet',
      //             isActive: false,
      //           ),

      //           // Harita
      //           _buildNavItem(
      //             context: context,
      //             index: 1,
      //             icon: Icons.map_outlined,
      //             activeIcon: Icons.map,
      //             label: 'Harita',
      //             isActive: false,
      //           ),

      //           // Anasayfa (Ortada ve büyük)
      //           _buildCenterNavItem(
      //             context: context,
      //             index: 2,
      //             icon: Icons.home_outlined,
      //             activeIcon: Icons.home,
      //             isActive: false,
      //           ),

      //           // Mesajlar (Aktif)
      //           _buildNavItem(
      //             context: context,
      //             index: 3,
      //             icon: Icons.chat_bubble_outline,
      //             activeIcon: Icons.chat_bubble,
      //             label: 'Mesajlar',
      //             isActive: true,
      //           ),

      //           // Profil
      //           _buildNavItem(
      //             context: context,
      //             index: 4,
      //             icon: Icons.person_outline,
      //             activeIcon: Icons.person,
      //             label: 'Profil',
      //             isActive: false,
      //           ),
      //         ],
      //       ),
      //     ),
      //   ),
      // ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.place,
              size: 60,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Henüz kimseyle bağlantı kurmadın.',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Şansını artırmak için yakındaki popüler bir mekana Check-in yapmaya ne dersin?',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.grey600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomePage(initialIndex: 0),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text(
              'Keşfete Git',
              style: TextStyle(color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewMatchCard(BuildContext context, WidgetRef ref, match) {
    return GestureDetector(
      onTap: () {
        ref.read(firebaseChatProvider.notifier).selectMatch(match);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(match: match),
          ),
        );
      },
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Stack(
              children: [
                // Profil fotoğrafı
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary,
                      width: 3,
                    ),
                    image: DecorationImage(
                      image: NetworkImage(match.profileImage),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                // YENİ etiketi
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'YENİ',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              match.name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            // Bağlantının GEREKÇESİ gösterilir: yaş değil, ortak mekan.
            // Uygulamanın vaadi bu — bağlantılar gerçek dünyada aynı yerde
            // bulunmaktan doğar.
            Text(
              match.commonCheckIns > 0
                  ? '${match.commonCheckIns} kez aynı mekanda'
                  : (match.commonVenues.isNotEmpty
                      ? match.commonVenues.first
                      : 'Mekan bağlantısı'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(BuildContext context, WidgetRef ref, match) {
    return InkWell(
      onTap: () {
        ref.read(firebaseChatProvider.notifier).selectMatch(match);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(match: match),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: match.unreadCount > 0
              ? AppColors.primary.withOpacity(0.05)
              : AppColors.transparent,
        ),
        child: Row(
          children: [
            // Profil fotoğrafı
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: match.unreadCount > 0
                      ? AppColors.primary
                      : AppColors.grey300,
                  width: 2,
                ),
                image: DecorationImage(
                  image: NetworkImage(match.profileImage),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Mesaj içeriği
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${match.name}, ${match.age}',
                        style: TextStyle(
                          fontWeight: match.unreadCount > 0
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        match.timeAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: match.unreadCount > 0
                              ? AppColors.primary
                              : AppColors.grey600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          match.lastMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: match.unreadCount > 0
                                ? AppColors.black
                                : AppColors.grey600,
                            fontWeight: match.unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (match.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          child: Text(
                            match.unreadCount.toString(),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Ortak mekanlar
                  if (match.commonVenues.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: AppColors.grey500,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            match.commonVenues.join(', '),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.grey500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Navigation Item Builder
  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomePage(initialIndex: index),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.primary : AppColors.grey400,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.grey400,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Center Navigation Item Builder (Anasayfa)
  Widget _buildCenterNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(initialIndex: index),
          ),
        );
      },
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
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Icon(
          isActive ? activeIcon : icon,
          color: isActive ? AppColors.white : AppColors.grey400,
          size: 28,
        ),
      ),
    );
  }
}
