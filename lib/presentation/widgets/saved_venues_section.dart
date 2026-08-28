// lib/presentation/widgets/saved_venues_section.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/saved_venues_service.dart';
import '../../core/theme/app_colors.dart';

/// Profilde "Gitmek İstediklerim" ve "Gittiklerim".
///
/// Uygulamanın kimlik vaadi: kullanıcı yaşı/cinsiyetiyle değil, gitmek
/// istediği ve gerçekten gittiği yerlerle tanımlanır. Tamamlanan kayıtlar
/// üstte sayaç olarak durur — kaydetmek değil, gitmek ödüllendirilir.
class SavedVenuesSection extends StatefulWidget {
  const SavedVenuesSection({super.key});

  @override
  State<SavedVenuesSection> createState() => _SavedVenuesSectionState();
}

class _SavedVenuesSectionState extends State<SavedVenuesSection> {
  late Future<List<SavedVenue>> _future;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _future = SavedVenuesService.getSaved(uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedVenue>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final all = snapshot.data!;
        final pending = all.where((v) => !v.isVisited).toList();
        final visited = all.where((v) => v.isVisited).toList();

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
              Row(
                children: [
                  const Icon(Icons.bookmark_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Text(
                    'Gitmek İstediklerim',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (visited.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${visited.length} tamamlandı',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (all.isEmpty)
                _emptyState()
              else if (pending.isEmpty)
                Text(
                  'Listendeki her yeri tamamladın 🎯',
                  style: TextStyle(fontSize: 13, color: AppColors.grey600),
                )
              else
                ...pending.take(5).map((v) => _row(v)),
              if (pending.length > 5) ...[
                const SizedBox(height: 6),
                Text(
                  've ${pending.length - 5} yer daha',
                  style: TextStyle(fontSize: 12, color: AppColors.grey500),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Text(
      'Gitmek istediğin bir mekanı listene ekle — yakınından geçtiğinde '
      'sana hatırlatalım.',
      style: TextStyle(fontSize: 13, color: AppColors.grey600),
    );
  }

  Widget _row(SavedVenue v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.grey500.withOpacity(0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.place_outlined,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.venueName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (v.venueCategory.isNotEmpty)
                  Text(
                    v.venueCategory,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.grey500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
