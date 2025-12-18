// lib/core/models/firestore_models.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// User Model
class UserModel {
  final String uid;
  final String email;
  final String name;
  final int age;
  final List<String> photos;
  final List<String> hobbies;
  final List<String> favoriteVenues;
  final GeoPoint? location;
  final String? city;
  final bool isPremium;
  final String? premiumType; // 🆕 Premium tipi (weekly/monthly/quarterly)
  final bool isActive;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final String? phoneNumber;
  final String? fcmToken;
  final int dailyChatRequestsRemaining; // 💬 Chat request limit
  final int superChatsRemaining; // 💬 IAP Super Chat balance
  final int rewindsRemaining;
  final DateTime? lastActiveAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> settings;
  
  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.age,
    required this.photos,
    required this.hobbies,
    required this.favoriteVenues,
    this.location,
    this.city,
    this.isPremium = false,
    this.premiumType,
    this.isActive = true,
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    this.phoneNumber,
    this.fcmToken,
    this.dailyChatRequestsRemaining = 5, // 💬 Default 5 chat/day
    this.superChatsRemaining = 0, // 💬 IAP Super Chat balance
    this.rewindsRemaining = 0,
    this.lastActiveAt,
    required this.createdAt,
    required this.updatedAt,
    Map<String, dynamic>? settings,
  }) : settings = settings ?? _defaultSettings();

  static Map<String, dynamic> _defaultSettings() => {
    'mapVisibility': true,
    'showAge': true,
    'showDistance': true,
    'notifications': {
      'matches': true,
      'messages': true,
      'likes': true,
      'superLikes': true,
    },
  };

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      age: data['age'] ?? 18,
      photos: List<String>.from(data['photos'] ?? []),
      hobbies: List<String>.from(data['hobbies'] ?? []),
      favoriteVenues: List<String>.from(data['favoriteVenues'] ?? []),
      location: data['location'],
      city: data['city'],
      isPremium: data['isPremium'] ?? false,
      premiumType: data['premiumType'], // 🆕 Premium tipi
      isActive: data['isActive'] ?? true,
      isEmailVerified: data['isEmailVerified'] ?? false,
      isPhoneVerified: data['isPhoneVerified'] ?? false,
      phoneNumber: data['phoneNumber'],
      fcmToken: data['fcmToken'],
      dailyChatRequestsRemaining: data['dailyChatRequestsRemaining'] ?? 5, // 💬
      superChatsRemaining: data['superChatsRemaining'] ?? 0, // 💬
      rewindsRemaining: data['rewindsRemaining'] ?? 0,
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      settings: data['settings'] ?? {},
    );
  }

  Map<String, dynamic> toFirestore() => {
    'email': email,
    'name': name,
    'age': age,
    'photos': photos,
    'hobbies': hobbies,
    'favoriteVenues': favoriteVenues,
    'location': location,
    'city': city,
    'isPremium': isPremium,
    'premiumType': premiumType, // 🆕 Premium tipi
    'isActive': isActive,
    'isEmailVerified': isEmailVerified,
    'isPhoneVerified': isPhoneVerified,
    'phoneNumber': phoneNumber,
    'fcmToken': fcmToken,
    'dailyChatRequestsRemaining': dailyChatRequestsRemaining, // 💬
    'superChatsRemaining': superChatsRemaining, // 💬
    'rewindsRemaining': rewindsRemaining,
    'lastActiveAt': lastActiveAt != null ? Timestamp.fromDate(lastActiveAt!) : FieldValue.serverTimestamp(),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
    'settings': settings,
  };
}

// Venue Model
class VenueModel {
  final String id;
  final String name;
  final String address;
  final GeoPoint location;
  final String city;
  final String? category;
  final String? photoUrl;
  final String? mayorUserId;
  final int checkInCount;
  final DateTime createdAt;
  
  VenueModel({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.city,
    this.category,
    this.photoUrl,
    this.mayorUserId,
    this.checkInCount = 0,
    required this.createdAt,
  });

