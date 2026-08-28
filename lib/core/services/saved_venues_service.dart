// lib/core/services/saved_venues_service.dart

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Kullanıcının "gitmek istiyorum" listesindeki bir mekan.
class SavedVenue {
  final String id;
  final String venueId;
  final String venueName;
  final String venueCategory;
  final double latitude;
  final double longitude;
  final String vicinity;
  final DateTime? savedAt;
  final DateTime? visitedAt;
  final String? note;

  const SavedVenue({
    required this.id,
    required this.venueId,
    required this.venueName,
    required this.venueCategory,
    required this.latitude,
    required this.longitude,
    required this.vicinity,
    required this.savedAt,
    required this.visitedAt,
    required this.note,
  });

  bool get isVisited => visitedAt != null;

  factory SavedVenue.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return SavedVenue(
      id: doc.id,
      venueId: (d['venueId'] ?? '').toString(),
      venueName: (d['venueName'] ?? '').toString(),
      venueCategory: (d['venueCategory'] ?? '').toString(),
      latitude: (d['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (d['longitude'] as num?)?.toDouble() ?? 0,
      vicinity: (d['vicinity'] ?? '').toString(),
      savedAt: (d['savedAt'] as Timestamp?)?.toDate(),
      visitedAt: (d['visitedAt'] as Timestamp?)?.toDate(),
      note: d['note'] as String?,
    );
  }
}

/// "Gitmek İstiyorum" listesi.
///
/// NEDEN VAR:
/// İnsanlar sosyal medyada bir mekan görüp kaydediyor ve asla gitmiyor
/// (literatürde "digital hoarding": kaydetmek, yapmanın yerine geçiyor).
/// Bu servis döngünün ilk halkası; döngüyü kapatan şey ise doğrulanmış
/// check-in — mekana gerçekten gidildiğinde kayıt "gidildi"ye taşınır.
///
/// Mevcut favori (kalp) sisteminden FARKLI: favoriler "gittiğim ve sevdiğim
/// yer" anlamına gelir ve check-in şartına baglidir; bu liste ise
/// "henüz gitmediğim ama gitmek istediğim yer".
class SavedVenuesService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'saved_venues';

  /// Mekanı listeye ekler. Zaten varsa tekrar eklemez.
  static Future<bool> save({
    required String userId,
    required String venueId,
    required String venueName,
    required String venueCategory,
    required double latitude,
    required double longitude,
    String vicinity = '',
    String? note,
  }) async {
    try {
      final existing = await _findDoc(userId, venueId);
      if (existing != null) return true;

      await _firestore.collection(_collection).add({
        'userId': userId,
        'venueId': venueId,
        'venueName': venueName,
        'venueCategory': venueCategory,
        'latitude': latitude,
        'longitude': longitude,
        'vicinity': vicinity,
        'savedAt': FieldValue.serverTimestamp(),
        'visitedAt': null,
        'note': note,
        // İleride Instagram/TikTok linkinden içe aktarma eklenince 'link' olacak.
        'source': 'app',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> remove(String userId, String venueId) async {
    try {
      final doc = await _findDoc(userId, venueId);
      if (doc == null) return false;
      await doc.reference.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isSaved(String userId, String venueId) async {
    final doc = await _findDoc(userId, venueId);
    return doc != null;
  }

  /// Listedeki tüm kayıtlar. [onlyPending] true ise sadece henüz gidilmemişler.
  static Future<List<SavedVenue>> getSaved(
    String userId, {
    bool onlyPending = false,
  }) async {
    try {
      final snap = await _firestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .limit(200)
          .get();

      var list = snap.docs.map(SavedVenue.fromDoc).toList();
      if (onlyPending) list = list.where((v) => !v.isVisited).toList();

      // En yeni kayıt üstte (sıralamayı istemci tarafında yapıyoruz ki
      // ek Firestore index'i gerekmesin).
      list.sort((a, b) {
        final x = a.savedAt, y = b.savedAt;
        if (x == null || y == null) return 0;
        return y.compareTo(x);
      });
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Check-in ile döngüyü kapatır. Kayıt listede yoksa false döner.
  static Future<bool> markVisited(String userId, String venueId) async {
    try {
      final doc = await _findDoc(userId, venueId);
      if (doc == null) return false;

      final already = (doc.data() as Map<String, dynamic>)['visitedAt'];
      if (already != null) return false; // zaten kapatılmış

      await doc.reference.update({'visitedAt': FieldValue.serverTimestamp()});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Kaç kayıt gidilerek kapatıldı (rozetler için).
  static Future<int> visitedCount(String userId) async {
    try {
      final all = await getSaved(userId);
      return all.where((v) => v.isVisited).length;
    } catch (_) {
      return 0;
    }
  }

  /// Verilen konuma [radiusMeters] içinde olan, henüz gidilmemiş kayıtlar.
  /// En yakın olan başta döner. Hatırlatma kartı bunu kullanır.
  static Future<List<SavedVenue>> nearbySaved({
    required String userId,
    required double latitude,
    required double longitude,
    double radiusMeters = 500,
  }) async {
    try {
      final pending = await getSaved(userId, onlyPending: true);
      final withDistance = <MapEntry<SavedVenue, double>>[];

      for (final v in pending) {
        if (v.latitude == 0 && v.longitude == 0) continue;
        final d = distanceMeters(latitude, longitude, v.latitude, v.longitude);
        if (d <= radiusMeters) withDistance.add(MapEntry(v, d));
      }

      withDistance.sort((a, b) => a.value.compareTo(b.value));
      return withDistance.map((e) => e.key).toList();
    } catch (_) {
      return [];
    }
  }

  /// İki koordinat arası mesafe (metre) — Haversine.
  static double distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;

  static Future<DocumentSnapshot?> _findDoc(
      String userId, String venueId) async {
    try {
      final snap = await _firestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .where('venueId', isEqualTo: venueId)
          .limit(1)
          .get();
      return snap.docs.isEmpty ? null : snap.docs.first;
    } catch (_) {
      return null;
    }
  }
}
