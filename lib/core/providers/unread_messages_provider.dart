// lib/core/providers/unread_messages_provider.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Alt gezinme çubuğundaki okunmamış rozeti.
///
/// DÜZELTİLEN İKİ HATA (30.08.2026):
///  1. İki `.listen()` çağrısı hiçbir değişkene atanmıyordu ve `dispose`
///     geçersiz kılınmamıştı — yani iki Firestore dinleyicisi süreç boyunca
///     açık kalıyordu.
///  2. Kullanıcı kimliği yapıcıda bir kez okunuyordu. Çıkış yapıp başka
///     hesapla girildiğinde dinleyiciler ÖNCEKİ kullanıcıyı dinlemeye devam
///     ediyor, rozet o kullanıcının sayılarını gösteriyordu. Artık
///     `authStateChanges` dinlenip abonelikler yeniden kuruluyor.
class UnreadMessagesNotifier extends StateNotifier<int> {
  UnreadMessagesNotifier() : super(0) {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _resubscribe(user?.uid);
    });
    _resubscribe(_auth.currentUser?.uid);
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _messagesSubscription;
  StreamSubscription<QuerySnapshot>? _requestsSubscription;

  String? _currentUserId;
  int _unreadMessagesCount = 0;
  int _pendingRequestsCount = 0;

  void _resubscribe(String? userId) {
    if (userId == _currentUserId) return;
    _currentUserId = userId;

    _messagesSubscription?.cancel();
    _requestsSubscription?.cancel();
    _messagesSubscription = null;
    _requestsSubscription = null;

    _unreadMessagesCount = 0;
    _pendingRequestsCount = 0;
    if (!mounted) return;
    state = 0;

    if (userId == null) return;

    _messagesSubscription = _firestore
        .collection('messages')
        .where('receiverId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .limit(200)
        .snapshots()
        .listen((snapshot) {
      _unreadMessagesCount = snapshot.docs.length;
      _updateTotalCount();
    }, onError: (_) {});

    _requestsSubscription = _firestore
        .collection('chat_requests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .limit(200)
        .snapshots()
        .listen((snapshot) {
      _pendingRequestsCount = snapshot.docs.length;
      _updateTotalCount();
    }, onError: (_) {});
  }

  void _updateTotalCount() {
    if (!mounted) return;
    state = _unreadMessagesCount + _pendingRequestsCount;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _messagesSubscription?.cancel();
    _requestsSubscription?.cancel();
    super.dispose();
  }
}

final unreadMessagesProvider =
    StateNotifierProvider<UnreadMessagesNotifier, int>((ref) {
  return UnreadMessagesNotifier();
});
