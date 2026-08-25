// lib/presentation/widgets/premium/premium_subscription_widget.dart
import 'package:flutter/material.dart';
import '../../../core/models/premium_models.dart';
import '../../../core/models/payment_models.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/services/iap_service.dart';
import '../../../core/theme/app_colors.dart';
import '../payment/universal_payment_button.dart';
import 'subscription_disclosure_widget.dart';

class PremiumSubscriptionWidget extends StatefulWidget {
  final Function(PremiumSubscriptionType)? onPurchaseSuccess;
  final Function(String)? onError;

  const PremiumSubscriptionWidget({
    super.key,
    this.onPurchaseSuccess,
    this.onError,
  });

  @override
  State<PremiumSubscriptionWidget> createState() => _PremiumSubscriptionWidgetState();
}

class _PremiumSubscriptionWidgetState extends State<PremiumSubscriptionWidget> {
  int _selectedPackageIndex = 1; // Default: Monthly (En popüler)
  bool _isProcessing = false;
  bool _isPremiumUser = false;
  DateTime? _premiumExpiryDate;
  bool _isLoadingPremiumStatus = true;

  late List<PremiumPackage> _packages;
  final IAPService _iapService = IAPService();
  // Store'da aktif olan premium key'leri — boşken tüm paketler görünür
  Set<String> _availablePremiumKeys = {};

  @override
  void initState() {
    super.initState();
    // Önce sabit fiyatlarla başlat
    _packages = [
      PremiumPackage.fromType(PremiumSubscriptionType.weekly),
      PremiumPackage.fromType(PremiumSubscriptionType.monthly),
      PremiumPackage.fromType(PremiumSubscriptionType.quarterly),
    ];
    _checkPremiumStatus();
    _loadIAPPrices();
  }

