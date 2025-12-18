// lib/core/services/message_rate_limiter_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Message Rate Limiter Service
/// 
/// Apple Guideline 4.3.0 - Spam Prevention
/// Kullanıcıların dakikada maksimum 30 mesaj göndermesine izin verir
class MessageRateLimiterService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Dakikada maksimum mesaj sayısı
  static const int maxMessagesPerMinute = 30;

  /// Kullanıcının mesaj gönderip gönderemeyeceğini kontrol et
  /// 
  /// Returns:
  /// - true: Mesaj gönderilebilir
  /// - false: Limit doldu, beklemeli
  static Future<MessageRateLimitResult> canSendMessage() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return MessageRateLimitResult(
          canSend: false,
          reason: 'Giriş yapmanız gerekiyor',
          messagesRemaining: 0,
          resetTime: null,
        );
      }

      // Son 1 dakikadaki mesajları say
      final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
      
      final recentMessages = await _firestore
          .collection('messages')
          .where('senderId', isEqualTo: user.uid)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(oneMinuteAgo))
          .orderBy('timestamp', descending: true)
          .get();

      final messageCount = recentMessages.docs.length;

      // Limit kontrolü
      if (messageCount >= maxMessagesPerMinute) {
        // İlk mesajın zamanını bul (en eski mesaj)
        final oldestMessage = recentMessages.docs.last;
        final oldestMessageTime = (oldestMessage.data()['timestamp'] as Timestamp).toDate();
        final resetTime = oldestMessageTime.add(const Duration(minutes: 1));
        final remainingSeconds = resetTime.difference(DateTime.now()).inSeconds;

        return MessageRateLimitResult(
          canSend: false,
          reason: 'Dakikada maksimum $maxMessagesPerMinute mesaj gönderebilirsiniz. '
                  'Lütfen $remainingSeconds saniye bekleyin.',
          messagesRemaining: 0,
          resetTime: resetTime,
        );
      }

      // Gönderebilir
      return MessageRateLimitResult(
        canSend: true,
        reason: null,
        messagesRemaining: maxMessagesPerMinute - messageCount,
        resetTime: null,
      );
    } catch (e) {
      // Hata durumunda izin ver (fail-open approach)
      return MessageRateLimitResult(
        canSend: true,
        reason: null,
        messagesRemaining: maxMessagesPerMinute,
        resetTime: null,
      );
    }
  }

  /// Premium kullanıcı için kontrol (opsiyonel - şimdilik tüm kullanıcılar aynı)
  static Future<MessageRateLimitResult> canSendMessageForPremium() async {
    // Premium kullanıcılar için de aynı limit
    // Gelecekte daha yüksek limit verilebilir
    return canSendMessage();
  }

  /// Kullanıcının son 1 dakikada kaç mesaj gönderdiğini getir
  static Future<int> getMessageCountInLastMinute(String userId) async {
    try {
      final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
      
      final recentMessages = await _firestore
          .collection('messages')
          .where('senderId', isEqualTo: userId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(oneMinuteAgo))
          .get();

      return recentMessages.docs.length;
    } catch (e) {
      return 0;
    }
  }

  /// Rate limit istatistiklerini getir (dashboard için)
  static Future<Map<String, dynamic>> getRateLimitStats() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {
          'messagesSentLastMinute': 0,
          'messagesRemaining': maxMessagesPerMinute,
          'canSend': false,
          'isRateLimited': false,
        };
      }

      final result = await canSendMessage();

      return {
        'messagesSentLastMinute': maxMessagesPerMinute - result.messagesRemaining,
        'messagesRemaining': result.messagesRemaining,
        'canSend': result.canSend,
        'isRateLimited': !result.canSend,
        'resetTime': result.resetTime?.toIso8601String(),
      };
    } catch (e) {
      return {
        'messagesSentLastMinute': 0,
        'messagesRemaining': maxMessagesPerMinute,
        'canSend': true,
        'isRateLimited': false,
      };
    }
  }
}

/// Message Rate Limit Result
class MessageRateLimitResult {
  /// Mesaj gönderilebilir mi?
  final bool canSend;

  /// Red sebebi (varsa)
  final String? reason;

  /// Kalan mesaj hakkı (bu dakika içinde)
  final int messagesRemaining;

  /// Limit sıfırlanma zamanı
  final DateTime? resetTime;

  MessageRateLimitResult({
    required this.canSend,
    this.reason,
    required this.messagesRemaining,
    this.resetTime,
  });

  /// Limit doldu mu?
  bool get isRateLimited => !canSend;

  /// Kalan saniye
  int get remainingSeconds {
    if (resetTime == null) return 0;
    return resetTime!.difference(DateTime.now()).inSeconds.clamp(0, 60);
  }

  /// Kullanıcı dostu mesaj
  String get userFriendlyMessage {
    if (canSend) {
      return 'Mesaj gönderebilirsiniz ($messagesRemaining mesaj hakkınız kaldı)';
    } else {
      return reason ?? 'Mesaj gönderemezsiniz';
    }
  }
}
