import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🛡️ Real-time Mayor Conflict Detection Service
/// 
/// Bu servis şunları yapar:
/// - Real-time mayor değişikliklerini dinler
/// - Diamond ile mayor olma işlemlerindeki conflict'leri tespit eder
/// - Conflict durumunda otomatik refund yapar
/// - User'a notification gönderir
/// - Telemetry ve monitoring sağlar
class MayorConflictDetectionService {
  static final MayorConflictDetectionService _instance = MayorConflictDetectionService._internal();
  static MayorConflictDetectionService get instance => _instance;
  MayorConflictDetectionService._internal();

  // 🔧 Core dependencies
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 📡 Active listeners
  final Map<String, StreamSubscription> _venueListeners = {};
  
  // ⏰ Monitoring windows
  final Map<String, Timer> _monitoringTimers = {};
  
  // 🎯 Active mayor attempts
  final Map<String, MayorAttempt> _activeMayorAttempts = {};
  
  // 📊 Conflict statistics
  int _totalConflictsDetected = 0;
  int _totalRefundsProcessed = 0;
  int _totalNotificationsSent = 0;

  // 🔑 SharedPreferences keys
  static const String CONFLICT_STATS_KEY = 'conflict_detection_stats';
  static const String MONITORED_VENUES_KEY = 'monitored_venues';

  /// 🚀 Initialize service
  Future<void> initialize() async {
    await _loadStatistics();
    await _restoreMonitoredVenues();
  }

  /// 📊 Load saved statistics
  Future<void> _loadStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final statsJson = prefs.getString(CONFLICT_STATS_KEY);
      
