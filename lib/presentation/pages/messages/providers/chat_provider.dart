// lib/presentation/pages/messages/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match_model.dart';
import '../models/message_model.dart';

// Chat State
class ChatState {
  final List<MatchModel> matches;
  final Map<String, List<MessageModel>> messages;
  final MatchModel? selectedMatch;
  final bool isTyping;
  final String currentUserId;

  ChatState({
    this.matches = const [],
    this.messages = const {},
    this.selectedMatch,
    this.isTyping = false,
    this.currentUserId = 'current_user',
  });

  ChatState copyWith({
    List<MatchModel>? matches,
    Map<String, List<MessageModel>>? messages,
    MatchModel? selectedMatch,
    bool? isTyping,
    String? currentUserId,
  }) {
    return ChatState(
      matches: matches ?? this.matches,
      messages: messages ?? this.messages,
      selectedMatch: selectedMatch ?? this.selectedMatch,
      isTyping: isTyping ?? this.isTyping,
      currentUserId: currentUserId ?? this.currentUserId,
    );
  }

  // Toplam okunmamış mesaj sayısı
  int get totalUnreadCount {
    return matches.fold(0, (sum, match) => sum + match.unreadCount);
  }

  // Aktif (online) kullanıcı sayısı
  int get onlineMatchesCount {
    return matches.where((match) => match.isOnline).length;
  }

  // Yeni eşleşmeler (24 saat içinde)
  List<MatchModel> get newMatches {
    final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
    return matches
        .where((match) => match.matchedAt.isAfter(oneDayAgo))
        .toList();
  }

  // Mesajlaşılan eşleşmeler
  List<MatchModel> get activeChats {
    return matches
        .where((match) => match.lastMessage.isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a.lastMessageTime == null) return 1;
        if (b.lastMessageTime == null) return -1;
        return b.lastMessageTime!.compareTo(a.lastMessageTime!);
      });
  }
}

// Chat Notifier
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(ChatState()) {
    _initializeMatches();
  }

  // Eşleşmeleri yükle
  void _initializeMatches() {
    final mockMatches = MatchModel.getMockMatches();
    state = state.copyWith(matches: mockMatches);
    
    // Her eşleşme için mesajları yükle
    for (var match in mockMatches) {
      loadMessages(match.id);
    }
  }

  // Mesajları yükle
  void loadMessages(String matchId) {
    final messageList = MessageModel.getMockMessages(matchId, state.currentUserId);
    final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
    updatedMessages[matchId] = messageList;
    state = state.copyWith(messages: updatedMessages);
  }

  // Mesaj gönder
  void sendMessage({
    required String matchId,
    required String message,
    MessageType type = MessageType.text,
    String? imageUrl,
    String? venueId,
    String? venueName,
  }) {
    final newMessage = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: state.currentUserId,
      receiverId: matchId,
      message: message,
      timestamp: DateTime.now(),
      isRead: false,
      type: type,
      imageUrl: imageUrl,
      venueId: venueId,
      venueName: venueName,
    );

    // Mesajı listeye ekle
    final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
    updatedMessages[matchId] = [...(updatedMessages[matchId] ?? []), newMessage];

    // Eşleşmenin son mesajını güncelle
    final updatedMatches = state.matches.map((match) {
      if (match.id == matchId) {
        return match.copyWith(
          lastMessage: message,
          lastMessageTime: DateTime.now(),
        );
      }
      return match;
    }).toList();

    state = state.copyWith(
      messages: updatedMessages,
      matches: updatedMatches,
    );

    // Fake yanıt simülasyonu (3 saniye sonra)
    if (type == MessageType.text && message.isNotEmpty) {
      Future.delayed(const Duration(seconds: 3), () {
        _simulateReply(matchId);
      });
    }
  }

  // Otomatik yanıt simülasyonu
  void _simulateReply(String matchId) {
    final replies = [
      'Harika! 😊',
      'Katılıyorum 👍',
      'Çok güzel!',
      'Teşekkürler 🌟',
      'Süper bir fikir!',
      'Kesinlikle!',
      'Yarın görüşürüz o zaman',
      'Tamam, anlaştık 😄',
    ];

    final randomReply = replies[DateTime.now().millisecond % replies.length];
    
    final replyMessage = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: matchId,
      receiverId: state.currentUserId,
      message: randomReply,
      timestamp: DateTime.now(),
      isRead: false,
    );

    // Yanıtı ekle
    final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
    updatedMessages[matchId] = [...(updatedMessages[matchId] ?? []), replyMessage];

    // Eşleşmenin son mesajını ve okunmamış sayısını güncelle
    final updatedMatches = state.matches.map((match) {
      if (match.id == matchId) {
        return match.copyWith(
          lastMessage: randomReply,
          lastMessageTime: DateTime.now(),
          unreadCount: match.unreadCount + 1,
        );
      }
      return match;
    }).toList();

    state = state.copyWith(
      messages: updatedMessages,
      matches: updatedMatches,
    );
  }

  // Mesajları okundu olarak işaretle
  void markAsRead(String matchId) {
    // Mesajları okundu yap
    final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
    if (updatedMessages[matchId] != null) {
      updatedMessages[matchId] = updatedMessages[matchId]!.map((msg) {
        if (msg.receiverId == state.currentUserId && !msg.isRead) {
          return msg.copyWith(isRead: true);
        }
        return msg;
      }).toList();
    }

    // Eşleşmenin okunmamış sayısını sıfırla
    final updatedMatches = state.matches.map((match) {
      if (match.id == matchId) {
        return match.copyWith(unreadCount: 0);
      }
      return match;
    }).toList();

    state = state.copyWith(
      messages: updatedMessages,
      matches: updatedMatches,
    );
  }

  // Seçili eşleşmeyi ayarla
  void selectMatch(MatchModel? match) {
    state = state.copyWith(selectedMatch: match);
    if (match != null) {
      markAsRead(match.id);
    }
  }

  // Yazıyor göstergesi
  void setTyping(bool isTyping) {
    state = state.copyWith(isTyping: isTyping);
  }

  // Eşleşmeyi sil
  void deleteMatch(String matchId) {
    final updatedMatches = state.matches.where((m) => m.id != matchId).toList();
    final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
    updatedMessages.remove(matchId);
    
    state = state.copyWith(
      matches: updatedMatches,
      messages: updatedMessages,
    );
  }

  // Mesajı sil
  void deleteMessage(String matchId, String messageId) {
    final updatedMessages = Map<String, List<MessageModel>>.from(state.messages);
    if (updatedMessages[matchId] != null) {
      updatedMessages[matchId] = updatedMessages[matchId]!
          .where((msg) => msg.id != messageId)
          .toList();
    }
    state = state.copyWith(messages: updatedMessages);
  }
}

// Provider
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});

// Computed Providers
final totalUnreadProvider = Provider<int>((ref) {
  final chatState = ref.watch(chatProvider);
  return chatState.totalUnreadCount;
});

final newMatchesProvider = Provider<List<MatchModel>>((ref) {
  final chatState = ref.watch(chatProvider);
  return chatState.newMatches;
});

final activeChatsProvider = Provider<List<MatchModel>>((ref) {
  final chatState = ref.watch(chatProvider);
  return chatState.activeChats;
});