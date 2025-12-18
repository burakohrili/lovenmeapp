// lib/presentation/pages/messages/models/message_model.dart

class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final MessageType type;
  final String? imageUrl;
  final String? voiceUrl;  
  final String? venueId;
  final String? venueName;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    required this.isRead,
    this.type = MessageType.text,
    this.imageUrl,
    this.voiceUrl,  
    this.venueId,
    this.venueName,
  });
  // CopyWith metodu
  MessageModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? message,
    DateTime? timestamp,
    bool? isRead,
    MessageType? type,
    String? imageUrl,
    String? venueId,
    String? venueName,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
      imageUrl: imageUrl ?? this.imageUrl,
      venueId: venueId ?? this.venueId,
      venueName: venueName ?? this.venueName,
    );
  }

  // Mesajın saatini formatla
  String get formattedTime {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Tarih gruplandırması için
  String get dateLabel {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays == 0) {
      return 'Bugün';
    } else if (difference.inDays == 1) {
      return 'Dün';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  // Mock mesajlar oluştur
  static List<MessageModel> getMockMessages(String matchId, String currentUserId) {
    final now = DateTime.now();
    
    switch (matchId) {
      case '1': // Ayşe ile sohbet
        return [
          MessageModel(
            id: 'm1',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Merhaba! 👋',
            timestamp: now.subtract(const Duration(hours: 3)),
            isRead: true,
          ),
          MessageModel(
            id: 'm2',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Selam Ayşe! Nasılsın?',
            timestamp: now.subtract(const Duration(hours: 2, minutes: 50)),
            isRead: true,
          ),
          MessageModel(
            id: 'm3',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'İyiyim teşekkürler, sen nasılsın? Profilinde Starbucks Alsancak\'ı görmüştüm',
            timestamp: now.subtract(const Duration(hours: 2, minutes: 45)),
            isRead: true,
          ),
          MessageModel(
            id: 'm4',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Ben de iyiyim. Evet oraya sık gidiyorum, sen de mi?',
            timestamp: now.subtract(const Duration(hours: 2, minutes: 40)),
            isRead: true,
          ),
          MessageModel(
            id: 'm5',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Aynen! Haftada 2-3 kez uğrarım. Belki denk gelmişizdir 😊',
            timestamp: now.subtract(const Duration(hours: 2, minutes: 35)),
            isRead: true,
          ),
          MessageModel(
            id: 'm6',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Yarın öğleden sonra orada olacağım, istersen buluşabiliriz?',
            timestamp: now.subtract(const Duration(minutes: 35)),
            isRead: true,
          ),
          MessageModel(
            id: 'm7',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Merhaba! Nasılsın? ☺️',
            timestamp: now.subtract(const Duration(minutes: 30)),
            isRead: false,
          ),
        ];
        
      case '2': // Zeynep ile sohbet
        return [
          MessageModel(
            id: 'm8',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Selam! Midpoint\'te check-in yaptığını gördüm',
            timestamp: now.subtract(const Duration(days: 1, hours: 5)),
            isRead: true,
          ),
          MessageModel(
            id: 'm9',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Evet, harika bir yer! Sen de gidiyor musun?',
            timestamp: now.subtract(const Duration(days: 1, hours: 4)),
            isRead: true,
          ),
          MessageModel(
            id: 'm10',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Favorilerimden biri! Canlı müzik olduğu günler muhteşem oluyor',
            timestamp: now.subtract(const Duration(days: 1, hours: 3)),
            isRead: true,
          ),
          MessageModel(
            id: 'm11',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Kesinlikle! Cuma akşamları genelde canlı müzik oluyor',
            timestamp: now.subtract(const Duration(hours: 3)),
            isRead: true,
          ),
          MessageModel(
            id: 'm12',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Yarın Alsancak\'ta buluşalım mı?',
            timestamp: now.subtract(const Duration(hours: 2)),
            isRead: true,
            type: MessageType.venue,
            venueName: 'Midpoint Alsancak',
          ),
        ];
        
      case '3': // Elif ile sohbet
        return [
          MessageModel(
            id: 'm13',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Merhaba Elif! 🌟',
            timestamp: now.subtract(const Duration(hours: 2)),
            isRead: true,
          ),
          MessageModel(
            id: 'm14',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Selam! Profil fotoğrafın çok güzel 🌟',
            timestamp: now.subtract(const Duration(hours: 1)),
            isRead: false,
          ),
        ];
        
      case '4': // Selin ile sohbet
        return [
          MessageModel(
            id: 'm15',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Hey! Spor salonına gidiyor musun?',
            timestamp: now.subtract(const Duration(days: 2)),
            isRead: true,
          ),
          MessageModel(
            id: 'm16',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Merhaba! Evet, haftada 3-4 gün gidiyorum',
            timestamp: now.subtract(const Duration(days: 2)),
            isRead: true,
          ),
          MessageModel(
            id: 'm17',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Süper! Ben de düzenli gidiyorum. Hangi salona gidiyorsun?',
            timestamp: now.subtract(const Duration(days: 1, hours: 12)),
            isRead: true,
          ),
          MessageModel(
            id: 'm18',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Mars Athletic Alsancak\'a gidiyorum',
            timestamp: now.subtract(const Duration(days: 1, hours: 6)),
            isRead: true,
          ),
          MessageModel(
            id: 'm19',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Görüşürüz! 👋',
            timestamp: now.subtract(const Duration(days: 1)),
            isRead: true,
          ),
        ];
        
      case '5': // Deniz ile yeni eşleşme
        return []; // Henüz mesaj yok
        
      case '6': // Ceren ile sohbet
        return [
          MessageModel(
            id: 'm20',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Merhaba Ceren! Sanatla ilgilendiğini gördüm 🎨',
            timestamp: now.subtract(const Duration(hours: 8)),
            isRead: true,
          ),
          MessageModel(
            id: 'm21',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Evet! Resim yapmayı çok seviyorum. Sen?',
            timestamp: now.subtract(const Duration(hours: 7)),
            isRead: true,
          ),
          MessageModel(
            id: 'm22',
            senderId: currentUserId,
            receiverId: matchId,
            message: 'Fotoğrafçılıkla ilgileniyorum ben de 📸',
            timestamp: now.subtract(const Duration(hours: 6, minutes: 30)),
            isRead: true,
          ),
          MessageModel(
            id: 'm23',
            senderId: matchId,
            receiverId: currentUserId,
            message: 'Teşekkürler! Sen de çok tatlısın 😊',
            timestamp: now.subtract(const Duration(hours: 6)),
            isRead: true,
          ),
        ];
        
      default:
        return [];
    }
  }
}

// Mesaj tipleri
enum MessageType {
  text,
  image,
  voice,
  venue,
  location,
  emoji
}