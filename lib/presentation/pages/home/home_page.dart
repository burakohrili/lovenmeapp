// lib/presentation/pages/home/home_page.dart

import 'package:flutter/material.dart';
// SystemNavigator için eklendi
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:async';
import '../../../core/services/notification_service.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/permission_service.dart';
import '../../../widgets/custom_navigation_bar.dart';
import '../map/map_page.dart';
import '../explore_nearby/explore_nearby_page.dart';
import '../profile/profile_page.dart';
import '../messages/messages_with_requests_page.dart';
import '../messages/chat_detail_page.dart';
import '../messages/models/match_model.dart';
import '../feed/models/feed_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../profile/user_profile_page.dart';
import '../notifications/notifications_page.dart';
import '../map/components/venue_details_sheet.dart';
import '../map/services/checkin_service.dart';
import '../../models/venue.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// final welcomeShownProvider = StateProvider<bool>((ref) => false);

class HomePage extends ConsumerStatefulWidget {
  final int? initialIndex;
  const HomePage({super.key, this.initialIndex});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  late int _currentIndex;
  final ScrollController _scrollController = ScrollController();

  // 🎯 HOMEPAGE REFRESH FIX: Match cache sistemi
  List<String>? _cachedMatchedUserIds;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 2;

    _initializeDailyLimits();

    // iOS için ana sayfaya girdiğinde izinleri iste
    _requestPermissionsOnHomeEntry();

    // FCM Token kontrolü ve kaydetme
    _ensureFCMTokenSaved();

    // 🔔 NotificationProvider otomatik olarak başlatılıyor (constructor'da)

