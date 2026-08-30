// lib/presentation/widgets/save_venue_button.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/saved_venues_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/analytics_service.dart';

/// "Gitmek İstiyorum" butonu.
///
/// FAVORİ (kalp) İLE KARIŞTIRILMAMALI:
/// Favori = "gittiğim ve sevdiğim yer" (check-in şartına bağlı).
/// Bu     = "henüz gitmediğim ama gitmek istediğim yer".
/// Bu yüzden ikon yer imi (bookmark), metin de niyet bildiriyor.
class SaveVenueButton extends StatefulWidget {
  final String venueId;
  final String venueName;
  final String venueCategory;
  final double latitude;
  final double longitude;
  final String vicinity;

  const SaveVenueButton({
    super.key,
    required this.venueId,
    required this.venueName,
    required this.venueCategory,
    required this.latitude,
    required this.longitude,
    this.vicinity = '',
  });

  @override
  State<SaveVenueButton> createState() => _SaveVenueButtonState();
}

class _SaveVenueButtonState extends State<SaveVenueButton> {
  bool _saved = false;
  bool _busy = true;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final saved = await SavedVenuesService.isSaved(uid, widget.venueId);
    if (mounted) {
      setState(() {
        _saved = saved;
        _busy = false;
      });
    }
  }

  Future<void> _toggle() async {
    final uid = _uid;
    if (uid == null || _busy) return;

    setState(() => _busy = true);
    final wasSaved = _saved;

    final ok = wasSaved
        ? await SavedVenuesService.remove(uid, widget.venueId)
        : await SavedVenuesService.save(
            userId: uid,
            venueId: widget.venueId,
            venueName: widget.venueName,
            venueCategory: widget.venueCategory,
            latitude: widget.latitude,
            longitude: widget.longitude,
            vicinity: widget.vicinity,
          );
      AnalyticsService.savedVenueAdded(widget.venueId);

    if (!mounted) return;
    setState(() {
      if (ok) _saved = !wasSaved;
      _busy = false;
    });

    if (ok && !wasSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listene eklendi — yakınına geldiğinde hatırlatacağız'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _toggle,
        icon: Icon(
          _saved ? Icons.bookmark : Icons.bookmark_border,
          size: 20,
          color: AppColors.primary,
        ),
        label: Text(
          _saved ? 'Listende' : 'Gitmek İstiyorum',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(
            color: AppColors.primary.withOpacity(_saved ? 0.8 : 0.4),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
