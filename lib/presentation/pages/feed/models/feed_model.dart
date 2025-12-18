// lib/presentation/pages/feed/models/feed_model.dart

import 'package:flutter/material.dart';

class FeedPost {
    final String id;
    final String userId;
    final String userName;
    final int userAge;
    final String userProfileImage;
    final String venueName;
    final String venueAddress;
    final String venueCategory;
    final String venueId; // Venue'nin Place ID'si
    final DateTime checkInTime;
    final String? postImage;
    final String? caption;
    final int likeCount;
    final int commentCount;
    final bool isLiked;
    final List<String> likedBy;
    final double? latitude;
    final double? longitude;

    FeedPost({
      required this.id,
      required this.userId,
      required this.userName,
      required this.userAge,
      required this.userProfileImage,
      required this.venueName,
      required this.venueAddress,
      required this.venueCategory,
      required this.venueId, // Venue'nin Place ID'si
      required this.checkInTime,
      this.postImage,
      this.caption,
      this.likeCount = 0,
      this.commentCount = 0,
      this.isLiked = false,
      this.likedBy = const [],
      this.latitude,
      this.longitude,
    });

  // Zaman hesaplama
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(checkInTime);
    
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

  // Mekan kategorisi ikonu
  IconData get categoryIcon {
    switch (venueCategory.toLowerCase()) {
      case 'cafe':
      case 'kafe':
        return Icons.coffee;
      case 'restaurant':
      case 'restoran':
        return Icons.restaurant;
      case 'bar':
        return Icons.local_bar;
      case 'gym':
      case 'spor':
        return Icons.fitness_center;
      case 'park':
        return Icons.park;
      case 'sinema':
      case 'cinema':
        return Icons.movie;
      case 'alışveriş':
      case 'shopping':
        return Icons.shopping_bag;
      default:
        return Icons.place;
    }
  }

