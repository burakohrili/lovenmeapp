// lib/core/services/offline_recovery_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// 📡 Offline durumlarında işlem kaybını önleyen recovery service
class OfflineRecoveryService {
  static final OfflineRecoveryService _instance = OfflineRecoveryService._internal();
  factory OfflineRecoveryService() => _instance;
  OfflineRecoveryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 🔑 SharedPreferences keys
  static const String PENDING_TRANSACTIONS_KEY = 'pending_diamond_transactions';
  static const String LAST_RECOVERY_KEY = 'last_recovery_attempt';
  
  // 📡 Network monitoring
  Timer? _networkCheckTimer;
  bool _isOnline = true;
  bool _recoveryInProgress = false;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    await _checkConnectivity();
    _startNetworkMonitoring();
    
    // App açılışında pending transactions'ları kontrol et
    if (_isOnline) {
      await processPendingTransactions();
    }
  }

  /// 📡 Basic network monitoring başlat
  void _startNetworkMonitoring() {
    _networkCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      final wasOffline = !_isOnline;
      await _checkConnectivity();
      
      
      // Offline'dan online'a geçince recovery başlat
      if (wasOffline && _isOnline) {
        await Future.delayed(const Duration(seconds: 2)); // Network stabilize olsun
        await processPendingTransactions();
      }
    });
  }

  /// 📡 Basic connectivity check
  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      _isOnline = false;
    }
  }

  /// 💾 Offline durumda pending transaction kaydet
  Future<void> savePendingTransaction({
    required String venueId,
    required String venueName,
    required int amount,
    required String type, // 'mayorship_purchase' veya 'buy_now_mayorship'
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final pendingTx = {
        'venueId': venueId,
        'venueName': venueName,
        'amount': amount,
        'type': type,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'userId': user.uid,
        'attemptCount': 0,
        'id': '${user.uid}_${venueId}_${DateTime.now().millisecondsSinceEpoch}',
      };
      
      final existing = prefs.getStringList(PENDING_TRANSACTIONS_KEY) ?? [];
      existing.add(jsonEncode(pendingTx));
      await prefs.setStringList(PENDING_TRANSACTIONS_KEY, existing);
      
    } catch (e) {
    }
  }

  /// 🔄 Pending transactions'ları process et
  Future<void> processPendingTransactions() async {
    if (_recoveryInProgress || !_isOnline) {
      return;
    }

    _recoveryInProgress = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingList = prefs.getStringList(PENDING_TRANSACTIONS_KEY) ?? [];
      
      if (pendingList.isEmpty) {
        return;
      }

      
      final successful = <String>[];
      final failed = <String>[];
      
      for (final txJson in pendingList) {
        try {
          final tx = jsonDecode(txJson) as Map<String, dynamic>;
          final age = DateTime.now().millisecondsSinceEpoch - (tx['timestamp'] as int);
          
          // 1 saatten eski işlemleri abandon et
          if (age > const Duration(hours: 1).inMilliseconds) {
            successful.add(txJson); // Remove from pending
            continue;
          }
          
          // Max 3 deneme
          final attemptCount = tx['attemptCount'] as int;
          if (attemptCount >= 3) {
            await _logFailedRecovery(tx, 'max_attempts_reached');
            successful.add(txJson); // Remove from pending
            continue;
          }
          
          // Recovery attempt
          final result = await _attemptRecovery(tx);
          
          if (result['success']) {
            successful.add(txJson);
          } else {
            // Attempt count artır
            tx['attemptCount'] = attemptCount + 1;
            failed.add(jsonEncode(tx));
          }
          
        } catch (e) {
          failed.add(txJson); // Keep for retry
        }
      }
      
      // Update pending list
      await prefs.setStringList(PENDING_TRANSACTIONS_KEY, failed);
      
      // Update last recovery time
      await prefs.setInt(LAST_RECOVERY_KEY, DateTime.now().millisecondsSinceEpoch);
      
      
    } finally {
      _recoveryInProgress = false;
    }
  }

  /// 🔄 Single transaction recovery attempt
  Future<Map<String, dynamic>> _attemptRecovery(Map<String, dynamic> tx) async {
    try {
      final venueId = tx['venueId'] as String;
      final amount = tx['amount'] as int;
      final userId = tx['userId'] as String;
      final type = tx['type'] as String;
      
      // 1. Mayor durumunu kontrol et
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final mayorDoc = await _firestore
          .collection('daily_mayors')
          .doc('${venueId}_$today')
          .get();
      
      // 2. User'ın transaction history'sini kontrol et
      final userTransactions = await _firestore
          .collection('diamond_transactions')
          .where('userId', isEqualTo: userId)
          .where('venueId', isEqualTo: venueId)
          .where('amount', isEqualTo: amount)
          .where('type', isEqualTo: type)
          .where('timestamp', isGreaterThan: 
              Timestamp.fromMillisecondsSinceEpoch(tx['timestamp'] as int))
          .get();
      
      // 3. Eğer transaction zaten varsa, duplicate
      if (userTransactions.docs.isNotEmpty) {
        return {
          'success': true,
          'action': 'duplicate_found',
          'message': 'Transaction already exists in Firestore',
        };
      }
      
      // 4. Mayor durumuna göre compensation logic
      if (mayorDoc.exists && mayorDoc.data()!['userId'] == userId) {
        // User muhtar olmuş ama elması düşmemiş - compensation yap
        return await _performCompensation(tx);
      } else {
        // User muhtar olamamış - refund yap
        return await _performRefund(tx);
      }
      
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 💰 Compensation: User muhtar olmuş ama elmas düşmemiş
  Future<Map<String, dynamic>> _performCompensation(Map<String, dynamic> tx) async {
    try {
      final userId = tx['userId'] as String;
      final amount = tx['amount'] as int;
      
      // User'ın current balance'ını al
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User not found for compensation');
      }
      
      final currentBalance = userDoc.data()!['diamonds'] ?? 0;
      
      // Atomic compensation
      await _firestore.runTransaction((transaction) async {
        transaction.update(_firestore.collection('users').doc(userId), {
          'diamonds': currentBalance - amount,
          'lastDiamondUpdate': FieldValue.serverTimestamp(),
        });
        
        // Compensation log
        final logRef = _firestore.collection('diamond_transactions').doc();
        transaction.set(logRef, {
          'userId': userId,
          'venueId': tx['venueId'],
          'venueName': tx['venueName'],
          'amount': amount,
          'type': 'offline_compensation',
          'timestamp': FieldValue.serverTimestamp(),
          'originalTimestamp': Timestamp.fromMillisecondsSinceEpoch(tx['timestamp'] as int),
          'recoveryAction': 'compensation',
          'previousBalance': currentBalance,
          'newBalance': currentBalance - amount,
        });
      });
      
      return {
        'success': true,
        'action': 'compensated',
        'message': 'User was mayor, diamonds deducted as compensation',
      };
      
    } catch (e) {
      return {
        'success': false,
        'error': 'compensation_failed: $e',
      };
    }
  }

  /// 🔄 Refund: User muhtar olamamış - elmas iade et
  Future<Map<String, dynamic>> _performRefund(Map<String, dynamic> tx) async {
    try {
      final userId = tx['userId'] as String;
      final amount = tx['amount'] as int;
      
      // Refund log
      await _firestore.collection('diamond_transactions').add({
        'userId': userId,
        'venueId': tx['venueId'],
        'venueName': tx['venueName'],
        'amount': amount,
        'type': 'offline_refund',
        'timestamp': FieldValue.serverTimestamp(),
        'originalTimestamp': Timestamp.fromMillisecondsSinceEpoch(tx['timestamp'] as int),
        'recoveryAction': 'refund',
        'reason': 'User did not become mayor, offline recovery refund',
      });
      
      return {
        'success': true,
        'action': 'refunded',
        'message': 'User did not become mayor, no action needed (virtual refund logged)',
      };
      
    } catch (e) {
      return {
        'success': false,
        'error': 'refund_failed: $e',
      };
    }
  }

  /// 📊 Failed recovery log
  Future<void> _logFailedRecovery(Map<String, dynamic> tx, String reason) async {
    try {
      await _firestore.collection('failed_recoveries').add({
        'userId': tx['userId'],
        'venueId': tx['venueId'],
        'amount': tx['amount'],
        'type': tx['type'],
        'originalTimestamp': Timestamp.fromMillisecondsSinceEpoch(tx['timestamp'] as int),
        'failureReason': reason,
        'failureTimestamp': FieldValue.serverTimestamp(),
        'needsManualReview': true,
      });
    } catch (e) {
    }
  }

  /// 🧹 Cleanup service
  void dispose() {
    _networkCheckTimer?.cancel();
  }

  /// 📊 Get pending transaction count
  Future<int> getPendingTransactionCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(PENDING_TRANSACTIONS_KEY) ?? [];
      return pending.length;
    } catch (e) {
      return 0;
    }
  }
}
