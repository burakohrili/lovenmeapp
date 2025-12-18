import 'package:flutter/material.dart';

class PhotoShareSheet extends StatefulWidget {
  final String venueId;
  final String venueName;
  final Function? onPhotoShared;

  const PhotoShareSheet({
    super.key,
    required this.venueId,
    required this.venueName,
    this.onPhotoShared,
  });

  @override
  State<PhotoShareSheet> createState() => _PhotoShareSheetState();
}

class _PhotoShareSheetState extends State<PhotoShareSheet> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  widget.venueName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Bu mekandan fotoğraf paylaşın',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildOptionButton(
                        icon: Icons.camera_alt,
                        label: 'Kamera',
                        onTap: _isLoading ? null : () => _openCamera(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildOptionButton(
                        icon: Icons.photo_library,
                        label: 'Galeri',
                        onTap: _isLoading ? null : () => _openGallery(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text(
                        'Fotoğraf yükleniyor...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: onTap != null ? const Color(0xFFE91E63) : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: onTap != null ? Colors.black87 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCamera() async {
    try {
      setState(() => _isLoading = true);
      
      await Future.delayed(const Duration(seconds: 2)); // Simulate processing
      
      if (widget.onPhotoShared != null) {
        widget.onPhotoShared!();
      }
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf başarıyla paylaşıldı!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf paylaşılamadı. Lütfen tekrar deneyiniz.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openGallery() async {
    try {
      setState(() => _isLoading = true);
      
      await Future.delayed(const Duration(seconds: 2)); // Simulate processing
      
      if (widget.onPhotoShared != null) {
        widget.onPhotoShared!();
      }
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf başarıyla paylaşıldı!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf paylaşılamadı. Lütfen tekrar deneyiniz.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
