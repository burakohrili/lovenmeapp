// lib/presentation/pages/explore_nearby/explore_nearby_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import 'models/explore_venue_model.dart';
import 'widgets/venue_card_widget.dart';
import 'venue_detail_page.dart';
import 'services/explore_nearby_service.dart';

class ExploreNearbyPage extends ConsumerStatefulWidget {
  const ExploreNearbyPage({super.key});

  @override
  ConsumerState<ExploreNearbyPage> createState() => _ExploreNearbyPageState();
}

class _ExploreNearbyPageState extends ConsumerState<ExploreNearbyPage> {
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<ExploreVenue> _venues = [];
  String? _errorMessage;
  final _exploreService = ExploreNearbyService();
  final _scrollController = ScrollController();
  
  // 🎯 PAGINATION
  static const int _pageSize = 10;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadVenues(fromCache: true);
    _setupScrollListener();
    _setupPeriodicRefresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 🎯 SCROLL: Pagination için scroll listener
  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent - 200) {
        // Son 200px kaldığında yeni sayfa yükle
        if (!_isLoadingMore && _hasMore) {
          _loadMoreVenues();
        }
      }
    });
  }

  /// 🔄 REAL-TIME: 10 dakikada bir otomatik yenile
  void _setupPeriodicRefresh() {
    Future.delayed(const Duration(minutes: 10), () {
      if (mounted) {
        _refreshInBackground();
        _setupPeriodicRefresh(); // Recursive
      }
    });
  }

  /// 🔄 BACKGROUND: Sessizce cache'i yenile
  Future<void> _refreshInBackground() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final venues = await _exploreService.getCachedUserCheckedInVenues(
        currentUser.uid,
        forceRefresh: true,
      );
      
      if (mounted) {
        setState(() {
          _venues = venues;
        });
      }
    } catch (e) {
    }
  }

  /// 📥 INITIAL LOAD: Cache'den hızlı yükle
  Future<void> _loadVenues({bool fromCache = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Lütfen giriş yapın';
          _isLoading = false;
        });
        return;
      }

      
      // Cache'den al veya Firestore'dan yükle
      final venues = fromCache
          ? await _exploreService.getCachedUserCheckedInVenues(currentUser.uid)
          : await _exploreService.getUserCheckedInVenues(currentUser.uid);
      
      setState(() {
        _venues = venues;
        _isLoading = false;
        _hasMore = venues.length >= _pageSize;
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Mekanlar yüklenirken bir hata oluştu';
        _isLoading = false;
      });
    }
  }

  /// 📄 PAGINATION: Daha fazla venue yükle
  Future<void> _loadMoreVenues() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      
      // Son venue'den sonrasını yükle
      final newVenues = await _exploreService.getUserCheckedInVenues(
        currentUser.uid,
        limit: _pageSize,
      );

      setState(() {
        if (newVenues.length < _pageSize) {
          _hasMore = false;
        }
        _venues.addAll(newVenues);
        _isLoadingMore = false;
      });
      
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: _buildPlacesContent(),
      ),
    );
  }

  Widget _buildPlacesContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_venues.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadVenues(fromCache: false),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _venues.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          // 📄 Loading indicator at bottom
          if (index == _venues.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              ),
            );
          }
          
          final venue = _venues[index];
          return VenueCardWidget(
            venue: venue,
            onTap: () => _navigateToVenueDetail(venue),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Henüz check-in yaptığınız mekan yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check in to venues to see them here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadVenues,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToVenueDetail(ExploreVenue venue) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VenueDetailPage(venueId: venue.id),
      ),
    );
  }
}
