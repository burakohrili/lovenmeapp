// lib/presentation/pages/messages/models/match_model.dart

class MatchModel {
  final String id;
  final String userId; // Karşı kullanıcının ID'si
  final String name;
  final int age;
  final String profileImage;
  final List<String> photos; // Birden fazla fotoğraf için
  final DateTime matchedAt;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final String? lastSeen;
  final List<String> commonVenues;
  final List<String> commonHobbies;
  final List<String> favoriteVenues; // Discover için
  final double distance; // Discover için
  final int commonCheckIns; // Discover için
  final bool isPremium; // Premium kullanıcı

  MatchModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.age,
    required this.profileImage,
    List<String>? photos,
    required this.matchedAt,
    this.lastMessage = '',
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastSeen,
    this.commonVenues = const [],
    this.commonHobbies = const [],
    this.favoriteVenues = const [],
    this.distance = 0.0,
    this.commonCheckIns = 0,
    this.isPremium = false,
  }) : photos = photos ?? [profileImage]; // Eğer photos yoksa profileImage'ı kullan

  // CopyWith metodu
  MatchModel copyWith({
    String? id,
    String? userId,
    String? name,
    int? age,
    String? profileImage,
    List<String>? photos,
    DateTime? matchedAt,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
    String? lastSeen,
    List<String>? commonVenues,
    List<String>? commonHobbies,
    List<String>? favoriteVenues,
    double? distance,
    int? commonCheckIns,
    bool? isPremium,
  }) {
    return MatchModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      age: age ?? this.age,
      profileImage: profileImage ?? this.profileImage,
      photos: photos ?? this.photos,
      matchedAt: matchedAt ?? this.matchedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      commonVenues: commonVenues ?? this.commonVenues,
      commonHobbies: commonHobbies ?? this.commonHobbies,
      favoriteVenues: favoriteVenues ?? this.favoriteVenues,
      distance: distance ?? this.distance,
      commonCheckIns: commonCheckIns ?? this.commonCheckIns,
      isPremium: isPremium ?? this.isPremium,
    );
  }

  // Zamandan beri geçen süreyi hesapla
  String get timeAgo {
    if (lastMessageTime == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(lastMessageTime!);
    
    if (difference.inDays > 7) {
      return '${difference.inDays ~/ 7} hafta önce';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} gün önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} saat önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} dakika önce';
    } else {
      return 'Şimdi';
    }
  }

  // Mock data oluşturucu - MESAJLAR İÇİN
  static List<MatchModel> getMockMatches() {
    return [
      
    ];
  }

  // DISCOVER İÇİN MOCK DATA - YÜKSEK ÇÖZÜNÜRLÜKLÜ FOTOĞRAFLARLA
  static List<MatchModel> getDiscoverCards() {
    return [
      
    ];
  }
}