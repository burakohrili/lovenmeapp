// lib/presentation/widgets/venue_cover_image.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Mekan kapak görseli — tek kaynak.
///
/// NEDEN VAR:
/// Görseller üç ayrı sebepten gelmiyordu:
///  1. Keşfet kartında hiçbir görsel widget'ı YOKTU (veri vardı, çizilmiyordu).
///  2. Mekan detayında vardı ama yedeği kapanmış bir alan adıydı
///     (`via.placeholder.com`) — yani her zaman kırık resim ikonu.
///  3. Firestore mekan kayıtlarının çoğunda zaten fotoğraf alanı yoktu.
///
/// Bu widget üçünü de kapatır: gerçek fotoğraf varsa onu gösterir, yoksa
/// kategoriye göre üretilmiş bir kapak çizer. **Hiçbir durumda boş gri kutu
/// veya kırık resim ikonu göstermez.**
class VenueCoverImage extends StatelessWidget {
  final String? photoUrl;
  final String category;
  final String venueName;
  final double height;
  final BorderRadius? borderRadius;

  const VenueCoverImage({
    super.key,
    required this.photoUrl,
    required this.category,
    required this.venueName,
    this.height = 160,
    this.borderRadius,
  });

  bool get _hasPhoto {
    final url = photoUrl;
    if (url == null || url.trim().isEmpty) return false;
    // Kapanmış plasholder servisleri: eski kayıtlarda hâlâ duruyor olabilir.
    if (url.contains('via.placeholder.com')) return false;
    if (url.contains('placeholder.com')) return false;
    return url.startsWith('http');
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(14);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: _hasPhoto
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, __) => _CategoryCover(
                  category: category,
                  venueName: venueName,
                  dimmed: true,
                ),
                // Ağ hatasında da kategori kapağına düşer — kırık ikon yok.
                errorWidget: (_, __, ___) => _CategoryCover(
                  category: category,
                  venueName: venueName,
                ),
              )
            : _CategoryCover(category: category, venueName: venueName),
      ),
    );
  }
}

/// Fotoğraf yokken çizilen kategori kapağı.
class _CategoryCover extends StatelessWidget {
  final String category;
  final String venueName;
  final bool dimmed;

  const _CategoryCover({
    required this.category,
    required this.venueName,
    this.dimmed = false,
  });

  static ({IconData icon, Color color}) _styleFor(String category) {
    switch (category.toLowerCase()) {
      case 'cafe':
      case 'kafe':
      case 'coffee_shop':
        return (icon: Icons.local_cafe_rounded, color: const Color(0xFF8B5E3C));
      case 'restaurant':
      case 'restoran':
      case 'meal_takeaway':
        return (icon: Icons.restaurant_rounded, color: const Color(0xFFE2603F));
      case 'bar':
      case 'night_club':
        return (icon: Icons.local_bar_rounded, color: const Color(0xFF7B4BA8));
      case 'bakery':
      case 'firin':
        return (icon: Icons.bakery_dining_rounded, color: const Color(0xFFD79A2B));
      case 'cinema':
      case 'sinema':
      case 'movie_theater':
        return (icon: Icons.movie_rounded, color: const Color(0xFF2F6FB0));
      case 'park':
        return (icon: Icons.park_rounded, color: const Color(0xFF3F8F4F));
      case 'gym':
      case 'spor':
      case 'fitness':
        return (icon: Icons.fitness_center_rounded, color: const Color(0xFFD4552F));
      case 'museum':
      case 'muze':
        return (icon: Icons.museum_rounded, color: const Color(0xFF5A6B8C));
      default:
        return (icon: Icons.place_rounded, color: AppColors.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(category);
    final base = style.color;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withOpacity(dimmed ? 0.20 : 0.85),
            base.withOpacity(dimmed ? 0.10 : 0.55),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Hafif doku: düz renk yerine derinlik hissi.
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              style.icon,
              size: 140,
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          if (!dimmed)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(style.icon, size: 26, color: Colors.white),
                  const SizedBox(height: 6),
                  Text(
                    venueName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(blurRadius: 6, color: Colors.black26),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
