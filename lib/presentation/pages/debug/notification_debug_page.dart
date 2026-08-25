// lib/presentation/pages/debug/notification_debug_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';

class NotificationDebugPage extends StatefulWidget {
  const NotificationDebugPage({super.key});

  @override
  State<NotificationDebugPage> createState() => _NotificationDebugPageState();
}

class _NotificationDebugPageState extends State<NotificationDebugPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _debugLog = '';
  String _targetUserId = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUserInfo();
  }

  Future<void> _loadCurrentUserInfo() async {
    final user = _auth.currentUser;
    if (user != null) {
      _addLog('Current User ID: ${user.uid}');
    }
  }

  void _addLog(String message) {
    setState(() {
      _debugLog += '${DateTime.now().toString().substring(11, 19)}: $message\n';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grey50,
      appBar: AppBar(
        title: const Text('Bildirim Debug'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(() {
                _debugLog = '';
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Target User ID Input
            TextField(
              decoration: const InputDecoration(
                labelText: 'Hedef Kullanıcı ID',
                hintText: 'Bildirim gönderilecek kullanıcı ID\'si',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _targetUserId = value;
              },
            ),
            const SizedBox(height: 16),
            
            // Debug Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _debugTokenInfo,
                  child: const Text('Token Bilgisi'),
                ),
                ElevatedButton(
                  onPressed: _debugPermissions,
                  child: const Text('İzinler'),
                ),
                ElevatedButton(
                  onPressed: _sendTestNotification,
                  child: const Text('Test Bildirimi'),
                ),
                ElevatedButton(
                  onPressed: _sendSuperLikeNotification,
                  child: const Text('Öne Çıkan İstek'),
                ),
                ElevatedButton(
                  onPressed: _checkCloudFunctions,
                  child: const Text('Cloud Functions'),
                ),
                ElevatedButton(
                  onPressed: _listNotificationRequests,
                  child: const Text('Request\'ler'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Debug Log
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _debugLog.isEmpty ? 'Debug log\'ları burada görünecek...' : _debugLog,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _debugTokenInfo() async {
    _addLog('🔍 Token bilgisi kontrol ediliyor...');
    await NotificationService().debugTokenInfo();
    
    // Get current user's token from Firestore
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        _addLog('✅ Firestore Token: ${userData?['fcmToken']?.substring(0, 20)}...');
        _addLog('✅ Platform: ${userData?['platform']}');
      } catch (e) {
        _addLog('❌ Firestore token okuma hatası: $e');
      }
    }
  }

  Future<void> _debugPermissions() async {
    _addLog('🔍 İzinler kontrol ediliyor...');
    await NotificationService().debugPermissions();
  }

  Future<void> _sendTestNotification() async {
    if (_targetUserId.isEmpty) {
      _addLog('❌ Hedef kullanıcı ID\'si boş!');
      return;
    }

    _addLog('📤 Test bildirimi gönderiliyor: $_targetUserId');
    try {
      await NotificationService.sendTestNotification(targetUserId: _targetUserId);
      _addLog('✅ Test bildirimi gönderildi');
    } catch (e) {
      _addLog('❌ Test bildirimi hatası: $e');
    }
  }

  Future<void> _sendSuperLikeNotification() async {
    if (_targetUserId.isEmpty) {
      _addLog('❌ Hedef kullanıcı ID\'si boş!');
      return;
    }

    _addLog('⭐ Öne çıkan istek bildirimi gönderiliyor: $_targetUserId');
    try {
      await NotificationService.sendLikeNotification(
        toUserId: _targetUserId,
        fromUserName: 'Debug Test',
        isSuper: true,
        isPremium: true,
      );
      _addLog('✅ Öne çıkan istek bildirimi gönderildi');
    } catch (e) {
      _addLog('❌ Öne çıkan istek bildirimi hatası: $e');
    }
  }

  Future<void> _checkCloudFunctions() async {
    _addLog('☁️ Cloud Functions kontrol ediliyor...');
    try {
      // Check recent notification requests
      final requests = await _firestore
          .collection('notification_requests')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      _addLog('📊 Son 5 bildirim isteği:');
      for (final doc in requests.docs) {
        final data = doc.data();
        _addLog('  ${doc.id}: ${data['processed'] ? '✅' : '⏳'} ${data['title']}');
      }
    } catch (e) {
      _addLog('❌ Cloud Functions kontrol hatası: $e');
    }
  }

  Future<void> _listNotificationRequests() async {
    _addLog('📋 Notification request\'ler listeleniyor...');
    try {
      final requests = await _firestore
          .collection('notification_requests')
          .where('processed', isEqualTo: false)
          .get();
      
      if (requests.docs.isEmpty) {
        _addLog('📭 İşlenmemiş request yok');
      } else {
        _addLog('📮 ${requests.docs.length} işlenmemiş request var:');
        for (final doc in requests.docs) {
          final data = doc.data();
          _addLog('  ${data['title']} → ${data['targetUserId']}');
        }
      }
    } catch (e) {
      _addLog('❌ Request listesi hatası: $e');
    }
  }
}
