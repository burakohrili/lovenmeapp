// lib/core/services/chat_validation_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_request_model.dart';
import 'chat_request_service.dart';
import 'premium_service.dart';

/// Chat Validation Service - Tüm chat isteği validasyonları burada
class ChatValidationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Ana validasyon metodu - tüm kontrolleri yapar
  static Future<ChatRequestValidationResult> validateChatRequest(
    String targetUserId, {
    bool isSuperChat = false,
    Map<String, dynamic>? cachedUserData, // Performance için cache
  }) async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) {
        return ChatRequestValidationResult.error('Giriş yapmanız gerekiyor');
      }

      // 1. Self-request kontrolü
      if (currentUserId == targetUserId) {
        return ChatRequestValidationResult.selfRequest();
      }

      // 2. Block kontrolü
      final isBlocked = await _checkBlockedUser(currentUserId, targetUserId);
      if (isBlocked) {
        return ChatRequestValidationResult.blocked();
      }

      // 3. Zaten match olmuş mu kontrolü
      final alreadyMatched = await ChatRequestService.areAlreadyMatched(targetUserId);
      if (alreadyMatched) {
        return ChatRequestValidationResult.alreadyMatched();
      }

      // 4. Duplicate request kontrolü
      final hasSent = await ChatRequestService.hasSentRequest(targetUserId);
      if (hasSent) {
        return ChatRequestValidationResult.alreadySent();
      }

      // 5. User data al (cache varsa kullan)
      Map<String, dynamic> userData;
      if (cachedUserData != null) {
        userData = cachedUserData;
      } else {
        final userDoc = await _firestore.collection('users').doc(currentUserId).get();
        if (!userDoc.exists) {
          return ChatRequestValidationResult.error('Kullanıcı verisi bulunamadı');
        }
        userData = userDoc.data()!;
      }

      // 6. Super chat kontrolü
      if (isSuperChat) {
        final canUseSuperChat = await PremiumService.canUseSuperChat();
        if (!canUseSuperChat) {
          return ChatRequestValidationResult.insufficientSuperChats();
        }
        return ChatRequestValidationResult.success;
      }

      // 7. Normal chat kontrolü
      final isPremium = userData['isPremium'] ?? false;
      if (isPremium) {
        // Premium kullanıcılar sınırsız chat
        return ChatRequestValidationResult.success;
      }

      // 8. Günlük chat limiti kontrolü
      final dailyChatRequestsRemaining = userData['dailyChatRequestsRemaining'] ?? 0;
      if (dailyChatRequestsRemaining <= 0) {
        return ChatRequestValidationResult.limitReached();
      }

      return ChatRequestValidationResult.success;
    } catch (e) {
      return ChatRequestValidationResult.error('Hata oluştu');
    }
  }

  /// Block kontrolü - her iki yönlü de kontrol et
  static Future<bool> _checkBlockedUser(String userId1, String userId2) async {
    try {
      // blocked_users collection'ında kontrol
      final snapshot = await _firestore
          .collection('blocked_users')
          .where('blocker', whereIn: [userId1, userId2])
          .get();

      for (var doc in snapshot.docs) {
        final blocker = doc.data()['blocker'];
        final blocked = doc.data()['blocked'];
        
        // userId1 blocked userId2 veya tam tersi
        if ((blocker == userId1 && blocked == userId2) ||
            (blocker == userId2 && blocked == userId1)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false; // Hata durumunda izin ver
    }
  }

  /// Spam prevention - Son 1 dakikada kaç istek gönderilmiş?
  static Future<bool> checkSpamPrevention() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));

      final snapshot = await _firestore
          .collection('chat_requests')
          .where('fromUserId', isEqualTo: currentUser.uid)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(oneMinuteAgo))
          .get();

      // 1 dakikada 5'ten fazla istek spam sayılır
      if (snapshot.docs.length >= 5) {
        return false;
      }

      return true;
    } catch (e) {
      return true; // Hata durumunda izin ver
    }
  }

  /// Kullanıcının mevcut chat durumunu al (cache için)
  static Future<Map<String, dynamic>?> getCurrentUserData() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return null;

      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      return userDoc.exists ? userDoc.data() : null;
    } catch (e) {
      return null;
    }
  }

  /// Chat request özeti (dashboard için)
  static Future<Map<String, dynamic>> getChatRequestSummary() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {
          'dailyChatRequestsRemaining': 0,
          'superChatsRemaining': 0,
          'isPremium': false,
          'canSendChat': false,
          'canSendSuperChat': false,
          'pendingRequestCount': 0,
        };
      }

      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      
      if (!userDoc.exists) {
        return {
          'dailyChatRequestsRemaining': 0,
          'superChatsRemaining': 0,
          'isPremium': false,
          'canSendChat': false,
          'canSendSuperChat': false,
          'pendingRequestCount': 0,
        };
      }

      final userData = userDoc.data()!;
      final isPremium = userData['isPremium'] ?? false;
      final dailyChatRequestsRemaining = userData['dailyChatRequestsRemaining'] ?? 0;
      
      final premiumStatus = await PremiumService.getPremiumStatus();
      final superChatsRemaining = premiumStatus.superChatsRemaining;

      final pendingRequestCount = await ChatRequestService.getPendingRequestCount();

      return {
        'dailyChatRequestsRemaining': isPremium ? 999 : dailyChatRequestsRemaining,
        'superChatsRemaining': superChatsRemaining,
        'isPremium': isPremium,
        'canSendChat': isPremium || dailyChatRequestsRemaining > 0,
        'canSendSuperChat': superChatsRemaining > 0,
        'pendingRequestCount': pendingRequestCount,
      };
    } catch (e) {
      return {
        'dailyChatRequestsRemaining': 0,
        'superChatsRemaining': 0,
        'isPremium': false,
        'canSendChat': false,
        'canSendSuperChat': false,
        'pendingRequestCount': 0,
      };
    }
  }
}
