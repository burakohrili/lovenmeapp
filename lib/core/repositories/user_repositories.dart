// lib/core/repositories/user_repository.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase/firebase_init.dart';
import '../models/firestore_models.dart';

class UserRepository {
  final FirebaseService _firebase = FirebaseService();
  
  // Get user stream
  Stream<UserModel?> getUserStream(String userId) {
    return _firebase.firestore
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((doc) {
        if (doc.exists) {
          return UserModel.fromFirestore(doc);
        }
        return null;
      });
  }

  // Get current user stream
  Stream<UserModel?> getCurrentUserStream() {
    final userId = _firebase.currentUserId;
    if (userId != null) {
      return getUserStream(userId);
    }
    return Stream.value(null);
  }

  // Update user photos
  Future<List<String>> uploadPhotos(List<String> localPaths) async {
    try {
      List<String> uploadedUrls = [];
      final userId = _firebase.currentUserId;
      
      if (userId == null) throw Exception('User not authenticated');

      for (int i = 0; i < localPaths.length; i++) {
        final file = File(localPaths[i]);
        final fileName = '${userId}_photo_$i.jpg';
        final ref = _firebase.storage
          .ref()
          .child('users/$userId/photos/$fileName');

        // Upload file
        final uploadTask = await ref.putFile(file);
        
        // Get download URL
        final url = await uploadTask.ref.getDownloadURL();
        uploadedUrls.add(url);
      }

      // Update Firestore
      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update({
          'photos': uploadedUrls,
          'updatedAt': FieldValue.serverTimestamp(),
        });

      return uploadedUrls;
    } catch (e) {
      rethrow;
    }
  }

  // Update favorite venues
  Future<void> updateFavoriteVenues(List<String> venueIds) async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update({
          'favoriteVenues': venueIds,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    } catch (e) {
      rethrow;
    }
  }

  // Update hobbies
  Future<void> updateHobbies(List<String> hobbies) async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update({
          'hobbies': hobbies,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    } catch (e) {
      rethrow;
    }
  }

  // Update location
  Future<void> updateLocation(double latitude, double longitude) async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update({
          'location': GeoPoint(latitude, longitude),
          'updatedAt': FieldValue.serverTimestamp(),
        });

    } catch (e) {
      rethrow;
    }
  }

  // Update phone verification
  Future<void> updatePhoneVerification(String phoneNumber) async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update({
          'phoneNumber': phoneNumber,
          'isPhoneVerified': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    } catch (e) {
      rethrow;
    }
  }

  // Update settings
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update({
          'settings': settings,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    } catch (e) {
      rethrow;
    }
  }

  // Update premium status
  Future<void> updatePremiumStatus(bool isPremium) async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      Map<String, dynamic> updates = {
        'isPremium': isPremium,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Reset limits for premium users
      if (isPremium) {
        updates['dailyLikesRemaining'] = 999999; // Unlimited
        // 🔥 YENİ SİSTEM: Super like artık günlük verilmiyor, sadece satın alma anında
        updates['rewindsRemaining'] = 3;
      } else {
        updates['dailyLikesRemaining'] = 5;
        // Normal kullanıcılar zaten super like alamaz
        updates['rewindsRemaining'] = 0;
      }

      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update(updates);

    } catch (e) {
      rethrow;
    }
  }

  // Get users for discovery
  Future<List<UserModel>> getDiscoverUsers({
    required List<String> favoriteVenues,
    required String currentUserId,
    int limit = 10,
  }) async {
    try {
      // Get users with at least one common favorite venue
      QuerySnapshot snapshot = await _firebase.firestore
        .collection('users')
        .where('favoriteVenues', arrayContainsAny: favoriteVenues)
        .where('isActive', isEqualTo: true)
        .limit(limit)
        .get();

      List<UserModel> users = [];
      for (var doc in snapshot.docs) {
        if (doc.id != currentUserId) {
          users.add(UserModel.fromFirestore(doc));
        }
      }

      return users;
    } catch (e) {
      return [];
    }
  }

  // Reset daily limits (should be called daily via Cloud Function)
  Future<void> resetDailyLimits() async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) return;

      // Get user data
      DocumentSnapshot doc = await _firebase.firestore
        .collection('users')
        .doc(userId)
        .get();
      
      if (!doc.exists) return;
      
      UserModel user = UserModel.fromFirestore(doc);

      Map<String, dynamic> updates = {
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (user.isPremium) {
        updates['dailyLikesRemaining'] = 999999; // Sınırsız like
        updates['dailyRewindsRemaining'] = 3; // � YENİ: Günde 3 geri alma hakkı
        // 🔥 FIXED: Super like artık günlük resetlenmiyor, sadece satın alma anında 'purchasedSuperLikes'
      } else {
        updates['dailyLikesRemaining'] = 5; // Günde 5 like
        updates['dailyRewindsRemaining'] = 0; // Geri alma hakkı yok
        // Normal kullanıcılar super like alamaz (sadece satın alabilir)
      }

      await _firebase.firestore
        .collection('users')
        .doc(userId)
        .update(updates);

    } catch (e) {
    }
  }

  // Block/Unblock user
  Future<void> toggleBlockUser(String blockedUserId, bool block) async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      if (block) {
        // Add to blocked users
        await _firebase.firestore
          .collection('users')
          .doc(userId)
          .collection('blocked')
          .doc(blockedUserId)
          .set({
            'blockedAt': FieldValue.serverTimestamp(),
          });
      } else {
        // Remove from blocked users
        await _firebase.firestore
          .collection('users')
          .doc(userId)
          .collection('blocked')
          .doc(blockedUserId)
          .delete();
      }

    } catch (e) {
      rethrow;
    }
  }

  // Get blocked users
  Future<List<String>> getBlockedUsers() async {
    try {
      final userId = _firebase.currentUserId;
      if (userId == null) return [];

      QuerySnapshot snapshot = await _firebase.firestore
        .collection('users')
        .doc(userId)
        .collection('blocked')
        .get();

      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      return [];
    }
  }
}