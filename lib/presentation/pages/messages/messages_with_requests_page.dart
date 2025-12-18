// lib/presentation/pages/messages/messages_with_requests_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/notification_provider.dart';
import 'providers/firebase_chat_provider.dart';
import 'chat_detail_page.dart';
import '../notifications/notifications_page.dart';
import '../profile/user_profile_page.dart';
import '../../../core/services/chat_request_service.dart';
import '../../../core/models/chat_request_model.dart';

/// Mesajlar ve İstekler sayfası - 2 tab ile
class MessagesWithRequestsPage extends ConsumerStatefulWidget {
  const MessagesWithRequestsPage({super.key});

  @override
  ConsumerState<MessagesWithRequestsPage> createState() =>
      _MessagesWithRequestsPageState();
}

class _MessagesWithRequestsPageState
    extends ConsumerState<MessagesWithRequestsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _pendingRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPendingRequestCount();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingRequestCount() async {
    final count = await ChatRequestService.getPendingRequestCount();
    if (mounted) {
      setState(() {
        _pendingRequestCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grey50,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Center(
                                  child: Text(
                                    unreadCount > 99
                                        ? '99+'
                                        : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
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

            // TabBar
            Container(
              color: AppColors.white,
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.grey500,
                labelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                ),
                tabs: [
                  const Tab(
                    icon: Icon(Icons.chat_bubble_outline),
                    text: 'Mesajlar',
                  ),
                  Tab(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.mail_outline),
                        if (_pendingRequestCount > 0)
                          Positioned(
                            right: -8,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Center(
                                child: Text(
                                  _pendingRequestCount > 9
                                      ? '9+'
                                      : _pendingRequestCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    text: 'İstekler',
                  ),
                ],
              ),
            ),

            // TabBarView
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Mesajlar (Mevcut MatchesPage içeriği)
                  _MessagesTabContent(),

                  // Tab 2: İstekler (Chat Requests)
                  _RequestsTabContent(
                    onRequestCountChanged: () {
                      _loadPendingRequestCount();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mesajlar Tab İçeriği - MatchesPage body'si
class _MessagesTabContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(firebaseChatProvider);
    final newMatches = chatState.newMatches;
    final activeChats = chatState.activeChats;

    if (chatState.matches.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 100,
              color: AppColors.grey300,
            ),
            SizedBox(height: 24),
            Text(
              'Henüz kimseyle eşleşmedin.',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.grey600,
              ),
            ),
            SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Şansını artırmak için yakındaki popüler bir mekana Check-in yapmaya ne dersin?',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.grey400,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Yeni Eşleşmeler
          if (newMatches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Yeni Eşleşmeler',
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
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: newMatches.length,
                itemBuilder: (context, index) {
                  final match = newMatches[index];
                  return _buildNewMatchCard(context, ref, match);
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Sohbetler
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
          const SizedBox(height: 16),

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
                      'Eşleşmelerinle sohbete başla!',
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
    );
  }

  Widget _buildNewMatchCard(
      BuildContext context, WidgetRef ref, dynamic match) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(
              match: match,
            ),
          ),
        );
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: match.photos.isNotEmpty
                      ? NetworkImage(match.photos.first)
                      : null,
                  child: match.photos.isEmpty
                      ? const Icon(Icons.person, size: 40)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              match.name ?? 'Unknown',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(BuildContext context, WidgetRef ref, dynamic match) {
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundImage:
            match.photos.isNotEmpty ? NetworkImage(match.photos.first) : null,
        child: match.photos.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(
        match.name ?? 'Unknown',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        match.lastMessage ?? 'Mesajlaşmaya başla',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: match.lastMessageTime != null
          ? Text(
              _formatTime(match.lastMessageTime),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey400,
              ),
            )
          : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(
              match: match,
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 0) {
      return '${diff.inDays}g';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}s';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}d';
    }
    return 'şimdi';
  }
}

/// İstekler Tab İçeriği - Chat Requests
class _RequestsTabContent extends ConsumerStatefulWidget {
  final VoidCallback? onRequestCountChanged;

  const _RequestsTabContent({
    this.onRequestCountChanged,
  });

  @override
  ConsumerState<_RequestsTabContent> createState() =>
      _RequestsTabContentState();
}

class _RequestsTabContentState extends ConsumerState<_RequestsTabContent> {
  List<Map<String, dynamic>> _requestsWithUserInfo = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      final requests = await ChatRequestService.getPendingRequests();
      final requestsWithInfo = <Map<String, dynamic>>[];

      // Her request için gönderen kullanıcının bilgilerini çek
      for (final request in requests) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(request.fromUserId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data()!;
            final photos = userData['photos'] as List?;
            final photoUrl = photos?.isNotEmpty == true ? photos![0] : null;

            requestsWithInfo.add({
              'request': request,
              'userName': userData['name'] ?? 'Unknown',
              'userPhoto': photoUrl,
            });
          }
        } catch (e) {}
      }

      if (mounted) {
        setState(() {
          _requestsWithUserInfo = requestsWithInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_requestsWithUserInfo.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mail_outline,
              size: 100,
              color: AppColors.grey300,
            ),
            SizedBox(height: 24),
            Text(
              'Henüz chat isteğin yok',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.grey600,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Yeni istekler burada görünecek',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.grey400,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _requestsWithUserInfo.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _requestsWithUserInfo[index];
        return _buildRequestCard(
          item['request'] as ChatRequest,
          item['userName'] as String,
          item['userPhoto'] as String?,
        );
      },
    );
  }

  Widget _buildRequestCard(
      ChatRequest request, String userName, String? userPhoto) {
    final isSuperChat = request.type == ChatRequestType.superChat;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSuperChat
            ? const BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _openUserProfile(request.fromUserId),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundImage:
                        userPhoto != null ? NetworkImage(userPhoto) : null,
                    child: userPhoto == null
                        ? const Icon(Icons.person, size: 30)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _openUserProfile(request.fromUserId),
                        child: Row(
                          children: [
                            if (isSuperChat)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child:
                                    Text('⭐', style: TextStyle(fontSize: 16)),
                              ),
                            Text(
                              userName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (request.message != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSuperChat
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.grey100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '"${request.message}"',
                            style: TextStyle(
                              fontSize: 14,
                              color: isSuperChat
                                  ? AppColors.primary
                                  : AppColors.grey700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptRequest(request.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Kabul Et'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rejectRequest(request.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Reddet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptRequest(String requestId) async {
    final success = await ChatRequestService.acceptChatRequest(requestId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İstek kabul edildi! 🎉')),
      );
      _loadRequests();
      widget.onRequestCountChanged?.call(); // Parent'a bildir
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final success = await ChatRequestService.rejectChatRequest(requestId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İstek reddedildi')),
      );
      _loadRequests();
      widget.onRequestCountChanged?.call(); // Parent'a bildir
    }
  }

  void _openUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfilePage(userId: userId),
      ),
    );
  }
}
