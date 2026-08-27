import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../models/venue.dart';
import '../../profile/user_profile_page.dart';
import '../../home/home_page.dart';
import '../services/checkin_service.dart';
import 'venue_leaderboard_section.dart';

class VenueDetailsSheet extends StatelessWidget {
  final Venue venue;
  final bool hasCheckedIn;
  final bool isCheckedIn;
  final bool canSeeUsers;
  final bool isPremium;
  final bool isUpdatingFavorite;
  final int actualUserCount;
  final Map<String, dynamic>? dailyMayor;
  final Set<String> userCheckedInVenues; // Yeni: Kullanıcının check-in yaptığı mekanlar
  final Function(Venue) onToggleFavorite;
  final Function(Venue) onCheckIn;
  final VoidCallback? onRefreshUserData; // Check-in sonrası veri yenileme
  final Function(Venue) onShowMayorDialog;
  final Function(Venue)? onPurchaseMayorship;
  final Function(Venue)? onPurchaseBuyNowMayorship; // Yeni: Buy Now callback
  final Future<int> Function(String)? calculateMayorshipPrice; // Yeni: Fiyat hesaplama
  final Future<int> Function(String)? calculateBuyNowPrice; // Yeni: Buy Now fiyat hesaplama
  final Function()? onShowPurchaseDiamondsPanel; // Yeni: Elmas satın alma paneli
  final int userDiamondBalance; // Yeni: Kullanıcının elmas bakiyesi
  final IconData Function(String) getCategoryIcon;
  final Widget Function(Venue, bool) buildCheckedInUsersList;
  // Chat request durumları ve callback'ler
  final Set<String>? sentChatRequestUserIds;
  final Function(String, String, {bool isSuper})? onHandleChatRequest; // userId, userName, isSuper
  // 🕐 Check-in cooldown durumu
  final CheckInCooldownStatus? cooldownStatus;
  // 📍 Check-in loading state
  final bool isCheckingIn;
  // 🏠 Home page view options
  final bool hideCheckInButton;
  final bool hideFavoriteButton;
  final bool hideMayorSection;

  const VenueDetailsSheet({
    super.key,
    required this.venue,
    required this.hasCheckedIn,
    required this.isCheckedIn,
    required this.canSeeUsers,
    required this.isPremium,
    required this.isUpdatingFavorite,
    required this.actualUserCount,
    this.dailyMayor,
    required this.userCheckedInVenues, // Yeni: Kullanıcının check-in yaptığı mekanlar
    required this.onToggleFavorite,
    required this.onCheckIn,
    this.onRefreshUserData, // Check-in sonrası veri yenileme
    required this.onShowMayorDialog,
    this.onPurchaseMayorship,
    this.onPurchaseBuyNowMayorship, // Yeni: Buy Now callback
    this.calculateMayorshipPrice, // Yeni: Fiyat hesaplama
    this.calculateBuyNowPrice, // Yeni: Buy Now fiyat hesaplama
    this.onShowPurchaseDiamondsPanel, // Yeni: Elmas satın alma paneli
    required this.userDiamondBalance, // Yeni: Kullanıcının elmas bakiyesi
    required this.getCategoryIcon,
    required this.buildCheckedInUsersList,
    // Chat request durumları ve callback'ler
    this.sentChatRequestUserIds,
    this.onHandleChatRequest,
    this.cooldownStatus, // 🕐 Check-in cooldown durumu
    this.isCheckingIn = false, // 📍 Check-in loading state
    this.hideCheckInButton = false, // 🏠 Home page'de check-in butonunu gizle
    this.hideFavoriteButton = false, // 🏠 Home page'de favori butonunu gizle
    this.hideMayorSection = false, // 🏠 Home page'de muhtar bölümünü gizle
  });

  // 🕒 Mekan kapanış saati kontrolü
  bool _isVenueClosed() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute; // Dakika cinsinden
    
    
    // Check if venue is 24/7 (no closing time)
    if (venue.closingTime == null) {
      return false; // 24/7 venues are never closed
    }
    