  FeedPost copyWith({
    String? id,
    String? userId,
    String? userName,
    int? userAge,
    String? userProfileImage,
    String? venueName,
    String? venueAddress,
    String? venueCategory,
    String? venueId,
    DateTime? checkInTime,
    String? postImage,
    String? caption,
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    List<String>? likedBy,
    // List<Comment>? comments,
    double? latitude,
    double? longitude,
  }) {
    return FeedPost(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAge: userAge ?? this.userAge,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      venueName: venueName ?? this.venueName,
      venueAddress: venueAddress ?? this.venueAddress,
      venueCategory: venueCategory ?? this.venueCategory,
      venueId: venueId ?? this.venueId,
      checkInTime: checkInTime ?? this.checkInTime,
      postImage: postImage ?? this.postImage,
      caption: caption ?? this.caption,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      likedBy: likedBy ?? this.likedBy,
      // comments: comments ?? this.comments,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  // Mock data oluştur - CAPTION'LAR KALDIRILDI
// static List<FeedPost> getMockFeedPosts() {
//   final now = DateTime.now();
  
//   return [
//     FeedPost(
//       id: 'post1',
//       userId: 'user1',
//       userName: 'Ayşe',
//       userAge: 25,
//       userProfileImage: 'https://randomuser.me/api/portraits/women/1.jpg',
//       venueName: 'Starbucks Alsancak',
//       venueAddress: 'Alsancak, İzmir',
//       venueCategory: 'Cafe',
//       checkInTime: now.subtract(const Duration(minutes: 30)),
//       postImage: 'https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=1080&h=1080&fit=crop',
//       caption: null, // KALDIRILDI
//       likeCount: 24,
//       commentCount: 5,
//       isLiked: true,
//       latitude: 38.4237,
//       longitude: 27.1428,
//     ),
//     FeedPost(
//       id: 'post2',
//       userId: 'user2',
//       userName: 'Zeynep',
//       userAge: 28,
//       userProfileImage: 'https://randomuser.me/api/portraits/women/2.jpg',
//       venueName: 'Midpoint Alsancak',
//       venueAddress: 'Kıbrıs Şehitleri Cad., İzmir',
//       venueCategory: 'Bar',
//       checkInTime: now.subtract(const Duration(hours: 2)),
//       postImage: 'https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=1080&h=1080&fit=crop',
//       caption: null, // KALDIRILDI
//       likeCount: 45,
//       commentCount: 12,
//       isLiked: false,
//       latitude: 38.4250,
//       longitude: 27.1410,
//     ),
//     FeedPost(
//       id: 'post3',
//       userId: 'user3',
//       userName: 'Elif',
//       userAge: 23,
//       userProfileImage: 'https://randomuser.me/api/portraits/women/3.jpg',
//       venueName: 'Kahve Dünyası',
//       venueAddress: 'Karşıyaka, İzmir',
//       venueCategory: 'Cafe',
//       checkInTime: now.subtract(const Duration(hours: 5)),
//       postImage: null, // Fotoğrafsız check-in
//       caption: null, // KALDIRILDI
//       likeCount: 18,
//       commentCount: 3,
//       isLiked: true,
//       latitude: 38.4555,
//       longitude: 27.1200,
//     ),
//     FeedPost(
//       id: 'post4',
//       userId: 'user4',
//       userName: 'Selin',
//       userAge: 26,
//       userProfileImage: 'https://randomuser.me/api/portraits/women/4.jpg',
//       venueName: 'Mars Athletic',
//       venueAddress: 'Bostanlı, İzmir',
//       venueCategory: 'Gym',
//       checkInTime: now.subtract(const Duration(days: 1)),
//       postImage: 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1080&h=1080&fit=crop',
//       caption: null, // KALDIRILDI
//       likeCount: 32,
//       commentCount: 8,
//       isLiked: false,
//       latitude: 38.4600,
//       longitude: 27.0900,
//     ),
//     FeedPost(
//       id: 'post5',
//       userId: 'user5',
//       userName: 'Deniz',
//       userAge: 24,
//       userProfileImage: 'https://randomuser.me/api/portraits/women/5.jpg',
//       venueName: 'Kordon',
//       venueAddress: 'Alsancak Kordon, İzmir',
//       venueCategory: 'Park',
//       checkInTime: now.subtract(const Duration(days: 1, hours: 3)),
//       postImage: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=1080&h=1080&fit=crop',
//       caption: null, // KALDIRILDI
//       likeCount: 67,
//       commentCount: 15,
//       isLiked: true,
//       latitude: 38.4350,
//       longitude: 27.1450,
//     ),
//     FeedPost(
//       id: 'post6',
//       userId: 'user6',
//       userName: 'Ceren',
//       userAge: 27,
//       userProfileImage: 'https://randomuser.me/api/portraits/women/6.jpg',
//       venueName: 'Agora AVM',
//       venueAddress: 'Balçova, İzmir',
//       venueCategory: 'Alışveriş',
//       checkInTime: now.subtract(const Duration(days: 2)),
//       postImage: null, // Fotoğrafsız check-in
//       caption: null, // KALDIRILDI
//       likeCount: 21,
//       commentCount: 4,
//       isLiked: false,
//       latitude: 38.3900,
//       longitude: 27.0400,
//     ),
//   ];
// }
// }

// Yorum modeli
// class Comment {
//   final String id;
//   final String userId;
//   final String userName;
//   final String userProfileImage;
//   final String text;
//   final DateTime timestamp;

//   Comment({
//     required this.id,
//     required this.userId,
//     required this.userName,
//     required this.userProfileImage,
//     required this.text,
//     required this.timestamp,
//   });

//   String get timeAgo {
//     final now = DateTime.now();
//     final difference = now.difference(timestamp);
    
//     if (difference.inDays > 0) {
//       return '${difference.inDays}g';
//     } else if (difference.inHours > 0) {
//       return '${difference.inHours}s';
//     } else if (difference.inMinutes > 0) {
//       return '${difference.inMinutes}d';
//     } else {
//       return 'Şimdi';
//     }
//   }
 }