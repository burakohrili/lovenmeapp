// lib/presentation/widgets/checkin_reward_sheet.dart

import 'package:flutter/material.dart';
import '../../core/services/gamification_service.dart';
import '../../core/theme/app_colors.dart';

/// Check-in sonrası kazanılan ilerlemeyi kutlayan sayfa altı paneli.
///
/// Mekan keşif oyununun geri bildirim katmanı: seri, seviye ve rozet.
/// Tamamen bireysel ilerleme gösterir — başka kullanıcı gerektirmez.
class CheckInRewardSheet extends StatelessWidget {
  final CheckInReward reward;
  final String venueName;

  const CheckInRewardSheet({
    super.key,
    required this.reward,
    required this.venueName,
  });

  /// Kazanılan bir şey varsa paneli gösterir; yoksa hiçbir şey yapmaz.
  static void showIfAny(
    BuildContext context, {
    required CheckInReward? reward,
    required String venueName,
  }) {
    if (reward == null || !reward.hasAnything) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CheckInRewardSheet(reward: reward, venueName: venueName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            venueName,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),

          if (reward.streakIncreased) _streakBlock(),
          if (reward.levelUp) ...[
            const SizedBox(height: 16),
            _levelBlock(),
          ],
          if (reward.newBadges.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              reward.newBadges.length == 1 ? 'Yeni rozet' : 'Yeni rozetler',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...reward.newBadges.map(_badgeRow),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Devam',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streakBlock() {
    return Column(
      children: [
        const Text('🔥', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 8),
        Text(
          '${reward.currentStreak} gün üst üste',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Serini sürdürdün',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _levelBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            'Seviye ${reward.level}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _badgeRow(BadgeDef badge) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(badge.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  badge.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
