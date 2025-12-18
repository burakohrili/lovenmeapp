// lib/widgets/recent_check_ins_widget.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import '../core/theme/app_colors.dart';

class RecentCheckInsWidget extends StatelessWidget {
  final String userId;

  const RecentCheckInsWidget({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    // 24 saat öncesini hesapla - UserProfilePage ile aynı mantık
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('check_ins')
          .where('userId', isEqualTo: userId)
          .where('checkInTime', isGreaterThan: Timestamp.fromDate(twentyFourHoursAgo)) // ✅ 24 saatlik filtre eklendi
          .orderBy('checkInTime', descending: true) // ✅ Field adı 'checkInTime' olarak düzeltildi
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          return _buildErrorState();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final checkIns = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            ...data,
            'id': doc.id,
          };
        }).toList();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: checkIns.map((checkIn) {
              return _buildCheckInItem(checkIn);
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          children: List.generate(3, (index) => Container(
            margin: const EdgeInsets.all(16),
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          )),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'Check-in\'lar yüklenemedi',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              color: Colors.grey,
              size: 24,
            ),
            SizedBox(height: 8),
            Text(
              'Son 24 saatte check-in yapılmamış', // ✅ 24 saatlik filtre mesajı güncellendi
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckInItem(Map<String, dynamic> checkIn) {
    final venueName = checkIn['venueName'] ?? checkIn['locationName'] ?? 'Bilinmeyen Mekan'; // ✅ locationName fallback eklendi
    final venueCategory = checkIn['venueCategory'] ?? 'genel';
    final checkInTimeStamp = checkIn['checkInTime'] as Timestamp?; // ✅ Field adı 'checkInTime' olarak düzeltildi
    final checkInTime = checkInTimeStamp?.toDate() ?? DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _getCategoryIcon(venueCategory),
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venueName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getTimeAgo(checkInTime),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            color: Colors.green[400],
            size: 20,
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'restoran':
      case 'restaurant':
        return Icons.restaurant;
      case 'kafe':
      case 'cafe':
        return Icons.local_cafe;
      case 'bar':
        return Icons.local_bar;
      case 'spor':
      case 'gym':
        return Icons.fitness_center;
      case 'alışveriş':
      case 'shopping':
        return Icons.shopping_bag;
      case 'eğlence':
      case 'entertainment':
        return Icons.movie;
      case 'park':
        return Icons.park;
      case 'müze':
      case 'museum':
        return Icons.museum;
      default:
        return Icons.place;
    }
  }

  String _getTimeAgo(DateTime checkInTime) {
    final now = DateTime.now();
    final difference = now.difference(checkInTime);

    if (difference.inDays == 0) {
      if (difference.inHours > 0) {
        return '${difference.inHours} saat önce';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} dakika önce';
      } else {
        return 'Şimdi';
      }
    } else if (difference.inDays == 1) {
      return 'Dün';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks hafta önce';
    } else {
      // UserProfilePage ile tutarlı olması için DateFormat import edilmeli
      return '${difference.inDays} gün önce';
    }
  }
}
