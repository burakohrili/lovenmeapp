// lib/core/services/encounter_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EncounterData {
  final String venueName;
  final int encounterCount;
  final String venueId;
  final String venueCategory;

  EncounterData({
    required this.venueName,
    required this.encounterCount,
    required this.venueId,
    required this.venueCategory,
  });
}

class EncounterService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// İki kullanıcının en çok karşılaştığı mekanı bulur
  static Future<EncounterData?> getTopEncounter(String currentUserId, String otherUserId) async {
    try {

      // Mevcut kullanıcının check-in'lerini al
      final currentUserCheckIns = await _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: currentUserId)
          .get();

      // Diğer kullanıcının check-in'lerini al
      final otherUserCheckIns = await _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: otherUserId)
          .get();


      // Mevcut kullanıcının venue'larını map'e çevir
      Map<String, List<Map<String, dynamic>>> currentUserVenues = {};
      
      for (var doc in currentUserCheckIns.docs) {
        final data = doc.data();
        final venueId = data['venueId'] as String?;
        final venueName = data['venueName'] ?? data['locationName'] as String?;
        
        if (venueId != null && venueName != null) {
          if (!currentUserVenues.containsKey(venueId)) {
            currentUserVenues[venueId] = [];
          }
          currentUserVenues[venueId]!.add(data);
        }
      }

      // Ortak venue'ları bul ve encounter sayısını hesapla
      Map<String, EncounterData> encounters = {};

      for (var doc in otherUserCheckIns.docs) {
        final data = doc.data();
        final venueId = data['venueId'] as String?;
        final venueName = data['venueName'] ?? data['locationName'] as String?;
        final venueCategory = data['venueCategory'] ?? '';
        
        if (venueId != null && venueName != null && currentUserVenues.containsKey(venueId)) {
          // Bu venue'da her iki kullanıcı da bulunmuş
          final currentUserVisits = currentUserVenues[venueId]!.length;
          const otherUserVisits = 1; // Bu spesifik check-in için 1
          
          if (encounters.containsKey(venueId)) {
            encounters[venueId] = EncounterData(
              venueName: venueName,
              encounterCount: encounters[venueId]!.encounterCount + 1,
              venueId: venueId,
              venueCategory: venueCategory,
            );
          } else {
            encounters[venueId] = EncounterData(
              venueName: venueName,
              encounterCount: 1,
              venueId: venueId,
              venueCategory: venueCategory,
            );
          }
        }
      }


      // En yüksek encounter sayısına sahip venue'yu bul
      if (encounters.isEmpty) {
        return null;
      }

      EncounterData topEncounter = encounters.values.first;
      for (var encounter in encounters.values) {
        if (encounter.encounterCount > topEncounter.encounterCount) {
          topEncounter = encounter;
        }
      }

      
      return topEncounter;

    } catch (e) {
      return null;
    }
  }

  /// Kullanıcının premium olup olmadığını kontrol eder
  static Future<bool> isUserPremium(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        return data['isPremium'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Mevcut kullanıcının premium olup olmadığını kontrol eder
  static Future<bool> isCurrentUserPremium() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    return await isUserPremium(currentUser.uid);
  }
}