    WidgetsBinding.instance.addPostFrameCallback((_) {
      //   final wasShown = ref.read(welcomeShownProvider);
      //   if (!wasShown && _currentIndex == 2) {
      //     _showWelcomeDialog();
      //     ref.read(welcomeShownProvider.notifier).state = true;
      //   }
    });
  }

  /// Ana sayfaya girdiğinde iOS izinlerini iste
  Future<void> _requestPermissionsOnHomeEntry() async {
    // Sadece iOS için ve ilk giriş için
    if (Platform.isIOS) {
      // Biraz bekle, sayfa tamamen yüklensin
      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        try {
          await PermissionService.requestEssentialPermissions(context);
        } catch (e) {}
      }
    }
  }

  /// FCM Token'ın kaydedildiğinden emin ol
  Future<void> _ensureFCMTokenSaved() async {
    try {
      // Biraz bekle ki user login tamamlansın
      await Future.delayed(const Duration(seconds: 2));

      // NotificationService'i yeniden başlat
      await NotificationService().initialize();
    } catch (e) {
      // Hata olursa 5 saniye sonra tekrar dene
      Timer(const Duration(seconds: 5), () async {
        try {
          await NotificationService().initialize();
        } catch (e2) {}
      });
    }
  }

  Future<void> _initializeDailyLimits() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final isPremium = data['isPremium'] ?? false;

        // Eğer limit bilgisi yoksa (yeni kullanıcı) başlat
        if (data['lastLimitReset'] == null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'dailyLikesRemaining': isPremium ? 999 : 5,
            // 🔥 YENİ SİSTEM: Super like artık günlük verilmiyor, sadece satın alma anında
            'dailyRewindsRemaining': isPremium ? 3 : 0,
            'lastLimitReset': FieldValue.serverTimestamp(),
            'dailyResetCount': 1, // İlk reset
          });
        } else {
          // Limit var, gece yarısı kontrolü yap
          final lastReset = (data['lastLimitReset'] as Timestamp).toDate();
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final lastResetDay =
              DateTime(lastReset.year, lastReset.month, lastReset.day);

          // Eğer son sıfırlama bugün değilse, sıfırla (fallback - Cloud Functions'ın yapmadığı durumlarda)
          if (lastResetDay.isBefore(today)) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({
              'dailyLikesRemaining': isPremium ? 999 : 5,
              // 🔥 YENİ SİSTEM: Super like artık günlük resetlenmiyor, sadece satın alma anında
              'dailyRewindsRemaining': isPremium ? 3 : 0,
              'lastLimitReset': FieldValue.serverTimestamp(),
              'dailyResetCount': (data['dailyResetCount'] ?? 0) + 1,
            });

            // Log this as a fallback reset
            await FirebaseFirestore.instance
                .collection('client_reset_logs')
                .add({
              'userId': user.uid,
              'resetTime': FieldValue.serverTimestamp(),
              'lastServerReset': lastReset,
              'type': 'client_fallback',
              'isPremium': isPremium,
            });
          } else {}
        }
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // void _showWelcomeDialog() {
  //   final profile = ref.read(userProfileProvider);

  //   showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (context) => Dialog(
  //       shape: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(20),
  //       ),
  //       child: Container(
  //         padding: const EdgeInsets.all(24),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             Container(
  //               width: 80,
  //               height: 80,
  //               decoration: BoxDecoration(
  //                 gradient: LinearGradient(
  //                   colors: [
  //                     AppColors.primary.withOpacity(0.8),
  //                     AppColors.secondary.withOpacity(0.8),
  //                   ],
  //                 ),
  //                 shape: BoxShape.circle,
  //               ),
  //               child: const Icon(
  //                 Icons.celebration,
  //                 size: 40,
  //                 color: AppColors.white,
  //               ),
  //             ),
  //             const SizedBox(height: 20),
  //             const Text(
  //               'Profil Kurulumu Tamamlandı!',
  //               style: TextStyle(
  //                 fontSize: 20,
  //                 fontWeight: FontWeight.bold,
  //                 color: AppColors.primary,
  //               ),
  //               textAlign: TextAlign.center,
  //             ),
  //             const SizedBox(height: 12),
  //             Text(
  //               'Hoş geldin ${profile.name}!',
  //               style: const TextStyle(
  //                 fontSize: 16,
  //                 fontWeight: FontWeight.w600,
  //               ),
  //             ),
  //             const SizedBox(height: 8),
  //             Text(
  //               'Artık uygulamayı kullanmaya başlayabilirsin',
  //               style: TextStyle(
  //                 fontSize: 14,
  //                 color: AppColors.grey600,
  //               ),
  //               textAlign: TextAlign.center,
  //             ),
  //             const SizedBox(height: 24),
  //             Container(
  //               padding: const EdgeInsets.all(16),
  //               decoration: BoxDecoration(
  //                 color: AppColors.grey50,
  //                 borderRadius: BorderRadius.circular(12),
  //                 border: Border.all(color: AppColors.grey200),
  //               ),
  //               child: Row(
  //                 mainAxisAlignment: MainAxisAlignment.spaceAround,
  //                 children: [
  //                   _buildMiniStat(
  //                     Icons.photo_camera,
  //                     profile.photos.length.toString(),
  //                     'Fotoğraf',
  //                   ),
  //                   Container(
  //                     width: 1,
  //                     height: 40,
  //                     color: AppColors.grey300,
  //                   ),
  //                   _buildMiniStat(
  //                     Icons.favorite,
  //                     profile.hobbies.length.toString(),
  //                     'Hobi',
  //                   ),
  //                   Container(
  //                     width: 1,
  //                     height: 40,
  //                     color: AppColors.grey300,
  //                   ),
  //                   _buildMiniStat(
  //                     Icons.place,
  //                     profile.favoriteVenues.length.toString(),
  //                     'Mekan',
  //                   ),
  //                 ],
  //               ),
  //             ),
  //             const SizedBox(height: 24),
  //             Row(
  //               children: [
  //                 Expanded(
  //                   child: OutlinedButton(
  //                     onPressed: () {
  //                       Navigator.pop(context);
  //                       setState(() {
  //                         _currentIndex = 0;
  //                       });
  //                     },
  //                     style: OutlinedButton.styleFrom(
  //                       foregroundColor: AppColors.primary,
  //                       side: const BorderSide(color: AppColors.primary),
  //                       padding: const EdgeInsets.symmetric(vertical: 12),
  //                       shape: RoundedRectangleBorder(
  //                         borderRadius: BorderRadius.circular(12),
  //                       ),
  //                     ),
  //                     child: const Row(
  //                       mainAxisAlignment: MainAxisAlignment.center,
  //                       children: [
  //                         Icon(Icons.explore, size: 18),
  //                         SizedBox(width: 6),
  //                         Text('Keşfet'),
  //                       ],
  //                     ),
  //                   ),
  //                 ),
  //                 const SizedBox(width: 12),
  //                 Expanded(
  //                   child: ElevatedButton(
  //                     onPressed: () {
  //                       Navigator.pop(context);
  //                     },
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: AppColors.primary,
  //                       padding: const EdgeInsets.symmetric(vertical: 12),
  //                       shape: RoundedRectangleBorder(
  //                         borderRadius: BorderRadius.circular(12),
  //                       ),
  //                     ),
  //                     child: const Row(
  //                       mainAxisAlignment: MainAxisAlignment.center,
  //                       children: [
  //                         Icon(Icons.check, color: AppColors.white, size: 18),
  //                         SizedBox(width: 6),
  //                         Text(
  //                           'Başla',
  //                           style: TextStyle(color: AppColors.white),
  //                         ),
  //                       ],
  //                     ),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    // WillPopScope ile geri tuşu kontrolü eklendi
    return WillPopScope(
      onWillPop: () async {
        // Geri tuşuna basıldığında çıkış dialogu göster
        return await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Çıkmak istiyor musunuz?'),
                content: const Text('Uygulamadan çıkmak üzeresiniz.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Hayır'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Evet'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      child: Scaffold(
        backgroundColor: AppColors.grey50,
        body: _buildCurrentPage(),
        bottomNavigationBar: CustomNavigationBar(
          currentIndex: _currentIndex,
          onIndexChanged: (index) {
            setState(() {
              _currentIndex = index;
            });

            if (index == 2 && _scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return const ExploreNearbyPage();
      case 1:
        return const MapPage();
      case 2:
        return _buildFeedPage();
      case 3:
        return const MatchesPageContent();
      case 4:
        return const ProfilePageContent();
      default:
        return _buildFeedPage();
    }
  }

  Widget _buildFeedPage() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text('Giriş yapmanız gerekiyor'),
      );
    }

    return SafeArea(
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
                        Icons.location_on,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Akış',
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
                    // Bildirim BUTONU - FIXED: StreamBuilder yerine Provider kullanımı
                    Consumer(
                      builder: (context, ref, child) {
                        // 🎯 REFRESH FIX: Local state from provider
                        final notificationState =
                            ref.watch(notificationProvider);
                        int unreadCount = notificationState.unreadCount;

                        return Stack(
                          children: [
                            IconButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const NotificationsPage(),
                                  ),
                                );
                              },
                              icon: Icon(
                                unreadCount > 0
                                    ? Icons.notifications_active
                                    : Icons.notifications_outlined,
                                color: AppColors.primary,
                                size: 26,
                              ),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  child: Center(
                                    child: Text(
                                      unreadCount > 9
                                          ? '9+'
                                          : unreadCount.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _currentIndex = 1;
                        });
                      },
                      icon: const Icon(Icons.add_box_outlined,
                          color: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            // 🎯 SMART SYNC: Hibrit sistem - Cache'li users + Real-time post updates
            child: FutureBuilder<List<String>>(
              future: _getCachedMatchedUsers(user.uid),
              builder: (context, matchSnapshot) {
                if (matchSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  );
                }

                List<String> matchedUserIds = matchSnapshot.data ?? [];

                if (!matchedUserIds.contains(user.uid)) {
                  matchedUserIds = [...matchedUserIds, user.uid];
                }

                if (matchedUserIds.isEmpty) {
                  return _buildEmptyFeed();
                }

                // 🎯 SMART PAGINATION: İlk yükleme cache'li, sonraki güncellemeler selective
                return FutureBuilder<List<FeedPost>>(
                  future: _getInitialFeedPosts(matchedUserIds),
                  builder: (context, initialSnapshot) {
                    if (initialSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF6B46C1),
                        ),
                      );
                    }

                    if (initialSnapshot.hasError) {
                      return Center(
                        child: Text('Hata: ${initialSnapshot.error}'),
                      );
                    }

                    if (!initialSnapshot.hasData ||
                        initialSnapshot.data!.isEmpty) {
                      return _buildNoPostsYet();
                    }

                    // 🎯 SMART PAGINATION: Cached posts + Selective real-time updates
                    return _SmartFeedList(
                      initialPosts: initialSnapshot.data!,
                      matchedUserIds: matchedUserIds,
                      onProfileTap: _navigateToUserProfile,
                      onChatTap: _goToChat,
                      onOptionsTap: _showPostOptions,
                      onRefresh: _refreshFeedData,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToUserProfile(String userId) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == userId) {
      setState(() {
        _currentIndex = 4;
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfilePage(userId: userId),
        ),
      );
    }
  }

  void _goToChat(FeedPost post) async {
    try {
      // Önce bu kullanıcı ile mevcut bir match var mı kontrol et
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Giriş yapmanız gerekiyor')),
        );
        return;
      }

      if (currentUserId == post.userId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kendinize mesaj gönderemezsiniz')),
        );
        return;
      }

      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Mevcut match'i bul veya oluştur
      final firestore = FirebaseFirestore.instance;

      // Önce mevcut match var mı kontrol et
      final existingMatches = await firestore
          .collection('matches')
          .where('user1Id', whereIn: [currentUserId, post.userId]).where(
              'user2Id',
              whereIn: [currentUserId, post.userId]).get();

      String matchId;

      if (existingMatches.docs.isNotEmpty) {
        // Mevcut match bulundu
        matchId = existingMatches.docs.first.id;
      } else {
        // Yeni match oluştur
        final newMatchRef = await firestore.collection('matches').add({
          'user1Id': currentUserId,
          'user2Id': post.userId,
          'matchedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageTime': null,
          'isActive': true,
        });
        matchId = newMatchRef.id;
      }

      // Loading'i kapat
      Navigator.pop(context);

      // Chat sayfasına git
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailPage(
            match: MatchModel(
              id: matchId, // Gerçek match ID'si
              userId: post.userId,
              name: post.userName,
              age: post.userAge,
              profileImage: post.userProfileImage,
              matchedAt: DateTime.now(),
              lastMessage: '',
              commonVenues: [post.venueName],
              commonHobbies: [],
            ),
          ),
        ),
      );
    } catch (e) {
      // Loading'i kapat (eğer açıksa)
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj sayfası açılırken hata oluştu')),
      );
    }
  }

  void _showPostOptions(FeedPost post) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.report_outlined, color: AppColors.error),
              title: const Text('Şikayet Et',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(context);
                _showPostReportDialog(post);
              },
            ),
            if (FirebaseAuth.instance.currentUser?.uid == post.userId)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: AppColors.error),
                title:
                    const Text('Sil', style: TextStyle(color: AppColors.error)),
                onTap: () async {
                  Navigator.pop(context);
                  await FirebaseFirestore.instance
                      .collection('feed_posts')
                      .doc(post.id)
                      .delete();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showPostReportDialog(FeedPost post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi Şikayet Et'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bu gönderiyi neden şikayet ediyorsunuz?'),
            const SizedBox(height: 16),
            ...[
              'Sahte Profil',
              'Taciz/Rahatsız Etme',
              'Uygunsuz İçerik',
              'Spam/Bot'
            ].map(
              (reason) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    reason,
                    style: const TextStyle(fontSize: 14),
                  ),
                  leading: Icon(
                    _getPostReportReasonIcon(reason),
                    color: AppColors.error,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.grey300),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _reportPost(post, reason);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  IconData _getPostReportReasonIcon(String reason) {
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

  Future<void> _reportPost(FeedPost post, String reason) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedUserId': post.userId,
        'reportedPostId': post.id,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'post_report',
        'status': 'pending',
        'context': 'feed_post',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Gönderi $reason nedeniyle şikayet edildi. İnceleyeceğiz.'),
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

  // Cache için değişkenler ekle

  /// 🎯 REFRESH FIX: Cache'li matched users metodu
  Future<List<String>> _getCachedMatchedUsers(String userId) async {
    try {
      // Cache kontrolü
      if (_cachedMatchedUserIds != null) {
        return _cachedMatchedUserIds!;
      }

      final List<String> matchedUserIds = [];

      // Matches where user is user1
      final matches1 = await FirebaseFirestore.instance
          .collection('matches')
          .where('user1Id', isEqualTo: userId)
          .get();

      for (var doc in matches1.docs) {
        matchedUserIds.add(doc.data()['user2Id']);
      }

      // Matches where user is user2
      final matches2 = await FirebaseFirestore.instance
          .collection('matches')
          .where('user2Id', isEqualTo: userId)
          .get();

      for (var doc in matches2.docs) {
        matchedUserIds.add(doc.data()['user1Id']);
      }

      // Cache'e kaydet
      _cachedMatchedUserIds = matchedUserIds;

      return matchedUserIds;
    } catch (e) {
      return [];
    }
  }

  /// 🎯 SMART PAGINATION: İlk yükleme için cache'li post metodu
  Future<List<FeedPost>> _getInitialFeedPosts(List<String> userIds) async {
    try {
      final feedSnapshot = await FirebaseFirestore.instance
          .collection('feed_posts')
          .where('userId', whereIn: userIds.take(10).toList())
          .orderBy('checkInTime', descending: true)
          .limit(20) // İlk yüklemede daha az post
          .get();

      final List<FeedPost> feedPosts = [];

      for (var doc in feedSnapshot.docs) {
        final data = doc.data();
        final likedByList = data['likedBy'] as List? ?? [];

        final post = FeedPost(
          id: doc.id,
          userId: data['userId'] ?? '',
          userName: data['userName'] ?? 'İsimsiz',
          userAge: data['userAge'] ?? 18,
          userProfileImage: data['userProfileImage'] ?? '',
          venueName: data['venueName'] ?? '',
          venueAddress: data['venueAddress'] ?? '',
          venueCategory: data['venueCategory'] ?? '',
          venueId: data['venueId'] ?? data['venueReferenceId'] ?? '',
          checkInTime: data['checkInTime'] != null
              ? (data['checkInTime'] as Timestamp).toDate()
              : DateTime.now(),
          postImage: data['postImage'],
          likeCount: likedByList.length,
          commentCount: data['commentCount'] ?? 0,
          isLiked: likedByList.contains(FirebaseAuth.instance.currentUser?.uid),
          latitude: data['latitude']?.toDouble(),
          longitude: data['longitude']?.toDouble(),
        );

        feedPosts.add(post);
      }

      return feedPosts;
    } catch (e) {
      return [];
    }
  }

  /// 🔄 SMART SYNC: Manuel refresh metodu - Cache'i temizle
  Future<void> _refreshFeedData() async {
    // Cache'i temizle
    _cachedMatchedUserIds = null;

    // Sayfayı yeniden yükle
    setState(() {});
  }

  Widget _buildEmptyFeed() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Henüz kimseyle eşleşmedin.',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Şansını artırmak için yakındaki popüler bir mekana Check-in yapmaya ne dersin?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _currentIndex = 0;
              });
            },
            icon: const Icon(Icons.explore, color: Colors.white),
            label: const Text('Keşfet\'e Git',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B46C1),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPostsYet() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Henüz Gönderi Yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Eşleştiklerin check-in yaptığında burada görünecek',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

