// lib/core/services/quest_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Bir görevin hedef tipi.
enum QuestGoalKind {
  /// Belirli bir mekana check-in.
  checkin,

  /// N farklı mekana check-in.
  distinctVenues,

  /// Belirli bir kategoride N check-in.
  category,
}

/// Ödül tipi.
enum QuestRewardKind {
  /// Yalnızca ilerleme/rozet — hiçbir işletme anlaşması gerektirmez.
  progress,

  /// Mekanın verdiği gerçek dünya avantajı (kod ile kullanılır).
  venueOffer,
}

/// Görev / kampanya.
///
/// TEK ŞEMA, İKİ TİP:
///  - `platform`: LoveNMe'nin kendi görevleri. Hiçbir işletme imzası
///    gerektirmez, ilk günden doludur, tek kişiyle oynanır.
///  - `venue`: bir mekanın boş saatleri için yayınladığı kampanya.
///
/// NEDEN İKİSİ AYNI ŞEMADA:
/// Kampanya pazaryeri iki taraflıdır ve soğuk başlangıçta ölür — imzalı mekan
/// yoksa ekran boş kalır. Bu, eski Akış sekmesinin hastalığıydı. Platform
/// görevleri aynı kartla aynı ekrana düştüğü için yüzey ilk günden çalışır;
/// işletme geldikçe zenginleşir.
///
/// ŞANSA DAYALI ÖDÜL YOKTUR: çekiliş, App Store 5.3.1/5.3.2 kapsamına girer
/// (resmî kurallar + "Apple sponsor değildir" ibaresi + yerel piyango
/// mevzuatı). Görevler deterministiktir: "şu saatte git, şunu al".
class Quest {
  final String id;
  final String type; // 'platform' | 'venue'
  final String title;
  final String description;
  final String? coverUrl;

  final String? venueId;
  final String? venueName;

  /// Mekanın BEYAN ettiği boş saat penceresi.
  /// (Google Places "popular times" alanını resmî API'de vermiyor; tahmin
  ///  etmek yerine mekana sorduruyoruz.)
  final List<int> days; // 1=Pazartesi ... 7=Pazar
  final String? startTime; // 'HH:mm'
  final String? endTime;

  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;

  final QuestGoalKind goalKind;
  final int goalCount;
  final String? goalCategory;

  final QuestRewardKind rewardKind;
  final String rewardText;

  final int quotaTotal;
  final int quotaPerUser;

  const Quest({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.coverUrl,
    this.venueId,
    this.venueName,
    this.days = const [],
    this.startTime,
    this.endTime,
    this.startDate,
    this.endDate,
    this.isActive = true,
    this.goalKind = QuestGoalKind.checkin,
    this.goalCount = 1,
    this.goalCategory,
    this.rewardKind = QuestRewardKind.progress,
    this.rewardText = '',
    this.quotaTotal = 0,
    this.quotaPerUser = 1,
  });

  bool get isVenueOffer => rewardKind == QuestRewardKind.venueOffer;

  /// Görev şu anda geçerli mi (tarih + gün + saat penceresi)?
  bool isOpenAt(DateTime now) {
    if (!isActive) return false;
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;

    if (days.isNotEmpty && !days.contains(now.weekday)) return false;

    if (startTime != null && endTime != null) {
      final minutes = now.hour * 60 + now.minute;
      final s = _toMinutes(startTime!);
      final e = _toMinutes(endTime!);
      if (s == null || e == null) return true;
      // Gece yarısını aşan pencere (ör. 22:00-02:00)
      if (e < s) return minutes >= s || minutes <= e;
      return minutes >= s && minutes <= e;
    }
    return true;
  }

  static int? _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  factory Quest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final window = (d['window'] as Map<String, dynamic>?) ?? const {};
    final goal = (d['goal'] as Map<String, dynamic>?) ?? const {};
    final reward = (d['reward'] as Map<String, dynamic>?) ?? const {};
    final quota = (d['quota'] as Map<String, dynamic>?) ?? const {};

    QuestGoalKind goalKind;
    switch ((goal['kind'] ?? 'checkin').toString()) {
      case 'distinct_venues':
        goalKind = QuestGoalKind.distinctVenues;
        break;
      case 'category':
        goalKind = QuestGoalKind.category;
        break;
      default:
        goalKind = QuestGoalKind.checkin;
    }

