// lib/presentation/widgets/friend_common_venues_section.dart

import 'package:flutter/material.dart';

import '../../core/services/friends_service.dart';
import '../../core/theme/app_colors.dart';

/// Arkadaş profilinde ortak mekan metrikleri.
///
/// TASARIM İLKESİ:
/// İki kişi arasındaki ilişki, demografiyle değil **birlikte bulunulan
/// yerlerle** anlatılır. Bu bölümde yaş, cinsiyet, uyum yüzdesi gibi hiçbir
/// şey yoktur — yalnızca kaç kez aynı mekanda bulunulduğu ve hangi mekanlar.
///
/// Yalnızca ARKADAŞ olunan profillerde görünür; yabancı profilinde bu bilgi
/// hiç yüklenmez.
class FriendCommonVenuesSection extends StatefulWidget {
  final String otherUserId;

  const FriendCommonVenuesSection({super.key, required this.otherUserId});

  @override
  State<FriendCommonVenuesSection> createState() =>
      _FriendCommonVenuesSectionState();
}

class _FriendCommonVenuesSectionState
    extends State<FriendCommonVenuesSection> {
  bool _loading = true;
  bool _isFriend = false;
  int _commonCheckIns = 0;
  List<String> _venueNames = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final friend = await FriendsService.isFriend(widget.otherUserId);
    if (!friend) {
      if (mounted) setState(() { _isFriend = false; _loading = false; });
      return;
    }

    final result = await FriendsService.commonVenues(widget.otherUserId);
    if (!mounted) return;
    setState(() {
      _isFriend = true;
      _commonCheckIns = result.commonCheckIns;
      _venueNames = result.venueNames;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_isFriend) return const SizedBox.shrink();

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
              const Icon(Icons.place_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'Ortak Mekanlarınız',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (_commonCheckIns > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_commonCheckIns kez',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_venueNames.isEmpty)
            Text(
              'Henüz aynı mekanda bulunmadınız.',
              style: TextStyle(fontSize: 13, color: AppColors.grey600),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _venueNames
                  .map((name) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.grey500.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
