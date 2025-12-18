// lib/presentation/pages/debug_iap_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/iap_service.dart';
// REMOVED: premium_service, super_like_test_helper - Like system removed

class DebugIAPPage extends StatefulWidget {
  const DebugIAPPage({super.key});

  @override
  State<DebugIAPPage> createState() => _DebugIAPPageState();
}

class _DebugIAPPageState extends State<DebugIAPPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  String _debugResult = '';
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _errors = [];
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadDebugData();
  }

  Future<void> _loadDebugData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadUserProfile();
      await _loadRecentPurchases();
      await _loadCriticalErrors();
    } catch (e) {
      setState(() {
        _debugResult = 'Debug data load error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      setState(() {
        _userProfile = doc.data();
      });
    }
  }

  Future<void> _loadRecentPurchases() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final query = await _firestore
        .collection('purchases')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();

    setState(() {
      _purchases = query.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    });
  }

  Future<void> _loadCriticalErrors() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final query = await _firestore
        .collection('critical_errors')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(5)
        .get();

    setState(() {
      _errors = query.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    });
  }

  Future<void> _runDebugCheck() async {
    setState(() {
      _isLoading = true;
      _debugResult = 'Running Android IAP debug check...';
    });

    try {
      await IAPService().debugAndroidPremiumStatus();
      await _loadDebugData(); // Refresh data
      setState(() {
        _debugResult = 'Debug check completed. Check console logs for details.';
      });
    } catch (e) {
      setState(() {
        _debugResult = 'Debug check error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _emergencyFix(String productId, String purchaseId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await IAPService().emergencyFixPurchase(
        productId: productId,
        purchaseId: purchaseId,
      );

      await _loadDebugData(); // Refresh data
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency fix applied! 🚨'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emergency fix failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _simulatePurchase(String internalProductId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Simulate a purchase by creating a fake purchase record and applying benefits
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      final fakeProductId = internalProductId == 'premium_monthly' 
          ? 'com.lovenme.premium.monthly'
          : internalProductId == 'super_likes_10'
          ? 'com.lovenme.superlikes.tenpack'
          : 'com.lovenme.diamonds.tenpack';
      
      final fakePurchaseId = 'sim_${DateTime.now().millisecondsSinceEpoch}';

      // Apply benefits using emergency fix (simulation mode)
      await IAPService().emergencyFixPurchase(
        productId: fakeProductId,
        purchaseId: fakePurchaseId,
        simulateOnly: true, // 🎭 Simulation mode - no real benefits
      );

      await _loadDebugData(); // Refresh data
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Simulated $internalProductId purchase!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Simulation failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IAP Debug Center'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDebugData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Debug Actions
                  _buildDebugActions(),
                  const SizedBox(height: 20),

                  // User Profile
                  _buildUserProfile(),
                  const SizedBox(height: 20),

                  // Recent Purchases
                  _buildRecentPurchases(),
                  const SizedBox(height: 20),

                  // Critical Errors
                  _buildCriticalErrors(),
                  const SizedBox(height: 20),

                  // Debug Result
                  if (_debugResult.isNotEmpty) _buildDebugResult(),
                ],
              ),
            ),
    );
  }

  Widget _buildDebugActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔧 Debug Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bug_report),
                label: const Text('Run Android IAP Debug'),
                onPressed: _runDebugCheck,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.credit_card),
                label: const Text('Simulate Premium Purchase'),
                onPressed: () => _simulatePurchase('premium_monthly'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.favorite),
                label: const Text('Simulate Super Like Purchase'),
                onPressed: () => _simulatePurchase('super_likes_10'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const Text(
              '⚠️ Super Like Tests - DEPRECATED',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '🚫 Like system removed - Use Chat Request system instead',
                style: TextStyle(color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            // 🔄 YENİ: Premium Reset Butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('🔄 Premium Durumunu Sıfırla'),
                onPressed: _resetPremiumStatus,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserProfile() {
    if (_userProfile == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No user profile found'),
        ),
      );
    }

    final isPremium = _userProfile!['isPremium'] ?? false;
    final premiumUntil = _userProfile!['premiumUntil'] as Timestamp?;
    final superLikes = _userProfile!['purchasedSuperLikes'] ?? 0;
    final balance = _userProfile!['balance'] ?? _userProfile!['diamonds'] ?? 0;
    final dailyLikes = _userProfile!['dailyLikesRemaining'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '👤 User Profile',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildProfileRow('Premium Status', isPremium ? '✅ Active' : '❌ Inactive'),
            if (premiumUntil != null)
              _buildProfileRow(
                'Premium Until', 
                premiumUntil.toDate().toString(),
              ),
            _buildProfileRow('Super Likes', superLikes.toString()),
            _buildProfileRow('Diamonds', balance.toString()),
            _buildProfileRow('Daily Likes', dailyLikes.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildRecentPurchases() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🛒 Recent Purchases',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_purchases.isEmpty)
              const Text('No purchases found')
            else
              ..._purchases.map((purchase) => _buildPurchaseItem(purchase)),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseItem(Map<String, dynamic> purchase) {
    final productId = purchase['productId'] ?? 'Unknown';
    final purchaseId = purchase['purchaseId'] ?? 'Unknown';
    final status = purchase['status'] ?? 'Unknown';
    final createdAt = purchase['createdAt'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: status == 'completed' ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              productId,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Status: $status'),
            Text('ID: $purchaseId'),
            if (createdAt != null)
              Text('Date: ${createdAt.toDate()}'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _emergencyFix(productId, purchaseId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('🚨 Emergency Fix'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriticalErrors() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🚨 Critical Errors',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_errors.isEmpty)
              const Text('No critical errors found')
            else
              ..._errors.map((error) => _buildErrorItem(error)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorItem(Map<String, dynamic> error) {
    final type = error['type'] ?? 'Unknown';
    final productId = error['productId'] ?? 'Unknown';
    final timestamp = error['timestamp'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Product: $productId'),
            if (timestamp != null)
              Text('Time: ${timestamp.toDate()}'),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugResult() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📋 Debug Result',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(_debugResult),
          ],
        ),
      ),
    );
  }

  // 🚫 SUPER LIKE TEST METHODS - REMOVED (Like system deprecated)

  Future<void> _resetPremiumStatus() async {
    setState(() {
      _isLoading = true;
      _debugResult = 'Resetting premium status...';
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _debugResult = '❌ No user logged in';
        });
        return;
      }

      // 🔄 YENİ: Önce Google Play subscription'larını iptal et
      setState(() {
        _debugResult = 'Cancelling Google Play subscriptions...';
      });
      await IAPService.cancelAllActiveSubscriptions();

      // Premium durumunu sıfırla
      setState(() {
        _debugResult = 'Resetting Firestore premium status...';
      });
      await _firestore.collection('users').doc(user.uid).update({
        'isPremium': false,
        'premiumType': null,
        'premiumUntil': null,
        'dailyRewindsRemaining': 0,
        'dailyLikesRemaining': 5, // Normal kullanıcı limitine döner
        'updatedAt': FieldValue.serverTimestamp(),
        'debugResetDate': FieldValue.serverTimestamp(),
        'debugResetReason': 'Manual reset from debug page + Google Play cancellation',
      });

      // 🔄 YENİ: Kuyrukta bekleyen premium subscription'ları da temizle
      try {
        final queuedSubscriptions = await _firestore
            .collection('premium_subscriptions')
            .where('userId', isEqualTo: user.uid)
            .where('isQueued', isEqualTo: true)
            .get();
        
        for (final doc in queuedSubscriptions.docs) {
          await doc.reference.update({
            'isQueued': false,
            'isActive': false,
            'debugCancelled': true,
            'debugCancelledDate': FieldValue.serverTimestamp(),
          });
        }
        
        if (queuedSubscriptions.docs.isNotEmpty) {
          setState(() {
            _debugResult = '✅ Premium status reset + Google Play subscriptions cancelled + ${queuedSubscriptions.docs.length} queued subscriptions cancelled.';
          });
        } else {
          setState(() {
            _debugResult = '✅ Premium status reset + Google Play subscriptions cancelled. Ready for new purchase.';
          });
        }
      } catch (e) {
        setState(() {
          _debugResult = '✅ Premium status reset + Google Play cancelled (queue cleanup failed: $e)';
        });
      }
      
      // Show confirmation dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Premium Reset Complete'),
            content: const Text('Premium status has been reset and Google Play subscriptions cancelled. You can now test premium purchases.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      
    } catch (e) {
      setState(() {
        _debugResult = '❌ Premium reset error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      await _loadDebugData(); // Refresh data
    }
  }

}