  factory VenueModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return VenueModel(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      location: data['location'],
      city: data['city'] ?? '',
      category: data['category'],
      photoUrl: data['photoUrl'],
      mayorUserId: data['mayorUserId'],
      checkInCount: data['checkInCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'address': address,
    'location': location,
    'city': city,
    'category': category,
    'photoUrl': photoUrl,
    'mayorUserId': mayorUserId,
    'checkInCount': checkInCount,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

// Match Model
class MatchModel {
  final String id;
  final List<String> userIds;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final Map<String, bool> hasSeenLastMessage;
  final bool isActive;
  final DateTime matchedAt;
  
  MatchModel({
    required this.id,
    required this.userIds,
    this.lastMessage,
    this.lastMessageTime,
    required this.hasSeenLastMessage,
    this.isActive = true,
    required this.matchedAt,
  });

  factory MatchModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return MatchModel(
      id: doc.id,
      userIds: List<String>.from(data['userIds'] ?? []),
      lastMessage: data['lastMessage'],
      lastMessageTime: data['lastMessageTime'] != null 
        ? (data['lastMessageTime'] as Timestamp).toDate() 
        : null,
      hasSeenLastMessage: Map<String, bool>.from(data['hasSeenLastMessage'] ?? {}),
      isActive: data['isActive'] ?? true,
      matchedAt: (data['matchedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userIds': userIds,
    'lastMessage': lastMessage,
    'lastMessageTime': lastMessageTime != null 
      ? Timestamp.fromDate(lastMessageTime!) 
      : null,
    'hasSeenLastMessage': hasSeenLastMessage,
    'isActive': isActive,
    'matchedAt': Timestamp.fromDate(matchedAt),
  };
}

// Message Model
class MessageModel {
  final String id;
  final String matchId;
  final String senderId;
  final String receiverId;
  final String content;
  final String type; // text, image, location
  final bool isRead;
  final DateTime sentAt;
  final DateTime? readAt;
  
  MessageModel({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.type = 'text',
    this.isRead = false,
    required this.sentAt,
    this.readAt,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      matchId: data['matchId'] ?? '',
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      content: data['content'] ?? '',
      type: data['type'] ?? 'text',
      isRead: data['isRead'] ?? false,
      sentAt: (data['sentAt'] as Timestamp).toDate(),
      readAt: data['readAt'] != null 
        ? (data['readAt'] as Timestamp).toDate() 
        : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'matchId': matchId,
    'senderId': senderId,
    'receiverId': receiverId,
    'content': content,
    'type': type,
    'isRead': isRead,
    'sentAt': Timestamp.fromDate(sentAt),
    'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
  };
}

// CheckIn Model
class CheckInModel {
  final String id;
  final String userId;
  final String venueId;
  final GeoPoint location;
  final DateTime checkInTime;
  final String? photoUrl;
  final String? note;
  
  CheckInModel({
    required this.id,
    required this.userId,
    required this.venueId,
    required this.location,
    required this.checkInTime,
    this.photoUrl,
    this.note,
  });

  factory CheckInModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return CheckInModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      venueId: data['venueId'] ?? '',
      location: data['location'],
      checkInTime: (data['checkInTime'] as Timestamp).toDate(),
      photoUrl: data['photoUrl'],
      note: data['note'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userId': userId,
    'venueId': venueId,
    'location': location,
    'checkInTime': Timestamp.fromDate(checkInTime),
    'photoUrl': photoUrl,
    'note': note,
  };
}

// Like Model
class LikeModel {
  final String id;
  final String fromUserId;
  final String toUserId;
  final bool isSuperLike;
  final DateTime likedAt;
  
  LikeModel({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    this.isSuperLike = false,
    required this.likedAt,
  });

  factory LikeModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return LikeModel(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      toUserId: data['toUserId'] ?? '',
      isSuperLike: data['isSuperLike'] ?? false,
      likedAt: (data['likedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'fromUserId': fromUserId,
    'toUserId': toUserId,
    'isSuperLike': isSuperLike,
    'likedAt': Timestamp.fromDate(likedAt),
  };
}