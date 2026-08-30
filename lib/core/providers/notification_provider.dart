// lib/core/providers/notification_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Notification State
class NotificationState {
  final int unreadCount;
  final List<NotificationModel> notifications;
  final bool isLoading;
  
  NotificationState({
    this.unreadCount = 0,
    this.notifications = const [],
    this.isLoading = false,
  });
  
  NotificationState copyWith({
    int? unreadCount,
    List<NotificationModel>? notifications,
    bool? isLoading,
  }) {
    return NotificationState(
      unreadCount: unreadCount ?? this.unreadCount,
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// Notification Model
class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  
  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });
  
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: data['type'] ?? 'general',
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// Notification Provider
class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(NotificationState()) {
    _initializeNotifications();
  }
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // DÜZELTİLEN İKİ HATA (30.08.2026):
  //  1. `.listen()` hiçbir değişkene atanmıyor, `dispose` da geçersiz
  //     kılınmıyordu — dinleyici süreç boyunca açık kalıyordu.
  //  2. Kullanıcı kimliği bir kez okunuyordu; çıkış/giriş sonrası
  //     ÖNCEKİ kullanıcının bildirimleri gösterilmeye devam ediyordu.
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _notificationsSubscription;
  String? _currentUserId;
  
  // 🎯 İlk yükleme + Realtime dinleme
  void _initializeNotifications() {
    _authSubscription ??= _auth.authStateChanges().listen((user) {
      _resubscribe(user?.uid);
    });
    _resubscribe(_auth.currentUser?.uid);
  }

  void _resubscribe(String? userId) {
    if (userId == _currentUserId && _notificationsSubscription != null) {
      return;
    }
    _currentUserId = userId;

    _notificationsSubscription?.cancel();
    _notificationsSubscription = null;

    if (userId == null) {
      state = NotificationState(notifications: const [], unreadCount: 0);
      return;
    }

    state = state.copyWith(isLoading: true);

    _notificationsSubscription = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      final notifications = snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
      
      final unreadCount = notifications.where((n) => !n.isRead).length;
      
      state = NotificationState(
        notifications: notifications,
        unreadCount: unreadCount,
        isLoading: false,
      );
      
    }, onError: (e) {
      state = state.copyWith(isLoading: false);
    });
  }
  
  // 🔔 Yeni bildirim ekle (Firebase'den değil, local olarak)
  void addNotification(NotificationModel notification) {
    final updatedNotifications = [notification, ...state.notifications];
    final unreadCount = notification.isRead ? state.unreadCount : state.unreadCount + 1;
    
    state = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: unreadCount,
    );
    
  }
  
  // ✅ Bildirimi okundu işaretle
  void markAsRead(String notificationId) {
    // Firebase'e async update - realtime stream otomatik güncelleyecek
    _updateReadStatusInFirestore(notificationId);
  }
  
  // 🔄 Firebase'e async update (UI block etmez)
  Future<void> _updateReadStatusInFirestore(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
    }
  }
  
  // 🔄 Manuel refresh (pull-to-refresh için)
  void refresh() {
    _initializeNotifications();
  }
  @override
  void dispose() {
    _authSubscription?.cancel();
    _notificationsSubscription?.cancel();
    super.dispose();
  }
}

// Provider tanımı
final notificationProvider = StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier();
});