// FEED POST WIDGET - Her post kendi state'ini yÃ¶netir
class FeedPostWidget extends StatefulWidget {
  final FeedPost post;
  final Function(String userId) onProfileTap;
  final Function(FeedPost post) onChatTap;
  final Function(FeedPost post) onOptionsTap;

  const FeedPostWidget({
    super.key,
    required this.post,
    required this.onProfileTap,
    required this.onChatTap,
    required this.onOptionsTap,
  });

  @override
  State<FeedPostWidget> createState() => _FeedPostWidgetState();
}

class _FeedPostWidgetState extends State<FeedPostWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isAnimating = false;
  late bool _isLiked;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likeCount = widget.post.likeCount;

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.5,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void didUpdateWidget(FeedPostWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🎯 SMART SYNC: Real-time güncellemeler için state'i sync et
    if (oldWidget.post.likeCount != widget.post.likeCount ||
        oldWidget.post.isLiked != widget.post.isLiked) {
      setState(() {
        _isLiked = widget.post.isLiked;
        _likeCount = widget.post.likeCount;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 🎯 SMART SYNC: Optimistic update - UI'ı hemen güncelle
    final wasLiked = _isLiked;
    final oldCount = _likeCount;

    setState(() {
      _isLiked = !_isLiked;
      _likeCount = _isLiked ? _likeCount + 1 : _likeCount - 1;
    });

    // ❤️ Beğeni animasyonu
    if (_isLiked) {
      _animationController.forward().then((_) {
        _animationController.reverse();
      });
    }

    try {
      final postRef = FirebaseFirestore.instance
          .collection('feed_posts')
          .doc(widget.post.id);

      // 🎯 SMART SYNC: Sadece likedBy array'ini güncelle, count Firestore'da hesaplanacak
      if (_isLiked) {
        await postRef.update({
          'likedBy': FieldValue.arrayUnion([user.uid]),
          // likeCount array uzunluğundan hesaplanacak, manuel güncelleme yok
        });

        // 🔔 Gönderi beğeni bildirimi gönder (sadece beğenirken)
        if (widget.post.userId != user.uid) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            final userData = userDoc.data();
            final userName = userData != null
                ? '${userData['name']} ${userData['surname']?[0] ?? ''}'
                : 'Kullanıcı';

            await NotificationService.sendPostLikeNotification(
              toUserId: widget.post.userId,
              fromUserName: userName,
              postId: widget.post.id,
              postContent: widget.post.caption,
            );
          } catch (e) {}
        }
      } else {
        await postRef.update({
          'likedBy': FieldValue.arrayRemove([user.uid]),
          // likeCount array uzunluğundan hesaplanacak, manuel güncelleme yok
        });
      }
    } catch (e) {
      // 🔄 Hata durumunda geri al
      setState(() {
        _isLiked = wasLiked;
        _likeCount = oldCount;
      });
    }
  }

  void _showAnimation() {
    setState(() {
      _isAnimating = true;
    });

    _animationController.forward().then((_) {
      _animationController.reset();
      if (mounted) {
        setState(() {
          _isAnimating = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final post = widget.post;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => widget.onProfileTap(post.userId),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: post.userProfileImage.isNotEmpty
                        ? NetworkImage(post.userProfileImage)
                        : null,
                    backgroundColor: AppColors.primaryLight.withOpacity(0.1),
                    child: post.userProfileImage.isEmpty
                        ? const Icon(Icons.person, color: AppColors.primary)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => widget.onProfileTap(post.userId),
                        child: Text(
                          '${post.userName}, ${post.userAge}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            post.categoryIcon,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _showVenueDetails(post),
                              child: Text(
                                post.venueName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            post.timeAgo,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: () => widget.onOptionsTap(post),
                ),
              ],
            ),
          ),
          if (post.postImage != null && post.postImage!.isNotEmpty)
            GestureDetector(
              onDoubleTap: () async {
                if (!_isLiked) {
                  _showAnimation();
                  await _handleLike();
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      post.postImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image, size: 50),
                        );
                      },
                    ),
                  ),
                  if (_isAnimating)
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _animation.value,
                            child: Opacity(
                              opacity: 1.0 - (_animation.value * 0.5),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.3),
                                      blurRadius: 30,
                                      spreadRadius: 20,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.favorite,
                                  color: Colors.red,
                                  size: 100,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            )
          else
            GestureDetector(
              onDoubleTap: () async {
                if (!_isLiked) {
                  _showAnimation();
                  await _handleLike();
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        // Google Maps arka plan resmi
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/feed_post_background.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.map,
                                    size: 50, color: Colors.grey),
                              );
                            },
                          ),
                        ),
                        // Gradient overlay
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withOpacity(0.7),
                                  AppColors.secondary.withOpacity(0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // İçerik
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                post.categoryIcon,
                                size: 48,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                post.venueName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isAnimating)
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _animation.value,
                            child: Opacity(
                              opacity: 1.0 - (_animation.value * 0.5),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.3),
                                      blurRadius: 30,
                                      spreadRadius: 20,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.favorite,
                                  color: Colors.red,
                                  size: 100,
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _handleLike,
                  child: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    color: _isLiked ? Colors.red : Colors.black87,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                if (post.userId != currentUserId)
                  GestureDetector(
                    onTap: () => widget.onChatTap(post),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
          if (_likeCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '$_likeCount beğeni',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          if (post.userId != currentUserId)
            GestureDetector(
              onTap: () => widget.onChatTap(post),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Text(
                  'Mesaj gönder',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B46C1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showVenueDetails(FeedPost post) async {
    try {
      // Loading dialog göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Venue ID'sini post'dan al (venueId = Place ID)
      String venueId = post.venueId;

      if (venueId.isEmpty) {
        // Eğer venueId boşsa, venue name'e göre Firebase'den venue ara

        try {
          // Firebase venues koleksiyonundan venue name'e göre ara
          final venueQuery = await FirebaseFirestore.instance
              .collection('venues')
              .where('name', isEqualTo: post.venueName)
              .limit(1)
              .get();

          if (venueQuery.docs.isNotEmpty) {
            venueId = venueQuery.docs.first.id;
          } else {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Venue bulunamadı: ${post.venueName}')),
            );
            return;
          }
        } catch (e) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Venue arama hatası: ${post.venueName}')),
          );
          return;
        }
      }

      // Firebase'den venue verilerini yükle
      final checkInService = CheckInService();

      // 1. Check-in yapan kullanıcıları yükle
      final checkedInUsers = await checkInService.getCheckedInUsers(
        venueId,
        isPremium: true, // Home'da herkesi görebilir
        userCheckedInVenues: const {},
        globalVenueCache: {},
      );

      // 2. Daily mayor bilgisini yükle
      Map<String, dynamic>? dailyMayor;
      try {
        final mayorDoc = await FirebaseFirestore.instance
            .collection('daily_mayors')
            .doc('${venueId}_${DateTime.now().toIso8601String().split('T')[0]}')
            .get();

        if (mayorDoc.exists) {
          dailyMayor = mayorDoc.data();
        }
      } catch (e) {}

      // 3. Venue objesini oluştur (gerçek verilerle)
      final venue = Venue(
        id: venueId,
        placeId: venueId, // Gerçek place ID
        name: post.venueName,
        category: post.venueCategory,
        location: LatLng(post.latitude ?? 0.0, post.longitude ?? 0.0),
        rating: 0.0,
        vicinity: post.venueAddress,
        checkedInUsers: checkedInUsers,
      );

      // 4. Kullanıcının premium durumunu ve diamond balance'ını al
      final currentUser = FirebaseAuth.instance.currentUser;
      bool isPremium = false;
      int userDiamondBalance = 0;

      if (currentUser != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data()!;
            isPremium = userData['isPremium'] ?? false;
            userDiamondBalance = userData['diamondBalance'] ?? 0;
          }
        } catch (e) {}
      }

      // Loading dialog'u kapat
      Navigator.of(context).pop();

      // 5. Venue details sheet'i göster (tam özellikli)
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => VenueDetailsSheet(
          venue: venue,
          hasCheckedIn: false,
          isCheckedIn: false,
          canSeeUsers: true,
          isPremium: isPremium,
          isUpdatingFavorite: false,
          actualUserCount: checkedInUsers.length,
          dailyMayor: dailyMayor,
          userCheckedInVenues: const {},
          onToggleFavorite: (venue) {}, // Home'da favori işlemi yok
          onCheckIn: (venue) {}, // Home'da check-in işlemi yok
          onShowMayorDialog: (venue) {}, // Home'da mayor işlemi yok
          getCategoryIcon: (category) {
            switch (category.toLowerCase()) {
              case 'cafe':
              case 'kafe':
                return Icons.coffee;
              case 'restaurant':
              case 'restoran':
                return Icons.restaurant;
              case 'bar':
                return Icons.local_bar;
              case 'gym':
              case 'spor':
                return Icons.fitness_center;
              case 'park':
                return Icons.park;
              default:
                return Icons.location_on;
            }
          },
          buildCheckedInUsersList: (venue, canSee) {
            if (!canSee || venue.checkedInUsers.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              children: venue.checkedInUsers.map((user) {
                // Time ago hesapla
                final now = DateTime.now();
                final difference = now.difference(user.checkInTime);
                String timeAgo;

                if (difference.inDays > 0) {
                  timeAgo = '${difference.inDays} gün önce';
                } else if (difference.inHours > 0) {
                  timeAgo = '${difference.inHours} saat önce';
                } else if (difference.inMinutes > 0) {
                  timeAgo = '${difference.inMinutes} dakika önce';
                } else {
                  timeAgo = 'Şimdi';
                }

                // Mayor olup olmadığını kontrol et
                final isMayor =
                    dailyMayor != null && dailyMayor['userId'] == user.userId;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        user.userPhoto != null && user.userPhoto!.isNotEmpty
                            ? NetworkImage(user.userPhoto!)
                            : null,
                    onBackgroundImageError: (_, __) {},
                    child: user.userPhoto == null || user.userPhoto!.isEmpty
                        ? Text(user.userName.isNotEmpty
                            ? user.userName[0].toUpperCase()
                            : '?')
                        : null,
                  ),
                  title: Text(
                    user.userName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(timeAgo),
                  trailing: isMayor
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, size: 16, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'MUHTAR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                  // Sadece mayor tıklanabilir
                  onTap: isMayor
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfilePage(
                                userId: user.userId,
                                showActions: true,
                              ),
                            ),
                          );
                        }
                      : null, // Mayor değilse tıklanamaz
                );
              }).toList(),
            );
          },
          userDiamondBalance: userDiamondBalance,
          hideCheckInButton: true, // Home'da check-in butonu gizli
          hideFavoriteButton: true, // Home'da favori butonu gizli
          hideMayorSection: true, // Home'da muhtar bölümü gizli
        ),
      );
    } catch (e) {
      // Loading dialog'u kapat (hata durumunda)
      Navigator.of(context).pop();

      // Hata mesajı göster
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mekan detayları yüklenirken hata oluştu'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// WRAPPER SINIFLAR
class MatchesPageContent extends StatelessWidget {
  const MatchesPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const MessagesWithRequestsPage();
  }
}

