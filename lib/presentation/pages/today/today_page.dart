// lib/presentation/pages/today/today_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/friends_service.dart';
import '../../../core/services/gamification_service.dart';
import '../../../core/services/saved_venues_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/venue_cover_image.dart';
import '../explore_nearby/venue_detail_page.dart';
import '../../../core/services/quest_service.dart';
import '../../../core/services/analytics_service.dart';

/// Tek bir mekan hareketi satırı — kişi değil, MEKAN odaklı.
class _VenueActivity {
  final String venueId;
  final String venueName;
  final String venueCategory;
  final String? photoUrl;
  final DateTime time;

  /// Yalnızca ARKADAŞ hareketinde dolu olur. Yabancıların adı asla yazılmaz.
  final String? friendName;

  const _VenueActivity({
    required this.venueId,
    required this.venueName,
    required this.venueCategory,
    required this.photoUrl,
    required this.time,
    this.friendName,
  });
}

/// "Bugün" sekmesi — Akış'ın yerine geçer.
///
/// ESKİ AKIŞ NEDEN DEĞİŞTİ:
///  - Gönderiler check-in'in otomatik kopyasıydı; kullanıcı hiçbir şey
///    üretmiyordu ("+" butonu yalnızca Harita sekmesine geçiyordu).
///  - İzleyici kitlesi `matches` idi; pivot sonrası çoğu kullanıcıda boştu.
///    `.take(10)` sınırı yüzünden 10+ bağlantısı olan kendi gönderisini bile
///    göremiyordu.
///  - Kalan dating sinyalinin neredeyse tamamı buradaydı: "Burak, 37",
///    kalp/beğeni, çift dokunup beğenme, "Eşleştiklerin…", yabancıya
///    "Mesaj gönder".
///
/// Yeni işi: *şu an ne yapmalıyım*. Üç bağımsız kaynaktan beslenir
/// (ilerlemem, listemdeki yakın yerler, arkadaşlarımın hareketi); biri boşsa
/// diğerleri ekranı ayakta tutar.
///
/// KAPI KURALI: Yabancıların adı/yüzü GÖSTERİLMEZ. Arkadaş hareketi ise
/// karşılıklı rızaya dayandığı için görünür.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _loading = true;
  Map<String, dynamic> _progress = const {};
  List<SavedVenue> _nearbySaved = const [];
  List<_VenueActivity> _friendActivity = const [];
  List<_VenueActivity> _myRecent = const [];
  List<Quest> _quests = const [];
  Map<String, QuestParticipation> _participations = const {};

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

    final progress = await GamificationService.getProgress(uid);
    final quests = await QuestService.openQuests();
    final participations = await QuestService.myParticipations(uid);
    final nearby = await _loadNearbySaved(uid);
    final friends = await _loadFriendActivity();
    final mine = await _loadMyRecent(uid);

    if (!mounted) return;
    setState(() {
      _progress = progress;
      _quests = quests;
      _participations = participations;
      _nearbySaved = nearby;
      _friendActivity = friends;
      _myRecent = mine;
      _loading = false;
    });
  }

  Future<List<SavedVenue>> _loadNearbySaved(String uid) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return const [];
      }
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return const [];

      return await SavedVenuesService.nearbySaved(
        userId: uid,
        latitude: pos.latitude,
        longitude: pos.longitude,
        radiusMeters: 1500,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<_VenueActivity>> _loadFriendActivity() async {
    try {
      final friendIds = await FriendsService.getFriendIds();
      if (friendIds.isEmpty) return const [];

      // Firestore whereIn sınırı; en fazla 30 arkadaş sorgulanır.
      final ids = friendIds.take(30).toList();
      final snap = await FirebaseFirestore.instance
          .collection('feed_posts')
          .where('userId', whereIn: ids)
          .orderBy('checkInTime', descending: true)
          .limit(25)
          .get();

      // Gizlilik: "arkadaşlarım hareketimi görsün" kapalı olan arkadaşların
      // check-in'leri akışta gösterilmez.
      final sharing = <String, bool>{};
      await Future.wait(ids.map((id) async {
        sharing[id] = await FriendsService.sharesActivity(id);
      }));

      final out = <_VenueActivity>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        if (sharing[(d['userId'] ?? '').toString()] == false) continue;
        final ts = d['checkInTime'];
        out.add(_VenueActivity(
          venueId: (d['venueId'] ?? '').toString(),
          venueName: (d['venueName'] ?? '').toString(),
          venueCategory: (d['venueCategory'] ?? '').toString(),
          photoUrl: d['postImage'] as String?,
          time: ts is Timestamp ? ts.toDate() : DateTime.now(),
          friendName: (d['userName'] ?? '').toString(),
        ));
      }
      return out;
    } catch (e) {
      return const [];
    }
  }

  Future<List<_VenueActivity>> _loadMyRecent(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('check_ins')
          .where('userId', isEqualTo: uid)
          .orderBy('checkInTime', descending: true)
          .limit(5)
          .get();

      return snap.docs.map((doc) {
        final d = doc.data();
        final ts = d['checkInTime'];
        return _VenueActivity(
          venueId: (d['venueId'] ?? '').toString(),
          venueName: (d['venueName'] ?? '').toString(),
          venueCategory: (d['venueCategory'] ?? '').toString(),
          photoUrl: d['photoUrl'] as String?,
          time: ts is Timestamp ? ts.toDate() : DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    return '${diff.inDays} gün önce';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _progressStrip(),
          if (_quests.isNotEmpty) ...[
            _sectionTitle('Bugünün görevleri', Icons.flag_rounded),
            ..._quests.take(5).map(_questCard),
          ],
          if (_nearbySaved.isNotEmpty) ...[
            _sectionTitle('Listendeki yakın yerler', Icons.near_me_rounded),
            ..._nearbySaved.take(3).map(_savedRow),
          ],
          if (_friendActivity.isNotEmpty) ...[
            _sectionTitle('Arkadaşlarının hareketi', Icons.people_alt_rounded),
            ..._friendActivity.take(10).map((a) => _activityCard(a)),
          ],
          if (_myRecent.isNotEmpty) ...[
            _sectionTitle('Son check-in\'lerin', Icons.history_rounded),
            ..._myRecent.map((a) => _activityCard(a)),
          ],
          if (_quests.isEmpty &&
              _nearbySaved.isEmpty &&
              _friendActivity.isEmpty &&
              _myRecent.isEmpty)
            _firstSteps(),
        ],
      ),
    );
  }

  Widget _progressStrip() {
    final streak = _progress['currentStreak'] ?? 0;
    final level = _progress['level'] ?? 1;
    final venues = _progress['uniqueVenuesVisited'] ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _stat('🔥', '$streak', 'gün seri'),
          _divider(),
          _stat('⭐', GamificationService.levelTitle(level), 'seviye'),
          _divider(),
          _stat('📍', '$venues', 'mekan'),
        ],
      ),
    );
  }

  Widget _stat(String emoji, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: Colors.white.withOpacity(0.25),
      );

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
        ],
      ),
    );
  }

  Widget _savedRow(SavedVenue v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openVenue(v.venueId),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.bookmark_rounded,
                    color: AppColors.primary, size: 20),
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
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Listende — check-in ile tamamla',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.grey600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.grey400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activityCard(_VenueActivity a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openVenue(a.venueId),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VenueCoverImage(
                photoUrl: a.photoUrl,
                category: a.venueCategory,
                venueName: a.venueName,
                height: 130,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.venueName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            // Yaş YOK, beğeni YOK. Yabancı ise isim de yok.
                            a.friendName != null && a.friendName!.isNotEmpty
                                ? '${a.friendName} burada — ${_timeAgo(a.time)}'
                                : 'Check-in — ${_timeAgo(a.time)}',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.grey600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.grey400),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questCard(Quest q) {
    final p = _participations[q.id];
    final joined = p != null;
    final done = p?.isCompleted ?? false;
    final progress = p?.progress ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done
                ? const Color(0xFF3F8F4F).withOpacity(0.4)
                : AppColors.primary.withOpacity(0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle_rounded : Icons.flag_rounded,
                  size: 18,
                  color: done ? const Color(0xFF3F8F4F) : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    q.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (q.isVenueOffer)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'MEKAN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8A6B00),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              q.description,
              style: TextStyle(
                  fontSize: 13, color: AppColors.grey600, height: 1.35),
            ),
            if (q.rewardText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      q.rewardText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (done && p?.redemptionCode != null)
              _redemptionCode(p!.redemptionCode!)
            else if (done)
              const Text(
                'Tamamlandı 🎯',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3F8F4F),
                ),
              )
            else if (joined)
              _progressBar(progress, q.goalCount)
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _join(q),
                  child: const Text('Katıl'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(int progress, int goal) {
    final ratio = goal <= 0 ? 0.0 : (progress / goal).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: AppColors.grey500.withOpacity(0.15),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$progress / $goal',
          style: TextStyle(fontSize: 12, color: AppColors.grey600),
        ),
      ],
    );
  }

  /// Mekanda personele gösterilecek kullanım kodu.
  ///
  /// ÖNEMLİ: Bu kod uygulama İÇİNDE hiçbir şey açmaz. App Store 3.1.1,
  /// kod/QR ile uygulama içi özellik açılmasını yasaklıyor; buradaki kod
  /// yalnızca mekanda gerçek dünya avantajı için gösterilir (3.1.3(e)).
  Widget _redemptionCode(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            'Mekanda göster',
            style: TextStyle(fontSize: 11, color: AppColors.grey600),
          ),
          const SizedBox(height: 3),
          Text(
            code,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _join(Quest q) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await QuestService.join(uid, q);
    AnalyticsService.questJoined(q.id, q.type);
    _load();
  }

  Widget _firstSteps() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
      child: Column(
        children: [
          const Icon(Icons.explore_rounded,
              size: 64, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Haydi başlayalım',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Haritadan gitmek istediğin bir mekanı listene ekle. '
            'Yakınından geçtiğinde hatırlatırız; oraya gidip check-in '
            'yaptığında serin başlar ve o mekanın topluluğu sana açılır.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppColors.grey600, height: 1.45),
          ),
        ],
      ),
    );
  }

  void _openVenue(String venueId) {
    if (venueId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueDetailPage(venueId: venueId)),
    ).then((_) => _load());
  }
}
