// lib/presentation/pages/profile/check_in_history_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/premium_service.dart';
import '../../widgets/premium/premium_subscription_widget.dart';
import 'package:intl/intl.dart';

class CheckInHistoryPage extends StatefulWidget {
  const CheckInHistoryPage({super.key});

  @override
  State<CheckInHistoryPage> createState() => _CheckInHistoryPageState();
}

class _CheckInHistoryPageState extends State<CheckInHistoryPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isPremium = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _checkIns = [];

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    await _checkPremiumStatus();
    await _loadCheckInHistory();
  }

  Future<void> _checkPremiumStatus() async {
    final isPremium = await PremiumService.isPremiumActive();
    setState(() {
      _isPremium = isPremium;
    });
  }

  Future<void> _loadCheckInHistory() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Premium kullanıcılar tüm geçmişi görebilir, normal kullanıcılar sadece son 7 gün
      final DateTime limitDate = _isPremium 
          ? DateTime(2020) // Çok eski bir tarih (tüm geçmiş)
          : DateTime.now().subtract(const Duration(days: 7));

      final querySnapshot = await _firestore
          .collection('check_ins')
          .where('userId', isEqualTo: user.uid)
          .where('checkInTime', isGreaterThan: Timestamp.fromDate(limitDate))
          .orderBy('checkInTime', descending: true)
          .get();

      final checkIns = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      setState(() {
        _checkIns = checkIns;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Header bölümü - Foursquare benzeri
                SliverAppBar(
                  expandedHeight: 200.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: Colors.white,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          // Stats kartları
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    '${_checkIns.length}',
                                    'Check-ins',
                                    Icons.location_on,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildStatCard(
                                    '${_getUniqueVenuesCount()}',
                                    'Places',
                                    Icons.place,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildStatCard(
                                    '${_getCategoriesCount()}/100',
                                    'Categories',
                                    Icons.category,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Premium Banner
                if (!_isPremium)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: AppColors.premiumGradient,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Premium ile Tüm Geçmişi Gör',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Sadece son 7 günü görebiliyorsun',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              _showPremiumSubscriptionSheet();
                            },
                            child: const Text(
                              'Yükselt',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Timeline başlığı
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      'Timeline',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),

                // Check-in Listesi
                _checkIns.isEmpty
                    ? SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Henüz check-in geçmişin yok',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final checkIn = _checkIns[index];
                            return _buildTimelineCheckInCard(checkIn, index);
                          },
                          childCount: _checkIns.length,
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  int _getUniqueVenuesCount() {
    final uniqueVenues = <String>{};
    for (final checkIn in _checkIns) {
      final venueId = checkIn['venueId'] ?? checkIn['venueName'];
      if (venueId != null) {
        uniqueVenues.add(venueId.toString());
      }
    }
    return uniqueVenues.length;
  }

  int _getCategoriesCount() {
    final categories = <String>{};
    for (final checkIn in _checkIns) {
      final category = checkIn['category'];
      if (category != null) {
        categories.add(category.toString());
      }
    }
    return categories.length;
  }

  Widget _buildTimelineCheckInCard(Map<String, dynamic> checkIn, int index) {
    final venueName = checkIn['venueName'] ?? 'Bilinmeyen Mekan';
    final checkInTime = (checkIn['checkInTime'] as Timestamp?)?.toDate();
    final hasPhoto = checkIn['hasPhoto'] ?? false;
    final fromFavorite = checkIn['fromFavorite'] ?? false;
    final points = checkIn['points'] ?? 0;
    final likes = checkIn['likes'] ?? 0;
    final comments = checkIn['comments'] ?? 0;

    // Tarihe göre gruplama
    String timeLabel = 'Today';
    if (checkInTime != null) {
      final now = DateTime.now();
      final difference = now.difference(checkInTime);
      
      if (difference.inDays == 0) {
        timeLabel = 'Today';
      } else if (difference.inDays == 1) {
        timeLabel = 'Yesterday';
      } else if (difference.inDays <= 7) {
        timeLabel = DateFormat('EEEE').format(checkInTime);
      } else {
        timeLabel = DateFormat('MMM d, yyyy').format(checkInTime);
      }
    }

    // Önceki öğe ile aynı gün mü kontrol et
    bool showDateHeader = true;
    if (index > 0) {
      final prevCheckIn = _checkIns[index - 1];
      final prevTime = (prevCheckIn['checkInTime'] as Timestamp?)?.toDate();
      if (prevTime != null && checkInTime != null) {
        final prevDifference = DateTime.now().difference(prevTime);
        String prevTimeLabel = 'Today';
        if (prevDifference.inDays == 0) {
          prevTimeLabel = 'Today';
        } else if (prevDifference.inDays == 1) {
          prevTimeLabel = 'Yesterday';
        } else if (prevDifference.inDays <= 7) {
          prevTimeLabel = DateFormat('EEEE').format(prevTime);
        } else {
          prevTimeLabel = DateFormat('MMM d, yyyy').format(prevTime);
        }
        showDateHeader = timeLabel != prevTimeLabel;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tarih başlığı
        if (showDateHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 16, 16, 8),
            child: Text(
              timeLabel,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),

        // Timeline öğesi
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline çizgisi ve icon
              SizedBox(
                width: 60,
                child: Column(
                  children: [
                    // Timeline line üst
                    if (index > 0)
                      Container(
                        width: 2,
                        height: 20,
                        color: Colors.orange[300],
                      ),
                    
                    // Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getVenueIcon(checkIn),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    
                    // Timeline line alt
                    if (index < _checkIns.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.orange[300],
                        ),
                      ),
                  ],
                ),
              ),

              // İçerik kartı
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 16, bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Venue adı ve zaman
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  venueName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: Colors.grey[500],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      points.toString(),
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (checkInTime != null)
                                      Text(
                                        DateFormat('h:mm a').format(checkInTime),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (fromFavorite)
                            const Icon(
                              Icons.favorite,
                              color: Colors.red,
                              size: 20,
                            ),
                        ],
                      ),

                      // Etkileşim bilgileri
                      if (likes > 0 || comments > 0) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (likes > 0) ...[
                              const Icon(
                                Icons.favorite,
                                size: 16,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                likes.toString(),
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (comments > 0) ...[
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                comments.toString(),
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getVenueIcon(Map<String, dynamic> checkIn) {
    final category = checkIn['category']?.toString().toLowerCase() ?? '';
    
    if (category.contains('restaurant') || category.contains('food')) {
      return Icons.restaurant;
    } else if (category.contains('coffee') || category.contains('cafe')) {
      return Icons.local_cafe;
    } else if (category.contains('shop') || category.contains('store')) {
      return Icons.shopping_bag;
    } else if (category.contains('park') || category.contains('outdoor')) {
      return Icons.park;
    } else if (category.contains('gym') || category.contains('fitness')) {
      return Icons.fitness_center;
    } else {
      return Icons.place;
    }
  }

  Widget _buildCheckInCard(Map<String, dynamic> checkIn) {
    final venueName = checkIn['venueName'] ?? 'Bilinmeyen Mekan';
    final checkInTime = (checkIn['checkInTime'] as Timestamp?)?.toDate();
    final hasPhoto = checkIn['hasPhoto'] ?? false;
    final fromFavorite = checkIn['fromFavorite'] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: fromFavorite 
                    ? AppColors.error.withOpacity(0.1)
                    : AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                fromFavorite ? Icons.favorite : Icons.location_on,
                color: fromFavorite ? AppColors.error : AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),

            // İçerik
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venueName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (checkInTime != null)
                    Text(
                      DateFormat('dd MMM yyyy, HH:mm').format(checkInTime),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  if (hasPhoto || fromFavorite) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (hasPhoto) ...[
                          const Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Foto',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (hasPhoto && fromFavorite) ...[
                          const SizedBox(width: 8),
                          const Text('•', style: TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(width: 8),
                        ],
                        if (fromFavorite) ...[
                          const Icon(
                            Icons.favorite,
                            size: 16,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Otomatik',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Premium badge (sadece premium kullanıcılar için eski check-inlerde)
            if (_isPremium && checkInTime != null && 
                checkInTime.isBefore(DateTime.now().subtract(const Duration(days: 7))))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Premium subscription sheet'ini göster
  void _showPremiumSubscriptionSheet() {
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Premium widget
              Expanded(
                child: PremiumSubscriptionWidget(
                  onPurchaseSuccess: (type) {
                    Navigator.pop(context);
                    _checkPremiumStatus(); // Premium durumunu yenile
                    _loadCheckInHistory(); // Check-in geçmişini yenile
                    
                    // Başarı mesajı göster
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Premium üyelik başarıyla satın alındı!'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          margin: EdgeInsets.all(16),
                        ),
                      );
                    }
                  },
                  onError: (error) {
                    Navigator.pop(context);
                    
                    // Hata mesajı göster
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Satın alma hatası: $error'),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((value) {
    });
  }
}
