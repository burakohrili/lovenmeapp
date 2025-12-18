// lib/core/services/notification_service.dart

import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // DEBUG: Homepage refresh tracking
  final Set<String> _processedMessageIds = <String>{};

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Bildirim servisini başlat
  Future<void> initialize() async {
    
    try {
      // İzin iste
      await _requestPermissions();
      
      // Local notifications başlat
      await _initializeLocalNotifications();
      
      // FCM token al ve kaydet - ZORUNLU
      await _getFCMToken();
      
      // Foreground mesajları dinle
      _configureForegroundMessages();
      
      // Background/terminated mesajları dinle
      _configureBackgroundMessages();
      
      
      // Extra: 3 saniye sonra token'ı bir kez daha kontrol et
      Timer(const Duration(seconds: 3), () async {
        await _ensureTokenIsSaved();
      });
      
    } catch (e) {
      rethrow;
    }
  }

  /// Token'ın kaydedildiğinden emin ol
  Future<void> _ensureTokenIsSaved() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return;
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final fcmToken = userDoc.data()?['fcmToken'];
      
      if (fcmToken == null) {
        await _getFCMToken();
      } else {
      }
    } catch (e) {
    }
  }

  /// Bildirimlerde izin iste
  Future<void> _requestPermissions() async {
    
    // Firebase Messaging izni
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    } else {
    }

    // iOS için additional permissions
    if (Platform.isIOS) {
      final notificationPermission = await Permission.notification.request();
    }
  }

  /// Local notifications başlat
  Future<void> _initializeLocalNotifications() async {
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Android notification channel oluştur
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        'lovenme_channel',
        'LoveNMe Notifications',
        description: 'Notifications for LoveNMe app',
        importance: Importance.high,
        enableVibration: true,
        enableLights: true,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }

  }

  /// FCM Token al ve kullanıcıya kaydet
  Future<void> _getFCMToken() async {
    try {
      
      // İlk önce mevcut token'ı kontrol et
      _fcmToken = await _messaging.getToken();
      
      if (_fcmToken == null) {
        // Token null ise biraz bekleyip tekrar dene
        await Future.delayed(const Duration(seconds: 2));
        _fcmToken = await _messaging.getToken();
      }
      
      final user = _auth.currentUser;
      if (user != null && _fcmToken != null) {
        try {
          await _firestore.collection('users').doc(user.uid).update({
            'fcmToken': _fcmToken,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
            'platform': Platform.isIOS ? 'ios' : 'android',
            'appVersion': '1.0.0',
            'tokenUpdatedAt': DateTime.now().toIso8601String(),
          });
        } catch (firestoreError) {
          // Firestore hatası olsa bile token'ı memory'de tut
        }
      } else {
      }
      
      // Token yenilendiğinde güncelle - sadece bir kez kurulsun
      _messaging.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        
        final user = _auth.currentUser;
        if (user != null) {
          try {
            await _firestore.collection('users').doc(user.uid).update({
              'fcmToken': newToken,
              'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
              'tokenRefreshedAt': DateTime.now().toIso8601String(),
            });
          } catch (e) {
          }
        }
      });
      
    } catch (e) {
      // Hata olsa bile tekrar denemeyi planla
      Timer(const Duration(seconds: 5), () {
        _getFCMToken();
      });
    }
  }

  /// Foreground mesajları yapılandır
  void _configureForegroundMessages() {
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      
      // Duplicate check
      if (_processedMessageIds.contains(message.messageId)) {
        return;
      } else {
        _processedMessageIds.add(message.messageId!);
        
        // Limit set size (keep last 100 messages)
        if (_processedMessageIds.length > 100) {
          final List<String> oldIds = _processedMessageIds.take(50).toList();
          _processedMessageIds.removeAll(oldIds);
        }
      }
      
      // Local notification göster
      _showLocalNotification(message);
      
      // 🎯 NEW: Local state'i güncelle (HomePage refresh olmaz)
      _updateLocalNotificationState(message);
      
    });
  }

  /// 🎯 LOCAL STATE UPDATE - Firestore'a yazmadan state güncelle
  void _updateLocalNotificationState(RemoteMessage message) {
    // Provider'a notification ekle (HomePage refresh olmaz)
    // Bu metod provider ile entegre edilecek
    
    // final notificationProvider = ProviderScope.containerOf(context).read(notificationProvider.notifier);
    // notificationProvider.addNotification(...);
  }

  /// Background/terminated mesajları yapılandır
  void _configureBackgroundMessages() {
    
    // Uygulama kapalıyken gelen mesajlar
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationNavigation(message);
    });
    
    // Uygulama tamamen kapalıyken gelen mesajlar için initial message kontrolü
    _messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationNavigation(message);
      }
    });
  }

  /// Local notification göster
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'lovenme_channel',
        'LoveNMe Notifications',
        channelDescription: 'Notifications for LoveNMe app',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        enableLights: true,
        playSound: true,
        autoCancel: true,
        ongoing: false,
        styleInformation: BigTextStyleInformation(''),
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'lovenme_notifications',
      );
      
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        message.hashCode,
        message.notification?.title ?? 'LoveNMe',
        message.notification?.body ?? 'Yeni bildirim',
        details,
        payload: message.data.toString(),
      );
      
    } catch (e) {
    }
  }

  /// Notification tıklandığında navigation
  void _onNotificationTapped(NotificationResponse response) {
  }

  /// Push notification navigation
  void _handleNotificationNavigation(RemoteMessage message) {
  }

  /// Kullanıcıya bildirim gönder
  Future<void> sendNotificationToUser({
    required String targetUserId,
    required String title,
    required String body,
    required String type,
    String? senderId,
    String? senderName,
    bool showSenderName = false,
    String? venueId,
    String? venueName,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      
      final firestore = FirebaseFirestore.instance;
      
      // Hedef kullanıcının FCM token'ını al
      final userDoc = await firestore.collection('users').doc(targetUserId).get();
      if (!userDoc.exists) {
        return;
      }
      
      final userData = userDoc.data()!;
      final fcmToken = userData['fcmToken'] as String?;
      
      if (fcmToken == null) {
        return;
      }
      
      // Notification verilerini hazırla
      final data = {
        'type': type,
        'senderId': senderId ?? '',
        'senderName': senderName ?? '',
        'showSenderName': showSenderName.toString(),
        'venueId': venueId ?? '',
        'venueName': venueName ?? '',
        ...?additionalData,
      };
      
      // Cloud Function'a bildirim gönderme isteği gönder
      await firestore.collection('notification_requests').add({
        'targetUserId': targetUserId,
        'fcmToken': fcmToken,
        'title': title,
        'body': body,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
      
      // In-app notification'ı manuel olarak ekle (Cloud Functions loop'u önlemek için)
      await firestore.collection('notifications').add({
        'userId': targetUserId,
        'title': title,
        'body': body,
        'type': type,
        'senderId': senderId ?? '',
        'senderName': senderName ?? '',
        'showSenderName': showSenderName,
        'venueId': venueId ?? '',
        'venueName': venueName ?? '',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'additionalData': additionalData ?? {},
      });
      
      
    } catch (e) {
    }
  }

  /// Eşleşme bildirimi gönder
  static Future<void> sendMatchNotification({
    required String toUserId,
    required String fromUserName,
  }) async {
    await NotificationService().sendNotificationToUser(
      targetUserId: toUserId,
      title: '🎉 Yeni Eşleşme!',
      body: '$fromUserName ile eşleştiniz! Hemen mesajlaşmaya başlayın.',
      type: 'match',
      senderName: fromUserName,
      showSenderName: true,
    );
  }

  /// 💬 Chat isteği bildirimi gönder
  static Future<void> sendChatRequestNotification({
    required String toUserId,
    required String fromUserId,
    required String fromUserName,
    String? fromUserPhoto,
    bool isSuperChat = false,
    String? customMessage,
  }) async {
    if (customMessage != null) {
    }
    
    // Super chat ve normal chat için farklı başlık ve mesajlar
    String title;
    String body;
    String notificationType;
    
    if (isSuperChat) {
      // SUPER CHAT: Özel mesaj ile gelir
      title = '⭐ SUPER CHAT İSTEĞİ!';
      body = customMessage != null && customMessage.isNotEmpty
          ? '$fromUserName: "$customMessage"'
          : '$fromUserName size özel bir mesaj gönderdi!';
      notificationType = 'super_chat_request';
    } else {
      // NORMAL CHAT: Sadece standart metin, mesaj yok
      title = '💬 Yeni Chat İsteği';
      body = '$fromUserName sizinle konuşmak istiyor';
      notificationType = 'chat_request';
    }
    
    await NotificationService().sendNotificationToUser(
      targetUserId: toUserId,
      title: title,
      body: body,
      type: notificationType,
      senderId: fromUserId,
      senderName: fromUserName,
      showSenderName: true,
      additionalData: {
        'fromUserId': fromUserId,
        'fromUserName': fromUserName,
        'fromUserPhoto': fromUserPhoto ?? '',
        'isSuperChat': isSuperChat.toString(),
        'customMessage': customMessage ?? '',
      },
    );
    
  }

  /// DEPRECATED: Like bildirimi - sistem kaldırıldı, Chat Request kullanın
  @Deprecated('Use sendChatRequestNotification() instead - Like system removed')
  static Future<void> sendLikeNotification({
    required String toUserId,
    required String fromUserName,
    required bool isSuper,
    required bool isPremium,
  }) async {
    // Artık hiçbir şey yapmıyor - Like sistemi kaldırıldı
  }

  /// Gönderi beğeni bildirimi gönder
  static Future<void> sendPostLikeNotification({
    required String toUserId,
    required String fromUserName,
    required String postId,
    String? postContent,
  }) async {
    await NotificationService().sendNotificationToUser(
      targetUserId: toUserId,
      title: '👍 Gönderi Beğenisi!',
      body: '$fromUserName gönderini beğendi!',
      type: 'post_like',
      senderName: fromUserName,
      showSenderName: true,
      additionalData: {
        'postId': postId,
        'postContent': postContent ?? '',
      },
    );
  }

  /// Mesaj bildirimi gönder
  static Future<void> sendMessageNotification({
    required String toUserId,
    required String fromUserName,
    required String fromUserId,
    required String messageContent,
    String? chatId,
  }) async {
    // Mesaj içeriğini kısalt (çok uzunsa)
    String displayMessage = messageContent;
    if (messageContent.length > 50) {
      displayMessage = '${messageContent.substring(0, 47)}...';
    }
    
    await NotificationService().sendNotificationToUser(
      targetUserId: toUserId,
      title: fromUserName,
      body: displayMessage,
      type: 'message',
      senderId: fromUserId,
      senderName: fromUserName,
      showSenderName: true,
      additionalData: {
        'chatId': chatId ?? '',
        'messageContent': messageContent,
      },
    );
  }

  /// Tüm bildirimleri okundu olarak işaretle
  Future<void> markAllNotificationsAsRead() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final batch = _firestore.batch();
      final notifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .get();

      for (final doc in notifications.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
    }
  }

  /// Okunmamış bildirim sayısını al
  Stream<int> getUnreadNotificationCount() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(0);

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Muhtar kaybetme bildirimi gönder
  static Future<void> sendMayorLostNotification({
    required String toUserId,
    required String venueName,
    required String mayorType, // 'first_checkin' veya 'diamond'
    String? newMayorName,
  }) async {
    String title;
    String body;
    
    if (mayorType == 'first_checkin') {
      title = '👑 Ücretsiz Muhtarlık Kaybedildi';
      body = '$venueName\'de ücretsiz muhtarlığınızı kaybettiniz${newMayorName != null ? '. Yeni muhtar: $newMayorName' : ''}';
    } else {
      title = '💎 Elmas Muhtarlık Kaybedildi';
      body = '$venueName\'de elmas muhtarlığınızı kaybettiniz${newMayorName != null ? '. Yeni muhtar: $newMayorName' : ''}';
    }
    
    await NotificationService().sendNotificationToUser(
      targetUserId: toUserId,
      title: title,
      body: body,
      type: 'mayor_lost',
      senderName: newMayorName,
      showSenderName: newMayorName != null,
      additionalData: {
        'mayorType': mayorType,
        'venueName': venueName,
        'newMayorName': newMayorName ?? '',
      },
    );
  }

  /// Yeni muhtar olma bildirimi gönder
  static Future<void> sendMayorGainedNotification({
    required String toUserId,
    required String venueName,
    required String mayorType, // 'first_checkin' veya 'diamond'
    required int diamondsSpent,
  }) async {
    String title;
    String body;
    
    if (mayorType == 'first_checkin') {
      title = '👑 Ücretsiz Muhtar Oldunuz!';
      body = '$venueName\'de ücretsiz muhtar oldunuz! İlk check-in avantajınızı kullandınız.';
    } else {
      title = '💎 Elmas Muhtar Oldunuz!';
      body = '$venueName\'de $diamondsSpent elmas harcayarak muhtar oldunuz! Tebrikler!';
    }
    
    await NotificationService().sendNotificationToUser(
      targetUserId: toUserId,
      title: title,
      body: body,
      type: 'mayor_gained',
      additionalData: {
        'mayorType': mayorType,
        'venueName': venueName,
        'diamondsSpent': diamondsSpent.toString(),
      },
    );
  }

  /// Test bildirimi gönder (Debug amaçlı)
  static Future<void> sendTestNotification({
    required String targetUserId,
  }) async {
    await NotificationService().sendNotificationToUser(
      targetUserId: targetUserId,
      title: '🧪 Test Bildirimi',
      body: 'Bu bir test bildirimidir. ${DateTime.now()}',
      type: 'test',
      showSenderName: true,
      additionalData: {
        'isTest': 'true',
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
  }

  /// FCM Token debug bilgisi
  Future<void> debugTokenInfo() async {
    try {
      final token = await _messaging.getToken();
      final user = _auth.currentUser;
      
      
      if (user != null) {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
      }
    } catch (e) {
    }
  }

  /// Notification permissions debug
  Future<void> debugPermissions() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      
      if (Platform.isAndroid) {
        final permission = await Permission.notification.status;
      }
    } catch (e) {
    }
  }
}
