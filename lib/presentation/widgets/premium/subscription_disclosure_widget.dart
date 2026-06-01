// lib/presentation/widgets/premium/subscription_disclosure_widget.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';

/// Apple Guideline 3.1.2 - Subscription Disclosure Widget
/// 
/// Otomatik yenilenen abonelikler için zorunlu bilgilendirme:
/// - Otomatik yenileme bilgisi
/// - Fiyat ve süre
/// - İptal yönergeleri
/// - Terms of Service ve Privacy Policy linkleri
class SubscriptionDisclosureWidget extends StatelessWidget {
  /// Abonelik süresi: 'weekly', 'monthly', 'quarterly'
  final String duration;
  
  /// Abonelik fiyatı (TL)
  final double price;
  
  /// Ürün adı (opsiyonel)
  final String? productName;
  
  /// Kompakt mod (daha az alan kaplar)
  final bool compact;
  
  /// Koyu tema mı?
  final bool darkMode;

  const SubscriptionDisclosureWidget({
    super.key,
    required this.duration,
    required this.price,
    this.productName,
    this.compact = false,
    this.darkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: darkMode 
            ? const Color(0xFF2C2C2E) // Daha açık koyu gri
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: darkMode 
              ? Colors.white.withOpacity(0.15)
              : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
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
          // Başlık
          if (!compact) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.15),
                    AppColors.primary.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Abonelik Bilgileri',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: darkMode ? Colors.white : Colors.black87,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          
          // Otomatik yenileme bilgisi
          _buildInfoRow(
            icon: Icons.autorenew,
            text: 'Bu abonelik otomatik olarak yenilenir',
            context: context,
          ),
          
          SizedBox(height: compact ? 6 : 8),
          
          // Fiyat ve süre bilgisi
          _buildInfoRow(
            icon: Icons.payment,
            text: _getPriceInfo(),
            context: context,
          ),
          
          SizedBox(height: compact ? 6 : 8),
          
          // İptal bilgisi
          _buildInfoRow(
            icon: Icons.cancel_outlined,
            text: 'Mevcut dönem bitmeden en az 24 saat önce iptal etmezseniz '
                  '${_formatPrice(price)} ücret tahsil edilecektir',
            context: context,
          ),
          
          SizedBox(height: compact ? 6 : 8),
          
          // İptal yönergeleri
          _buildInfoRow(
            icon: Icons.settings,
            text: Platform.isIOS
                ? 'Aboneliği App Store > Hesabım > Abonelikler\'den iptal edebilirsiniz'
                : 'Aboneliği Google Play > Ödemeler ve abonelikler > Abonelikler\'den iptal edebilirsiniz',
            context: context,
          ),
          
          if (!compact) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 12),
          ] else ...[
            const SizedBox(height: 8),
          ],
          
          // Terms & Privacy Links
          _buildLinks(context),
        ],
      ),
    );
  }

  /// Bilgi satırı widget'ı
  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    required BuildContext context,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: darkMode 
            ? Colors.white.withOpacity(0.03)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: darkMode 
                  ? Colors.white.withOpacity(0.1)
                  : AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: compact ? 16 : 18,
              color: darkMode 
                  ? Colors.white.withOpacity(0.9)
                  : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: compact ? 12 : 13.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: darkMode 
                      ? Colors.white.withOpacity(0.95)
                      : Colors.black87,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Terms of Service ve Privacy Policy linkleri
  Widget _buildLinks(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLinkButton(
              text: 'Kullanım Koşulları',
              url: 'https://lovenme.app/hizmet-sartlari/',
              context: context,
            ),
            
            const SizedBox(width: 12),
            
            _buildLinkButton(
              text: 'Gizlilik Politikası',
              url: 'https://lovenme.app/gizlilik-politikasi',
              context: context,
            ),
          ],
        ),
      ],
    );
  }

  /// Link butonu
  Widget _buildLinkButton({
    required String text,
    required String url,
    required BuildContext context,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _openUrl(url, context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  /// URL açma fonksiyonu
  Future<void> _openUrl(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link açılamadı: $url'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Fiyat bilgisi metni
  String _getPriceInfo() {
    final durationText = _getDurationText();
    return 'Her $durationText ${_formatPrice(price)} ücret tahsil edilir';
  }

  /// Süre metni
  String _getDurationText() {
    switch (duration.toLowerCase()) {
      case 'weekly':
        return 'hafta';
      case 'monthly':
        return 'ay';
      case 'quarterly':
        return '3 ay';
      case 'yearly':
        return 'yıl';
      default:
        return duration;
    }
  }

  /// Fiyat formatla
  String _formatPrice(double price) {
    return '₺${price.toStringAsFixed(2)}';
  }
}

/// Basit Disclosure (sadece metin, link yok)
class SimpleSubscriptionDisclosure extends StatelessWidget {
  final String duration;
  final double price;
  final bool darkMode;

  const SimpleSubscriptionDisclosure({
    super.key,
    required this.duration,
    required this.price,
    this.darkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: darkMode 
            ? Colors.grey[900]?.withOpacity(0.3)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        Platform.isIOS
            ? 'Otomatik yenilenir. İptal için App Store > Abonelikler. '
              'Detaylar için Kullanım Koşulları ve Gizlilik Politikası\'na bakın.'
            : 'Otomatik yenilenir. İptal için Google Play > Abonelikler. '
              'Detaylar için Kullanım Koşulları ve Gizlilik Politikası\'na bakın.',
        style: TextStyle(
          fontSize: 10,
          color: darkMode 
              ? Colors.white.withOpacity(0.6)
              : Colors.grey[600],
          height: 1.3,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
