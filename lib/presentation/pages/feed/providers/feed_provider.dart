// lib/presentation/pages/feed/providers/feed_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feed_model.dart';

class FeedState {
  final List<FeedPost> posts;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  FeedState copyWith({
    List<FeedPost>? posts,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error ?? this.error,
    );
  }
}

class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier() : super(FeedState()) {
    loadFeed();
  }

  // Akışı yükle
  // loadFeed metodunu Firebase'e bağla
Future<void> loadFeed() async {
  state = state.copyWith(isLoading: true);
  
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('feed_posts')
        .orderBy('checkInTime', descending: true)
        .limit(20)
        .get();
    
    final posts = snapshot.docs.map((doc) {
      final data = doc.data();
      return FeedPost(
        id: doc.id,
        userId: data['userId'],
        userName: data['userName'],
        userAge: data['userAge'],
        userProfileImage: data['userProfileImage'],
        venueName: data['venueName'],
        venueAddress: data['venueAddress'],
        venueCategory: data['venueCategory'],
        venueId: data['venueId'] ?? data['venueReferenceId'] ?? '', // Venue'nin Place ID'si
        checkInTime: (data['checkInTime'] as Timestamp).toDate(),
        postImage: data['postImage'],
        caption: null,
        likeCount: data['likeCount'] ?? 0,
        commentCount: data['commentCount'] ?? 0,
        isLiked: false,
        latitude: data['latitude']?.toDouble(),
        longitude: data['longitude']?.toDouble(),
      );
    }).toList();
    
    state = state.copyWith(
      posts: posts,
      isLoading: false,
    );
  } catch (e) {
    state = state.copyWith(
      isLoading: false,
      error: 'Akış yüklenemedi',
    );
  }
}

  // Yenile
  Future<void> refreshFeed() async {
    await loadFeed();
  }

  // Daha fazla yükle (pagination)
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    
    // Simüle edilmiş daha fazla yükleme
    await Future.delayed(const Duration(seconds: 1));
    
    // Mock: Daha fazla post ekle
    // final newPosts = FeedPost.getMockFeedPosts()
    //     .map((post) => post.copyWith(
    //           id: '${post.id}_${DateTime.now().millisecondsSinceEpoch}',
    //         ))
    //     .toList();
    
    state = state.copyWith(
      posts: [...state.posts],
      hasMore: state.posts.length < 50, // 50'den fazla yüklenmesin
    );
  }

  // Beğen/Beğenme
  void toggleLike(String postId) {
    final updatedPosts = state.posts.map((post) {
      if (post.id == postId) {
        return post.copyWith(
          isLiked: !post.isLiked,
          likeCount: post.isLiked ? post.likeCount - 1 : post.likeCount + 1,
        );
      }
      return post;
    }).toList();
    
    state = state.copyWith(posts: updatedPosts);
  }

  // Yorum ekle
  // void addComment(String postId, String commentText, String userName, String userImage) {
  //   final updatedPosts = state.posts.map((post) {
  //     if (post.id == postId) {
  //       final newComment = Comment(
  //         id: 'comment_${DateTime.now().millisecondsSinceEpoch}',
  //         userId: 'current_user',
  //         userName: userName,
  //         userProfileImage: userImage,
  //         text: commentText,
  //         timestamp: DateTime.now(),
  //       );
        
  //       return post.copyWith(
  //         comments: [...post.comments, newComment],
  //         commentCount: post.commentCount + 1,
  //       );
  //     }
  //     return post;
  //   }).toList();
    
  //   state = state.copyWith(posts: updatedPosts);
  // }

  // Post sil
  void deletePost(String postId) {
    final updatedPosts = state.posts.where((post) => post.id != postId).toList();
    state = state.copyWith(posts: updatedPosts);
  }
}

// Provider
final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  return FeedNotifier();
});