// lib/presentation/pages/messages/providers/firebase_chat_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/match_model.dart';
import '../models/message_model.dart';
import 'chat_provider.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/encounter_service.dart';

class FirebaseChatNotifier extends StateNotifier<ChatState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<QuerySnapshot>? _matchesSubscription;
  StreamSubscription<QuerySnapshot>? _matchesSideTwoSubscription;
  final Map<String, Map<String, dynamic>> _matchDocsAsUser1 = {};
  final Map<String, Map<String, dynamic>> _matchDocsAsUser2 = {};
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
    _matchesSideTwoSubscription?.cancel();
    _matchesSideTwoSubscription = null;
    _matchDocsAsUser1.clear();
    _matchDocsAsUser2.clear();
    
    for (var sub in _messageSubscriptions.values) {
      sub.cancel();
    }
    _messageSubscriptions.clear();
  }

  /// Kullanıcının bağlantılarını dinler.
  ///
  /// GÜVENLİK + MALİYET: Eskiden burada `where('isActive', isEqualTo: true)`
  /// ile TÜM koleksiyon dinleniyor, eşleşmeyenler Dart tarafında eleniyordu.
  /// Yani her cihaz uygulamadaki bütün bağlantı grafiğini indiriyordu — hem
  /// veri sızıntısı hem faturanın en büyük kalemi. Firestore'da OR sorgusu
  /// olmadığı için iki ayrı taraf sorgusu açıp sonuçları birleştiriyoruz.
  void _listenToMatches() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _matchesSubscription?.cancel();
    _matchesSideTwoSubscription?.cancel();
    _matchDocsAsUser1.clear();
    _matchDocsAsUser2.clear();

    _matchesSubscription = _firestore
        .collection('matches')
        .where('isActive', isEqualTo: true)
        .where('user1Id', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      _matchDocsAsUser1
        ..clear()
        ..addEntries(snapshot.docs.map((d) => MapEntry(d.id, d.data())));
      _rebuildMatches(userId);
    }, onError: (_) {});

    _matchesSideTwoSubscription = _firestore
        .collection('matches')
        .where('isActive', isEqualTo: true)
        .where('user2Id', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      _matchDocsAsUser2
        ..clear()
        ..addEntries(snapshot.docs.map((d) => MapEntry(d.id, d.data())));
      _rebuildMatches(userId);
    }, onError: (_) {});
  }

  /// İki taraftan gelen dokümanları birleştirip state'i kurar.
  Future<void> _rebuildMatches(String userId) async {
    final merged = <String, Map<String, dynamic>>{}
      ..addAll(_matchDocsAsUser1)
      ..addAll(_matchDocsAsUser2);

    final List<MatchModel> matches = [];

    for (final entry in merged.entries) {
      final docId = entry.key;
      final data = entry.value;

      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null || currentUserId != userId) return;

      if (data['isActive'] != true) continue;

      String otherUserId = '';
      if (data['user1Id'] == currentUserId) {
        otherUserId = (data['user2Id'] ?? '').toString();
      } else if (data['user2Id'] == currentUserId) {
        otherUserId = (data['user1Id'] ?? '').toString();
      } else {
        continue;
      }
      if (otherUserId.isEmpty) continue;

      try {
        final userDoc =
            await _firestore.collection('users').doc(otherUserId).get();
        if (!userDoc.exists) continue;

        final userData = userDoc.data()!;

        final matchedAtData = data['matchedAt'] ?? data['timestamp'];
        final DateTime matchedAt = matchedAtData is Timestamp
            ? matchedAtData.toDate()
            : DateTime.now();

        DateTime? lastMessageTime;
        if (data['lastMessageTime'] is Timestamp) {
          lastMessageTime = (data['lastMessageTime'] as Timestamp).toDate();
        }

        final photos = List<String>.from(userData['photos'] ?? const []);

        final match = MatchModel(
          id: docId,
          userId: otherUserId,
          name: userData['name'] ?? 'İsimsiz',
          age: userData['age'] ?? 18,
          profileImage: photos.isNotEmpty ? photos.first : '',
          photos: photos,
          matchedAt: matchedAt,
          lastMessage: data['lastMessage'] ?? '',
          lastMessageTime: lastMessageTime,
          unreadCount: 0,
          isOnline: userData['isOnline'] ?? false,
          lastSeen: userData['lastSeen']?.toString(),
          commonHobbies: const [],
          isPremium: userData['isPremium'] ?? false,
        );

        int commonCheckIns = 0;
        List<String> commonVenueNames = [];
        try {
          final encounter =
              await EncounterService.getTopEncounter(currentUserId, otherUserId);
          if (encounter != null) {
            commonCheckIns = encounter.encounterCount;
            commonVenueNames = [encounter.venueName];
          }
        } catch (_) {}

        matches.add(match.copyWith(
          commonCheckIns: commonCheckIns,
          commonVenues: commonVenueNames,
        ));

        _listenToMessages(docId);
      } catch (_) {
        // Tek bir bağlantı hidrasyonu başarısız olursa listeyi bozmayalım.
      }
    }

    final finalUserId = _auth.currentUser?.uid;
    if (finalUserId != null && finalUserId == userId) {
      state = state.copyWith(matches: matches, currentUserId: finalUserId);
    }
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