    // Eğer venue'da closing time bilgisi varsa, onu kullan (opening time null olsa bile)
    if (venue.closingTime != null) {
      try {
        // Saat formatını parse et (örn: "09:00", "23:30", "+01:00" for cross-day)
        // Eğer opening time null ise, varsayılan olarak 08:00 kabul et (çoğu işletme sabah açılır)
        final openingTimeStr = venue.openingTime ?? "08:00";
        final openingParts = openingTimeStr.split(':');
        
        // Check for cross-day closing (starts with + OR closing time is before opening time)
        final closingTimeStr = venue.closingTime!;
        final isCrossDay = closingTimeStr.startsWith('+');
        final actualClosingTime = isCrossDay ? closingTimeStr.substring(1) : closingTimeStr;
        final closingParts = actualClosingTime.split(':');
        
        if (openingParts.length == 2 && closingParts.length == 2) {
          final openingMinutes = int.parse(openingParts[0]) * 60 + int.parse(openingParts[1]);
          final closingMinutes = int.parse(closingParts[0]) * 60 + int.parse(closingParts[1]);
          
          // Auto-detect cross-day if closing time is before opening time
          final isAutoCrossDay = !isCrossDay && closingMinutes < openingMinutes;
          final isFinalCrossDay = isCrossDay || isAutoCrossDay;
          
          
          bool isClosed;
          
          if (isFinalCrossDay) {
            // Cross-day closing logic: venue is open if current time is after opening OR before closing
            // Example: Opens at 08:00, closes at 02:00 (next day)
            // Open from 08:00-23:59 (same day) and 00:00-02:00 (next day)
            if (currentTime >= openingMinutes || currentTime < closingMinutes) {
              isClosed = false;
            } else {
              isClosed = true;
            }
          } else {
            // Normal işletme saatleri mantığı
            // Eğer şu anki saat açılış saatinden önce veya kapanış saatinden sonra ise kapalı
            if (currentTime < openingMinutes || currentTime >= closingMinutes) {
              isClosed = true;
            } else {
              isClosed = false;
            }
          }
          
          return isClosed;
        } else {
        }
      } catch (e) {
      }
    } else {
    }
    
    // Eğer açılış/kapanış saati bilgisi yoksa, varsayılan olarak 02:00-07:00 arası kapalı
    final isDefaultClosed = hour >= 2 && hour < 7; // 02:00-07:00 arası kapalı (global check-in hours)
    
