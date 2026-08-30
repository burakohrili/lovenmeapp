// lib/core/services/chat_request_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_request_model.dart';
import 'notification_service.dart';
import 'premium_service.dart';
import 'block_service.dart';

/// Chat Request Service - Tüm chat isteği işlemlerini yönetir
class ChatRequestService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Hazır mesajlar (5 tane)
  static List<String> getQuickMessages() {
    return [
      'Merhaba! 👋',
      'Aynı mekandayız ✨',
      'Mekan önerin var mı? ☕',
      'Bu yer nasıl? 💬',
      'Selam! 👋',
    ];
  }

  /// Custom mesaj validasyonu (max 20 karakter)
  static bool validateCustomMessage(String message) {
    final trimmed = message.trim();
    return trimmed.isNotEmpty && trimmed.length <= 20;
  }

  /// Chat isteği gönder
  static Future<bool> sendChatRequest({
    required String toUserId,
    bool isSuperChat = false,
    String? customMessage,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return false;
      }

      // 🛡️ ENGELLEME KONTROLÜ (iki yönlü)
      // Bu kontrol hiç yoktu: engellenen kişi, kendisini engelleyene bağlantı
      // isteği göndermeye devam edebiliyordu. Engelleme, göstermelik değil
      // gerçek bir sınır olmalı.
      if (await BlockService.isBlockedEitherWay(toUserId)) {
        return false;
      }

      // 🛡️ DUPLICATE KONTROLÜ: Aynı kullanıcıya zaten istek gönderilmiş mi?
      final alreadySent = await hasSentRequest(toUserId);
      if (alreadySent) {
        return false;
      }

      // Aynı kullanıcıyla zaten aktif bağlantı var mı?
      final alreadyMatched = await areAlreadyMatched(toUserId);
      if (alreadyMatched) {
        return false;
      }

      // 🛡️ LİMİT KONTROLLERI
      final premiumStatus = await PremiumService.getPremiumStatus();
      
      if (isSuperChat) {
        // Süper chat hakkı kontrolü
        final canUseSuperChat = premiumStatus.superChatsRemaining > 0;
        
        if (!canUseSuperChat) {
          return false;
        }
        
      } else {
        // Normal chat için günlük limit kontrolü
        if (!premiumStatus.isPremium) {
          // Premium değilse günlük limit kontrol et
          final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
          final userData = userDoc.data();
          final dailyChatRequestsRemaining = userData?['dailyChatRequestsRemaining'] ?? 5;
          
          if (dailyChatRequestsRemaining <= 0) {
            return false;
          }
          
        } else {
        }
      }

      // Super chat ise mesaj zorunlu
      if (isSuperChat && (customMessage == null || customMessage.trim().isEmpty)) {
        return false;
      }

      // Mesaj uzunluk kontrolü
      if (customMessage != null && !validateCustomMessage(customMessage)) {
        return false;
      }

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(days: 30)); // 30 gün sonra expire

      final requestData = {
        'fromUserId': currentUser.uid,
        'toUserId': toUserId,
        'type': isSuperChat ? 'superChat' : 'normal',
        'status': 'pending',
        'message': customMessage?.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'respondedAt': null,
      };

      // Firestore'a ekle
      await _firestore.collection('chat_requests').add(requestData);
      
      // Limit düşür
      if (isSuperChat) {
        // 💬 Süper chat: superChatsRemaining düşür
        await _firestore.collection('users').doc(currentUser.uid).update({
          'superChatsRemaining': FieldValue.increment(-1),
        });
      } else {
        // Normal chat: Günlük limiti düşür
        await _firestore.collection('users').doc(currentUser.uid).update({
          'dailyChatRequestsRemaining': FieldValue.increment(-1),
        });
      }
      
      // 📲 BİLDİRİM GÖNDER
      try {
        // Gönderen kullanıcının bilgilerini al
        final senderDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        final senderData = senderDoc.data();
        final senderName = senderData?['name'] ?? 'Bir kullanıcı';
        final senderPhoto = senderData?['profilePhotos'] != null && 
            (senderData!['profilePhotos'] as List).isNotEmpty
            ? senderData['profilePhotos'][0]
            : null;

        await NotificationService.sendChatRequestNotification(
          toUserId: toUserId,
          fromUserId: currentUser.uid,
          fromUserName: senderName,
          fromUserPhoto: senderPhoto,
          isSuperChat: isSuperChat,
          customMessage: customMessage,
        );
      } catch (e) {
        // Bildirim hatası isteğin gönderilmesini engellemesin
      }
      
      if (customMessage != null) {
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Chat isteğini kabul et
  static Future<bool> acceptChatRequest(String requestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return false;
      }

      final requestRef = _firestore.collection('chat_requests').doc(requestId);
      final requestDoc = await requestRef.get();

      if (!requestDoc.exists) {
        return false;
      }

      final requestData = requestDoc.data()!;
      
      // İsteğin kendisine gönderildiğini kontrol et
      if (requestData['toUserId'] != currentUser.uid) {
        return false;
      }

      // Zaten yanıtlandı mı kontrol et
      if (requestData['status'] != 'pending') {
        return false;
      }

      // İsteği kabul et
      await requestRef.update({
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      
      // Bağlantı oluşturulması Cloud Function tarafından yapılacak
      // veya burada yapabiliriz
      await _createMatchFromRequest(requestData);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Chat isteğini reddet
  static Future<bool> rejectChatRequest(String requestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return false;
      }

      final requestRef = _firestore.collection('chat_requests').doc(requestId);
      final requestDoc = await requestRef.get();

      if (!requestDoc.exists) {
        return false;
      }

      final requestData = requestDoc.data()!;
      
      // İsteğin kendisine gönderildiğini kontrol et
      if (requestData['toUserId'] != currentUser.uid) {
        return false;
      }

      // Zaten yanıtlandı mı kontrol et
      if (requestData['status'] != 'pending') {
        return false;
      }

      // İsteği reddet
      await requestRef.update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      
      // Privacy için gönderene bildirim GÖNDERİLMEZ

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Pending (bekleyen) istekleri getir
  static Future<List<ChatRequest>> getPendingRequests() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return [];
      }

      final snapshot = await _firestore
          .collection('chat_requests')
          .where('toUserId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      // Timestamp'e göre sıralama client-side'da yap
      final requests = snapshot.docs
          .map((doc) => ChatRequest.fromFirestore(doc))
          .toList();
      
      requests.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return requests;
    } catch (e) {
      return [];
    }
  }

  /// Pending (bekleyen) istekleri real-time dinle (Stream)
  static Stream<List<ChatRequest>> getPendingRequestsStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('chat_requests')
        .where('toUserId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => ChatRequest.fromFirestore(doc))
              .toList();
          
          // Timestamp'e göre sıralama client-side'da yap
          requests.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          
          return requests;
        });
  }

  /// Pending request sayısını getir (badge için)
  static Future<int> getPendingRequestCount() async {
    try {
      final requests = await getPendingRequests();
      return requests.length;
    } catch (e) {
      return 0;
    }
  }

  /// Real-time pending request count stream
  static Stream<int> watchPendingRequestCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('chat_requests')
        .where('toUserId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Belirli bir kullanıcıya daha önce istek gönderilmiş mi?
  static Future<bool> hasSentRequest(String toUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final snapshot = await _firestore
          .collection('chat_requests')
          .where('fromUserId', isEqualTo: currentUser.uid)
          .where('toUserId', isEqualTo: toUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// İki kullanıcı zaten match olmuş mu? (Overload - single parameter)
  static Future<bool> areAlreadyMatched(String toUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    return areAlreadyMatchedWith(currentUser.uid, toUserId);
  }

  /// İki kullanıcı zaten match olmuş mu? (original method)
  static Future<bool> areAlreadyMatchedWith(String userId1, String userId2) async {
    try {
      // users array içinde her iki kullanıcı ID'si de var mı kontrol et
      final snapshot = await _firestore
          .collection('matches')
          .where('users', arrayContains: userId1)
          .get();

      for (var doc in snapshot.docs) {
        final users = List<String>.from(doc.data()['users'] ?? []);
        if (users.contains(userId2)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Request'ten match oluştur (private helper)
  static Future<void> _createMatchFromRequest(Map<String, dynamic> requestData) async {
    try {
      final fromUserId = requestData['fromUserId'] as String;
      final toUserId = requestData['toUserId'] as String;
      final initialMessage = requestData['message'] as String?;

      // Zaten match olmuş mu kontrol et
      final alreadyMatched = await areAlreadyMatchedWith(fromUserId, toUserId);
      if (alreadyMatched) {
        return;
      }

      // Bağlantı oluştur
      final matchRef = await _firestore.collection('matches').add({
        'user1Id': fromUserId,
        'user2Id': toUserId,
        'users': [fromUserId, toUserId],
        'timestamp': FieldValue.serverTimestamp(),
        'isActive': true,
        'initiatedBy': fromUserId,
        'requestType': requestData['type'],
        'initialMessage': initialMessage,
      });

      // Super chat ile gelen mesajı ilk mesaj olarak gönder
      if (initialMessage != null && initialMessage.trim().isNotEmpty) {
        await _sendInitialMessage(
          matchId: matchRef.id,
          fromUserId: fromUserId,
          toUserId: toUserId,
          message: initialMessage,
        );
      }

    } catch (e) {
    }
  }

  /// İlk mesajı gönder (Super chat'ten gelen mesaj için)
  static Future<void> _sendInitialMessage({
    required String matchId,
    required String fromUserId,
    required String toUserId,
    required String message,
  }) async {
    try {
      // Mesajı root level messages koleksiyonuna ekle (Firebase Chat Provider ile uyumlu)
      await _firestore.collection('messages').add({
        'matchId': matchId,
        'senderId': fromUserId,
        'receiverId': toUserId,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 0, // MessageType.text = 0
        'imageUrl': null,
        'voiceUrl': null,
        'venueId': null,
        'venueName': null,
      });

      // Match'in lastMessage bilgilerini güncelle
      await _firestore.collection('matches').doc(matchId).update({
        'lastMessage': message,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': fromUserId,
      });

    } catch (e) {
    }
  }

  /// Expired requestleri temizle (Cloud Function tarafından da yapılabilir)
  static Future<void> cleanupExpiredRequests() async {
    try {
      final now = Timestamp.now();
      
      final snapshot = await _firestore
          .collection('chat_requests')
          .where('status', isEqualTo: 'pending')
          .where('expiresAt', isLessThan: now)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'status': 'expired'});
      }

      await batch.commit();
    } catch (e) {
    }
  }
}