class ProfilePageContent extends StatelessWidget {
  const ProfilePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProfilePage();
  }
}

class FakeQuerySnapshot implements QuerySnapshot {
  @override
  final List<QueryDocumentSnapshot> docs;

  FakeQuerySnapshot({this.docs = const []});

  @override
  int get size => docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 🎯 SMART FEED LIST: Selective updates ile akıllı liste
class _SmartFeedList extends StatefulWidget {
  final List<FeedPost> initialPosts;
  final List<String> matchedUserIds;
  final Function(String) onProfileTap;
  final Function(FeedPost) onChatTap;
  final Function(FeedPost) onOptionsTap;
  final Future<void> Function() onRefresh;

  const _SmartFeedList({
    required this.initialPosts,
    required this.matchedUserIds,
    required this.onProfileTap,
    required this.onChatTap,
    required this.onOptionsTap,
    required this.onRefresh,
  });

  @override
  State<_SmartFeedList> createState() => _SmartFeedListState();
}

class _SmartFeedListState extends State<_SmartFeedList> {
  List<FeedPost> _currentPosts = [];
  StreamSubscription<QuerySnapshot>? _likesSubscription;

  @override
  void initState() {
    super.initState();
    _currentPosts = List.from(widget.initialPosts);
    _startSelectiveLikeListening();
  }

