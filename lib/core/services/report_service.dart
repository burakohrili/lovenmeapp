import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum ReportType {
  user('user_report'),
  post('post_report'),
  chat('chat_report');

  const ReportType(this.value);
  final String value;
}

enum ReportReason {
  fakeProfile('Sahte Profil', Icons.person_off),
  harassment('Taciz/Rahatsız Etme', Icons.warning),
  inappropriateContent('Uygunsuz İçerik', Icons.block),
  spam('Spam/Bot', Icons.smart_toy);

  const ReportReason(this.displayName, this.icon);
  final String displayName;
  final IconData icon;

  static List<ReportReason> get all => ReportReason.values;
}

class ReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Kullanıcı şikayet etme
  static Future<bool> reportUser({
    required String reportedUserId,
    required ReportReason reason,
    String? context,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      await _firestore.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedUserId': reportedUserId,
        'reason': reason.displayName,
        'timestamp': FieldValue.serverTimestamp(),
        'type': ReportType.user.value,
        'status': 'pending',
        'context': context ?? 'profile_view',
        ...?additionalData,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Post şikayet etme
  static Future<bool> reportPost({
    required String postId,
    required String postOwnerId,
    required ReportReason reason,
    String? context,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      await _firestore.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedUserId': postOwnerId,
        'reportedPostId': postId,
        'reason': reason.displayName,
        'timestamp': FieldValue.serverTimestamp(),
        'type': ReportType.post.value,
        'status': 'pending',
        'context': context ?? 'feed_post',
        ...?additionalData,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Chat şikayet etme
  static Future<bool> reportChat({
    required String reportedUserId,
    required ReportReason reason,
    String? matchId,
    String? context,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      await _firestore.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedUserId': reportedUserId,
        'reason': reason.displayName,
        'timestamp': FieldValue.serverTimestamp(),
        'type': ReportType.chat.value,
        'status': 'pending',
        'context': context ?? 'chat_conversation',
        'matchId': matchId,
        ...?additionalData,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Şikayet sayısını al (kullanıcı için)
  static Future<int> getUserReportCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('reports')
          .where('reportedUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'confirmed')
          .get();
      
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  /// Kullanıcının şikayet ettiği kişiler listesi
  static Future<List<String>> getUserReportedList(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('reports')
          .where('reporterId', isEqualTo: userId)
          .get();
      
      return snapshot.docs
          .map((doc) => doc.data()['reportedUserId'] as String)
          .toSet() // Duplicate'leri çıkar
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// Şikayet seçim dialog'u göstermek için helper widget
class ReportDialog extends StatelessWidget {
  final String title;
  final String description;
  final Function(ReportReason) onReasonSelected;

  const ReportDialog({
    super.key,
    required this.title,
    required this.description,
    required this.onReasonSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          ...ReportReason.all.map(
            (reason) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  reason.displayName,
                  style: const TextStyle(fontSize: 14),
                ),
                leading: Icon(
                  reason.icon,
                  color: Colors.red,
                  size: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onReasonSelected(reason);
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
      ],
    );
  }
}
