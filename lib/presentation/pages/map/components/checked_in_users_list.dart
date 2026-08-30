import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/models/checkedin_user.dart';  // Doğru model import'u
import '../../../models/venue.dart';
import '../../profile/user_profile_page.dart';

class CheckedInUsersList extends StatelessWidget {
  final Venue venue;
  final bool canSeeUsers;
  final Set<String> sentChatRequestUserIds;
  final bool isPremium;
  final Function(String userId, String userName, {bool isSuper}) onHandleChatRequest;
  final String Function(DateTime) getTimeAgo;
  final Function({required String message, bool isSuper})? onShowOverlayMessage;

  const CheckedInUsersList({
    super.key,
    required this.venue,
    required this.canSeeUsers,
    required this.sentChatRequestUserIds,
    required this.isPremium,
    required this.onHandleChatRequest,
    required this.getTimeAgo,
    this.onShowOverlayMessage,
  });

  @override
  Widget build(BuildContext context) {
    // MEVCUDİYET KAPISI: Bu mekana check-in yapmadıysan topluluğu göremezsin.
    // "Henüz kimse yok" demek yanıltıcı olurdu — insanlar orada olabilir;
    // erişim için gerçek dünyada bulunmuş olmak gerekiyor.
    if (!canSeeUsers) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_outlined,
                    size: 50, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Buranın topluluğu check-in ile açılır',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Bu mekana check-in yaptığında buradaki topluluğu görebilir '
                've bağlantı kurabilirsin.',
                style: TextStyle(color: AppColors.grey600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (venue.checkedInUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.grey500.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline_rounded,
                  size: 50, color: AppColors.grey400),
            ),
            const SizedBox(height: 16),
            const Text(
              'Henüz kimse yok',
              style: TextStyle(
                color: AppColors.grey600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'İlk check-in yapan sen ol!',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Sadece muhtar olan kullanıcıları filtrele (muhtar zaten en üstte gösterilecek)
    // Kendimizi de dahil et, sadece mayor'ları filtrele
    final filteredUsers = venue.checkedInUsers.where((user) => 
      !user.isMayor 
    ).toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        final isCurrentUser = user.id == currentUserId;
        return UserListItem(
          user: user,
          isCurrentUser: isCurrentUser,
          hasSentRequest: sentChatRequestUserIds.contains(user.id),
          isPremium: isPremium,
          timeAgo: getTimeAgo(user.checkInTime),
          onHandleChatRequest: onHandleChatRequest,
          onShowOverlayMessage: onShowOverlayMessage,
        );
      },
    );
  }
}

class UserListItem extends StatelessWidget {
  final CheckedInUser user;
  final bool isCurrentUser;
  final bool hasSentRequest;
  final bool isPremium;
  final String timeAgo;
  final Function(String userId, String userName, {bool isSuper}) onHandleChatRequest;
  final Function({required String message, bool isSuper})? onShowOverlayMessage;

  const UserListItem({
    super.key,
    required this.user,
    required this.isCurrentUser,
    required this.hasSentRequest,
    required this.isPremium,
    required this.timeAgo,
    required this.onHandleChatRequest,
    this.onShowOverlayMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isCurrentUser
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.grey500.withOpacity(0.1),
          width: isCurrentUser ? 2 : 1,
        ),
      ),
      child: Material(
        color: AppColors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // PROFİLİ AÇ. Eskiden kapalıydı (`onTap: null`): kullanıcı birine
          // bağlantı isteği gönderebiliyor ama önce profiline BAKAMIYORDU.
          // Hem tuhaf hem güvenlik açısından yanlıştı — kime istek attığını
          // görebilmelisin.
          //
          // Bu liste zaten mevcudiyet kapısının ARKASINDA: buraya ancak o
          // mekana check-in yapmış biri ulaşabiliyor. Dolayısıyla profil
          // açmak bir "insan tarama" yüzeyi yaratmıyor.
          onTap: isCurrentUser
              ? null
              : () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: AppColors.transparent,
                    builder: (_) => DraggableScrollableSheet(
                      initialChildSize: 0.9,
                      minChildSize: 0.5,
                      maxChildSize: 0.95,
                      builder: (context, scrollController) => UserProfilePage(
                        userId: user.id,
                        showActions: true,
                        isBottomSheet: true,
                      ),
                    ),
                  ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildUserAvatar(),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildUserInfo(),
                ),
                if (!isCurrentUser) ...[
                  _buildSuperChatButton(context),
                  _buildChatButton(context),
                ] else ...[
                  _buildCurrentUserBadge(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: user.photoUrl == null
                ? LinearGradient(
                    colors: [
                      Colors.primaries[user.name.length % Colors.primaries.length],
                      Colors.primaries[(user.name.length + 1) % Colors.primaries.length],
                    ],
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.transparent,
            backgroundImage: user.photoUrl != null
                ? NetworkImage(user.photoUrl!)
                : null,
            child: user.photoUrl == null
                ? Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  )
                : null,
          ),
        ),
        if (user.isPremium)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.premium,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.white,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 12,
                color: AppColors.white,
              ),
            ),
          ),
        if (isCurrentUser)
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.white,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.person,
                size: 10,
                color: AppColors.white,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUserInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                isCurrentUser ? '${user.name} (Sen)' : user.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isCurrentUser ? AppColors.primary : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (user.isPremium) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.amber, Colors.orange],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.access_time,
              size: 14,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              timeAgo,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuperChatButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        gradient: hasSentRequest
            ? LinearGradient(
                colors: [AppColors.primary.withOpacity(0.7), AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(
          Icons.chat_bubble,
          color: Colors.white,
        ),
        iconSize: 22,
        onPressed: hasSentRequest
            ? () {
                if (onShowOverlayMessage != null) {
                  onShowOverlayMessage!(
                    message: 'Bu kullanıcıya zaten mesaj isteği gönderdiniz',
                    isSuper: true,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Bu kullanıcıya zaten mesaj isteği gönderdiniz'),
                        ],
                      ),
                      backgroundColor: Colors.purple,
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            : () => onHandleChatRequest(user.id, user.name, isSuper: true),
        splashRadius: 24,
      ),
    );
  }

  Widget _buildChatButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: hasSentRequest
            ? AppColors.primary.withOpacity(0.2)
            : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: hasSentRequest
              ? AppColors.primary.withOpacity(0.5)
              : AppColors.primary.withOpacity(0.6),
          width: 2,
        ),
      ),
      child: IconButton(
        icon: Icon(
          Icons.chat_bubble_outline,
          color: hasSentRequest
              ? AppColors.primary.withOpacity(0.7)
              : AppColors.primary,
        ),
        iconSize: 22,
        onPressed: hasSentRequest
            ? () {
                if (onShowOverlayMessage != null) {
                  onShowOverlayMessage!(
                    message: 'Bu kullanıcıya zaten mesaj isteği gönderdiniz',
                    isSuper: false,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Bu kullanıcıya zaten mesaj isteği gönderdiniz'),
                        ],
                      ),
                      backgroundColor: AppColors.primary,
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            : () => onHandleChatRequest(user.id, user.name, isSuper: false),
        splashRadius: 24,
      ),
    );
  }

  Widget _buildCurrentUserBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Sen',
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
