// lib/widgets/super_chat_purchase_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/theme/app_colors.dart';
import '../core/services/iap_service.dart';
import '../core/services/premium_service.dart';
import '../core/config/iap_config.dart';

/// Super Chat Satın Alma Paneli
/// Like sistemi yerine Chat Request sistemi için
class SuperChatPurchaseSheet extends ConsumerStatefulWidget {
  final VoidCallback? onPurchaseSuccess;

  const SuperChatPurchaseSheet({
    super.key,
    this.onPurchaseSuccess,
  });

  @override
  ConsumerState<SuperChatPurchaseSheet> createState() => _SuperChatPurchaseSheetState();
}

class _SuperChatPurchaseSheetState extends ConsumerState<SuperChatPurchaseSheet>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  int _currentSuperChats = 0;
  late AnimationController _sparkleController;

  @override
  void initState() {
    super.initState();
    _loadCurrentSuperChats();
    _initAnimations();
  }

  void _initAnimations() {
    _sparkleController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _sparkleController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _sparkleController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSuperChats() async {
    try {
      final status = await PremiumService.getPremiumStatus();
      setState(() {
        _currentSuperChats = status.superChatsRemaining;
      });
    } catch (e) {
    }
  }

  Future<void> _purchaseSuperChats(String productId, int quantity) async {
    setState(() {
      _isLoading = true;
    });

    final iapService = IAPService();
    await iapService.purchaseSuperChats(
      productId,
      onSuccess: () async {
        // Başarı animasyonu
        _sparkleController.forward();

        // Super chat sayısını güncelle
        await _loadCurrentSuperChats();

        if (mounted) {
          setState(() => _isLoading = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.chat_bubble, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('$quantity Super Chat satın alındı! 💬'),
                ],
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );

          widget.onPurchaseSuccess?.call();
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Satın alma başarısız: $error'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      },
      onPendingTimeout: () {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ödeme işlemi devam ediyor. Onaylandığında Super Chat\'ler hesabınıza eklenecek.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildCurrentBalance(),
            Expanded(
              child: _buildPackagesList(),
            ),
            _buildBottomInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Super Chat',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Özel mesajla fark yarat',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFeaturesList(),
        ],
      ),
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      {'icon': Icons.message, 'text': '20 karakterlik özel mesaj'},
      {'icon': Icons.flash_on, 'text': '5 hızlı mesaj seçeneği'},
      {'icon': Icons.star, 'text': 'Anında ilgi çek'},
    ];

    return Column(
      children: features.map((feature) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                feature['icon'] as IconData,
                color: AppColors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                feature['text'] as String,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCurrentBalance() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        int currentBalance = _currentSuperChats;
        
        // 🔥 Gerçek zamanlı bakiye güncellemesi
        if (snapshot.hasData && snapshot.data?.exists == true) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          currentBalance = data?['superChatsRemaining'] ?? 0;
        }
        
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade50, Colors.blue.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mevcut Bakiyeniz',
                    style: TextStyle(
                      color: AppColors.grey600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currentBalance Super Chat',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPackagesList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: IAPConfig.superChatPackages.length,
      itemBuilder: (context, index) {
        final package = IAPConfig.superChatPackages[index];
        return _buildPackageCard(package);
      },
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> package) {
    final isPopular = package['isPopular'] == true;
    final quantity = package['quantity'] as int;
    final pricePerUnit = package['pricePerUnit'] as double;
    final discountPercent = package['discountPercent'] as int?;
    final totalPrice = pricePerUnit * quantity;
    final productId = package['id'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? AppColors.primary : AppColors.grey300,
          width: isPopular ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chat_bubble,
                        color: AppColors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            package['title'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            package['description'] as String,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.grey600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (package['features'] != null) ...[
                  ...((package['features'] as List).map((feature) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            feature as String,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    if (discountPercent != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '%$discountPercent İNDİRİM',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '₺${pricePerUnit.toStringAsFixed(2)}/adet',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.grey600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _purchaseSuperChats(productId, quantity),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            '₺${totalPrice.toStringAsFixed(2)} - Satın Al',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (isPopular)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
                child: const Text(
                  '🔥 POPÜLER',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.grey100,
        border: Border(
          top: BorderSide(
            color: AppColors.grey300,
            width: 1,
          ),
        ),
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.grey600,
                size: 16,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Super Chat ile özel mesajınızla dikkat çekin ve yeni insanlarla bağlantı kurun!',
                  style: TextStyle(
                    color: AppColors.grey600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Helper function - Sheet'i göster
Future<void> showSuperChatPurchaseSheet(
  BuildContext context, {
  VoidCallback? onPurchaseSuccess,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: SuperChatPurchaseSheet(
        onPurchaseSuccess: onPurchaseSuccess,
      ),
    ),
  );
}
