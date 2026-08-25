// lib/core/models/chat_request_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Chat request tipi
enum ChatRequestType {
  normal,      // Normal chat isteği
  superChat,   // Super chat (mesaj ile)
}

/// Chat request durumu
enum ChatRequestStatus {
  pending,   // Bekliyor
  accepted,  // Kabul edildi
  rejected,  // Reddedildi
  expired,   // Süresi doldu (30 gün)
}

/// Chat Request Model
class ChatRequest {
  final String id;
  final String fromUserId;
  final String toUserId;
  final ChatRequestType type;
  final ChatRequestStatus status;
  final String? message; // Super chat için mesaj (max 20 karakter) - Bu mesaj kabul edildiğinde ilk mesaj olarak gönderilir
  final DateTime timestamp;
  final DateTime? respondedAt;
  final DateTime? expiresAt; // 30 gün sonrası

  ChatRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.type,
    required this.status,
    this.message,
    required this.timestamp,
    this.respondedAt,
    this.expiresAt,
  });

  /// Firestore'dan ChatRequest oluştur
  factory ChatRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return ChatRequest(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      toUserId: data['toUserId'] ?? '',
      type: _parseType(data['type']),
      status: _parseStatus(data['status']),
      message: data['message'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      respondedAt: data['respondedAt'] != null 
          ? (data['respondedAt'] as Timestamp).toDate() 
          : null,
      expiresAt: data['expiresAt'] != null 
          ? (data['expiresAt'] as Timestamp).toDate() 
          : null,
    );
  }

  /// Firestore'a kaydetmek için Map'e çevir
  Map<String, dynamic> toFirestore() {
    return {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'type': type.name,
      'status': status.name,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'respondedAt': respondedAt != null 
          ? Timestamp.fromDate(respondedAt!) 
          : null,
      'expiresAt': expiresAt != null 
          ? Timestamp.fromDate(expiresAt!) 
          : null,
    };
  }

  /// String'den ChatRequestType parse et
  static ChatRequestType _parseType(String? typeString) {
    switch (typeString) {
      case 'super':
      case 'superChat':
        return ChatRequestType.superChat;
      case 'normal':
      default:
        return ChatRequestType.normal;
    }
  }

  /// String'den ChatRequestStatus parse et
  static ChatRequestStatus _parseStatus(String? statusString) {
    switch (statusString) {
      case 'accepted':
        return ChatRequestStatus.accepted;
      case 'rejected':
        return ChatRequestStatus.rejected;
      case 'expired':
        return ChatRequestStatus.expired;
      case 'pending':
      default:
        return ChatRequestStatus.pending;
    }
  }

  /// Pending durumda mı?
  bool get isPending => status == ChatRequestStatus.pending;

  /// Super chat mi?
  bool get isSuperChat => type == ChatRequestType.superChat;

  /// Mesaj var mı?
  bool get hasMessage => message != null && message!.isNotEmpty;

  /// Süresi dolmuş mu?
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Ne kadar zaman önce gönderildi?
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} gün önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} saat önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} dakika önce';
    } else {
      return 'Az önce';
    }
  }

  /// Copy with
  ChatRequest copyWith({
    String? id,
    String? fromUserId,
    String? toUserId,
    ChatRequestType? type,
    ChatRequestStatus? status,
    String? message,
    DateTime? timestamp,
    DateTime? respondedAt,
    DateTime? expiresAt,
  }) {
    return ChatRequest(
      id: id ?? this.id,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      type: type ?? this.type,
      status: status ?? this.status,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      respondedAt: respondedAt ?? this.respondedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

/// Chat Request ile ilgili validasyon sonucu
class ChatRequestValidationResult {
  final bool canSend;
  final String? errorMessage;
  final bool shouldShowPremiumInfo;

  const ChatRequestValidationResult({
    required this.canSend,
    this.errorMessage,
    this.shouldShowPremiumInfo = false,
  });

  static const ChatRequestValidationResult success = 
      ChatRequestValidationResult(canSend: true);

  static ChatRequestValidationResult error(String message) => 
      ChatRequestValidationResult(
        canSend: false,
        errorMessage: message,
      );

  static ChatRequestValidationResult limitReached() => 
      const ChatRequestValidationResult(
        canSend: false,
        errorMessage: 'Günlük chat isteği limitiniz doldu',
        shouldShowPremiumInfo: true,
      );

  static ChatRequestValidationResult insufficientSuperChats() => 
      const ChatRequestValidationResult(
        canSend: false,
        errorMessage: 'Öne çıkan istek hakkınız bulunmuyor',
        shouldShowPremiumInfo: true,
      );

  static ChatRequestValidationResult alreadySent() => 
      const ChatRequestValidationResult(
        canSend: false,
        errorMessage: 'Bu kullanıcıya zaten chat isteği göndermişsiniz',
      );

  static ChatRequestValidationResult alreadyMatched() => 
      const ChatRequestValidationResult(
        canSend: false,
        errorMessage: 'Bu kullanıcı ile zaten bağlantı kurmuşsunuz',
      );

  static ChatRequestValidationResult selfRequest() => 
      const ChatRequestValidationResult(
        canSend: false,
        errorMessage: 'Kendinize chat isteği gönderemezsiniz',
      );

  static ChatRequestValidationResult blocked() => 
      const ChatRequestValidationResult(
        canSend: false,
        errorMessage: 'Bu kullanıcıya chat isteği gönderemezsiniz',
      );
}
