import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/venue.dart';
import '../../../core/theme/app_colors.dart';

class SponsorAdminPage extends ConsumerStatefulWidget {
  const SponsorAdminPage({super.key});

  @override
  ConsumerState<SponsorAdminPage> createState() => _SponsorAdminPageState();
}

class _SponsorAdminPageState extends ConsumerState<SponsorAdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _logoUrlController = TextEditingController();
  final TextEditingController _badgeTextController = TextEditingController();
  final TextEditingController _priorityController = TextEditingController();
  
  List<Venue> _venues = [];
  List<Venue> _filteredVenues = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadVenues();
    _searchController.addListener(_filterVenues);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _logoUrlController.dispose();
    _badgeTextController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  Future<void> _loadVenues() async {
    setState(() => _isLoading = true);
    
    try {
      final snapshot = await _firestore.collection('venues').get();
      _venues = snapshot.docs
          .map((doc) => Venue.fromPlaceData({...doc.data(), 'id': doc.id}))
          .toList();
      
      _filteredVenues = _venues;
      setState(() {});
    } catch (e) {
      _showSnackBar('Venue\'lar yüklenirken hata: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterVenues() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredVenues = _venues
          .where((venue) => venue.name.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _makeSponsor(Venue venue) async {
    // Form dialog'u göster
    await _showSponsorDialog(venue);
  }

  Future<void> _removeSponsor(Venue venue) async {
    try {
      await _firestore.collection('venues').doc(venue.id).update({
        'isSponsored': false,
        'sponsorLogoUrl': FieldValue.delete(),
        'sponsorBadgeText': FieldValue.delete(),
        'sponsorPriority': FieldValue.delete(),
        'sponsorStartDate': FieldValue.delete(),
        'sponsorEndDate': FieldValue.delete(),
      });
      
      _showSnackBar('${venue.name} sponsorluğu kaldırıldı');
      _loadVenues(); // Refresh
    } catch (e) {
      _showSnackBar('Hata: $e');
    }
  }

  Future<void> _showSponsorDialog(Venue venue) async {
    _logoUrlController.text = venue.sponsorLogoUrl ?? '';
    _badgeTextController.text = venue.sponsorBadgeText ?? 'Sponsor';
    _priorityController.text = venue.sponsorPriority.toString();
    
    DateTime startDate = venue.sponsorStartDate ?? DateTime.now();
    DateTime endDate = venue.sponsorEndDate ?? DateTime.now().add(const Duration(days: 30));

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${venue.name}\nSponsor Yap'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _logoUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Logo URL (opsiyonel)',
                    hintText: 'https://example.com/logo.png',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _badgeTextController,
                  decoration: const InputDecoration(
                    labelText: 'Badge Text',
                    hintText: 'Sponsor',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _priorityController,
                  decoration: const InputDecoration(
                    labelText: 'Öncelik (1-100)',
                    hintText: '10',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Başlangıç Tarihi:'),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() => startDate = picked);
                              }
                            },
                            child: Text('${startDate.day}/${startDate.month}/${startDate.year}'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Bitiş Tarihi:'),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: startDate,
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() => endDate = picked);
                              }
                            },
                            child: Text('${endDate.day}/${endDate.month}/${endDate.year}'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _saveSponsor(venue, startDate, endDate);
                Navigator.pop(context);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSponsor(Venue venue, DateTime startDate, DateTime endDate) async {
    try {
      final priority = int.tryParse(_priorityController.text) ?? 10;
      
      await _firestore.collection('venues').doc(venue.id).update({
        'isSponsored': true,
        'sponsorLogoUrl': _logoUrlController.text.isEmpty ? null : _logoUrlController.text,
        'sponsorBadgeText': _badgeTextController.text.isEmpty ? 'Sponsor' : _badgeTextController.text,
        'sponsorPriority': priority,
        'sponsorStartDate': Timestamp.fromDate(startDate),
        'sponsorEndDate': Timestamp.fromDate(endDate),
      });
      
      _showSnackBar('${venue.name} sponsor yapıldı! 💎');
      _loadVenues(); // Refresh
    } catch (e) {
      _showSnackBar('Hata: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💎 Sponsor Yönetimi'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Arama çubuğu
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Venue Ara',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          
          // Venue listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filteredVenues.length,
                    itemBuilder: (context, index) {
                      final venue = _filteredVenues[index];
                      final isSponsored = venue.isSponsored;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            isSponsored ? Icons.diamond : Icons.location_on,
                            color: isSponsored ? Colors.amber : Colors.grey,
                          ),
                          title: Text(
                            venue.name,
                            style: TextStyle(
                              fontWeight: isSponsored ? FontWeight.bold : FontWeight.normal,
                              color: isSponsored ? Colors.amber[800] : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(venue.category),
                              if (isSponsored) ...[
                                Text(
                                  '💎 ${venue.sponsorBadgeText} (Öncelik: ${venue.sponsorPriority})',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (venue.sponsorEndDate != null)
                                  Text(
                                    'Bitiş: ${venue.sponsorEndDate!.day}/${venue.sponsorEndDate!.month}/${venue.sponsorEndDate!.year}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                              ],
                            ],
                          ),
                          trailing: isSponsored
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                                  onPressed: () => _removeSponsor(venue),
                                  tooltip: 'Sponsorluğu Kaldır',
                                )
                              : IconButton(
                                  icon: const Icon(Icons.diamond, color: Colors.amber),
                                  onPressed: () => _makeSponsor(venue),
                                  tooltip: 'Sponsor Yap',
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
