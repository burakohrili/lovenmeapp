// lib/presentation/pages/map/components/saved_nearby_banner.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/services/saved_venues_service.dart';
import '../../../../core/theme/app_colors.dart';

/// "Kaydettiğin yer yakınında" hatırlatması.
///
/// UYGULAMANIN ÇEKİRDEK VAADİ:
/// İnsanlar bir mekanı kaydedip unutuyor (digital hoarding — kaydetmek,
/// yapmanın yerine geçiyor). Bu kart, listeye eklenen yerin yanından
/// geçerken kullanıcıyı uyandırır; check-in ise döngüyü kapatır.
///
/// BİLİNÇLİ SINIR: Yalnızca uygulama açıkken çalışır. Arka plan konumu
/// (geofence) KULLANILMAZ — gizlilik duruşunu ve Info.plist'i bozmamak için.
class SavedNearbyBanner extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  /// Karta dokunulunca mekanı açmak için (opsiyonel).
  final void Function(SavedVenue venue)? onTap;

  const SavedNearbyBanner({
    super.key,
    required this.latitude,
    required this.longitude,
    this.onTap,
  });

  @override
  State<SavedNearbyBanner> createState() => _SavedNearbyBannerState();
}

class _SavedNearbyBannerState extends State<SavedNearbyBanner> {
  SavedVenue? _venue;
  double _distance = 0;
  final Set<String> _dismissed = {};
  double? _lastLat;
  double? _lastLon;

  @override
  void didUpdateWidget(covariant SavedNearbyBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRefresh();
  }

  @override
  void initState() {
    super.initState();
    _maybeRefresh();
  }

  /// Konum belirgin şekilde değiştiyse tekrar sorgula (gereksiz okuma yapma).
  void _maybeRefresh() {
    final lat = widget.latitude, lon = widget.longitude;
    if (lat == null || lon == null) return;

    if (_lastLat != null && _lastLon != null) {
      final moved =
          SavedVenuesService.distanceMeters(_lastLat!, _lastLon!, lat, lon);
      if (moved < 100) return; // 100 m'den az hareket: yeniden sorgulama
    }
    _lastLat = lat;
    _lastLon = lon;
    _load(lat, lon);
  }

  Future<void> _load(double lat, double lon) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final nearby = await SavedVenuesService.nearbySaved(
      userId: uid,
      latitude: lat,
      longitude: lon,
      radiusMeters: 500,
    );

    if (!mounted) return;
    final next = nearby.where((v) => !_dismissed.contains(v.venueId)).toList();
    setState(() {
      _venue = next.isEmpty ? null : next.first;
      _distance = _venue == null
          ? 0
          : SavedVenuesService.distanceMeters(
              lat, lon, _venue!.latitude, _venue!.longitude);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _venue;
    if (v == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap == null ? null : () => widget.onTap!(v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: AppColors.primary.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bookmark,
                    size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Listendeki ${v.venueName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_distance.round()} m ötede — check-in ile tamamla',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.grey600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.grey500,
                onPressed: () {
                  setState(() {
                    _dismissed.add(v.venueId);
                    _venue = null;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
