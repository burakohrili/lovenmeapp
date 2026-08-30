// lib/presentation/pages/my_list/my_list_page.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/saved_venues_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/venue_cover_image.dart';
import '../explore_nearby/venue_detail_page.dart';

/// "Listem" sekmesi — Gitmek İstediklerim ve Gittiklerim.
///
/// NEDEN BU SEKME DEĞİŞTİ:
/// Burası eskiden "Keşfet"ti ama adı gerçeği yansıtmıyordu: dosya adı
/// `explore_nearby` olmasına rağmen içinde TEK SATIR konum kodu yoktu.
/// Yaptığı tek şey, kullanıcının ZATEN gittiği mekanları listelemekti — yani
/// Profil'deki check-in geçmişinin kopyasıydı. Sayaç son 30 günün benzersiz
/// ziyaretçisini gösterdiği için normal bir kullanıcıda her kart
/// "Henüz check-in yok / 0" yazıyordu. Harita zaten canlı keşfi yapıyordu.
///
/// Yeni işi net: uygulamanın çekirdek döngüsü olan "kaydet → git → kapat"
/// listesinin evi. Kaydedilen liste daha önce yalnızca Profil'de,
/// fotoğrafların arasında gömülüydü.
///
/// TASARIM KURALI: Bu ekranda kişi avatarı YOK. Hem kartlardan check-in
/// yapmadan profil açılan kapı deliği kapanıyor, hem de "insan tarama"
/// yüzeyi tamamen ortadan kalkıyor.
class MyListPage extends StatefulWidget {
  const MyListPage({super.key});

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  bool _loading = true;
  List<SavedVenue> _pending = const [];
  List<SavedVenue> _visited = const [];
  Position? _position;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Konum yalnızca sıralama için; izin yoksa liste yine çalışır.
    Position? pos;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        pos = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition();
      }
    } catch (_) {
      pos = null;
    }

    final all = await SavedVenuesService.getSaved(uid);
    final pending = all.where((v) => !v.isVisited).toList();
    final visited = all.where((v) => v.isVisited).toList();

    if (pos != null) {
      pending.sort((a, b) {
        final da = SavedVenuesService.distanceMeters(
            pos!.latitude, pos.longitude, a.latitude, a.longitude);
        final db = SavedVenuesService.distanceMeters(
            pos.latitude, pos.longitude, b.latitude, b.longitude);
        return da.compareTo(db);
      });
    }

    if (!mounted) return;
    setState(() {
      _pending = pending;
      _visited = visited;
      _position = pos;
      _loading = false;
    });
  }

  String? _distanceLabel(SavedVenue v) {
    final pos = _position;
    if (pos == null || (v.latitude == 0 && v.longitude == 0)) return null;
    final m = SavedVenuesService.distanceMeters(
        pos.latitude, pos.longitude, v.latitude, v.longitude);
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grey50,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _header()),
                    if (_pending.isEmpty && _visited.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _emptyState(),
                      )
                    else ...[
                      if (_pending.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _sectionTitle(
                            'Gitmek İstediklerim',
                            '${_pending.length} yer',
                            Icons.bookmark_outlined,
                          ),
                        ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _venueCard(_pending[i], false),
                          childCount: _pending.length,
                        ),
                      ),
                      if (_visited.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _sectionTitle(
                            'Gittiklerim',
                            '${_visited.length} tamamlandı',
                            Icons.check_circle_outline,
                          ),
                        ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _venueCard(_visited[i], true),
                          childCount: _visited.length,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Icon(Icons.bookmark_rounded,
              color: AppColors.primary, size: 26),
          const SizedBox(width: 8),
          const Text(
            'Listem',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (_visited.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_visited.length} tamamlandı',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String trailing, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.grey600),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            trailing,
            style: TextStyle(fontSize: 12, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  Widget _venueCard(SavedVenue v, bool isVisited) {
    final distance = _distanceLabel(v);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VenueDetailPage(venueId: v.venueId),
              ),
            );
            _load(); // dönüşte liste tazelensin
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  VenueCoverImage(
                    photoUrl: null,
                    category: v.venueCategory,
                    venueName: v.venueName,
                    height: 120,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                  ),
                  if (isVisited)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 14, color: Color(0xFF3F8F4F)),
                            SizedBox(width: 4),
                            Text(
                              'Gittin',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3F8F4F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.venueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (v.venueCategory.isNotEmpty) ...[
                          Text(
                            v.venueCategory,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.grey600),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (distance != null) ...[
                          const Icon(Icons.near_me,
                              size: 13, color: AppColors.primary),
                          const SizedBox(width: 3),
                          Text(
                            distance,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!isVisited) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Yakınından geçtiğinde sana hatırlatacağız.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.grey500),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bookmark_border_rounded,
              size: 72, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Listen henüz boş',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Gitmek istediğin bir mekanı haritadan listene ekle. '
            'Yakınından geçtiğinde sana hatırlatırız; oraya gidip check-in '
            'yaptığında liste kapanır.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppColors.grey600, height: 1.45),
          ),
        ],
      ),
    );
  }
}
