// lib/presentation/widgets/mayorship_bid_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../pages/profile/diamond_provider.dart';
import '../pages/profile/profile_page.dart';

class MayorshipBidDialog extends ConsumerStatefulWidget {
  final String venueId;
  final String venueName;
  final int currentHighestBid;
  final String? currentMayorName;

  const MayorshipBidDialog({
    super.key,
    required this.venueId,
    required this.venueName,
    this.currentHighestBid = 0,
    this.currentMayorName,
  });

  @override
  ConsumerState<MayorshipBidDialog> createState() => _MayorshipBidDialogState();
}

class _MayorshipBidDialogState extends ConsumerState<MayorshipBidDialog> {
  final TextEditingController _bidController = TextEditingController();
  bool _isLoading = false;
  int _selectedBid = 0;

  @override
  void initState() {
    super.initState();
    _selectedBid = widget.currentHighestBid + 1;
    _bidController.text = _selectedBid.toString();
  }

  @override
  Widget build(BuildContext context) {
    final diamondState = ref.watch(diamondProvider);
    final minBid = widget.currentHighestBid + 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Colors.amber,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Muhtarlık Teklifi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.venueName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Mevcut durum
              if (widget.currentHighestBid > 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Mevcut Muhtar: ${widget.currentMayorName ?? "Bilinmiyor"}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.diamond, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'En yüksek teklif: ${widget.currentHighestBid} 💎',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Elmas bakiyesi
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.diamond, color: Colors.amber, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Elmas Bakiyeniz',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${diamondState.balance} 💎',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (diamondState.balance < minBid)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Profile sayfasına git - elmas satın alma artık orada
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const ProfilePage(),
                            ),
                          );
                        },
                        child: const Text(
                          'Elmas Al',
                          style: TextStyle(color: Colors.amber),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Hızlı teklif butonları
              const Text(
                'Hızlı Teklif',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQuickBidButton(minBid),
                  _buildQuickBidButton(minBid + 5),
                  _buildQuickBidButton(minBid + 10),
                  _buildQuickBidButton(minBid + 20),
                ],
              ),
              const SizedBox(height: 20),

              // Manuel teklif
              const Text(
                'Özel Teklif',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _bidController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Minimum $minBid 💎',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.diamond, color: Colors.amber),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _selectedBid = int.tryParse(value) ?? minBid;
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Minimum teklif: $minBid 💎',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),

              // Butonlar
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                      ),
                      child: const Text(
                        'İptal',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _canPlaceBid() ? _placeBid : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                              ),
                            )
                          : Text(
                              'Teklif Ver ($_selectedBid 💎)',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickBidButton(int bid) {
    final diamondState = ref.watch(diamondProvider);
    final canAfford = diamondState.balance >= bid;
    final isSelected = _selectedBid == bid;

    return InkWell(
      onTap: canAfford ? () {
        setState(() {
          _selectedBid = bid;
          _bidController.text = bid.toString();
        });
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? Colors.amber.withOpacity(0.3)
              : Colors.white.withOpacity(canAfford ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? Colors.amber
                : Colors.white.withOpacity(canAfford ? 0.3 : 0.1),
          ),
        ),
        child: Text(
          '$bid 💎',
          style: TextStyle(
            color: canAfford ? Colors.white : Colors.white38,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  bool _canPlaceBid() {
    final diamondState = ref.watch(diamondProvider);
    final minBid = widget.currentHighestBid + 1;
    
    return !_isLoading && 
           _selectedBid >= minBid && 
           diamondState.balance >= _selectedBid;
  }

  Future<void> _placeBid() async {
    setState(() => _isLoading = true);

    try {
      final success = await ref.read(diamondProvider.notifier)
          .bidForMayorship(widget.venueId, widget.venueName, _selectedBid);
      
      if (success && mounted) {
        Navigator.of(context).pop(true); // Başarılı olduğunu bildir
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.venueName} için $_selectedBid 💎 teklif verildi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Teklif verilemedi. Lütfen tekrar deneyiniz.'),
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

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }
}
