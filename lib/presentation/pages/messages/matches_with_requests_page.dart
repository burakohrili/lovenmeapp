// lib/presentation/pages/messages/matches_with_requests_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../pages/chat_request_inbox_page.dart';
import 'matches_page.dart';
import '../notifications/notifications_page.dart';

/// Matches Page with Chat Requests Tab
/// Eşleşmeler + Chat İstekleri sekmelerini içerir
class MatchesWithRequestsPage extends ConsumerStatefulWidget {
  const MatchesWithRequestsPage({super.key});

  @override
  ConsumerState<MatchesWithRequestsPage> createState() => _MatchesWithRequestsPageState();
}

class _MatchesWithRequestsPageState extends ConsumerState<MatchesWithRequestsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grey50,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Notification Icon
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
                              size: 28,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const NotificationsPage(),
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
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Text(
                                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
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
            
            // TabBar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.normal,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.chat_bubble),
                    text: 'Mesajlar',
                  ),
                  Tab(
                    icon: Icon(Icons.mark_email_unread),
                    text: 'Mesaj İstekleri',
                  ),
                ],
              ),
            ),
            
            // TabBarView
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  // Eşleşmeler sekmesi
                  MatchesPageContent(),
                  
                  // Chat İstekleri sekmesi
                  ChatRequestInboxPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Matches Page Content (Original Content without AppBar)
class MatchesPageContent extends ConsumerWidget {
  const MatchesPageContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // MatchesPage'in içeriğini buraya taşıyoruz (AppBar olmadan)
    // Orijinal MatchesPage'den body kısmını kullanacağız
    return const MatchesPage();
  }
}