    return isDefaultClosed;
  }

  // 🚫 Check-in butonu devre dışı mı kontrolü
  bool _isCheckInDisabled() {
    
    // Loading sırasında check-in deaktif
    if (isCheckingIn) {
      return true;
    }
    // Eğer cooldown aktifse, check-in deaktif
    if (cooldownStatus != null && !cooldownStatus!.canCheckIn) {
      return true;
    }
    
    final isDisabled = isCheckedIn || _isVenueClosed();
    return isDisabled;
  }

  // 🔄 Gerçek zamanlı cooldown durumu ile button disable kontrolü
  bool _isCheckInDisabledWithStatus(CheckInCooldownStatus? currentCooldownStatus) {
    
    // Loading sırasında check-in deaktif
    if (isCheckingIn) {
      return true;
    }
    // Eğer cooldown aktifse, check-in deaktif
    if (currentCooldownStatus != null && !currentCooldownStatus.canCheckIn) {
      return true;
    }
    
    final isDisabled = isCheckedIn || _isVenueClosed();
    return isDisabled;
  }

  // 📝 Check-in buton metni
  String _getCheckInButtonText() {
    if (isCheckingIn) {
      return 'Check-in yapılıyor... ⏳';
    } else if (cooldownStatus != null && !cooldownStatus!.canCheckIn) {
      final minutes = cooldownStatus!.remainingMinutes;
      return 'Bekleme süresi: ${minutes}dk ⏳';
    } else if (isCheckedIn) {
      return 'Check-in Yapıldı ✔';
    } else if (_isVenueClosed()) {
      return 'Mekan Kapalı 🔒';
    } else {
      return 'Check-in Yap';
    }
  }

  // 🔄 Gerçek zamanlı cooldown durumu ile button text
  String _getCheckInButtonTextWithStatus(CheckInCooldownStatus? currentCooldownStatus) {
    if (isCheckingIn) {
      return 'Check-in yapılıyor... ⏳';
    } else if (currentCooldownStatus != null && !currentCooldownStatus.canCheckIn) {
      final minutes = currentCooldownStatus.remainingMinutes;
      return 'Bekleme süresi: ${minutes}dk ⏳';
    } else if (isCheckedIn) {
      return 'Check-in Yapıldı ✔';
    } else if (_isVenueClosed()) {
      return 'Mekan Kapalı 🔒';
    } else {
      return 'Check-in Yap';
    }
  }

  // 🎨 Check-in buton ikonu
  IconData _getCheckInButtonIcon() {
    if (isCheckingIn) {
      return Icons.hourglass_empty;
    } else if (cooldownStatus != null && !cooldownStatus!.canCheckIn) {
      return Icons.timer;
    } else if (isCheckedIn) {
      return Icons.check_circle;
    } else if (_isVenueClosed()) {
      return Icons.lock_clock;
    } else {
      return Icons.location_on;
    }
  }

  // 🔄 Gerçek zamanlı cooldown durumu ile button icon
  IconData _getCheckInButtonIconWithStatus(CheckInCooldownStatus? currentCooldownStatus) {
    if (isCheckingIn) {
      return Icons.hourglass_empty;
    } else if (currentCooldownStatus != null && !currentCooldownStatus.canCheckIn) {
      return Icons.timer;
    } else if (isCheckedIn) {
      return Icons.check_circle;
    } else if (_isVenueClosed()) {
      return Icons.lock_clock;
    } else {
      return Icons.location_on;
    }
  }

  // Mayor kartının gösterilip gösterilmeyeceğini kontrol et
  bool _shouldShowMayorshipCard() {
    // Muhtar satın alma fonksiyonu yoksa gösterme
    if (onPurchaseMayorship == null) return false;
    
    // Check-in yapmamışsa gösterme
    if (!isCheckedIn) return false;
    
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return false;
    
    // Eğer mayor yoksa göster (ilk mayor olabilir)
    if (dailyMayor == null) return true;
    
    // Eğer kullanıcı zaten muhtarsa, upgrade edebilir mi kontrol et
    final isCurrentUserMayor = dailyMayor!['userId'] == userId;
    if (isCurrentUserMayor) {
      // final mayorType = dailyMayor!['mayorType'] ?? 'first_checkin';
      // first_checkin muhtarı diamond'a upgrade edebilir
      // diamond muhtarı da daha fazla elmas yatırarak upgrade edebilir
      return true;
    }
    
    // Başka biri muhtarsa, kullanıcı rekabet edebilir
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        // Sponsor mekanları için özel border
        border: venue.isSponsored ? Border.all(
          color: AppColors.primary,
          width: 2,
        ) : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
          // Sponsor mekanları için ekstra glow efekti
          if (venue.isSponsored) BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            if (dailyMayor != null) Stack(
              children: [
                _buildDailyMayorCard(context),
                
                // Real-time mayor change detector
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('daily_mayors')
                      .doc('${venue.id}_${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}')
                      .snapshots(),
                  builder: (context, mayorSnapshot) {
                    if (mayorSnapshot.hasData) {
                      final currentMayorData = mayorSnapshot.data!.exists 
                          ? mayorSnapshot.data!.data() as Map<String, dynamic>? 
                          : null;
                          
                      // Mayor değişikliği tespit et
                      if (currentMayorData != null && dailyMayor != null) {
                        final currentMayorId = currentMayorData['userId'] ?? '';
                        final cachedMayorId = dailyMayor!['userId'] ?? '';
                        final currentDiamonds = currentMayorData['diamondsSpent'] ?? 0;
                        final cachedDiamonds = dailyMayor!['diamondsSpent'] ?? 0;
                        
                        if (currentMayorId != cachedMayorId || currentDiamonds != cachedDiamonds) {
                          // Kısa gecikme ile refresh tetikle
                          Future.delayed(const Duration(milliseconds: 500), () {
                            if (onRefreshUserData != null) {
                              onRefreshUserData!();
                            }
                          });
                        }
                      }
                    }
                    return const SizedBox.shrink(); // Görünmez
                  },
                ),
              ],
            ),
            if (_shouldShowMayorshipCard()) _buildDiamondMayorshipCard(),
            _buildVenueInfo(context),
            _buildDivider(),
            // Mekan içi sıralama: puan tablosu olduğu için check-in kapısının
            // önünde durur; kişi listesi ve bağlantı kurma kapının arkasında.
            VenueLeaderboardSection(venueId: venue.id),
            _buildDivider(),
            if (canSeeUsers) ...[
              _buildUsersHeader(),
              SizedBox(
                height: 300, // Sabit yükseklik
                child: Stack(
                  children: [
                    // Ana kullanıcı listesi (cache'den)
                    buildCheckedInUsersList(venue, canSeeUsers),
                    
                    // Invisible real-time trigger (sadece yeni check-in'leri tespit eder)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('check_ins')
                          .where('venueId', isEqualTo: venue.id)
                          .where('checkInTime', isGreaterThan: Timestamp.fromDate(
                            DateTime.now().subtract(const Duration(minutes: 2)) // Son 2 dakika
                          ))
                          .limit(3) // Sadece son 3 check-in
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.docChanges.isNotEmpty) {
                          // Yeni check-in tespit edildi
                          final newCheckIns = snapshot.data!.docChanges
                              .where((change) => change.type == DocumentChangeType.added)
                              .length;
                              
                          if (newCheckIns > 0) {
                            // Kısa gecikme ile refresh tetikle (duplicate önlemek için)
                            Future.delayed(const Duration(milliseconds: 1000), () {
                              if (onRefreshUserData != null) {
                                onRefreshUserData!();
                              }
                            });
                          }
                        }
                        return const SizedBox.shrink(); // Görünmez
                      },
                    ),
                  ],
                ),
              ),
            ] else ...[
              _buildCheckInRequired(),
            ],
            const SizedBox(height: 20), // Alt boşluk
          ],
        ),
      ),
    );
  }

  Widget _buildDailyMayorCard(BuildContext context) {
    if (dailyMayor == null) return const SizedBox.shrink();
    
    // 🔄 YENİ SİSTEM: Mayor tipine göre tıklanabilirlik kontrolü
    final mayorType = dailyMayor!['mayorType'] ?? 'first_checkin';
    final isClickable = dailyMayor!['isClickable'] ?? false;
    final basCanMessage = dailyMayor!['canMessage'] ?? false;
    
    // 🚫 Kullanıcı kendi kendine mesaj atamaz
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final mayorUserId = dailyMayor!['userId'] ?? '';
    final canMessage = basCanMessage && (currentUserId != mayorUserId);
    
    return GestureDetector(
      onTap: isClickable ? () {
        // Sadece elmas muhtarların profili tıklanabilir - UserProfilePage'i bottom sheet olarak aç
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) => UserProfilePage(
              userId: dailyMayor!['userId'] ?? '',
              showActions: true,
              isBottomSheet: true,
              isMayor: true,
              mayorVenueName: venue.name,
              // External chat request durumu
              externalHasSentRequest: sentChatRequestUserIds?.contains(dailyMayor!['userId'] ?? '') ?? false,
              onExternalChatRequest: onHandleChatRequest != null 
                ? () => onHandleChatRequest!(dailyMayor!['userId'] ?? '', dailyMayor!['userName'] ?? 'Kullanıcı', isSuper: false) 
                : null,
              onExternalSuperChatRequest: onHandleChatRequest != null 
                ? () => onHandleChatRequest!(dailyMayor!['userId'] ?? '', dailyMayor!['userName'] ?? 'Kullanıcı', isSuper: true) 
                : null,
            ),
          ),
        );
      } : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: mayorType == 'diamond' 
              ? [AppColors.primaryLight.withOpacity(0.8), AppColors.primary, AppColors.primaryDark] // Primary pembe tonları
              : [AppColors.premium, const Color(0xFFFFA500), const Color(0xFFFF8C00)], // Altın tonları first_checkin için
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: mayorType == 'diamond' 
                ? AppColors.primary.withOpacity(0.4) // Primary shadow
                : Colors.amber.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        child: Row(
          children: [
            // Sol taraf - Avatar ve crown icon
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: mayorType == 'diamond'
                        ? [AppColors.primary, AppColors.primaryDark] // Primary pembe tonları
                        : [const Color(0xFFFFD700), const Color(0xFFFFA500)], // İlk check-in altın
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundImage: dailyMayor!['userPhoto'] != null
                        ? NetworkImage(dailyMayor!['userPhoto'])
                        : null,
                    child: dailyMayor!['userPhoto'] == null
                        ? const Icon(Icons.person, color: Colors.white, size: 28)
                        : null,
                  ),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: mayorType == 'diamond' 
                        ? AppColors.primary // Primary pembe
                        : const Color(0xFFFFD700), // İlk check-in altın
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      mayorType == 'diamond' ? Icons.diamond : Icons.emoji_events,
                      color: mayorType == 'diamond' 
                        ? Colors.white 
                        : const Color(0xFFFF6B00),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Orta - Muhtar bilgileri
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        mayorType == 'diamond' ? Icons.diamond : Icons.star, 
                        color: mayorType == 'diamond' 
                          ? AppColors.primary // Primary pembe
                          : const Color(0xFFFFD700), 
                        size: 16
                      ),
                      const SizedBox(width: 4),
                      Text(
                        mayorType == 'diamond' ? 'ELMAS MUHTAR' : 'GÜNÜN MUHTARI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: mayorType == 'diamond' 
                            ? AppColors.primary // Primary pembe
                            : const Color(0xFFFF6B00),
                          letterSpacing: 1,
                        ),
                      ),
                      if (!isClickable) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.visibility_off,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dailyMayor!['userName'] ?? 'İsimsiz',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dailyMayor!['mayorType'] == 'diamond' 
                      ? 'Elmas muhtarı (Toplam ${dailyMayor!['diamondsSpent'] ?? 0} 💎 harcandı)'
                      : 'İlk check-in muhtarı (Ücretsiz)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: mayorType == 'first_checkin' ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            // Sağ taraf - Sadece mesaj/profil butonu
            Column(
              children: [
                if (isClickable && canMessage) ...[
                  GestureDetector(
                    onTap: () {
                      // Mesaj dialog'unu direkt aç
                      _showMessageDialog(context, dailyMayor!['userId'] ?? '', dailyMayor!['userName'] ?? 'İsimsiz');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1), // Primary tema
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary, width: 1.5), // Primary border
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.message, size: 20, color: AppColors.primary), // Primary icon
                          SizedBox(height: 4),
                          Text(
                            'Mesaj',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary, // Primary text
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (isClickable) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade300, width: 1.5),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility, size: 20, color: Colors.green),
                        SizedBox(height: 4),
                        Text(
                          'Profil',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildVenueInfo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Sponsor badge'ini en üstte göster
          if (venue.isSponsored) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'SPONSORLU MEKAN',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.star_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _buildCategoryChip(),
                    const SizedBox(height: 12),
                    _buildRatingAndUserCount(),
                  ],
                ),
              ),
              if (!hideFavoriteButton) _buildFavoriteButton(),
            ],
          ),
          // Mayor section kontrolü
          if (!hideMayorSection) // Muhtar bölümü gizlenmemişse göster
            Builder(
              builder: (context) {
                if (dailyMayor != null) {
                  // Eğer daily mayor varsa
                  final userId = FirebaseAuth.instance.currentUser?.uid;
                  final isCurrentUserMayor = dailyMayor!['userId'] == userId;
                  
                  if (isCurrentUserMayor) {
                    // Kullanıcı zaten muhtar ise, hiçbir şey gösterme (zaten üstte mayor card var)
                    return const SizedBox.shrink();
                  } else {
                    // Başka biri muhtar ise, sadece "yeni muhtar ol" göster (mayor card zaten üstte)
                    return _buildBecomeMayorSection(isFirstMayor: false); // Yeni muhtar ol
                  }
                } else {
                  // Kimse muhtar değilse, sadece "ilk muhtar ol" göster
                  return _buildBecomeMayorSection(isFirstMayor: true);
                }
              },
            ),
          const SizedBox(height: 16),
          if (!hideCheckInButton) _buildCheckInButton(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCategoryChip() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            getCategoryIcon(venue.category),
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            venue.category,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingAndUserCount() {
    return Row(
      children: [
        if (venue.rating > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.premium.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded,
                    color: AppColors.premium, size: 18),
                const SizedBox(width: 4),
                Text(
                  venue.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
        ],
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.success.withOpacity(0.15),
                AppColors.info.withOpacity(0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_rounded,
                  color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Text(
                canSeeUsers
                    ? '$actualUserCount kişi burada'
                    : isPremium 
                        ? '$actualUserCount kişi burada'
                        : 'Check-in yapın',
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFavoriteButton() {
    final hasCheckedInToVenue = userCheckedInVenues.contains(venue.id);
    final canAddToFavorites = hasCheckedInToVenue || venue.isFavorite; // Zaten favori ise kaldırabilir
    
    return Container(
      decoration: BoxDecoration(
        color: venue.isFavorite
            ? AppColors.error.withOpacity(0.1)
            : hasCheckedInToVenue 
                ? AppColors.grey500.withOpacity(0.1)
                : AppColors.grey300.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(
          venue.isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: venue.isFavorite 
              ? AppColors.error 
              : hasCheckedInToVenue 
                  ? AppColors.grey600 
                  : AppColors.grey400,
          size: 28,
        ),
        onPressed: (isUpdatingFavorite || !canAddToFavorites) 
            ? null 
            : () => onToggleFavorite(venue),
      ),
    );
  }

  Widget _buildBecomeMayorSection({bool isFirstMayor = true}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GestureDetector(
        onTap: () => onShowMayorDialog(venue),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.premium,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isFirstMayor ? Icons.emoji_events : Icons.military_tech,
                color: AppColors.premium, 
                size: 24
              ),
              const SizedBox(width: 12),
              Text(
                isFirstMayor ? 'İlk Muhtar Siz Olun!' : 'Yeni Muhtar Siz Olun!',
                style: const TextStyle(
                  color: AppColors.premium,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInButton() {
    final isButtonDisabled = _isCheckInDisabled();
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isButtonDisabled ? null : () async {
          onCheckIn(venue);
          // Check-in sonrası veri yenile
          if (onRefreshUserData != null) {
            await Future.delayed(const Duration(milliseconds: 500));
            onRefreshUserData!();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isButtonDisabled
              ? AppColors.grey400
              : AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: isButtonDisabled ? 0 : 8,
          shadowColor: AppColors.primary.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isCheckingIn)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                ),
              )
            else
              Icon(
                _getCheckInButtonIcon(),
                color: AppColors.white,
                size: 24,
              ),
            const SizedBox(width: 10),
            Text(
              _getCheckInButtonText(),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.transparent,
            AppColors.grey500.withOpacity(0.3),
            AppColors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _buildUsersHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_alt_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'Bugün Burada',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$actualUserCount',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const Spacer(),
          if (isPremium)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.premium.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium,
                      size: 14, color: AppColors.premium),
                  SizedBox(width: 4),
                  Text(
                    'Premium',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.premium,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckInRequired() {
    return SizedBox(
      height: 300, // Sabit yükseklik
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  size: 50, color: AppColors.warning),
            ),
            const SizedBox(height: 16),
            const Text(
              'Check-in Gerekli',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bu mekandaki kişileri görmek için\nönce check-in yapmalısınız',
              style: TextStyle(
                color: AppColors.grey600,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiamondMayorshipCard() {
    return FutureBuilder<Map<String, int>>(
      future: _calculatePrices(),
      builder: (context, snapshot) {
        final regularPrice = snapshot.data?['regular'] ?? 5;
        final buyNowPrice = snapshot.data?['buyNow'] ?? 10;
        
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8F4FD), Color(0xFFF3E5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst kısım - Başlık ve açıklama
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.diamond,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getMayorshipButtonTitle(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getMayorshipButtonSubtitle(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Alt kısım - Butonlar
              _buildMayorshipButtonsWithPrices(regularPrice, buyNowPrice),
            ],
          ),
        );
      },
    );
  }

  // Fiyatları hesaplayan async fonksiyon
  Future<Map<String, int>> _calculatePrices() async {
    if (calculateMayorshipPrice == null || calculateBuyNowPrice == null) {
      return {'regular': 5, 'buyNow': 10};
    }
    
    try {
      final regular = await calculateMayorshipPrice!(venue.id);
      final buyNow = await calculateBuyNowPrice!(venue.id);
      return {'regular': regular, 'buyNow': buyNow};
    } catch (e) {
      return {'regular': 5, 'buyNow': 10};
    }
  }

  // Mayor olma butonlarını oluştur (Regular + Buy Now) - Fiyatlarla
  Widget _buildMayorshipButtonsWithPrices(int regularPrice, int buyNowPrice) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final isCurrentUserMayor = dailyMayor != null && dailyMayor!['userId'] == userId;
    
    // Debug: Mayor data'sını kontrol et
    if (isCurrentUserMayor) {
    }
    
    // Eğer kullanıcı zaten muhtarsa, upgrade seçenekleri göster
    if (isCurrentUserMayor) {
      final mayorType = dailyMayor!['mayorType'] ?? 'first_checkin';
      final currentDiamonds = dailyMayor!['diamondsSpent'] ?? 0;
      
      
      return Column(
        children: [
          // Mevcut durum
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sen bu mekanın muhtarısın! 👑',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (mayorType == 'first_checkin')
                        const Text(
                          'İlk check-in ile muhtar oldun (Ücretsiz)',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        )
                      else
                        Text(
                          'Bu mekana toplam $currentDiamonds 💎 harcadın',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Upgrade butonları
          Row(
            children: [
              // Regular upgrade buton
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleMayorshipPurchase(venue, regularPrice),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, // Primary pembe
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.diamond, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$regularPrice',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        mayorType == 'first_checkin' ? 'Yükselt' : 'Arttır',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Buy Now buton (opsiyonel)
              if (onPurchaseBuyNowMayorship != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onPurchaseBuyNowMayorship!(venue),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 2,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.flash_on, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '$buyNowPrice',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Rekabetçi Muhtar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    
    // İki buton: Regular ve Buy Now (yeni kullanıcı için)
    return Row(
      children: [
        // Regular buton
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleMayorshipPurchase(venue, regularPrice),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.diamond, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$regularPrice',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Muhtar Ol',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Buy Now buton (opsiyonel)
        if (onPurchaseBuyNowMayorship != null)
          Expanded(
            child: ElevatedButton(
              onPressed: () => _handleBuyNowPurchase(venue, buyNowPrice),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flash_on, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$buyNowPrice',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Rekabetçi Muhtar',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
  Widget _buildMayorshipButtons() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final isCurrentUserMayor = dailyMayor != null && dailyMayor!['userId'] == userId;
    
    // Debug: Mayor data'sını kontrol et (static version)
    if (isCurrentUserMayor) {
    }
    
    // Eğer kullanıcı zaten muhtarsa, upgrade seçenekleri göster
    if (isCurrentUserMayor) {
      final mayorType = dailyMayor!['mayorType'] ?? 'first_checkin';
      final currentDiamonds = dailyMayor!['diamondsSpent'] ?? 0;
      
      
      return Column(
        children: [
          // Mevcut durum
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sen bu mekanın muhtarısın! 👑',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (mayorType == 'first_checkin')
                        const Text(
                          'İlk check-in ile muhtar oldun (Ücretsiz)',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        )
                      else
                        Text(
                          'Bu mekana toplam $currentDiamonds 💎 harcadın',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Upgrade butonları
          Row(
            children: [
              // Regular upgrade buton
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleMayorshipPurchaseStatic(venue),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.diamond, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _getMayorshipButtonAmount(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        mayorType == 'first_checkin' ? 'Yükselt' : 'Arttır',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Buy Now buton (opsiyonel)
              if (onPurchaseBuyNowMayorship != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onPurchaseBuyNowMayorship!(venue),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 2,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.flash_on, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              _getBuyNowButtonAmount(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Rekabetçi Muhtar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    
    // İki buton: Regular ve Buy Now
    return Row(
      children: [
        // Regular buton
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleMayorshipPurchaseStatic(venue),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.diamond, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _getMayorshipButtonAmount(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Muhtar Ol',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Buy Now buton (opsiyonel)
        if (onPurchaseBuyNowMayorship != null)
          Expanded(
            child: ElevatedButton(
              onPressed: () => _handleBuyNowMayorshipPurchaseStatic(venue),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flash_on, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _getBuyNowButtonAmount(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Rekabetçi Muhtar',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Muhtar olma butonunun başlığını belirle
  String _getMayorshipButtonTitle() {
    if (dailyMayor != null) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final isCurrentUserMayor = dailyMayor!['userId'] == userId;
      
      if (isCurrentUserMayor) {
        return 'Sen Bu Mekanın Muhtarısın! 👑';
      } else {
        return 'Muhtarlığı Ele Geçir!';
      }
    } else {
      return 'Elmas ile Muhtar Ol!';
    }
  }

  // Muhtar olma butonunun alt metnini belirle
  String _getMayorshipButtonSubtitle() {
    if (dailyMayor != null) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final isCurrentUserMayor = dailyMayor!['userId'] == userId;
      final currentDiamonds = dailyMayor!['diamondsSpent'] ?? 0;
      
      if (isCurrentUserMayor) {
        return 'Bu mekana $currentDiamonds elmas harcadın';
      } else {
        final mayorType = dailyMayor!['mayorType'] ?? 'first_checkin';
        if (mayorType == 'first_checkin') {
          return 'Mevcut muhtar ilk check-in ile muhtar oldu. Sen elmas ile daha üst seviye muhtar olabilirsin!';
        } else {
          return 'Mevcut muhtar $currentDiamonds elmas harcadı. Basamaklı artış sistemi ile muhtar olabilirsin!';
        }
      }
    } else {
      return 'Basamaklı fiyatlandırma: İlk başta düşük, rekabet arttıkça yükselir!';
    }
  }

  // Muhtar olma butonundaki elmas miktarını belirle (yeni basamaklı sistem)
  String _getMayorshipButtonAmount() {
    if (dailyMayor != null) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final isCurrentUserMayor = dailyMayor!['userId'] == userId;
      final currentDiamonds = dailyMayor!['diamondsSpent'] ?? 0;
      
      if (isCurrentUserMayor) {
        return '$currentDiamonds';
      } else {
        final mayorType = dailyMayor!['mayorType'] ?? 'first_checkin';
        if (mayorType == 'first_checkin') {
          return '5'; // İlk diamond mayor minimum fiyat
        } else {
          // Basamaklı artış hesapla
          return '${_calculateNextPrice(currentDiamonds)}';
        }
      }
    } else {
      return '5'; // İlk başlangıç fiyatı
    }
  }

  // Buy Now butonundaki elmas miktarını belirle
  String _getBuyNowButtonAmount() {
    final regularAmount = int.tryParse(_getMayorshipButtonAmount()) ?? 5;
    final buyNowAmount = regularAmount * 2;
    return '$buyNowAmount';
  }

  // Basamaklı fiyat hesaplama (UI için)
  int _calculateNextPrice(int currentPrice) {
    int increment;
    
    if (currentPrice < 10) {
      increment = 5;
    } else if (currentPrice < 50) {
      increment = 10;
    } else if (currentPrice < 99) {
      increment = 25;
    } else {
      increment = 50;
    }
    
    return currentPrice + increment;
  }

  // Elmas yetersizliği kontrolü ve uyarı gösterme
  void _handleMayorshipPurchase(Venue venue, int requiredDiamonds) {
    if (userDiamondBalance >= requiredDiamonds) {
      // Yeterli elmas var, satın alma işlemini başlat
      onPurchaseMayorship!(venue);
    } else {
      // Yetersiz elmas, elmas satın alma panelini aç
      if (onShowPurchaseDiamondsPanel != null) {
        onShowPurchaseDiamondsPanel!();
      }
    }
  }

  // Buy Now için elmas yetersizliği kontrolü
  void _handleBuyNowPurchase(Venue venue, int requiredDiamonds) {
    if (userDiamondBalance >= requiredDiamonds) {
      // Yeterli elmas var, satın alma işlemini başlat
      onPurchaseBuyNowMayorship!(venue);
    } else {
      // Yetersiz elmas, elmas satın alma panelini aç
      if (onShowPurchaseDiamondsPanel != null) {
        onShowPurchaseDiamondsPanel!();
      }
    }
  }

  // Static fiyatlarla elmas kontrolü (eski fonksiyon için)
  void _handleMayorshipPurchaseStatic(Venue venue) {
    final requiredDiamonds = int.tryParse(_getMayorshipButtonAmount()) ?? 5;
    _handleMayorshipPurchase(venue, requiredDiamonds);
  }

    // Static Buy Now fiyatlarla elmas kontrolü (eski fonksiyon için)  
  void _handleBuyNowMayorshipPurchaseStatic(Venue venue) {
    // final requiredDiamonds = int.tryParse(_getBuyNowButtonAmount()) ?? 20;
    // _handleBuyNowMayorshipPurchase(venue, requiredDiamonds);
    // Bu fonksiyon implement edilmemiş, gerekirse onPurchaseBuyNowMayorship callback'ini çağır
    if (onPurchaseBuyNowMayorship != null) {
      onPurchaseBuyNowMayorship!(venue);
    }
  }

  // 💬 MESAJ YÖNLENDIRME FONKSIYONU
  Future<void> _showMessageDialog(BuildContext context, String receiverId, String receiverName) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giriş yapmalısınız'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
        return;
      }

      // Önce match oluştur (eğer yoksa)
      await _createMatchIfNeeded(currentUser.uid, receiverId);
      
      // HomePage'e yönlendir ve matches tab'ını aç (index: 3)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const HomePage(initialIndex: 3), // 3 = Mesajlar tab'ı
        ),
        (route) => false, // Tüm önceki route'ları temizle
      );
      
      // Başarılı yönlendirme mesajı
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$receiverName ile mesajlaşmak için match oluşturuldu ve Mesajlar sayfasına yönlendirildiniz'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesajlaşma başlatılamadı'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  // 🤝 MATCH OLUŞTURMA FONKSIYONU
  Future<void> _createMatchIfNeeded(String currentUserId, String otherUserId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // Önce bu iki kullanıcı arasında aktif match var mı kontrol et
      final existingMatch = await firestore
          .collection('matches')
          .where('isActive', isEqualTo: true)
          .get();
      
      bool matchExists = false;
      for (var doc in existingMatch.docs) {
        final data = doc.data();
        final user1 = data['user1Id'];
        final user2 = data['user2Id'];
        
        if ((user1 == currentUserId && user2 == otherUserId) ||
            (user1 == otherUserId && user2 == currentUserId)) {
          matchExists = true;
          break;
        }
      }
      
      // Eğer match yoksa oluştur
      if (!matchExists) {
        await firestore.collection('matches').add({
          'user1Id': currentUserId,
          'user2Id': otherUserId,
          'matchedAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'lastMessage': null,
          'lastMessageTime': null,
        });
      }
    } catch (e) {
      rethrow;
    }
  }
}
