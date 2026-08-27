// lib/presentation/widgets/venue_progress_section.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/gamification_service.dart';
import '../../core/theme/app_colors.dart';

/// Profildeki mekan keşif ilerlemesi: seri, seviye ve rozetler.
///
/// TASARIM İLKESİ — tek kişilik oynanabilirlik:
/// Buradaki her şey bireysel ilerlemedir. Uygulamada tek kullanıcı olsa bile
/// seri işler, seviye yükselir, rozet kazanılır. Başka kullanıcıya bağlı
/// hiçbir mekanik yok.
class VenueProgressSection extends StatefulWidget {
  const VenueProgressSection({super.key});

  @override
  State<VenueProgressSection> createState() => _VenueProgressSectionState();
}

class _VenueProgressSectionState extends State<VenueProgressSection> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _future = GamificationService.getProgress(uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final d = snapshot.data!;

        final streak = (d['currentStreak'] as int?) ?? 0;
        final longest = (d['longestStreak'] as int?) ?? 0;
        final level = (d['level'] as int?) ?? 1;
        final total = (d['totalCheckIns'] as int?) ?? 0;
        final unique = (d['uniqueVenuesVisited'] as int?) ?? 0;
        final nextAt = d['nextLevelAt'] as int?;
        final owned = ((d['badges'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Keşif İlerlemen',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),

              // Üst satır: seri / seviye / mekan
              Row(
                children: [
                  _stat('🔥', '$streak', 'gün seri'),
                  _stat('⭐', '$level', 'seviye'),
                  _stat('📍', '$unique', 'mekan'),
                ],
              ),

              if (nextAt != null) ...[
                const SizedBox(height: 14),
                _levelProgress(total, nextAt),
              ],

              if (longest > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'En uzun serin: $longest gün',
                  style: TextStyle(fontSize: 12, color: AppColors.grey600),
                ),
              ],

              const SizedBox(height: 16),
              Text(
                'Rozetler (${owned.length}/${GamificationService.allBadges.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: GamificationService.allBadges
                    .map((b) => _badge(b, owned.contains(b.id)))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String emoji, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.grey600),
          ),
        ],
      ),
    );
  }

  Widget _levelProgress(int total, int nextAt) {
    final ratio = nextAt == 0 ? 0.0 : (total / nextAt).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: AppColors.grey500.withOpacity(0.15),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sonraki seviyeye ${nextAt - total > 0 ? nextAt - total : 0} check-in',
          style: TextStyle(fontSize: 11, color: AppColors.grey600),
        ),
      ],
    );
  }

  Widget _badge(BadgeDef b, bool earned) {
    return Tooltip(
      message: '${b.title} — ${b.description}',
      child: Container(
        width: 54,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: earned
              ? AppColors.primary.withOpacity(0.08)
              : AppColors.grey500.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: earned
              ? Border.all(color: AppColors.primary.withOpacity(0.3))
              : null,
        ),
        child: Column(
          children: [
            Opacity(
              opacity: earned ? 1.0 : 0.3,
              child: Text(b.emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 4),
            Text(
              b.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: earned ? AppColors.textPrimary : AppColors.grey500,
                fontWeight: earned ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