  @override
  void dispose() {
    _likesSubscription?.cancel();
    super.dispose();
  }

  /// 🎯 SMART SYNC: Sadece like/comment güncellemeleri için selective listening
  void _startSelectiveLikeListening() {
    final postIds = _currentPosts.map((p) => p.id).toList();

    // Sadece mevcut post'ların like güncellemelerini dinle
    _likesSubscription = FirebaseFirestore.instance
        .collection('feed_posts')
        .where(FieldPath.documentId,
            whereIn: postIds.take(10).toList()) // Firestore limit
        .snapshots()
        .listen((snapshot) {
      _handleSelectiveUpdates(snapshot);
    });
  }

  /// 🎯 SMART SYNC: Sadece değişen post'ları güncelle
  void _handleSelectiveUpdates(QuerySnapshot snapshot) {
    bool hasChanges = false;

    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.modified) {
        final data = change.doc.data() as Map<String, dynamic>;
        final likedByList = data['likedBy'] as List? ?? [];
        final postId = change.doc.id;

        // Sadece bu post'u güncelle
        final postIndex = _currentPosts.indexWhere((p) => p.id == postId);
        if (postIndex != -1) {
          final oldPost = _currentPosts[postIndex];
          final newLikeCount = likedByList.length;
          final newIsLiked =
              likedByList.contains(FirebaseAuth.instance.currentUser?.uid);

          // Sadece like verisi değiştiyse güncelle
          if (oldPost.likeCount != newLikeCount ||
              oldPost.isLiked != newIsLiked) {
            _currentPosts[postIndex] = oldPost.copyWith(
              likeCount: newLikeCount,
              isLiked: newIsLiked,
              commentCount: data['commentCount'] ?? oldPost.commentCount,
            );
            hasChanges = true;
          }
        }
      }
    }

    // Sadece değişiklik varsa setState
    if (hasChanges) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        itemCount: _currentPosts.length,
        itemBuilder: (context, index) {
          final post = _currentPosts[index];

          return FeedPostWidget(
            key: ValueKey(post.id),
            post: post,
            onProfileTap: widget.onProfileTap,
            onChatTap: widget.onChatTap,
            onOptionsTap: widget.onOptionsTap,
          );
        },
      ),
    );
  }
}