  /// Google Play / App Store'dan gerçek fiyatları çek ve paketlere uygula
  Future<void> _loadIAPPrices() async {
    // IAP initialize edilmemişse bekle (max 5 sn)
    for (int i = 0; i < 10; i++) {
      if (_iapService.products.isNotEmpty) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;

    final keys = ['premium_weekly', 'premium_monthly', 'premium_quarterly'];
    final types = [
      PremiumSubscriptionType.weekly,
      PremiumSubscriptionType.monthly,
      PremiumSubscriptionType.quarterly,
    ];

    bool changed = false;
    final updatedPackages = List<PremiumPackage>.from(_packages);

    for (int i = 0; i < keys.length; i++) {
      final rawPrice = _iapService.getProductRawPrice(keys[i]);
      final priceString = _iapService.getProductPriceString(keys[i]);
      if (rawPrice > 0 && rawPrice != updatedPackages[i].price) {
        // IAP'tan gelen fiyat farklıysa paketi güncelle
        updatedPackages[i] = PremiumPackage(
          type: types[i],
          title: updatedPackages[i].title,
          subtitle: updatedPackages[i].subtitle,
          price: rawPrice,
          priceString: priceString,
          originalPrice: updatedPackages[i].originalPrice,
          duration: updatedPackages[i].duration,
          features: updatedPackages[i].features,
          isRecommended: updatedPackages[i].isRecommended,
          isLaunchOffer: updatedPackages[i].isLaunchOffer,
        );
        changed = true;
      }
    }

    if (changed && mounted) {
      setState(() => _packages = updatedPackages);
    }

    // Store'da hangi premium ürünler aktif?
    if (mounted) {
      final availableKeys = _iapService.getAvailablePackageKeys('premium_');
      setState(() {
        _availablePremiumKeys = availableKeys;
        // Sadece store'da aktif olan paketleri göster
        // _iapService.products boşsa (internet yok / yükleniyor) filtreleme yapma
        if (availableKeys.isNotEmpty) {
          final keyMap = {
            PremiumSubscriptionType.weekly: 'premium_weekly',
            PremiumSubscriptionType.monthly: 'premium_monthly',
            PremiumSubscriptionType.quarterly: 'premium_quarterly',
          };
          final filtered = updatedPackages
              .where((p) => availableKeys.contains(keyMap[p.type]))
              .toList();
          if (filtered.isNotEmpty) {
            _packages = filtered;
            // Seçili index aralık dışına çıkmışsa 0'a resetle
            if (_selectedPackageIndex >= _packages.length) {
              _selectedPackageIndex = 0;
            }
          }
        }
      });
    }
  }
  Future<void> _checkPremiumStatus() async {
    try {
      final premiumStatus = await PremiumService.getPremiumStatus();
      
      if (mounted) {
        setState(() {
          _isPremiumUser = premiumStatus.isPremium;
          _premiumExpiryDate = premiumStatus.expiryDate;
          _isLoadingPremiumStatus = false;
        });
        
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPremiumStatus = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading state'i göster
    if (_isLoadingPremiumStatus) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return SafeArea( // 🔧 SAFE AREA: Premium subscription wrapper
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.premium.withOpacity(0.1),
              Colors.transparent,
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildPackageSelection(),
              const SizedBox(height: 20),
              _buildSelectedPackageDetails(),
              const SizedBox(height: 16),
              _buildSubscriptionDisclosure(),
              const SizedBox(height: 20),
              _buildPurchaseButton(),
              const SizedBox(height: 12),
              _buildRestorePurchasesButton(),
              const SizedBox(height: 12),
              _buildLegalText(),
              const SizedBox(height: 20), // Bottom padding
            ],
          ),
        ),
      ),
    ); // 🔧 SAFE AREA: Close SafeArea wrapper
  }

  Widget _buildHeader() {
    // Premium kullanıcılar için farklı header
    if (_isPremiumUser) {
      String remainingText = '';
      if (_premiumExpiryDate != null) {
        final now = DateTime.now();
        final difference = _premiumExpiryDate!.difference(now);
        final daysLeft = difference.inDays;
        
        if (daysLeft > 0) {
          remainingText = '$daysLeft gün kaldı';
        } else {
          remainingText = 'Bugün sona eriyor';
        }
      }
      
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.premium, AppColors.premium.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Premium Sürenizi Uzatın',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            if (remainingText.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.premium.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.premium.withOpacity(0.3)),
                ),
                child: Text(
                  '⏰ $remainingText',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.premium,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Daha fazla ayrıcalığın keyfini çıkarın',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // Premium olmayan kullanıcılar için varsayılan header
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.premium, AppColors.premium.withOpacity(0.8)],
              ),
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Icon(
              Icons.workspace_premium,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Premium\'a Geç',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sınırsız özellikler ve özel ayrıcalıklar',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPackageSelection() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _packages.length,
        itemBuilder: (context, index) {
          final package = _packages[index];
          final isSelected = index == _selectedPackageIndex;
          
          return GestureDetector(
            onTap: () {
              
              setState(() => _selectedPackageIndex = index);
              
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 130,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.premium : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? AppColors.premium : Colors.grey[300]!,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.premium.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.duration,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          package.priceString ?? '₺${package.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppColors.premium,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (package.originalPrice != null)
                          Text(
                            '₺${package.originalPrice!.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough,
                              color: isSelected ? Colors.white70 : Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Badge'ler için güvenli alan - sadece biri gösterilsin
                  if (package.isRecommended && !package.isLaunchOffer)
                    Positioned(
                      top: 4,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'POPÜLER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // Lansman badge'i öncelikli - hem popüler hem lansman varsa sadece lansman göster
                  if (package.isLaunchOffer)
                    Positioned(
                      top: 4,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'LANSMAN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedPackageDetails() {
    final selectedPackage = _packages[_selectedPackageIndex];
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedPackage.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.premium.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${selectedPackage.type.superLikes} Öne Çıkan İstek',
                  style: const TextStyle(
                    color: AppColors.premium,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            selectedPackage.subtitle,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          
          // Premium kullanıcı için ek bilgi
          if (_isPremiumUser && _premiumExpiryDate != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.success, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu paket mevcut premium sürenizin sonuna eklenecek',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          ...selectedPackage.features.map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton() {
    final selectedPackage = _packages[_selectedPackageIndex];
    
    for (int i = 0; i < _packages.length; i++) {
    }
    
    // Premium kullanıcı için button text'ini değiştir
    String customButtonText = _isPremiumUser ? 'Süreyi Uzat' : 'Satın Al';
    
    // PremiumPackage'ı PaymentPackage'a dönüştür
    final paymentPackage = PaymentPackage(
      id: selectedPackage.type.name,
      type: PaymentType.premium,
      title: selectedPackage.title,
      amount: 1,
      price: selectedPackage.price,
      originalPrice: selectedPackage.originalPrice ?? selectedPackage.price,
      description: selectedPackage.subtitle,
      duration: selectedPackage.duration,
      isPopular: selectedPackage.isRecommended,
      features: [
        selectedPackage.subtitle,
        'Premium özellikler',
        'Daha fazla bağlantı isteği',
        'Check-in yapanların profillerini gör',
        'Check-in yapmadan kişileri görebilme',
      ],
    );


    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: UniversalPaymentButton(
        package: paymentPackage,
        customButtonText: customButtonText,
        onPaymentSuccess: () {
          final currentSelectedType = _packages[_selectedPackageIndex].type;
          _handlePurchaseSuccess(currentSelectedType);
        },
        onPaymentError: (error) => _handlePurchaseError('Premium satın alma işlemi tamamlanamadı'),
        onPaymentStarted: () {
          setState(() {
            _isProcessing = true;
          });
        },
        height: 50,
      ),
    );
  }

  /// Apple Guideline 3.1.2 - Subscription Disclosure
  Widget _buildSubscriptionDisclosure() {
    final selectedPackage = _packages[_selectedPackageIndex];
    
    // Determine duration string for disclosure
    String duration;
    switch (selectedPackage.type) {
      case PremiumSubscriptionType.weekly:
        duration = 'weekly';
        break;
      case PremiumSubscriptionType.monthly:
        duration = 'monthly';
        break;
      case PremiumSubscriptionType.quarterly:
        duration = 'quarterly';
        break;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SubscriptionDisclosureWidget(
        duration: duration,
        price: selectedPackage.price,
      ),
    );
  }

  Widget _buildLegalText() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
    //   child: Text(
    //     'Aboneliğiniz otomatik olarak yenilenir. İstediğiniz zaman iptal edebilirsiniz.',
    //     style: TextStyle(
    //       fontSize: 12,
    //       color: Colors.grey[600],
    //     ),
    //     textAlign: TextAlign.center,
    //   ),
    );
  }

  Future<void> _handlePurchaseSuccess(PremiumSubscriptionType type) async {
    setState(() => _isProcessing = true);
    
    try {
      
      // Mock transaction ID (gerçek uygulamada Google Play'den gelir)
      final transactionId = 'mock_${DateTime.now().millisecondsSinceEpoch}';
      
      final success = await PremiumService.purchasePremiumSubscription(
        type: type,
        transactionId: transactionId,
      );
      
      if (success) {
        // Premium state'i yenile
        await _checkPremiumStatus();
        
        // Success callback'i çağır
        widget.onPurchaseSuccess?.call(type);
        
        // Premium extension mi yoksa yeni satın alma mı olduğunu belirle
        if (_isPremiumUser) {
        } else {
        }
      } else {
        _handlePurchaseError('Premium abonelik aktivasyonu başarısız');
      }
    } catch (e) {
      _handlePurchaseError('Premium satın alma işlemi tamamlanamadı');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _handlePurchaseError(String error) {
    widget.onError?.call(error);
    setState(() => _isProcessing = false);
  }

  /// Restore Purchases Button - Apple App Store Requirement (Guideline 3.1.1)
  /// Also available on Android for subscription recovery
  Widget _buildRestorePurchasesButton() {
    return TextButton(
      onPressed: _isProcessing ? null : _restorePurchases,
      child: Text(
        'Satın Almaları Geri Yükle',
        style: TextStyle(
          color: _isProcessing ? Colors.grey : AppColors.primary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Restore previously purchased subscriptions
  Future<void> _restorePurchases() async {
    setState(() => _isProcessing = true);
    
    try {
      
      // IAP servisinden restore işlemini çağır
      final iapService = IAPService();
      final restoredCount = await iapService.restorePurchases();
      
      // Premium durumunu yenile
      await _checkPremiumStatus();
      
      if (mounted) {
        if (restoredCount > 0) {
          // Restore edilmiş ürün bulundu
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $restoredCount satın alma başarıyla geri yüklendi'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          // Restore edilecek ürün yok
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ℹ️ Geri yüklenecek satın alma bulunamadı'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      
    } catch (e) {
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Geri yükleme başarısız: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