    return Quest(
      id: doc.id,
      type: (d['type'] ?? 'platform').toString(),
      title: (d['title'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      coverUrl: d['coverUrl'] as String?,
      venueId: d['venueId'] as String?,
      venueName: d['venueName'] as String?,
      days: ((window['days'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      startTime: window['startTime'] as String?,
      endTime: window['endTime'] as String?,
      startDate: (d['startDate'] as Timestamp?)?.toDate(),
      endDate: (d['endDate'] as Timestamp?)?.toDate(),
      isActive: d['isActive'] ?? true,
      goalKind: goalKind,
      goalCount: (goal['count'] as num?)?.toInt() ?? 1,
      goalCategory: goal['category'] as String?,
      rewardKind: (reward['kind'] ?? 'progress').toString() == 'venue_offer'
          ? QuestRewardKind.venueOffer
          : QuestRewardKind.progress,
      rewardText: (reward['text'] ?? '').toString(),
      quotaTotal: (quota['total'] as num?)?.toInt() ?? 0,
      quotaPerUser: (quota['perUser'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Kullanıcının bir göreve katılımı.
class QuestParticipation {
  final String id;
  final String questId;
  final int progress;
  final DateTime? completedAt;
  final DateTime? redeemedAt;
  final String? redemptionCode;

  const QuestParticipation({
    required this.id,
    required this.questId,
    required this.progress,
    this.completedAt,
    this.redeemedAt,
    this.redemptionCode,
  });

  bool get isCompleted => completedAt != null;
  bool get isRedeemed => redeemedAt != null;

  factory QuestParticipation.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return QuestParticipation(
      id: doc.id,
      questId: (d['questId'] ?? '').toString(),
      progress: (d['progress'] as num?)?.toInt() ?? 0,
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      redeemedAt: (d['redeemedAt'] as Timestamp?)?.toDate(),
      redemptionCode: d['redemptionCode'] as String?,
    );
  }
}

/// Görev ve kampanya katmanı.
class QuestService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Şu anda açık olan görevler.
  static Future<List<Quest>> openQuests() async {
    try {
      final snap = await _firestore
          .collection('quests')
          .where('isActive', isEqualTo: true)
          .limit(50)
          .get();

      final now = DateTime.now();
      return snap.docs
          .map(Quest.fromDoc)
          .where((q) => q.isOpenAt(now))
          .toList();
    } catch (e) {
      debugPrint('Gorevler alinamadi: $e');
      return const [];
    }
  }

  /// Kullanıcının katıldığı görevler (questId -> katılım).
  static Future<Map<String, QuestParticipation>> myParticipations(
      String userId) async {
    try {
      final snap = await _firestore
          .collection('quest_participations')
          .where('userId', isEqualTo: userId)
          .limit(200)
          .get();

      return {
        for (final doc in snap.docs)
          QuestParticipation.fromDoc(doc).questId:
              QuestParticipation.fromDoc(doc)
      };
    } catch (e) {
      debugPrint('Katilimlar alinamadi: $e');
      return const {};
    }
  }

  /// Göreve katıl.
  static Future<bool> join(String userId, Quest quest) async {
    try {
      final existing = await _findParticipation(userId, quest.id);
      if (existing != null) return true;

      await _firestore.collection('quest_participations').add({
        'userId': userId,
        'questId': quest.id,
        'venueId': quest.venueId,
        'joinedAt': FieldValue.serverTimestamp(),
        'progress': 0,
        'completedAt': null,
        'redeemedAt': null,
        'redemptionCode': null,
      });
      return true;
    } catch (e) {
      debugPrint('Goreve katilinamadi: $e');
      return false;
    }
  }

  /// Check-in sonrası ilerlemeyi işler; tamamlananların listesini döner.
  ///
  /// Check-in akışından çağrılır — "Gitmek İstiyorum" listesinin kapanışıyla
  /// aynı desende.
  static Future<List<Quest>> registerCheckIn({
    required String userId,
    required String venueId,
    required String venueCategory,
    required bool isNewVenue,
  }) async {
    final completed = <Quest>[];
    try {
      final quests = await openQuests();
      if (quests.isEmpty) return completed;

      final participations = await myParticipations(userId);
      final now = DateTime.now();

      for (final quest in quests) {
        final p = participations[quest.id];
        if (p == null || p.isCompleted) continue;

        // Bu check-in bu görevi ilerletiyor mu?
        bool counts;
        switch (quest.goalKind) {
          case QuestGoalKind.checkin:
            counts = quest.venueId == null || quest.venueId == venueId;
            break;
          case QuestGoalKind.distinctVenues:
            counts = isNewVenue;
            break;
          case QuestGoalKind.category:
            counts = quest.goalCategory != null &&
                venueCategory.toLowerCase() ==
                    quest.goalCategory!.toLowerCase();
            break;
        }
        if (!counts) continue;
        if (!quest.isOpenAt(now)) continue;

        final newProgress = p.progress + 1;
        final isDone = newProgress >= quest.goalCount;

        final doc = await _findParticipation(userId, quest.id);
        if (doc == null) continue;

        await doc.reference.update({
          'progress': newProgress,
          if (isDone) 'completedAt': FieldValue.serverTimestamp(),
          if (isDone && quest.isVenueOffer)
            'redemptionCode': _generateCode(userId, quest.id),
        });

        if (isDone) completed.add(quest);
      }
    } catch (e) {
      debugPrint('Gorev ilerlemesi islenemedi: $e');
    }
    return completed;
  }

  /// Mekanda gösterilecek kullanım kodu.
  ///
  /// ÖNEMLİ: Bu kod uygulama İÇİNDE hiçbir şey açmaz. App Store 3.1.1,
  /// QR/kod ile uygulama içi özellik açılmasını yasaklıyor; buradaki kod
  /// yalnızca mekanda gerçek dünya avantajı için personele gösterilir
  /// (3.1.3(e) kapsamı).
  static String _generateCode(String userId, String questId) {
    final seed = '$userId$questId${DateTime.now().millisecondsSinceEpoch}';
    final hash = seed.hashCode.abs().toString().padLeft(6, '0');
    return hash.substring(hash.length - 6);
  }

  static Future<DocumentSnapshot?> _findParticipation(
      String userId, String questId) async {
    try {
      final snap = await _firestore
          .collection('quest_participations')
          .where('userId', isEqualTo: userId)
          .where('questId', isEqualTo: questId)
          .limit(1)
          .get();
      return snap.docs.isEmpty ? null : snap.docs.first;
    } catch (_) {
      return null;
    }
  }
}
