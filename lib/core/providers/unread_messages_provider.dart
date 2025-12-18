// lib/core/providers/unread_messages_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Unread Messages Count Provider
class UnreadMessagesNotifier extends StateNotifier<int> {
  UnreadMessagesNotifier() : super(0) {
    _listenToUnreadMessages();
    _listenToPendingRequests();
  }
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  int _unreadMessagesCount = 0;
  int _pendingRequestsCount = 0;
  
  void _listenToUnreadMessages() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    
    _firestore
        .collection('messages')
        .where('receiverId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _unreadMessagesCount = snapshot.docs.length;
      _updateTotalCount();
    }, onError: (error) {
    });
  }
  
  void _listenToPendingRequests() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    
    _firestore
        .collection('chat_requests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      _pendingRequestsCount = snapshot.docs.length;
      _updateTotalCount();
    }, onError: (error) {
    });
  }
  
  void _updateTotalCount() {
    state = _unreadMessagesCount + _pendingRequestsCount;
  }
}

// Provider tanımı
final unreadMessagesProvider = StateNotifierProvider<UnreadMessagesNotifier, int>((ref) {
  return UnreadMessagesNotifier();
});
