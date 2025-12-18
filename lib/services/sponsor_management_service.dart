import 'package:cloud_firestore/cloud_firestore.dart';

class SponsorManagementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🎯 SPONSOR VENUE EKLEME
  Future<bool> addSponsorVenue({
    required String venueId,
    required String sponsorName,
    required String sponsorLogoUrl,
    required String sponsorBadgeText,
    required int sponsorPriority,
    required DateTime sponsorStartDate,
    required DateTime sponsorEndDate,
    String? sponsorDescription,
    String? sponsorContactInfo,
    double? sponsorPrice,
  }) async {
    try {
      
      await _firestore.collection('venues').doc(venueId).set({
        'isSponsored': true,
        'sponsorName': sponsorName,
        'sponsorLogoUrl': sponsorLogoUrl,
        'sponsorBadgeText': sponsorBadgeText,
        'sponsorPriority': sponsorPriority,
        'sponsorStartDate': Timestamp.fromDate(sponsorStartDate),
        'sponsorEndDate': Timestamp.fromDate(sponsorEndDate),
        'sponsorDescription': sponsorDescription,
        'sponsorContactInfo': sponsorContactInfo,
        'sponsorPrice': sponsorPrice,
        'sponsorAddedAt': FieldValue.serverTimestamp(),
        'sponsorStatus': 'active',
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      return false;
    }
  }

  // 🗑️ SPONSOR VENUE SİLME
  Future<bool> removeSponsorVenue(String venueId) async {
    try {
      
      await _firestore.collection('venues').doc(venueId).update({
        'isSponsored': FieldValue.delete(),
        'sponsorName': FieldValue.delete(),
        'sponsorLogoUrl': FieldValue.delete(),
        'sponsorBadgeText': FieldValue.delete(),
        'sponsorPriority': FieldValue.delete(),
        'sponsorStartDate': FieldValue.delete(),
        'sponsorEndDate': FieldValue.delete(),
        'sponsorDescription': FieldValue.delete(),
        'sponsorContactInfo': FieldValue.delete(),
        'sponsorPrice': FieldValue.delete(),
        'sponsorAddedAt': FieldValue.delete(),
        'sponsorStatus': FieldValue.delete(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // 📊 TÜM SPONSOR VENUE'LARI LİSTELE
  Future<List<Map<String, dynamic>>> getAllSponsorVenues() async {
    try {
      final snapshot = await _firestore
          .collection('venues')
          .where('isSponsored', isEqualTo: true)
          .orderBy('sponsorPriority', descending: false)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ⏰ SÜRESİ DOLMUŞ SPONSOR'LARI TEMİZLE
  Future<void> cleanExpiredSponsors() async {
    try {
      final now = Timestamp.now();
      final snapshot = await _firestore
          .collection('venues')
          .where('isSponsored', isEqualTo: true)
          .where('sponsorEndDate', isLessThan: now)
          .get();

      final batch = _firestore.batch();
      
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isSponsored': false,
          'sponsorStatus': 'expired',
        });
      }

      await batch.commit();
    } catch (e) {
    }
  }

  // 🔄 SPONSOR GÜNCELLEME
  Future<bool> updateSponsorVenue({
    required String venueId,
    String? sponsorName,
    String? sponsorLogoUrl,
    String? sponsorBadgeText,
    int? sponsorPriority,
    DateTime? sponsorStartDate,
    DateTime? sponsorEndDate,
    String? sponsorDescription,
    String? sponsorContactInfo,
    double? sponsorPrice,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (sponsorName != null) updateData['sponsorName'] = sponsorName;
      if (sponsorLogoUrl != null) updateData['sponsorLogoUrl'] = sponsorLogoUrl;
      if (sponsorBadgeText != null) updateData['sponsorBadgeText'] = sponsorBadgeText;
      if (sponsorPriority != null) updateData['sponsorPriority'] = sponsorPriority;
      if (sponsorStartDate != null) updateData['sponsorStartDate'] = Timestamp.fromDate(sponsorStartDate);
      if (sponsorEndDate != null) updateData['sponsorEndDate'] = Timestamp.fromDate(sponsorEndDate);
      if (sponsorDescription != null) updateData['sponsorDescription'] = sponsorDescription;
      if (sponsorContactInfo != null) updateData['sponsorContactInfo'] = sponsorContactInfo;
      if (sponsorPrice != null) updateData['sponsorPrice'] = sponsorPrice;
      
      updateData['sponsorUpdatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('venues').doc(venueId).update(updateData);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  // 📈 SPONSOR İSTATİSTİKLERİ
  Future<Map<String, dynamic>> getSponsorStats() async {
    try {
      final totalSponsors = await _firestore
          .collection('venues')
          .where('isSponsored', isEqualTo: true)
          .count()
          .get();

      final now = Timestamp.now();
      final activeSponsors = await _firestore
          .collection('venues')
          .where('isSponsored', isEqualTo: true)
          .where('sponsorEndDate', isGreaterThan: now)
          .count()
          .get();

      final expiredSponsors = await _firestore
          .collection('venues')
          .where('sponsorStatus', isEqualTo: 'expired')
          .count()
          .get();

      return {
        'totalSponsors': totalSponsors.count,
        'activeSponsors': activeSponsors.count,
        'expiredSponsors': expiredSponsors.count,
        'lastUpdated': DateTime.now(),
      };
    } catch (e) {
      return {};
    }
  }
}
