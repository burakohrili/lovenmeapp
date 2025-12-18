// lib/presentation/pages/messages/providers/firebase_chat_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/match_model.dart';
import '../models/message_model.dart';
import 'chat_provider.dart';
import '../../../../core/services/notification_service.dart';

class FirebaseChatNotifier extends StateNotifier<ChatState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<QuerySnapshot>? _matchesSubscription;
  StreamSubscription<User?>? _authSubscription;
  final Map<String, StreamSubscription<QuerySnapshot>> _messageSubscriptions = {};

  FirebaseChatNotifier() : super(ChatState()) {
    _initializeChat();
  }

  void _initializeChat() {
    // Auth state değişikliklerini dinle
    _authSubscription = _auth.authStateChanges().listen((user) {
      
      if (user != null) {
        // Kullanıcı giriş yaptı veya değişti
        if (state.currentUserId != user.uid) {
          _resetForNewUser(user.uid);
        }
      } else {
        // Kullanıcı çıkış yaptı
        _clearAllData();
      }
    });
  }

  void _resetForNewUser(String userId) {
    // Eski abonelikleri temizle
    _cancelAllSubscriptions();
    
    // State'i yeni kullanıcı için sıfırla
    state = ChatState(currentUserId: userId);
    
    // Yeni kullanıcı için verileri yükle
    _listenToMatches();
  }

  void _clearAllData() {
    _cancelAllSubscriptions();
    state = ChatState();
  }

  void _cancelAllSubscriptions() {
    _matchesSubscription?.cancel();
    _matchesSubscription = null;
    
    for (var sub in _messageSubscriptions.values) {
      sub.cancel();
    }
    _messageSubscriptions.clear();
  }

  void _listenToMatches() {
    final userId = _auth.currentUser?.uid;

    if (userId == null) {
      return;
    }

    // Önceki subscription'ı iptal et
    _matchesSubscription?.cancel();

    // Yeni subscription başlat
    _matchesSubscription = _firestore
        .collection('matches')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snapshot) async {
      

      List<MatchModel> matches = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        // Her seferinde güncel userId'yi kontrol et
        final currentUserId = _auth.currentUser?.uid;
        if (currentUserId == null || currentUserId != userId) {
          return;
        }
        

        if (data['isActive'] != true) {
          continue;
        }

        String otherUserId = '';

        if (data['user1Id'] == currentUserId) {
          otherUserId = data['user2Id'];
        } else if (data['user2Id'] == currentUserId) {
          otherUserId = data['user1Id'];
        } else {
          continue;
        }

        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(otherUserId)
              .get();

          if (!userDoc.exists) {
            continue;
          }

          final userData = userDoc.data()!;

          final matchedAtData = data['matchedAt'];
          DateTime matchedAt;
          if (matchedAtData is Timestamp) {
            matchedAt = matchedAtData.toDate();
          } else {
            matchedAt = DateTime.now();
          }

          DateTime? lastMessageTime;
          if (data['lastMessageTime'] != null &&
              data['lastMessageTime'] is Timestamp) {
            lastMessageTime = (data['lastMessageTime'] as Timestamp).toDate();
          }

          final match = MatchModel(
            id: doc.id,
            userId: otherUserId,
            name: userData['name'] ?? 'İsimsiz',
            age: userData['age'] ?? 18,
            profileImage: userData['photos']?.isNotEmpty == true
                ? userData['photos'][0]
                : 'https://via.placeholder.com/150',
            photos: List<String>.from(
                userData['photos'] ?? ['https://via.placeholder.com/150']),
            matchedAt: matchedAt,
            lastMessage: data['lastMessage'] ?? '',
            lastMessageTime: lastMessageTime,
            unreadCount: 0,
            isOnline: userData['isOnline'] ?? false,
            lastSeen: userData['lastSeen']?.toString(),
            commonVenues: [],
            commonHobbies: [],
            isPremium: userData['isPremium'] ?? false,
          );

          matches.add(match);

          // Her match için mesajları dinle
          _listenToMessages(doc.id);
        } catch (e) {
        }
      }

      
      // State'i güncelle - currentUserId'yi de kontrol et
      final finalUserId = _auth.currentUser?.uid;
      if (finalUserId != null && finalUserId == userId) {
        state = state.copyWith(
          matches: matches,
          currentUserId: finalUserId,
        );
      }
      
    }, onError: (error) {
    });
  }

  void _listenToMessages(String matchId) {
    
    _messageSubscriptions[matchId]?.cancel();
    
    _messageSubscriptions[matchId] = _firestore
        .collection('messages')
        .where('matchId', isEqualTo: matchId)
        .snapshots()
        .listen((snapshot) {
      
      
      List<MessageModel> messages = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        DateTime timestamp;
        if (data['timestamp'] != null && data['timestamp'] is Timestamp) {
          timestamp = (data['timestamp'] as Timestamp).toDate();
        } else {
          timestamp = DateTime.now();
        }
        
        final message = MessageModel(
          id: doc.id,
          senderId: data['senderId'] ?? '',
          receiverId: data['receiverId'] ?? '',
          message: data['message'] ?? '',
          timestamp: timestamp,
          isRead: data['isRead'] ?? false,
          type: MessageType.values[data['type'] ?? 0],
          imageUrl: data['imageUrl'],
          voiceUrl: data['voiceUrl'],
          venueId: data['venueId'],
          venueName: data['venueName'],
        );
        
        messages.add(message);
      }
      
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
      updatedMessages[matchId] = messages;
      
      state = state.copyWith(messages: updatedMessages);
      
      _updateUnreadCount(matchId, messages);
    }, onError: (error) {
    });
  }

  void _updateUnreadCount(String matchId, List<MessageModel> messages) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final unreadCount = messages
        .where((msg) => msg.receiverId == userId && !msg.isRead)
        .length;

    final updatedMatches = state.matches.map((match) {
      if (match.id == matchId) {
        return match.copyWith(unreadCount: unreadCount);
      }
      return match;
    }).toList();

    state = state.copyWith(matches: updatedMatches);
  }

  Future<void> sendMessage({
    required String matchId,
    required String message,
    MessageType type = MessageType.text,
    String? imageUrl,
    String? voiceUrl,
    String? venueId,
    String? venueName,
  }) async {
    
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return;
    }
    
    
    try {
      final matchDoc = await _firestore
          .collection('matches')
          .doc(matchId)
          .get();
      
      if (!matchDoc.exists) {
        return;
      }
      
      final matchData = matchDoc.data()!;
      
      final receiverId = matchData['user1Id'] == userId 
          ? matchData['user2Id'] 
          : matchData['user1Id'];
      
      
      await _firestore.collection('messages').add({
        'matchId': matchId,
        'senderId': userId,
        'receiverId': receiverId,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': type.index,
        'imageUrl': imageUrl,
        'voiceUrl': voiceUrl,
        'venueId': venueId,
        'venueName': venueName,
      });
      
      
      
      // Update match with last message
      await _firestore.collection('matches').doc(matchId).update({
        'lastMessage': message,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
      
      
      // Bildirim gönder
      try {
        
        // Gönderen kullanıcının bilgilerini al
        final senderDoc = await _firestore.collection('users').doc(userId).get();
        final senderData = senderDoc.data();
        final senderName = senderData != null 
            ? '${senderData['name']} ${senderData['surname']?[0] ?? ''}'
            : 'Kullanıcı';
        
        await NotificationService.sendMessageNotification(
          toUserId: receiverId,
          fromUserName: senderName,
          fromUserId: userId,
          messageContent: message,
          chatId: matchId,
        );
        
      } catch (e) {
      }
      
    } catch (e) {
    }
  }

  Future<void> markAsRead(String matchId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final batch = _firestore.batch();

    final unreadMessages = await _firestore
        .collection('messages')
        .where('matchId', isEqualTo: matchId)
        .where('receiverId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in unreadMessages.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  void selectMatch(MatchModel? match) {
    state = state.copyWith(selectedMatch: match);
    if (match != null) {
      markAsRead(match.id);
    }
  }

  void setTyping(bool isTyping) {
    state = state.copyWith(isTyping: isTyping);
  }

  Future<void> deleteMatch(String matchId) async {
    await _firestore.collection('matches').doc(matchId).update({
      'isActive': false,
      'deletedAt': FieldValue.serverTimestamp(),
    });

    _messageSubscriptions[matchId]?.cancel();
    _messageSubscriptions.remove(matchId);

    final updatedMatches = state.matches.where((m) => m.id != matchId).toList();
    final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
    updatedMessages.remove(matchId);

    state = state.copyWith(
      matches: updatedMatches,
      messages: updatedMessages,
    );
  }

  Future<void> updateOnlineStatus(bool isOnline) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _firestore.collection('users').doc(userId).update({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cancelAllSubscriptions();
    super.dispose();
  }
}

// Firebase Chat Provider
final firebaseChatProvider =
    StateNotifierProvider<FirebaseChatNotifier, ChatState>((ref) {
  return FirebaseChatNotifier();
});