// lib/presentation/pages/map/components/venue_leaderboard_section.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/services/leaderboard_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Mekan içi sıralama tablosu.
///
/// TASARIM İLKESİ — global sıralama yok:
/// Sıralama yalnızca bu mekanın havuzunda yapılır. Küçük havuzda herkes
/// kendini üst sıralarda görür; kullanıcı her zaman kazanabileceği bir
/// tabloda olur. Mutlak/global sıralama alttaki çoğunluğu demotive eder.
///
/// Bu bölüm bir *puan tablosu* olduğu için check-in kapısının önünde durur;
/// fotoğraflı kişi listesi ve bağlantı kurma ise kapının arkasındadır.
class VenueLeaderboardSection extends StatelessWidget {
  final String venueId;

  const VenueLeaderboardSection({super.key, required this.venueId});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return FutureBuilder<List<LeaderboardEntry>>(
      future: LeaderboardService.getVenueLeaderboard(
        venueId,
        currentUserId: currentUserId,
        limit: 5,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final entries = snapshot.data ?? const <LeaderboardEntry>[];

        // Boşken gizlemek yerine davet göster: sıralama mekanın kalıcı bir
        // parçası, henüz kimse yoksa ilk sırayı almak bir teşvik.
        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bu mekanda henüz sıralama yok — ilk sırayı sen al.',
                    style: TextStyle(fontSize: 13, color: AppColors.grey600),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Text(
                    'Mekan Sıralaması',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'bu mekana özel',
                    style: TextStyle(fontSize: 11, color: AppColors.grey500),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...entries.map(_buildRow),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(LeaderboardEntry e) {
    final isMe = e.isCurrentUser;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.primary.withOpacity(0.08)
            : AppColors.grey500.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: isMe
            ? Border.all(color: AppColors.primary.withOpacity(0.35))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${e.rank}.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: e.rank <= 3 ? AppColors.primary : AppColors.grey600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              isMe ? '${e.userName} (sen)' : e.userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '${e.checkInCount} check-in',
            style: TextStyle(fontSize: 12, color: AppColors.grey600),
          ),
        ],
      ),
    );
  }
}
