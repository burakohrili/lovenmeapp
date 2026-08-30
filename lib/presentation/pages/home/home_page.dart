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
import '../profile/profile_page.dart';
import '../messages/messages_with_requests_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../notifications/notifications_page.dart';
import '../my_list/my_list_page.dart';
import '../today/today_page.dart';
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 1;

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
            // dailyLikesRemaining / dailyRewindsRemaining KALDIRILDI:
            // beğeni ve geri alma sistemleri yok; bu alanlar yazılıyor ama
            // hiçbir kod tarafından okunmuyordu.
            'dailyChatRequestsRemaining': isPremium ? 999 : 5,
            'lastLimitReset': FieldValue.serverTimestamp(),
            // Sunucudaki dailyReset de aynı işareti yazar; ikisi artık
            // aynı alanı kullanıyor (eskiden sunucu lastDailyReset yazıyor,
            // istemci lastLimitReset okuyordu — her sabah çift reset).
            'lastDailyReset': FieldValue.serverTimestamp(),
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
              'dailyChatRequestsRemaining': isPremium ? 999 : 5,
              'lastLimitReset': FieldValue.serverTimestamp(),
              'lastDailyReset': FieldValue.serverTimestamp(),
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
        // "Keşfet" -> "Listem". Eski sayfa konum kullanmıyordu ve
        // yalnızca zaten gidilen mekanları listeliyordu; Harita'nın ve
        // Profil geçmişinin kopyasıydı.
        return const MyListPage();
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
                      'Bugün',
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
                    // Eskiden burada '+' (add_box) ikonu vardi ve hicbir sey
                    // uretmiyordu; yalnizca Harita sekmesine geciyordu. Yani
                    // olusturma butonu gibi gorunen bir yonlendirmeydi.
                    // Artik ne yaptigini soyluyor.
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _currentIndex = 1;
                        });
                      },
                      icon: const Icon(Icons.add_location_alt_outlined,
                          size: 20, color: AppColors.primary),
                      label: const Text(
                        'Yer ekle',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // İÇERİK ARTIK TodayPage'den geliyor.
          // Eskiden burada `matches` tabanlı bir gönderi listesi vardı:
          // kitle ölü eşleşme sistemiydi, gönderiler check-in'in otomatik
          // kopyasıydı ve kartlarda yaş / kalp / "beğeni" / yabancıya
          // "mesaj gönder" duruyordu.
          const Expanded(child: TodayPage()),
        ],
      ),
    );
  }







  // Cache için değişkenler ekle

  /// 🎯 REFRESH FIX: Cache'li matched users metodu

  /// 🎯 SMART PAGINATION: İlk yükleme için cache'li post metodu

  /// 🔄 SMART SYNC: Manuel refresh metodu - Cache'i temizle


}

// FEED POST WIDGET - Her post kendi state'ini yÃ¶netir
// NOT: FeedPostWidget ve _FeedPostWidgetState kaldirildi (30.08.2026).
// Bu iki sinif, kalan dating sinyalinin neredeyse tamamini tasiyordu:
//   - '${post.userName}, ${post.userAge}' (yas)
//   - kalp ikonu, 'N begeni', cift dokunup begenme animasyonu
//   - yabanciya 'Mesaj gonder' kisayolu
// Icerik artik TodayPage'den geliyor ve MEKAN odakli.

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

// NOT: FakeQuerySnapshot, _SmartFeedList ve _SmartFeedListState kaldirildi.
// _SmartFeedList ilk 10 gonderinin begeni sayisini canli dinliyordu; begeni
// sistemi tamamen kaldirildigi icin karsiligi kalmadi.
