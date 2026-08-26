// lib/core/services/leaderboard_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Liderlik tablosundaki tek satır.
class LeaderboardEntry {
  final String userId;
  final String userName;
  final String? userPhoto;
  final int checkInCount;
  final int rank;
  final bool isCurrentUser;

  const LeaderboardEntry({
    required this.userId,
    required this.userName,
    required this.userPhoto,
    required this.checkInCount,
    required this.rank,
    required this.isCurrentUser,
  });
}

/// Mekan bazlı liderlik tablosu.
///
/// TASARIM İLKESİ — asla global sıralama:
/// Mutlak/global sıralama, tepeye ulaşamayacak kullanıcıların büyük
/// çoğunluğunu demotive eder ve retention'a zarar verir. Bu yüzden sıralama
/// yalnızca **tek bir mekan** havuzunda yapılır. Küçük havuzda herkes
/// kendini üst sıralarda görür; kullanıcı her zaman kazanabileceği bir
/// tabloda olur.
///
/// Ayrıca kullanıcı ilk N'e giremese bile kendi satırı her zaman eklenir —
/// "listede yokum" hissi oluşmaz.
class LeaderboardService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Bu mekanın liderlik tablosu: en çok check-in yapanlar.
  ///
  /// [currentUserId] verilirse kullanıcının satırı, ilk [limit] içinde
  /// olmasa bile sona eklenir.
  static Future<List<LeaderboardEntry>> getVenueLeaderboard(
    String venueId, {
    String? currentUserId,
    int limit = 10,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('check_ins')
          .where('venueId', isEqualTo: venueId)
          .limit(500)
          .get();

      if (snapshot.docs.isEmpty) return [];

      // Kullanıcı bazında check-in say
      final counts = <String, int>{};
      final names = <String, String>{};
      final photos = <String, String?>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] as String?;
        if (userId == null || userId.isEmpty) continue;

        counts[userId] = (counts[userId] ?? 0) + 1;
        names[userId] = (data['userName'] as String?) ?? 'İsimsiz';
        photos[userId] ??= data['userPhoto'] as String?;
      }

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final result = <LeaderboardEntry>[];
      for (var i = 0; i < sorted.length && i < limit; i++) {
        final e = sorted[i];
        result.add(LeaderboardEntry(
          userId: e.key,
          userName: names[e.key] ?? 'İsimsiz',
          userPhoto: photos[e.key],
          checkInCount: e.value,
          rank: i + 1,
          isCurrentUser: e.key == currentUserId,
        ));
      }

      // Kullanıcı ilk N'de değilse kendi satırını ekle
      if (currentUserId != null &&
          !result.any((e) => e.isCurrentUser) &&
          counts.containsKey(currentUserId)) {
        final index = sorted.indexWhere((e) => e.key == currentUserId);
        if (index >= 0) {
          result.add(LeaderboardEntry(
            userId: currentUserId,
            userName: names[currentUserId] ?? 'İsimsiz',
            userPhoto: photos[currentUserId],
            checkInCount: counts[currentUserId]!,
            rank: index + 1,
            isCurrentUser: true,
          ));
        }
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  /// Kullanıcının bu mekandaki sırası ve toplam katılımcı sayısı.
  /// Sıra bulunamazsa null döner.
  static Future<Map<String, int>?> getUserVenueRank(
    String venueId,
    String userId,
  ) async {
    try {
      final board = await getVenueLeaderboard(
        venueId,
        currentUserId: userId,
        limit: 1000,
      );
      if (board.isEmpty) return null;

      final mine = board.where((e) => e.isCurrentUser).toList();
      if (mine.isEmpty) return null;

      return {
        'rank': mine.first.rank,
        'total': board.length,
        'checkIns': mine.first.checkInCount,
      };
    } catch (_) {
      return null;
    }
  }
}
