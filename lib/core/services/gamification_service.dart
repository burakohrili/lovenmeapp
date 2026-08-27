// lib/core/services/gamification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Rozet tanımı
class BadgeDef {
  final String id;
  final String title;
  final String description;
  final String emoji;

  const BadgeDef(this.id, this.title, this.description, this.emoji);
}

/// Check-in sonrası kazanılan ödüller (UI'da göstermek için)
class CheckInReward {
  final int currentStreak;
  final bool streakIncreased;
  final bool streakReset;
  final int level;
  final bool levelUp;
  final List<BadgeDef> newBadges;

  const CheckInReward({
    required this.currentStreak,
    required this.streakIncreased,
    required this.streakReset,
    required this.level,
    required this.levelUp,
    required this.newBadges,
  });

  bool get hasAnything => streakIncreased || levelUp || newBadges.isNotEmpty;
}

/// Mekan keşif oyununun ilerleme katmanı: seri, seviye ve rozetler.
///
/// TASARIM İLKESİ — tek kişilik oynanabilirlik:
/// Buradaki hiçbir mekanik başka kullanıcıya ihtiyaç duymaz. Uygulamada tek
/// kullanıcı olsa bile seri işler, seviye yükselir, rozet kazanılır. Sosyal
/// katman (liderlik, karşılaşma) bunun üstüne bonus olarak gelir.
class GamificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Tüm rozetler. Hepsi tek başına kazanılabilir.
  static const List<BadgeDef> allBadges = [
    BadgeDef('first_step', 'İlk Adım', 'İlk check-in\'ini yaptın', '👣'),
    BadgeDef('explorer_5', 'Kâşif', '5 farklı mekan keşfettin', '🧭'),
    BadgeDef('explorer_15', 'Gezgin', '15 farklı mekan keşfettin', '🗺️'),
    BadgeDef('explorer_30', 'Şehir Kâşifi', '30 farklı mekan keşfettin', '🏙️'),
    BadgeDef('streak_3', 'Düzenli', '3 gün üst üste check-in', '🔥'),
    BadgeDef('streak_7', 'Sadık', '7 gün üst üste check-in', '⚡'),
    BadgeDef('streak_30', 'Efsane', '30 gün üst üste check-in', '👑'),
    BadgeDef('checkin_10', 'Alışkanlık', 'Toplam 10 check-in', '📍'),
    BadgeDef('checkin_50', 'Müdavim', 'Toplam 50 check-in', '🎯'),
    BadgeDef('checkin_100', 'Yüzler Kulübü', 'Toplam 100 check-in', '💯'),
  ];

  static BadgeDef? badgeById(String id) {
    for (final b in allBadges) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Toplam check-in sayısından seviye hesaplar (1'den başlar).
  static int levelFor(int totalCheckIns) {
    if (totalCheckIns >= 100) return 6;
    if (totalCheckIns >= 50) return 5;
    if (totalCheckIns >= 25) return 4;
    if (totalCheckIns >= 10) return 3;
    if (totalCheckIns >= 5) return 2;
    return 1;
  }

  /// Bir sonraki seviye için gereken toplam check-in (son seviyede null).
  static int? nextLevelAt(int level) {
    const thresholds = {1: 5, 2: 10, 3: 25, 4: 50, 5: 100};
    return thresholds[level];
  }

  /// Check-in sonrası seri/seviye/rozet ilerlemesini işler.
  ///
  /// [isNewVenue] bu mekana ilk kez gelinip gelinmediğini belirtir; farklı
  /// mekan sayacı buna göre artar.
  ///
  /// Hata durumunda check-in'i bozmamak için sessizce boş ödül döner —
  /// oyunlaştırma asla check-in akışını engellememeli.
  static Future<CheckInReward> registerCheckIn({
    required String userId,
    required bool isNewVenue,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);

      return await _firestore.runTransaction<CheckInReward>((tx) async {
        final snap = await tx.get(userRef);
        if (!snap.exists) return _empty();

        final data = snap.data() ?? <String, dynamic>{};

        // Check-in akışı totalCheckIns'i BU çağrıdan önce artırıyor; yani
        // buradaki değer bu check-in dahil güncel toplam.
        final currentTotal = (data['totalCheckIns'] as num?)?.toInt() ?? 0;
        final newLevel = levelFor(currentTotal);
        // Seviye atlandı mı: bu check-in'den ÖNCEKİ toplamın seviyesiyle kıyasla.
        final previousLevel = levelFor(currentTotal > 0 ? currentTotal - 1 : 0);

        final uniqueVenues = ((data['uniqueVenuesVisited'] as num?)?.toInt() ?? 0) +
            (isNewVenue ? 1 : 0);

        // --- Seri hesabı ---
        final lastDay = _dayKey(data['lastStreakDate']);
        final todayKey = _dayKey(Timestamp.now());
        final yesterdayKey = _dayKey(
          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
        );

        int currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
        bool streakIncreased = false;
        bool streakReset = false;
        // Seri koruması harcandıysa tek update içinde uygulanır; aynı dokümana
        // birden fazla tx.update çağırmak riskli olduğu için biriktiriyoruz.
        bool freezeUsed = false;

        if (lastDay == todayKey) {
          // Bugün zaten sayıldı; seri değişmez.
          if (currentStreak == 0) currentStreak = 1;
        } else if (lastDay == yesterdayKey) {
          currentStreak += 1;
          streakIncreased = true;
        } else {
          // Seri koruması varsa seriyi kırma, korumayı harca.
          final freezes = (data['streakFreezes'] as num?)?.toInt() ?? 0;
          if (lastDay != null && freezes > 0) {
            currentStreak += 1;
            streakIncreased = true;
            freezeUsed = true;
          } else {
            streakReset = currentStreak > 1;
            currentStreak = 1;
          }
        }

        final longestStreak = (data['longestStreak'] as num?)?.toInt() ?? 0;
        final newLongest =
            currentStreak > longestStreak ? currentStreak : longestStreak;

        // --- Rozetler ---
        final owned = ((data['badges'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();

        final earned = _evaluateBadges(
          totalCheckIns: currentTotal,
          uniqueVenues: uniqueVenues,
          streak: currentStreak,
          owned: owned,
        );

        final updates = <String, dynamic>{
          'currentStreak': currentStreak,
          'longestStreak': newLongest,
          'lastStreakDate': FieldValue.serverTimestamp(),
          'uniqueVenuesVisited': uniqueVenues,
          'level': newLevel,
        };
        if (earned.isNotEmpty) {
          updates['badges'] =
              FieldValue.arrayUnion(earned.map((b) => b.id).toList());
        }
        if (freezeUsed) {
          updates['streakFreezes'] = FieldValue.increment(-1);
        }
        tx.update(userRef, updates);

        return CheckInReward(
          currentStreak: currentStreak,
          streakIncreased: streakIncreased,
          streakReset: streakReset,
          level: newLevel,
          levelUp: newLevel > previousLevel,
          newBadges: earned,
        );
      });
    } catch (_) {
      return _empty();
    }
  }

  /// Kullanıcının ilerleme özetini getirir (profil / ana ekran için).
  static Future<Map<String, dynamic>> getProgress(String userId) async {
    try {
      final snap = await _firestore.collection('users').doc(userId).get();
      final data = snap.data() ?? <String, dynamic>{};
      final total = (data['totalCheckIns'] as num?)?.toInt() ?? 0;
      final level = levelFor(total);

      return {
        'totalCheckIns': total,
        'uniqueVenuesVisited':
            (data['uniqueVenuesVisited'] as num?)?.toInt() ?? 0,
        'currentStreak': (data['currentStreak'] as num?)?.toInt() ?? 0,
        'longestStreak': (data['longestStreak'] as num?)?.toInt() ?? 0,
        'streakFreezes': (data['streakFreezes'] as num?)?.toInt() ?? 0,
        'level': level,
        'nextLevelAt': nextLevelAt(level),
        'badges': ((data['badges'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      };
    } catch (_) {
      return {
        'totalCheckIns': 0,
        'uniqueVenuesVisited': 0,
        'currentStreak': 0,
        'longestStreak': 0,
        'streakFreezes': 0,
        'level': 1,
        'nextLevelAt': 5,
        'badges': <String>[],
      };
    }
  }

  /// Seri korumasını stok olarak ekler (elmas harcamasının karşılığı).
  static Future<bool> grantStreakFreeze(String userId, int count) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'streakFreezes': FieldValue.increment(count),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- yardımcılar ---

  static List<BadgeDef> _evaluateBadges({
    required int totalCheckIns,
    required int uniqueVenues,
    required int streak,
    required Set<String> owned,
  }) {
    final earned = <BadgeDef>[];

    void award(String id, bool condition) {
      if (condition && !owned.contains(id)) {
        final def = badgeById(id);
        if (def != null) earned.add(def);
      }
    }

    award('first_step', totalCheckIns >= 1);
    award('checkin_10', totalCheckIns >= 10);
    award('checkin_50', totalCheckIns >= 50);
    award('checkin_100', totalCheckIns >= 100);
    award('explorer_5', uniqueVenues >= 5);
    award('explorer_15', uniqueVenues >= 15);
    award('explorer_30', uniqueVenues >= 30);
    award('streak_3', streak >= 3);
    award('streak_7', streak >= 7);
    award('streak_30', streak >= 30);

    return earned;
  }

  /// Timestamp'i 'yyyy-MM-dd' anahtarına çevirir; null ise null döner.
  static String? _dayKey(dynamic value) {
    if (value is! Timestamp) return null;
    final d = value.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static CheckInReward _empty() => const CheckInReward(
        currentStreak: 0,
        streakIncreased: false,
        streakReset: false,
        level: 1,
        levelUp: false,
        newBadges: [],
      );
}
