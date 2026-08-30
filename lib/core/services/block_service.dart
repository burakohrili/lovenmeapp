// lib/core/services/block_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Kullanıcı engelleme — TEK kaynak.
///
/// NEDEN VAR:
/// Kodda dört ayrı engelleme deposu vardı ve üçü işe yaramıyordu:
///   1. `users/{uid}.blockedUsers[]`  → tek çalışan; check-in listesini filtreliyor
///   2. `users/{uid}/blocked_users/…` → alt koleksiyonun Firestore kuralı YOKTU,
///      yazma reddediliyordu; hata boş bir `catch` içinde yutulup kullanıcıya
///      "Kullanıcı engellendi" deniyordu. Yani profilden engelleme sahteydi.
///   3. üst düzey `blocked_users`      → okunuyordu, hiç yazılmıyordu
///   4. `blocks`                       → kuralı vardı, kodu yoktu
/// Ayrıca sohbetteki "Engelle" butonu hiçbir engelleme kaydı yazmıyor,
/// yalnızca konuşmayı siliyordu — karşı taraf anında yeni istek gönderebiliyordu.
///
/// Apple Guideline 1.2, kullanıcıların taciz eden kişileri engelleyebilmesini
/// şart koşuyor; inceleme sırasında bu yollar test edilir.
class BlockService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Kullanıcıyı engeller: listeye ekler ve aradaki bağlantıyı pasifleştirir.
  static Future<bool> block(String targetUserId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || targetUserId.isEmpty || me.uid == targetUserId) {
      return false;
    }

    try {
      await _firestore.collection('users').doc(me.uid).update({
        'blockedUsers': FieldValue.arrayUnion([targetUserId]),
      });

      await _deactivateMatches(me.uid, targetUserId);
      return true;
    } catch (e) {
      debugPrint('Engelleme basarisiz: $e');
      return false;
    }
  }

  static Future<bool> unblock(String targetUserId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return false;

    try {
      await _firestore.collection('users').doc(me.uid).update({
        'blockedUsers': FieldValue.arrayRemove([targetUserId]),
      });
      return true;
    } catch (e) {
      debugPrint('Engel kaldirma basarisiz: $e');
      return false;
    }
  }

  /// Ben bu kişiyi engelledim mi?
  static Future<bool> hasBlocked(String targetUserId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(me.uid).get();
      final list = List<String>.from(doc.data()?['blockedUsers'] ?? const []);
      return list.contains(targetUserId);
    } catch (_) {
      return false;
    }
  }

  /// İki yönlü kontrol: taraflardan biri diğerini engellemişse true.
  ///
  /// Bağlantı isteği göndermeden önce bu kontrol edilmeli; aksi halde
  /// engellenen kişi engelleyene istek göndermeye devam edebilir.
  static Future<bool> isBlockedEitherWay(String otherUserId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return false;
    try {
      final results = await Future.wait([
        _firestore.collection('users').doc(me.uid).get(),
        _firestore.collection('users').doc(otherUserId).get(),
      ]);

      final mine =
          List<String>.from(results[0].data()?['blockedUsers'] ?? const []);
      if (mine.contains(otherUserId)) return true;

      final theirs =
          List<String>.from(results[1].data()?['blockedUsers'] ?? const []);
      return theirs.contains(me.uid);
    } catch (_) {
      // Emin olamıyorsak engellenmemiş say — aksi halde geçici bir ağ hatası
      // kullanıcıyı kilitlerdi.
      return false;
    }
  }

  static Future<void> _deactivateMatches(String uid, String otherId) async {
    try {
      // Firestore'da OR yok; iki yönü ayrı sorguluyoruz.
      final asUser1 = await _firestore
          .collection('matches')
          .where('user1Id', isEqualTo: uid)
          .where('user2Id', isEqualTo: otherId)
          .get();
      final asUser2 = await _firestore
          .collection('matches')
          .where('user1Id', isEqualTo: otherId)
          .where('user2Id', isEqualTo: uid)
          .get();

      for (final doc in [...asUser1.docs, ...asUser2.docs]) {
        await doc.reference.update({'isActive': false});
      }
    } catch (e) {
      debugPrint('Baglanti pasiflestirilemedi: $e');
    }
  }
}