      if (statsJson != null) {
        // Parse saved stats if needed
      }
    } catch (e) {
    }
  }

  /// 🔄 Restore previously monitored venues
  Future<void> _restoreMonitoredVenues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final monitoredVenues = prefs.getStringList(MONITORED_VENUES_KEY) ?? [];
      
      for (String venueId in monitoredVenues) {
        // Re-establish monitoring without immediate conflict detection
        await _startVenueMonitoring(venueId, skipInitialCheck: true);
      }
      
    } catch (e) {
    }
  }

  /// 🎯 Register a mayor attempt for conflict detection
  Future<void> registerMayorAttempt({
    required String venueId,
    required String userId,
    required int diamondAmount,
    required String transactionId,
    Duration monitoringDuration = const Duration(minutes: 10),
  }) async {
    try {
      
      // Record the attempt
      final attempt = MayorAttempt(
        venueId: venueId,
        userId: userId,
        diamondAmount: diamondAmount,
        transactionId: transactionId,
        timestamp: DateTime.now(),
        monitoringDuration: monitoringDuration,
      );
      
      _activeMayorAttempts[venueId] = attempt;
      
      // Start real-time monitoring for this venue
      await _startVenueMonitoring(venueId);
      
      // Set monitoring timeout
      _setupMonitoringTimeout(venueId, monitoringDuration);
      
      // Save to persistent storage
      await _saveMonitoredVenues();
      
      
    } catch (e) {
      throw Exception('Failed to register mayor attempt: $e');
    }
  }

  /// 📡 Start real-time venue monitoring
  Future<void> _startVenueMonitoring(String venueId, {bool skipInitialCheck = false}) async {
    try {
      // Cancel existing listener if any
      await _stopVenueMonitoring(venueId);
      
      
      // Listen to venue document changes
      final venueStream = _firestore
          .collection('venues')
          .doc(venueId)
          .snapshots();
          
      final subscription = venueStream.listen(
        (snapshot) async {
          if (!snapshot.exists) return;
          
          try {
            final venueData = snapshot.data() as Map<String, dynamic>;
            
            if (!skipInitialCheck) {
              await _checkForConflict(venueId, venueData);
            }
            
          } catch (e) {
          }
        },
        onError: (error) {
          // Attempt to restart monitoring
          Future.delayed(const Duration(seconds: 30), () {
            _startVenueMonitoring(venueId);
          });
        },
      );
      
      _venueListeners[venueId] = subscription;
      
    } catch (e) {
    }
  }

  /// ⚔️ Check for mayor conflict
  Future<void> _checkForConflict(String venueId, Map<String, dynamic> venueData) async {
    final attempt = _activeMayorAttempts[venueId];
    if (attempt == null) return;
    
    try {
      final currentMayorId = venueData['currentMayorId'] as String?;
      final mayorChangeTime = venueData['mayorChangeTime'] as Timestamp?;
      
      
      // Conflict tespit edildi mi?
      final conflictDetected = await _detectConflict(
        attempt: attempt,
        currentMayorId: currentMayorId,
        mayorChangeTime: mayorChangeTime,
      );
      
      if (conflictDetected) {
        await _handleConflict(attempt, venueData);
      }
      
    } catch (e) {
    }
  }

  /// 🕵️ Detect if conflict occurred
  Future<bool> _detectConflict({
    required MayorAttempt attempt,
    String? currentMayorId,
    Timestamp? mayorChangeTime,
  }) async {
    try {
      // Eğer current mayor bizim user'ımız ise conflict yok
      if (currentMayorId == attempt.userId) {
        return false;
      }
      
      // Mayor değişiklik zamanını kontrol et
      if (mayorChangeTime != null) {
        final changeTime = mayorChangeTime.toDate();
        final attemptTime = attempt.timestamp;
        
        // Eğer mayor değişikliği bizim attempt'imizden sonra olduysa conflict
        if (changeTime.isAfter(attemptTime)) {
          final timeDifference = changeTime.difference(attemptTime);
          
          // 30 saniye içinde başka biri mayor olduysa conflict
          if (timeDifference.inSeconds <= 30) {
            return true;
          }
        }
      }
      
      // Firestore transaction loglarını kontrol et
      return await _checkTransactionLogs(attempt);
      
    } catch (e) {
      return false;
    }
  }

  /// 📋 Check transaction logs for conflicts
  Future<bool> _checkTransactionLogs(MayorAttempt attempt) async {
    try {
      final logsQuery = await _firestore
          .collection('mayor_transaction_logs')
          .where('venueId', isEqualTo: attempt.venueId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(attempt.timestamp.subtract(const Duration(seconds: 30))))
          .where('timestamp', isLessThan: Timestamp.fromDate(attempt.timestamp.add(const Duration(seconds: 30))))
          .where('status', isEqualTo: 'completed')
          .get();
      
      // Bizim transaction'ımız dışında başka completed transaction var mı?
      final otherTransactions = logsQuery.docs.where(
        (doc) => doc.id != attempt.transactionId,
      ).toList();
      
      if (otherTransactions.isNotEmpty) {
        return true;
      }
      
      return false;
      
    } catch (e) {
      return false;
    }
  }

  /// 🛠️ Handle detected conflict
  Future<void> _handleConflict(MayorAttempt attempt, Map<String, dynamic> venueData) async {
    try {
      _totalConflictsDetected++;
      
      
      // 1. Diamond refund yap
      final refundSuccess = await _processRefund(attempt);
      
      if (refundSuccess) {
        _totalRefundsProcessed++;
        
        // 2. User'a notification gönder
        await _sendConflictNotification(attempt, venueData);
        _totalNotificationsSent++;
        
        // 3. Conflict logla
        await _logConflictResolution(attempt, 'refunded');
        
      } else {
        // Refund başarısız, manuel review gerekli
        await _logConflictResolution(attempt, 'refund_failed');
      }
      
      // 4. Monitoring'i durdur
      await _stopAttemptMonitoring(attempt.venueId);
      
      // 5. Statistics güncelle
      await _saveStatistics();
      
    } catch (e) {
    }
  }

  /// 💎 Process diamond refund
  Future<bool> _processRefund(MayorAttempt attempt) async {
    try {
      
      return await _firestore.runTransaction((transaction) async {
        // User balance'ını güncelle
        final userRef = _firestore.collection('users').doc(attempt.userId);
        final userDoc = await transaction.get(userRef);
        
        if (!userDoc.exists) {
          throw Exception('User not found for refund');
        }
        
        final userData = userDoc.data()!;
        final currentDiamonds = (userData['diamonds'] as int?) ?? 0;
        final newDiamonds = currentDiamonds + attempt.diamondAmount;
        
        transaction.update(userRef, {
          'diamonds': newDiamonds,
          'lastDiamondUpdate': FieldValue.serverTimestamp(),
        });
        
        // Refund transaction log
        final refundLogRef = _firestore.collection('diamond_refund_logs').doc();
        transaction.set(refundLogRef, {
          'userId': attempt.userId,
          'venueId': attempt.venueId,
          'originalTransactionId': attempt.transactionId,
          'refundAmount': attempt.diamondAmount,
          'reason': 'mayor_conflict',
          'timestamp': FieldValue.serverTimestamp(),
          'refundId': refundLogRef.id,
        });
        
        return true;
      });
      
    } catch (e) {
      return false;
    }
  }

  /// 🔔 Send conflict notification to user
  Future<void> _sendConflictNotification(MayorAttempt attempt, Map<String, dynamic> venueData) async {
    try {
      final venueName = venueData['name'] as String? ?? 'Unknown Venue';
      
      // Notification document oluştur
      await _firestore.collection('notifications').add({
        'userId': attempt.userId,
        'type': 'mayor_conflict_refund',
        'title': 'Diamond Refund',
        'message': 'You received a refund of ${attempt.diamondAmount} diamonds from $venueName due to a timing conflict.',
        'data': {
          'venueId': attempt.venueId,
          'venueName': venueName,
          'refundAmount': attempt.diamondAmount,
          'transactionId': attempt.transactionId,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      
      
    } catch (e) {
    }
  }

  /// 📝 Log conflict resolution
  Future<void> _logConflictResolution(MayorAttempt attempt, String resolution) async {
    try {
      await _firestore.collection('conflict_resolution_logs').add({
        'venueId': attempt.venueId,
        'userId': attempt.userId,
        'transactionId': attempt.transactionId,
        'diamondAmount': attempt.diamondAmount,
        'attemptTimestamp': Timestamp.fromDate(attempt.timestamp),
        'resolution': resolution,
        'resolvedAt': FieldValue.serverTimestamp(),
        'detectionService': 'MayorConflictDetectionService',
      });
      
      
    } catch (e) {
    }
  }

  /// ⏰ Setup monitoring timeout
  void _setupMonitoringTimeout(String venueId, Duration duration) {
    // Cancel existing timer
    _monitoringTimers[venueId]?.cancel();
    
    // Set new timer
    _monitoringTimers[venueId] = Timer(duration, () async {
      await _stopAttemptMonitoring(venueId);
    });
  }

  /// 🛑 Stop monitoring for specific attempt
  Future<void> _stopAttemptMonitoring(String venueId) async {
    try {
      // Remove active attempt
      _activeMayorAttempts.remove(venueId);
      
      // Cancel monitoring timer
      _monitoringTimers[venueId]?.cancel();
      _monitoringTimers.remove(venueId);
      
      // Stop venue listener
      await _stopVenueMonitoring(venueId);
      
      // Update persistent storage
      await _saveMonitoredVenues();
      
      
    } catch (e) {
    }
  }

  /// 🛑 Stop venue monitoring
  Future<void> _stopVenueMonitoring(String venueId) async {
    try {
      _venueListeners[venueId]?.cancel();
      _venueListeners.remove(venueId);
    } catch (e) {
    }
  }

  /// 💾 Save monitored venues to persistent storage
  Future<void> _saveMonitoredVenues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final monitoredVenues = _activeMayorAttempts.keys.toList();
      await prefs.setStringList(MONITORED_VENUES_KEY, monitoredVenues);
    } catch (e) {
    }
  }

  /// 📊 Save statistics
  Future<void> _saveStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stats = {
        'totalConflicts': _totalConflictsDetected,
        'totalRefunds': _totalRefundsProcessed,
        'totalNotifications': _totalNotificationsSent,
        'lastUpdate': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Convert to JSON string for storage
      await prefs.setString(CONFLICT_STATS_KEY, stats.toString());
    } catch (e) {
    }
  }

  /// 📊 Get conflict detection statistics
  Map<String, int> getStatistics() {
    return {
      'totalConflicts': _totalConflictsDetected,
      'totalRefunds': _totalRefundsProcessed,
      'totalNotifications': _totalNotificationsSent,
      'activeMonitoring': _activeMayorAttempts.length,
    };
  }

  /// 🏃‍♂️ Get active monitoring status
  List<String> getActivelyMonitoredVenues() {
    return _activeMayorAttempts.keys.toList();
  }

  /// 🧹 Clean up expired monitoring
  Future<void> cleanupExpiredMonitoring() async {
    final now = DateTime.now();
    final expiredVenues = <String>[];
    
    for (final entry in _activeMayorAttempts.entries) {
      final attempt = entry.value;
      final expiryTime = attempt.timestamp.add(attempt.monitoringDuration);
      
      if (now.isAfter(expiryTime)) {
        expiredVenues.add(entry.key);
      }
    }
    
    for (final venueId in expiredVenues) {
      await _stopAttemptMonitoring(venueId);
    }
    
    if (expiredVenues.isNotEmpty) {
    }
  }

  /// 🛑 Dispose service
  void dispose() {
    // Cancel all listeners
    for (final subscription in _venueListeners.values) {
      subscription.cancel();
    }
    _venueListeners.clear();
    
    // Cancel all timers
    for (final timer in _monitoringTimers.values) {
      timer.cancel();
    }
    _monitoringTimers.clear();
    
    // Clear active attempts
    _activeMayorAttempts.clear();
    
  }
}

/// 🎯 Mayor attempt data model
class MayorAttempt {
  final String venueId;
  final String userId;
  final int diamondAmount;
  final String transactionId;
  final DateTime timestamp;
  final Duration monitoringDuration;

  MayorAttempt({
    required this.venueId,
    required this.userId,
    required this.diamondAmount,
    required this.transactionId,
    required this.timestamp,
    required this.monitoringDuration,
  });

  Map<String, dynamic> toJson() {
    return {
      'venueId': venueId,
      'userId': userId,
      'diamondAmount': diamondAmount,
      'transactionId': transactionId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'monitoringDuration': monitoringDuration.inMilliseconds,
    };
  }

  factory MayorAttempt.fromJson(Map<String, dynamic> json) {
    return MayorAttempt(
      venueId: json['venueId'],
      userId: json['userId'],
      diamondAmount: json['diamondAmount'],
      transactionId: json['transactionId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      monitoringDuration: Duration(milliseconds: json['monitoringDuration']),
    );
  }
}
