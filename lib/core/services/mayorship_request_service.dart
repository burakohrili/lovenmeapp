// lib/core/services/mayorship_request_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🛡️ Race condition ve duplicate request koruması için service
class MayorshipRequestService {
  static final MayorshipRequestService _instance = MayorshipRequestService._internal();
  factory MayorshipRequestService() => _instance;
  MayorshipRequestService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 🛡️ Aktif request'leri takip et (duplicate prevention)
  static final Set<String> _activeRequests = <String>{};
  
  // 🛡️ Rate limiting için (5 dakikada max 3 request)
  static final Map<String, List<DateTime>> _userRequestHistory = <String, List<DateTime>>{};

    /// 🛡️ Quick check if user can make a request (without executing)
  Future<bool> canMakeRequest(String venueId, String userId, String requestType) async {
    final requestKey = '${userId}_$venueId';
    final now = DateTime.now();

    try {
      // 1. Active request kontrolü
      if (_activeRequests.contains(requestKey)) {
        return false;
      }

      // 2. Rate limiting kontrolü
      final lastRequestKey = '${userId}_last_request';
      final prefs = await SharedPreferences.getInstance();
      final lastRequestTime = prefs.getInt(lastRequestKey);
      
      if (lastRequestTime != null) {
        final lastRequest = DateTime.fromMillisecondsSinceEpoch(lastRequestTime);
        final timeSinceLastRequest = now.difference(lastRequest);
        
        if (timeSinceLastRequest.inMinutes < 5) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 🛡️ Main request handler with comprehensive deduplication
  Future<Map<String, dynamic>> requestMayorship({
    required String venueId,
    required String venueName,
    required int amount,
    required String requestType, // 'normal' veya 'buy_now'
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': 'user_not_authenticated',
        'message': 'Kullanıcı giriş yapmamış',
      };
    }

    final userId = user.uid;
    final requestKey = '${userId}_$venueId';
    final now = DateTime.now();

    try {
      // 🛡️ 1. Active request kontrolü
      if (_activeRequests.contains(requestKey)) {
        return {
          'success': false,
          'error': 'request_in_progress',
          'message': 'Bu mekana zaten bir muhtarlık işlemi devam ediyor',
        };
      }

      // 🛡️ 2. Rate limiting kontrolü
      final userHistory = _userRequestHistory[userId] ?? [];
      final recentRequests = userHistory
          .where((timestamp) => now.difference(timestamp).inMinutes <= 5)
          .toList();

      if (recentRequests.length >= 3) {
        return {
          'success': false,
          'error': 'rate_limit_exceeded',
          'message': 'Son 5 dakika içinde çok fazla işlem yaptınız. Lütfen bekleyin.',
        };
      }

      // 🛡️ 3. Firestore duplicate kontrolü
      final recentTransaction = await _checkRecentTransactions(userId, venueId, amount);
      if (recentTransaction != null) {
        return {
          'success': false,
          'error': 'duplicate_transaction',
          'message': 'Son 3 dakika içinde aynı işlemi zaten yaptınız',
          'existingTransaction': recentTransaction,
        };
      }

      // 🛡️ 4. Request'i aktif listesine ekle
      _activeRequests.add(requestKey);
      
      // 🛡️ 5. Rate limiting history'e ekle
      userHistory.add(now);
      _userRequestHistory[userId] = userHistory;


      // 🚀 6. Asıl işlemi yap (CheckinService'e delegate et)
      Map<String, dynamic> result;
      if (requestType == 'buy_now') {
        result = await _executeBuyNowRequest(venueId, venueName, amount);
      } else {
        result = await _executeNormalRequest(venueId, venueName, amount);
      }

      // 🛡️ 7. Success durumunda deduplication ID ekle
      if (result['success'] == true) {
        result['deduplicationId'] = '${userId}_${venueId}_${now.millisecondsSinceEpoch}';
      }

      return result;

    } catch (e) {
      return {
        'success': false,
        'error': 'request_failed',
        'message': 'İşlem sırasında hata oluştu: $e',
      };
    } finally {
      // 🛡️ 8. Request'i aktif listesinden çıkar
      _activeRequests.remove(requestKey);
      
      // 🛡️ 9. Timeout ile cleanup (memory leak prevention)
      Timer(const Duration(minutes: 5), () {
        _cleanupOldRequests(userId);
      });
    }
  }

  /// Firestore'da son işlemleri kontrol et
  Future<Map<String, dynamic>?> _checkRecentTransactions(String userId, String venueId, int amount) async {
    try {
      final cutoffTime = DateTime.now().subtract(const Duration(minutes: 3));
      
      final query = await _firestore
          .collection('diamond_transactions')
          .where('userId', isEqualTo: userId)
          .where('venueId', isEqualTo: venueId)
          .where('amount', isEqualTo: amount)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoffTime))
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        return {
          'id': doc.id,
          'timestamp': doc.data()['timestamp'],
          'type': doc.data()['type'],
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Normal mayorship request execute
  Future<Map<String, dynamic>> _executeNormalRequest(String venueId, String venueName, int amount) async {
    // CheckinService'in atomic metodunu çağır
    // Bu import gerekecek: import '../../presentation/pages/map/services/checkin_service.dart';
    // Şimdilik placeholder return
    return {
      'success': true,
      'message': 'Normal mayorship request executed (placeholder)',
    };
  }

  /// Buy Now request execute
  Future<Map<String, dynamic>> _executeBuyNowRequest(String venueId, String venueName, int amount) async {
    // CheckinService'in buy now atomic metodunu çağır
    // Şimdilik placeholder return
    return {
      'success': true,
      'message': 'Buy now request executed (placeholder)',
    };
  }

  /// Memory cleanup - eski request history'leri temizle
  void _cleanupOldRequests(String userId) {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    final userHistory = _userRequestHistory[userId];
    
    if (userHistory != null) {
      userHistory.removeWhere((timestamp) => timestamp.isBefore(cutoff));
      
      if (userHistory.isEmpty) {
        _userRequestHistory.remove(userId);
      }
    }
  }

  /// 🧹 Manual cleanup - test için
  static void clearRequestHistory() {
    _activeRequests.clear();
    _userRequestHistory.clear();
  }

  /// 📊 Debug: Aktif request sayısını getir
  static int getActiveRequestCount() {
    return _activeRequests.length;
  }

  /// 📊 Debug: User request history getir
  static List<DateTime>? getUserRequestHistory(String userId) {
    return _userRequestHistory[userId];
  }
}
