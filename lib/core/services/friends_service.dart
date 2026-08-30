// lib/core/services/friends_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Bir arkadaşlık bağı ve onu mekanlar üzerinden anlatan metrikler.
class FriendLink {
  final String userId;
  final String name;
  final String? photoUrl;

  /// Kaç kez aynı mekanda bulunuldu.
  final int commonCheckIns;

  /// En çok ortak olunan mekanın adı.
  final String? topVenueName;

  const FriendLink({
    required this.userId,
    required this.name,
    required this.photoUrl,
    this.commonCheckIns = 0,
    this.topVenueName,
  });
}

/// Arkadaşlık katmanı.
///
/// NEDEN VAR:
/// Kodda arkadaşlık kavramı HİÇ yoktu — `friends`, `following`, `followers`,
/// `groups` diye tek bir alan bile geçmiyordu. Kullanıcılar arası tek ilişki
/// `matches` koleksiyonuydu; yani "arkadaş" aslında zaten vardı, ama adı
/// **eşleşme**, dili dating idi ve ilişkiye dair hiçbir metrik yoktu.
///
/// TASARIM KURALI — yabancı ile arkadaş ayrımı:
///   yabancı = mevcudiyet kapısı (bir mekanın topluluğunu görmek için oraya
///             check-in yapmış olmak gerekir)
///   arkadaş = rıza (iki taraf da kabul etti)
/// Arkadaşın gerçek dünya hareketini görmek yabancı taramak değildir; bu
/// yüzden arkadaş etkinliği kapının dışında kalır.
///
/// Firestore tarafında `matches` koleksiyonu AYNEN kalır (Android yayında,
/// koleksiyon adı değişmez). Değişen yalnızca anlam ve arayüz.
class FriendsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Kullanıcının arkadaşlarının kimlikleri.
  ///
  /// Firestore'da OR yok; iki tarafı ayrı sorgulayıp birleştiriyoruz.
  /// (Eskiden sohbet sağlayıcısı bunun yerine TÜM koleksiyonu dinliyordu.)
  static Future<List<String>> getFriendIds() async {
    final me = _auth.currentUser?.uid;
    if (me == null) return const [];

    try {
      final results = await Future.wait([
        _firestore
            .collection('matches')
            .where('isActive', isEqualTo: true)
            .where('user1Id', isEqualTo: me)
            .limit(200)
            .get(),
        _firestore
            .collection('matches')
            .where('isActive', isEqualTo: true)
            .where('user2Id', isEqualTo: me)
            .limit(200)
            .get(),
      ]);

      final ids = <String>{};
      for (final doc in results[0].docs) {
        final id = (doc.data()['user2Id'] ?? '').toString();
        if (id.isNotEmpty) ids.add(id);
      }
      for (final doc in results[1].docs) {
        final id = (doc.data()['user1Id'] ?? '').toString();
        if (id.isNotEmpty) ids.add(id);
      }
      ids.remove(me);
      return ids.toList();
    } catch (e) {
      debugPrint('Arkadas listesi alinamadi: $e');
      return const [];
    }
  }

  /// İki kullanıcı arkadaş mı?
  static Future<bool> isFriend(String otherUserId) async {
    final ids = await getFriendIds();
    return ids.contains(otherUserId);
  }

  /// Ortak mekan metrikleri — arkadaş profilinde gösterilir.
  ///
  /// Demografik hiçbir şey döndürmez; ilişki yalnızca birlikte bulunulan
  /// yerlerle anlatılır.
  static Future<({int commonCheckIns, List<String> venueNames})>
      commonVenues(String otherUserId) async {
    final me = _auth.currentUser?.uid;
    if (me == null) return (commonCheckIns: 0, venueNames: <String>[]);

    try {
      // Her iki kullanıcının son 30 günlük geçmişini alıp kesiştiriyoruz.
      final results = await Future.wait([
        _firestore
            .collection('check_in_history')
            .where('userId', isEqualTo: me)
            .limit(300)
            .get(),
        _firestore
            .collection('check_in_history')
            .where('userId', isEqualTo: otherUserId)
            .limit(300)
            .get(),
      ]);

      final mine = <String, String>{}; // venueId -> venueName
      for (final d in results[0].docs) {
        final data = d.data();
        final id = (data['venueId'] ?? '').toString();
        if (id.isNotEmpty) mine[id] = (data['venueName'] ?? '').toString();
      }

      final counts = <String, int>{};
      for (final d in results[1].docs) {
        final id = (d.data()['venueId'] ?? '').toString();
        if (id.isEmpty || !mine.containsKey(id)) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return (
        commonCheckIns: counts.values.fold<int>(0, (a, b) => a + b),
        venueNames: sorted
            .take(3)
            .map((e) => mine[e.key] ?? '')
            .where((n) => n.isNotEmpty)
            .toList(),
      );
    } catch (e) {
      debugPrint('Ortak mekan hesabi basarisiz: $e');
      return (commonCheckIns: 0, venueNames: <String>[]);
    }
  }

  /// Kullanıcı, check-in'lerinin arkadaşlarına görünmesini istiyor mu?
  ///
  /// Varsayılan açık; ayarlardan kapatılabilir.
  static Future<bool> sharesActivity(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data()?['shareActivityWithFriends'] ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> setSharesActivity(bool value) async {
    final me = _auth.currentUser?.uid;
    if (me == null) return false;
    try {
      await _firestore.collection('users').doc(me).update({
        'shareActivityWithFriends': value,
      });
      return true;
    } catch (e) {
      debugPrint('Paylasim tercihi kaydedilemedi: $e');
      return false;
    }
  }
}
