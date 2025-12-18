// lib/presentation/pages/map/map_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// Core theme
import '../../../core/theme/app_colors.dart';

// Core services
import '../../../core/services/muhtar_firebase_service.dart';
import '../../../core/services/iap_service.dart'; // IAP Service

// UI Components
import '../../../widgets/chat_request_modal.dart';

// Payment config
import '../../../core/config/iap_config.dart'; // IAP Config import

// Models
import '../../../core/models/premium_models.dart';

// Components
import 'components/venue_details_sheet.dart';
import 'components/checked_in_users_list.dart';

// Widgets

import '../../widgets/premium/premium_subscription_widget.dart';

// Services
import 'services/venue_service.dart';
import 'services/optimized_venue_service.dart';
import 'services/checkin_service.dart';
import '../../../core/models/checkedin_user.dart';

// Models
import '../../models/venue.dart';

// Utils
import 'utils/map_styles.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final FocusNode _searchFocusNode =
      FocusNode(); // Genel focus node - gelecekte kullanılabilir

  Position? _currentPosition;
  bool _isLocationPermissionGranted = false;
  bool _isLoading = false;

  // Dynamic loading variables
  double _currentZoom = 18.0;
  double _lastZoom = 18.0; // Track zoom changes
  LatLng? _lastLoadedCenter;
  final Set<String> _loadedAreas = {}; // Yüklenen bölgeleri takip et

  // Venue related variables
  Set<Marker> _markers = {};
  List<Venue> _venues = [];
  final VenueService _venueService = VenueService();
  final OptimizedVenueService _optimizedVenueService = OptimizedVenueService();
  final CheckInService _checkInService = CheckInService();
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, int> _venueUserCounts = {}; // Venue ID -> Actual user count

  final Set<String> _loadedVenueIds = {}; // Tekrarları önlemek için

  // Optimized caching system
  final Map<String, List<Venue>> _tileVenueCache = {}; // Tile-based venue cache
  // 💎 GLOBAL VENUE CACHE & SPONSOR CHAINS
  final Map<String, Map<String, dynamic>> _globalVenueCache =
      {}; // Global venue data cache
  final Map<String, Map<String, dynamic>> _sponsoredChains =
      {}; // Chain sponsor cache
  final Map<String, Venue> _sponsoredVenues =
      {}; // 💎 FIREBASE SPONSOR VENUES (2km radius)
  final Set<String> _loadedTiles = {}; // Loaded tile tracking
  int _loadingRequestId = 0; // Request cancellation tracking
  LatLngBounds? _visibleBounds; // Current viewport bounds
  bool _isDisposed = false; // Dispose tracking
  bool _isInitialLoad = true; // Navigation tracking
  bool _isVenueDetailsOpen = false; // Prevent multiple venue detail sheets

  // Performance constants
  static const double _maxDistance = 200.0; // 200m max for all venues
  static const int _maxMarkersOnScreen = 60; // Limit markers for performance
  static const double _minZoomForMarkers =
      12.0; // Don't show markers below this zoom

  // Firebase related
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MuhtarFirebaseService _muhtarService = MuhtarFirebaseService();
  final Map<String, List<CheckedInUser>> _venueCheckIns = {};
  bool _isPremium = false;
  Set<String> _userCheckedInVenues = {}; // Changed back to Set, not final
  Map<String, Map<String, dynamic>> _dailyMayors =
      {}; // Changed back to Map, not final
  Set<String> _userFavoriteVenues = {}; // User's favorite venue IDs

  // Muhtar related
  int _userDiamondBalance = 0;
  StreamSubscription<int>? _diamondBalanceSubscription;

  // 🕐 Check-in cooldown related
  CheckInCooldownStatus? _cooldownStatus;
  Timer? _cooldownTimer;

  // 📍 Check-in loading state
  bool _isCheckingIn = false;

  // 💬 CHAT REQUEST SYSTEM VARIABLES
  final Set<String> _sentChatRequestUserIds =
      {}; // Chat request gönderilen kullanıcılar
  Animation<double>? _likeOpacityAnimation;
  Animation<double>? _superLikeOpacityAnimation;

  // �🎨 CUSTOM MARKER ICONS CACHE

  BitmapDescriptor?
      _starMarkerIcon; // Check-in yapılan mekanlar için check mark (✅)
  BitmapDescriptor? _crownMarkerIcon; // Muhtar olduğu mekanlar için taç şekli
  BitmapDescriptor?
      _sponsorMarkerIcon; // 💎 SPONSOR MEKANLAR İÇİN DIAMOND MARKER

  // 📍 CATEGORY-BASED MARKER ICONS (Cache system)
  final Map<String, BitmapDescriptor> _categoryMarkerIcons =
      {}; // Kategori bazlı icon cache

  // ⚡ PERFORMANCE CACHE - Data freshness tracking
  DateTime? _lastDataRefresh;
  static const int _cacheValidityMinutes = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Lifecycle observer ekle
    _loadInitialDiamondBalance(); // İlk bakiyeyi yükle
    _startDiamondBalanceListener(); // Sonra stream'i başlat
    _loadCustomMarkerIcons(); // Custom marker icon'ları yükle
    _loadSponsoredChains(); // Chain sponsor data'sını yükle
    _loadCheckInCooldownStatus(); // 🕐 Check-in cooldown kontrolü
    _initializeMap();
    // İlk giriş yaptığımızda yakın çevreyi hemen yükle
    _loadInitialNearbyArea();
  }

  @override
  void dispose() {
    _isDisposed = true; // Set disposal flag first
    _isVenueDetailsOpen = false; // Reset venue details flag
    WidgetsBinding.instance.removeObserver(this); // Observer'ı temizle
    _searchFocusNode.dispose(); // Genel focus node'u temizle
    _diamondBalanceSubscription?.cancel();
    _cooldownTimer?.cancel(); // 🕐 Cooldown timer'ı temizle

    // Memory cache'leri temizle (persistent cache kalacak)
    _tileVenueCache.clear();
    _globalVenueCache.clear();
    _sponsoredChains.clear(); // Chain cache temizle
    _categoryMarkerIcons.clear(); // Category marker cache temizle
    _loadedTiles.clear();
    _loadedVenueIds.clear();
    _loadedAreas.clear();

    super.dispose();
  }

  // 🕐 CHECK-IN COOLDOWN KONTROLÜ
  Future<void> _loadCheckInCooldownStatus() async {
    try {
      _cooldownStatus = await _checkInService.getCheckInCooldownStatus();

      // Eğer cooldown aktifse, timer başlat
      if (_cooldownStatus != null &&
          !_cooldownStatus!.canCheckIn &&
          _cooldownStatus!.remainingMinutes > 0) {
        _startCooldownTimer();
      }

      if (mounted) setState(() {});
    } catch (e) {}
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _loadCheckInCooldownStatus();
      if (_cooldownStatus?.canCheckIn == true) {
        timer.cancel();

        // Cooldown bittiğinde loading state'i kaldır
        if (mounted && _isCheckingIn) {
          setState(() {
            _isCheckingIn = false;
          });
        }
      }
    });
  }

  void _refreshCooldownAfterCheckIn() {
    // Check-in yaptıktan sonra cooldown'ı yenile
    _loadCheckInCooldownStatus();
  }

  // 🏢 CHAIN SPONSOR KONTROLÜ
  bool _isChainSponsored(String venueName) {
    for (final chainData in _sponsoredChains.values) {
      final keywords = List<String>.from(chainData['keywords'] ?? []);
      final isActive = chainData['isActive'] ?? false;

      if (!isActive) continue;

      // CHAIN SPONSOR TARİH KONTROLÜ
      final startDateStr = chainData['startDate'];
      final endDateStr = chainData['endDate'];

      if (startDateStr != null || endDateStr != null) {
        final now = DateTime.now();

        // Başlangıç tarihi kontrolü
        if (startDateStr != null) {
          try {
            final startDate = DateTime.parse(startDateStr);
            if (now.isBefore(startDate)) {
              continue;
            }
          } catch (e) {
            continue;
          }
        }

        // Bitiş tarihi kontrolü
        if (endDateStr != null) {
          try {
            final endDate = DateTime.parse(endDateStr);
            if (now.isAfter(endDate)) {
              continue;
            }
          } catch (e) {
            continue;
          }
        }
      }

      // Venue adında chain keyword'ü var mı kontrol et
      for (final keyword in keywords) {
        if (venueName.toLowerCase().contains(keyword.toLowerCase())) {
          return true;
        }
      }
    }
    return false;
  }

  // 🏢 SPONSORED CHAINS YÜKLEMESİ
  Future<void> _loadSponsoredChains() async {
    try {
      final querySnapshot = await _firestore
          .collection('sponsored_chains')
          .where('isActive', isEqualTo: true)
          .get();

      _sponsoredChains.clear();
      for (final doc in querySnapshot.docs) {
        _sponsoredChains[doc.id] = doc.data();
      }
    } catch (e) {}
  }

  // 💎 SPONSORED VENUES YÜKLEMESİ (2KM RADIUS)
  Future<List<Venue>> _loadSponsoredVenues(LatLng userLocation) async {
    try {
      // Admin panel'den sponsor yapılan venues'ları çek
      final querySnapshot = await _firestore
          .collection('venues')
          .where('isSponsored', isEqualTo: true)
          .get();

      List<Venue> sponsoredVenues = [];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();

        // Venue koordinatları kontrolü
        if (data['latitude'] == null || data['longitude'] == null) {
          continue;
        }

        final venueLocation = LatLng(
          data['latitude'].toDouble(),
          data['longitude'].toDouble(),
        );

        // 2km radius kontrolü (2000m)
        final distance = Geolocator.distanceBetween(
          userLocation.latitude,
          userLocation.longitude,
          venueLocation.latitude,
          venueLocation.longitude,
        );

        if (distance <= 2000) {
          // 2km = 2000m

          // Firebase venue'yu Venue modeline dönüştür
          final venue = Venue(
            id: doc.id,
            placeId: doc.id, // Firebase doc ID as place ID
            name: data['name'] ?? 'Sponsor Venue',
            category: data['type'] ?? 'restaurant',
            location: venueLocation,
            rating: (data['rating'] ?? 4.5).toDouble(),
            vicinity: data['vicinity'] ?? data['address'] ?? '',
            isFavorite: false, // Favorites loaded separately
            isSponsored: true, // SPONSOR MARKER
            sponsorLogoUrl: data['sponsorLogoUrl'],
            sponsorBadgeText: data['sponsorBadgeText'],
            sponsorPriority: data['sponsorPriority'] ?? 1,
            totalCheckIns: data['totalCheckIns'] ?? 0,
            logoUrl: data['logoUrl'],
            openingTime: data['openingTime'] ?? '08:00',
            closingTime: data['closingTime'] ?? '22:00',
          );

          sponsoredVenues.add(venue);
        } else {}
      }

      // Sponsor priority ve mesafeye göre sırala
      sponsoredVenues.sort((a, b) {
        final priorityCompare = a.sponsorPriority.compareTo(b.sponsorPriority);
        if (priorityCompare != 0) return priorityCompare;

        final distanceA = Geolocator.distanceBetween(
          userLocation.latitude,
          userLocation.longitude,
          a.location.latitude,
          a.location.longitude,
        );
        final distanceB = Geolocator.distanceBetween(
          userLocation.latitude,
          userLocation.longitude,
          b.location.latitude,
          b.location.longitude,
        );
        return distanceA.compareTo(distanceB);
      });

      if (sponsoredVenues.isNotEmpty) {}

      return sponsoredVenues;
    } catch (e) {
      return [];
    }
  }

  // REMOVED: Animation controllers for old Like system no longer needed

  /// Venue details sheet açıkken beğeni mesajı göster (panel üzerinde)
  void _showLikeOverlayMessage({required bool isSuper}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 60,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isSuper ? AppColors.superLike : AppColors.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (isSuper ? AppColors.superLike : AppColors.primary)
                      .withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 3,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuper ? Icons.star : Icons.favorite,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isSuper
                        ? '⭐ Süper Chat Gönderildi!'
                        : '� Chat İsteği Gönderildi!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // 2.5 saniye sonra overlay'i kaldır
    Timer(const Duration(milliseconds: 2500), () {
      overlayEntry.remove();
    });
  }

  /// Kullanıcıya already liked/super liked mesajı göster
  void _showAlreadyLikedMessage(
      {required String message, bool isSuper = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 60,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isSuper ? Colors.amber : Colors.orange,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color:
                      (isSuper ? Colors.amber : Colors.orange).withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 3,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuper ? Icons.star : Icons.info_outline,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // 2.5 saniye sonra overlay'i kaldır
    Timer(const Duration(milliseconds: 2500), () {
      overlayEntry.remove();
    });
  }

  // Safe setState helper to prevent calls after disposal
  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  // Lifecycle handler - navigation event'lerini dinle
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bu method page'e her geri döndüğünde çalışır
    if (!_isInitialLoad) {
      _forceRefreshCurrentUserMayorships();
    }
    _isInitialLoad = false;
  }

  // Current user'ın muhtarlık verilerini zorla yenile
  Future<void> _forceRefreshCurrentUserMayorships() async {
    if (_isDisposed) return;

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Daily mayors cache'ini temizle ve yeniden yükle
      _dailyMayors.clear();
      _dailyMayors = await _checkInService.loadDailyMayors();

      // Kullanıcının muhtar olduğu venue'ları fresh data ile kontrol et
      final userMayorVenues = _dailyMayors.entries
          .where((entry) => entry.value['userId'] == currentUserId)
          .map((entry) => entry.key)
          .toList();

      if (userMayorVenues.isNotEmpty) {
        // Her venue için fresh data çek
        for (final venueId in userMayorVenues) {
          await Future.delayed(
              const Duration(milliseconds: 200)); // Rate limiting
          final freshMayorData =
              await _checkInService.getDailyMayorForVenue(venueId);
          if (freshMayorData != null) {
            _dailyMayors[venueId] = freshMayorData;
          }
        }

        // UI'ı güncelle
        _safeSetState(() {
          _updateMapMarkers();
        });
      }
    } catch (e) {}
  }

  void _startDiamondBalanceListener() {
    // Önce mevcut subscription'ı iptal et
    _diamondBalanceSubscription?.cancel();

    _diamondBalanceSubscription =
        _muhtarService.listenToUserDiamondBalance().listen(
      (balance) {
        _safeSetState(() {
          _userDiamondBalance = balance;
        });
      },
      onError: (error) {},
    );
  }

  /// İlk elmas bakiyesini yükle (stream başlamadan önce)
  Future<void> _loadInitialDiamondBalance() async {
    try {
      final balance = await _muhtarService.getUserDiamondBalance();

      _safeSetState(() {
        _userDiamondBalance = balance;
      });
    } catch (e) {
      // Hata durumunda 0 olarak bırak, stream geldiğinde düzelecek
    }
  }

  /// Kullanıcının elmas bakiyesini yükle
  Future<void> _loadUserDiamondBalance() async {
    try {
      final balance = await MuhtarFirebaseService().getUserDiamondBalance();

      _safeSetState(() {
        _userDiamondBalance = balance;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Elmas bakiyesi yüklenemedi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// 💕 Kullanıcının like verilerini yükle
  // REMOVED: Old Like system - now using Chat Request system
  Future<void> _loadUserLikeData() async {
    // No longer needed - Chat Request system handles this differently
  }

  // 🎨 ULTRA-FAST MARKER ICON LOADER
  // 🚀 ULTRA-FAST BACKGROUND MARKER ICON LOADER
  Future<void> _loadCustomMarkerIcons() async {
    try {
      // 🔄 Cache'i temizle - Her açılışta marker'lar yeniden oluşturulsun
      _categoryMarkerIcons.clear();

      // Star marker (Check-in yapılan mekanlar için check mark)
      _starMarkerIcon = await _createStarMarkerIcon(
        color: AppColors.primary,
        borderColor: Colors.white,
        borderWidth: 3.0,
      );

      // Crown marker (Muhtar olduğu mekanlar için)
      _crownMarkerIcon = await _createCrownMarkerIcon(
        color: AppColors.primary,
        borderColor: Colors.white,
        borderWidth: 3.0,
      );

      // � SPONSOR MARKER (Sponsorlu mekanlar için diamond)
      _sponsorMarkerIcon = await _createSponsorBubbleMarkerIcon(
        venueName: "Sponsor",
        logoUrl: null,
      );

      // �🔄 BACKGROUND ISOLATE PROCESSING - Create icons in parallel background threads
    } catch (e) {
      _starMarkerIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      _crownMarkerIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
      _sponsorMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueOrange); // 💎 SPONSOR FALLBACK
    }
  }

  // ✅ CHECK MARK MARKER (Check-in yapılan mekanlar için)
  Future<BitmapDescriptor> _createStarMarkerIcon({
    required Color color,
    required Color borderColor,
    required double borderWidth,
  }) async {
    try {
      const double size = 140.0; // Crown ile aynı boyut

      // Yeni Canvas oluştur
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Pin base çiz (tema rengi)
      final pinPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final pinPath = Path();
      // Pin başı - daire
      pinPath.addOval(Rect.fromCenter(
        center: const Offset(size * 0.5, size * 0.6),
        width: size * 0.6,
        height: size * 0.6,
      ));
      // Pin ucu - üçgen
      pinPath.moveTo(size * 0.35, size * 0.85);
      pinPath.lineTo(size * 0.5, size * 0.95);
      pinPath.lineTo(size * 0.65, size * 0.85);
      pinPath.close();

      canvas.drawPath(pinPath, pinPaint);

      // Pin beyaz çerçeve (kalın border)
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawPath(pinPath, borderPaint);

      // Check mark (✓) çiz - pin'in üst kısmına
      final checkPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // Check mark koordinatları (pin'in ortasında)
      const centerX = size * 0.5;
      const centerY = size * 0.55;
      const checkSize = size * 0.2;

      final checkPath = Path();
      // Sol alt -> orta
      checkPath.moveTo(centerX - checkSize * 0.6, centerY);
      checkPath.lineTo(centerX - checkSize * 0.2, centerY + checkSize * 0.4);
      // Orta -> sağ üst
      checkPath.lineTo(centerX + checkSize * 0.6, centerY - checkSize * 0.4);

      canvas.drawPath(checkPath, checkPaint);

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final finalBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      return BitmapDescriptor.fromBytes(finalBytes!.buffer.asUint8List());
    } catch (e) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }
  }

  // 👑 PNG ICON + PIN MARKER (Muhtar olduğu mekanlar için)
  Future<BitmapDescriptor> _createCrownMarkerIcon({
    required Color color,
    required Color borderColor,
    required double borderWidth,
  }) async {
    try {
      const double size = 140.0; // Boyutu büyüttük

      // PNG icon'u yükle
      final ByteData data =
          await rootBundle.load('assets/icons/crown_icon_64.png');
      final Uint8List bytes = data.buffer.asUint8List();

      // Codec ile decode et
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image originalImage = frameInfo.image;

      // Yeni Canvas oluştur
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Pin base çiz (pembe renkte)
      final pinPaint = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.fill;

      final pinPath = Path();
      // Pin başı - daire
      pinPath.addOval(Rect.fromCenter(
        center: const Offset(size * 0.5, size * 0.6),
        width: size * 0.6,
        height: size * 0.6,
      ));
      // Pin ucu - üçgen
      pinPath.moveTo(size * 0.35, size * 0.85);
      pinPath.lineTo(size * 0.5, size * 0.95);
      pinPath.lineTo(size * 0.65, size * 0.85);
      pinPath.close();

      canvas.drawPath(pinPath, pinPaint);

      // Pin beyaz çerçeve (kalın border)
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0; // Kalınlığı artırdık
      canvas.drawPath(pinPath, borderPaint);

      // PNG icon'u pembe renge çevir ve pin'in üstüne çiz
      final pinkFilter = Paint()
        ..colorFilter = const ColorFilter.mode(
          AppColors.primary,
          BlendMode.srcIn,
        );

      // Icon'u pin'in üst kısmına yerleştir - daha büyük boyutta
      const iconSize = size * 0.8;
      final iconRect = Rect.fromCenter(
        center: const Offset(size * 0.5, size * 0.35),
        width: iconSize,
        height: iconSize,
      );

      canvas.drawImageRect(
        originalImage,
        Rect.fromLTWH(0, 0, originalImage.width.toDouble(),
            originalImage.height.toDouble()),
        iconRect,
        pinkFilter,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final finalBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      return BitmapDescriptor.fromBytes(finalBytes!.buffer.asUint8List());
    } catch (e) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
    }
  }

  // 💎 SPONSOR BUBBLE MARKER (Sponsorlu mekanlar için konuşma baloncuğu + logo + isim)
  Future<BitmapDescriptor> _createSponsorBubbleMarkerIcon({
    required String venueName,
    required String? logoUrl,
  }) async {
    try {
      // İsmi 18 karaktere sınırla
      String displayName = venueName.length > 18
          ? '${venueName.substring(0, 15)}...'
          : venueName;

      const double height = 176.0; // 1.1 kat (160 * 1.1)
      const double width = 440.0; // 1.1 kat (400 * 1.1)
      const double bubbleHeight = 110.0; // 1.1 kat (100 * 1.1)
      const double tailHeight = 33.0; // 1.1 kat (30 * 1.1)
      const double cornerRadius = 27.5; // 1.1 kat (25 * 1.1)

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // � TEMA RENGİ GRADYAN BALONCUK
      final gradientPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary, // Tema ana rengi
            AppColors.primaryDark, // Tema koyu rengi
          ],
        ).createShader(const Rect.fromLTWH(0, 0, width, bubbleHeight));

      // Konuşma baloncuğu path'i oluştur
      final bubblePath = Path();

      // Ana balon (rounded rectangle)
      final bubbleRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(
            22, 22, width - 44, bubbleHeight - 44), // 1.1 kat (20 -> 22)
        const Radius.circular(cornerRadius),
      );
      bubblePath.addRRect(bubbleRect);

      // Balon kuyruğu (alt ortada küçük üçgen)
      const tailCenterX = width / 2;
      const tailStartY = bubbleHeight - 22;
      bubblePath.moveTo(tailCenterX - 17.6, tailStartY); // 1.1 kat (16 -> 17.6)
      bubblePath.lineTo(tailCenterX, tailStartY + tailHeight);
      bubblePath.lineTo(tailCenterX + 17.6, tailStartY); // 1.1 kat (16 -> 17.6)
      bubblePath.close();

      // Baloncuğu çiz
      canvas.drawPath(bubblePath, gradientPaint);

      // Beyaz border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4; // 1.1 kat (4 -> 4.4)
      canvas.drawPath(bubblePath, borderPaint);

      // 🎨 İÇERİK: LOGO + İSİM

      const double logoSize = 55.0; // 1.1 kat (50 * 1.1)
      const double logoX = 44.0; // 1.1 kat (40 * 1.1)
      const logoY = bubbleHeight / 2 - 5; // Yazı ile aynı hizada (yukarıda)

      // LOGO LOADING ve DRAW
      ui.Image? logoImage;
      if (logoUrl != null && logoUrl.isNotEmpty) {
        try {
          logoImage = await _loadNetworkImage(logoUrl);
        } catch (e) {}
      }

      if (logoImage != null) {
        // Canvas state'i kaydet
        canvas.save();

        // Gerçek logo'yu çiz (yuvarlak kırpılmış)
        final logoRect = Rect.fromCircle(
          center: const Offset(logoX, logoY),
          radius: logoSize / 2,
        );

        // Yuvarlak clipping için path
        final clipPath = Path()..addOval(logoRect);
        canvas.clipPath(clipPath);

        // Logo'yu çiz (aspect ratio korunarak)
        final srcRect = Rect.fromLTWH(
            0, 0, logoImage.width.toDouble(), logoImage.height.toDouble());
        canvas.drawImageRect(logoImage, srcRect, logoRect, Paint());

        // Canvas state'i geri yükle
        canvas.restore();

        // Logo border
        final logoBorderPaint = Paint()
          ..color = AppColors.primaryLight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.3; // 1.1 kat (3 -> 3.3)
        canvas.drawCircle(
          const Offset(logoX, logoY),
          logoSize / 2,
          logoBorderPaint,
        );
      }
      // Logo yoksa hiçbir şey çizmiyoruz (boş kalıyor)

      // Mekan ismi - Logo durumuna göre konumlandırma
      const centerY =
          bubbleHeight / 2 - 5; // Bubble'ın ortasından biraz yukarı (11 -> -5)

      double nameStartX;
      double nameMaxWidth;

      if (logoImage != null) {
        // Logo varsa: Logo'nun yanından başla
        nameStartX = logoX + logoSize / 2 + 13; // Logo'nun yanından başla
        nameMaxWidth = width - logoSize - 66; // Logo için yer ayır
      } else {
        // Logo yoksa: Tam ortalanmış
        nameMaxWidth = width - 66; // Yan kenar boşlukları

        // Önce yazı boyutunu hesapla ortalamak için
        final tempTextPainter = TextPainter(
          text: TextSpan(
            text: displayName,
            style: const TextStyle(
              fontSize: 35.2, // 1.1 kat (32 * 1.1)
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        );
        tempTextPainter.layout(maxWidth: nameMaxWidth);

        // Yazıyı bubble'da ortala
        nameStartX = (width - tempTextPainter.width) / 2;
      }

      final nameTextPainter = TextPainter(
        text: TextSpan(
          text: displayName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 35.2, // 1.1 kat (32 * 1.1)
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black26,
                offset: Offset(2.2, 2.2), // 1.1 kat
                blurRadius: 4.4, // 1.1 kat
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      nameTextPainter.layout(maxWidth: nameMaxWidth);
      nameTextPainter.paint(
        canvas,
        Offset(
          nameStartX,
          centerY - nameTextPainter.height / 2, // Bubble ortasında
        ),
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final finalBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      return BitmapDescriptor.fromBytes(finalBytes!.buffer.asUint8List());
    } catch (e) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }
  }

  // 🖼️ NETWORK IMAGE LOADER (Logo'ları yüklemek için)
  Future<ui.Image> _loadNetworkImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final codec = await ui.instantiateImageCodec(bytes,
            targetHeight: 220, targetWidth: 220); // 1.1 kat (200 -> 220)
        final frame = await codec.getNextFrame();
        return frame.image;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 🎨 KATEGORİ BAZLI MARKER ICON OLUŞTURUCU
  Future<BitmapDescriptor> _createCategoryMarkerIcon({
    required String category,
    required IconData icon,
    required Color color,
  }) async {
    try {
      const double size = 140.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Pin base çiz
      final pinPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final pinPath = Path();
      // Pin başı - daire (diğer marker'larla aynı boyut ve pozisyon)
      pinPath.addOval(Rect.fromCenter(
        center: const Offset(size * 0.5, size * 0.6),
        width: size * 0.6,
        height: size * 0.6,
      ));
      // Pin ucu - üçgen
      pinPath.moveTo(size * 0.35, size * 0.85);
      pinPath.lineTo(size * 0.5, size * 0.95);
      pinPath.lineTo(size * 0.65, size * 0.85);
      pinPath.close();

      canvas.drawPath(pinPath, pinPaint);

      // Pin beyaz çerçeve
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawPath(pinPath, borderPaint);

      // Icon çiz (Material Icon) - Star marker ile aynı pozisyon
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );
      textPainter.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 24.0, // Daha da küçültüldü - pin içinde daha orantılı
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
          shadows: const [
            Shadow(
              color: Colors.black26,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        ),
      );
      textPainter.layout();

      // Icon'u tam ortaya yerleştir
      final iconX = (size * 0.5) - (textPainter.width / 2);
      final iconY = (size * 0.6) - (textPainter.height / 2);

      textPainter.paint(canvas, Offset(iconX, iconY));

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final finalBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      return BitmapDescriptor.fromBytes(finalBytes!.buffer.asUint8List());
    } catch (e) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
  }

  // 🎨 KATEGORİ İÇİN ICON VE RENK BELİRLE
  Future<BitmapDescriptor> _getMarkerIconForCategory(String category) async {
    // Cache'de varsa onu kullan
    if (_categoryMarkerIcons.containsKey(category)) {
      return _categoryMarkerIcons[category]!;
    }

    // Kategori bazlı icon ve renk tanımlamaları
    IconData icon;
    Color color;

    switch (category.toLowerCase()) {
      case 'cafe':
      case 'kahve':
        icon = Icons.local_cafe;
        color = const Color(0xFF6F4E37); // Kahverengi
        break;
      case 'restaurant':
      case 'restoran':
        icon = Icons.restaurant;
        color = const Color(0xFFFF6B35); // Turuncu
        break;
      case 'bar':
        icon = Icons.local_bar;
        color = const Color(0xFF9C27B0); // Mor
        break;
      case 'night_club':
      case 'gece kulübü':
        icon = Icons.nightlife;
        color = const Color(0xFFE91E63); // Pembe-kırmızı
        break;
      case 'gym':
      case 'spor salonu':
        icon = Icons.fitness_center;
        color = const Color(0xFF2196F3); // Mavi
        break;
      case 'shopping_mall':
      case 'alışveriş merkezi':
        icon = Icons.shopping_bag;
        color = const Color(0xFF4CAF50); // Yeşil
        break;
      case 'art_gallery':
      case 'sanat galerisi':
        icon = Icons.palette;
        color = const Color(0xFF9C27B0); // Mor
        break;
      case 'museum':
      case 'müze':
        icon = Icons.museum;
        color = const Color(0xFF795548); // Kahverengi
        break;
      case 'theater':
      case 'tiyatro':
      case 'movie_theater':
        icon = Icons.theaters;
        color = const Color(0xFFE91E63); // Pembe
        break;
      case 'park':
        icon = Icons.park;
        color = const Color(0xFF4CAF50); // Yeşil
        break;
      case 'beach':
      case 'plaj':
        icon = Icons.beach_access;
        color = const Color(0xFF00BCD4); // Cyan
        break;
      case 'spa':
        icon = Icons.spa;
        color = const Color(0xFF9C27B0); // Mor
        break;
      case 'library':
      case 'kütüphane':
        icon = Icons.local_library;
        color = const Color(0xFF607D8B); // Gri-mavi
        break;
      case 'bowling_alley':
      case 'bowling salonu':
        icon = Icons.sports_baseball;
        color = const Color(0xFFFF9800); // Turuncu
        break;
      case 'amusement_park':
      case 'lunapark':
        icon = Icons.attractions;
        color = const Color(0xFFFF5722); // Kırmızı-turuncu
        break;
      default:
        icon = Icons.place;
        color = const Color(0xFFF44336); // Kırmızı (varsayılan)
    }

    // Marker oluştur ve cache'e ekle
    final markerIcon = await _createCategoryMarkerIcon(
      category: category,
      icon: icon,
      color: color,
    );

    _categoryMarkerIcons[category] = markerIcon;
    return markerIcon;
  }

  // 🎨 CUSTOM MARKER ICON OLUŞTURUCU (ESKİ - KULLANILMIYOR)
  Future<BitmapDescriptor> _createCustomMarkerIcon({
    required Color color,
    required Color borderColor,
    required double borderWidth,
    double scale = 1.0, // Boyut çarpanı
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const baseSize = 240.0; // Temel pin boyutu
    final size = baseSize * scale; // Ölçeklenmiş boyut

    // Pin ana gövdesi (üst kısım - daire)
    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Beyaz çerçeve
    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth * scale;

    // Shadow (gölge efekti)
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 2.0 * scale);

    final center = Offset(size / 2, size / 3); // Pin'in üst kısmının merkezi
    final radius = size / 6; // Pin başının yarıçapı
    final pinTipY = size * 0.85; // Pin ucunun Y konumu

    // Pin şekli çiz (daire + üçgen)
    final Path pinPath = Path();

    // Üst daire kısmı
    pinPath.addOval(Rect.fromCircle(center: center, radius: radius));

    // Alt üçgen kısmı (pin ucu)
    pinPath.moveTo(center.dx - radius * 0.5, center.dy + radius * 0.8);
    pinPath.lineTo(center.dx, pinTipY);
    pinPath.lineTo(center.dx + radius * 0.5, center.dy + radius * 0.8);
    pinPath.close();

    // Gölge çiz
    final Path shadowPath = pinPath.shift(Offset(1.5 * scale, 1.5 * scale));
    canvas.drawPath(shadowPath, shadowPaint);

    // Ana pin'i çiz
    canvas.drawPath(pinPath, fillPaint);

    // Çerçeve çiz
    canvas.drawPath(pinPath, borderPaint);

    // Merkeze küçük nokta (location indicator)
    final Paint centerDot = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.4, centerDot);

    // Picture'ı image'e çevir
    final ui.Picture picture = pictureRecorder.endRecording();
    final ui.Image image = await picture.toImage(size.toInt(), size.toInt());
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(uint8List);
  }

  Future<void> _initializeMap() async {
    try {
      _safeSetState(() => _isLoading = true);
      await _checkLocationPermission();
      await _getCurrentLocation();
      await _loadUserData(); // User data yükle (diamond balance da burada yüklenecek)
      // Load venues after getting location - but only if we don't have enough markers
      if (_currentPosition != null && _markers.length < _maxMarkersOnScreen) {
        await _loadNearbyVenues();
      } else if (_markers.length >= _maxMarkersOnScreen) {}
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // ⚡ CACHE CHECK - Skip if data is fresh (unless forced)
      if (!forceRefresh &&
          _lastDataRefresh != null &&
          DateTime.now().difference(_lastDataRefresh!).inMinutes <
              _cacheValidityMinutes) {
        return;
      }

      // User premium status al
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;

        // 🔄 State güncellemesi
        _safeSetState(() {
          _isPremium = userData['isPremium'] ?? false;
        });

        // 🚀 PARALLEL DATA LOADING - Load check-ins, mayors and favorites simultaneously
        final futures = <Future>[
          _refreshUserCheckedInVenues(),
          _checkInService.loadDailyMayors(),
          _loadUserFavoriteVenues(),
        ];

        final results = await Future.wait(futures);
        _dailyMayors = results[1] as Map<String, Map<String, dynamic>>;
        _lastDataRefresh = DateTime.now();
      } else {}
    } catch (e) {}
  }

  // Check-in venue'leri yeniden yükle (sadece bugünkü check-in'ler)
  Future<void> _refreshUserCheckedInVenues() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Bugünün başlangıcını hesapla
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);

        final checkInsSnapshot = await _firestore
            .collection('check_ins')
            .where('userId', isEqualTo: user.uid)
            .where('checkInTime',
                isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .get();

        _userCheckedInVenues = checkInsSnapshot.docs
            .map((doc) => doc.data()['venueId'] as String)
            .toSet();
      }
    } catch (e) {}
  }

  // Load user's favorite venues
  Future<void> _loadUserFavoriteVenues() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final favoriteVenues =
            List<String>.from(userData['favoriteVenues'] ?? []);
        _userFavoriteVenues = favoriteVenues.toSet();
      }
    } catch (e) {}
  }

  //  İki koordinat arası mesafe hesapla (km)
  double _calculateDistance(LatLng coords1, LatLng coords2) {
    const double earthRadiusKm = 6371.0;

    final double lat1Rad = coords1.latitude * (math.pi / 180);
    final double lat2Rad = coords2.latitude * (math.pi / 180);
    final double deltaLatRad =
        (coords2.latitude - coords1.latitude) * (math.pi / 180);
    final double deltaLngRad =
        (coords2.longitude - coords1.longitude) * (math.pi / 180);

    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLngRad / 2) *
            math.sin(deltaLngRad / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  // Update venue favorite status based on user's favorites
  void _updateVenueFavoriteStatus(List<Venue> venues) {
    for (var venue in venues) {
      venue.isFavorite = _userFavoriteVenues.contains(venue.id);
    }
  }

  Future<void> _checkLocationPermission() async {
    try {
      // iOS ve Android için farklı izin sistemleri
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS için Geolocator'ın kendi izin sistemi
        LocationPermission permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            _isLocationPermissionGranted = false;
            _showPermissionDialog();
            return;
          }
        }

        if (permission == LocationPermission.deniedForever) {
          _isLocationPermissionGranted = false;
          _showPermissionDialog();
          return;
        }

        _isLocationPermissionGranted = true;
      } else {
        // Android için permission_handler
        final permission = await Permission.location.request();
        _isLocationPermissionGranted = permission.isGranted;

        if (!_isLocationPermissionGranted) {
          _showPermissionDialog();
        }
      }
    } catch (e) {
      _isLocationPermissionGranted = false;
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konum İzni Gerekli'),
        content: Text(
          defaultTargetPlatform == TargetPlatform.iOS
              ? 'Yakınındaki mekanları gösterebilmek için konum izni vermelisiniz. '
                  'Ayarlar > Gizlilik ve Güvenlik > Konum Hizmetleri\'nden uygulamaya izin verebilirsiniz.'
              : 'Uygulamanın düzgün çalışması için konum iznine ihtiyaç vardır. '
                  'Lütfen ayarlardan konum iznini açın.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Ayarlara Git'),
          ),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    if (!_isLocationPermissionGranted) return;

    try {
      // Platform-specific timeouts
      final timeoutDuration = defaultTargetPlatform == TargetPlatform.iOS
          ? const Duration(seconds: 35)
          : const Duration(seconds: 40);

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeoutDuration,
      );

      _safeSetState(() {
        _currentPosition = position;
      });

      // Move camera to user location
      if (_mapController != null) {
        await _moveCameraToLocation(
          LatLng(position.latitude, position.longitude),
        );
      }

      // İlk konum alındıktan sonra yakın çevreyi yükle - but only if we don't have enough markers
      if (_markers.length < _maxMarkersOnScreen) {
        await _loadNearbyVenues();
      } else {}
    } catch (e) {}
  }

  // İlk giriş yaptığımızda yakın çevreyi hemen yükle
  Future<void> _loadInitialNearbyArea() async {
    await _getCurrentLocation();
  }

  Future<void> _moveCameraToLocation(LatLng target) async {
    if (_mapController != null) {
      // Current zoom'u koruyarak move et, minimum 16 zoom kullan
      final targetZoom = math.max(_currentZoom, 16.0);
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: targetZoom),
        ),
      );
    }
  }

  Future<void> _loadNearbyVenues() async {
    if (_currentPosition == null) return;

    // 🚫 MARKER LIMIT: Stop all venue loading if we already have maximum markers
    if (_markers.length >= _maxMarkersOnScreen) {
      return;
    }

    try {
      _safeSetState(() => _isLoading = true);

      final userLocation =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

      // 💎 1️⃣ ÖNCE SPONSORED VENUES'LARI YÜKLELELİM (2KM RADIUS)
      List<Venue> sponsoredVenues = [];
      try {
        sponsoredVenues = await _loadSponsoredVenues(userLocation);
      } catch (e) {}

      final radius =
          _getRadiusForZoom(_currentZoom); // Dynamic radius based on zoom

      // 🚀 TEK API ÇAĞRISI ile TÜM KATEGORİLERİ getir - EN YAKIN ÖNCE!
      final allVenues = await _optimizedVenueService.fetchVenuesOptimized(
        userLocation,
        radius: radius,
        maxResults:
            20, // Google API max per request (hedef 60 venue için çoklu tile)
        sortByDistance: true, // EN YAKIN ÖNCE - MESAFEYE GÖRE SIRALA!
        priorityByDistance:
            true, // PURE distance sorting - kategoriden bağımsız
      );

      // Check if disposed after async operation
      if (_isDisposed) return;

      // � 2️⃣ SPONSORED VENUES'LARI NORMAL VENUES İLE BİRLEŞTİR
      final combinedVenues = <Venue>[];

      // Önce sponsored venues'ları ekle (priority için)
      combinedVenues.addAll(sponsoredVenues);

      // Sonra normal venues'ları ekle (duplicate check ile)
      for (var venue in allVenues) {
        // Aynı venue zaten sponsor olarak eklenmişse tekrar ekleme
        bool isDuplicate = sponsoredVenues.any((sv) =>
                sv.name.toLowerCase().trim() ==
                    venue.name.toLowerCase().trim() &&
                _calculateDistance(sv.location, venue.location) <
                    50 // 50m içinde aynı venue
            );

        if (!isDuplicate) {
          combinedVenues.add(venue);
        } else {}
      }

      // �💖 Update favorite status for venues
      _updateVenueFavoriteStatus(combinedVenues);

      // Firebase'den venue bilgilerini al ve check-in'leri yükle
      await _loadVenueDataFromFirebase(combinedVenues);

      // 🎯 PRIORITY SORTING: Sponsor → Check-in yapılan → En yakınlar
      final prioritySortedVenues =
          _sortVenuesByPriority(combinedVenues, userLocation);

      // Yüklenen venue ID'lerini kaydet
      for (var venue in prioritySortedVenues) {
        _loadedVenueIds.add(venue.id);
      }

      // İlk bölgeyi yüklenmiş olarak işaretle
      final areaKey = _getAreaKey(userLocation, radius);
      _loadedAreas.add(areaKey);
      _lastLoadedCenter = userLocation;

      _safeSetState(() {
        _venues = prioritySortedVenues;
        _isLoading = false; // Stop loading early - show progress via markers
        _updateMapMarkers(); // Start progressive loading
      });
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  // 🎯 PRIORITY SORTING: Check-in yapılan mekanları en üste, sonra en yakınları
  List<Venue> _sortVenuesByPriority(List<Venue> venues, LatLng userLocation) {
    final sponsorVenues = <Venue>[];
    final checkedInVenues = <Venue>[];
    final otherVenues = <Venue>[];

    // 1️⃣ Sponsor, Check-in ve diğer mekanları ayır
    for (var venue in venues) {
      if (venue.isSponsored) {
        sponsorVenues.add(venue);
      } else if (_userCheckedInVenues.contains(venue.id)) {
        checkedInVenues.add(venue);
      } else {
        otherVenues.add(venue);
      }
    }

    // 2️⃣ Sponsor venues'ları priority'ye göre sırala (yüksek priority önce), sonra mesafe
    sponsorVenues.sort((a, b) {
      // Önce sponsor priority'ye göre (yüksek önce)
      final priorityComparison = b.sponsorPriority.compareTo(a.sponsorPriority);
      if (priorityComparison != 0) return priorityComparison;

      // Priority aynıysa mesafeye göre (yakın önce)
      final distanceA = _calculateDistance(userLocation, a.location);
      final distanceB = _calculateDistance(userLocation, b.location);
      return distanceA.compareTo(distanceB);
    });

    // 3️⃣ Check-in venues'ları mesafeye göre sırala (en yakın önce)
    checkedInVenues.sort((a, b) {
      final distanceA = _calculateDistance(userLocation, a.location);
      final distanceB = _calculateDistance(userLocation, b.location);
      return distanceA.compareTo(distanceB);
    });

    // 4️⃣ Other venues'ları mesafeye göre sırala (en yakın önce)
    otherVenues.sort((a, b) {
      final distanceA = _calculateDistance(userLocation, a.location);
      final distanceB = _calculateDistance(userLocation, b.location);
      return distanceA.compareTo(distanceB);
    });

    // 5️⃣ Birleştir: Sponsor → Check-in → Others
    final sortedVenues = [...sponsorVenues, ...checkedInVenues, ...otherVenues];

    return sortedVenues;
  }

  // Zoom seviyesine göre radius hesapla
  double _getRadiusForZoom(double zoom) {
    if (zoom >= 18.0) return 200.0; // 200m - Maksimum radius
    if (zoom >= 17.0) return 200.0; // 200m
    if (zoom >= 16.0) return 200.0; // 200m
    if (zoom >= 15.0) return 200.0; // 200m
    if (zoom >= 14.0) return 200.0; // 200m
    if (zoom >= 13.0) return 200.0; // 200m
    if (zoom >= 12.0) return 200.0; // 200m
    return 200.0; // 200m - Tüm zoom seviyelerinde
  }

  // Bölge anahtarı oluştur (grid sistemi)
  String _getAreaKey(LatLng center, double radius) {
    // 100m grid sistemi
    final latGrid = (center.latitude * 1000).round();
    final lngGrid = (center.longitude * 1000).round();
    return '${latGrid}_${lngGrid}_${radius.toInt()}';
  }

  // Kamera hareket ettiğinde yeni mekanları yükle
  void _onCameraMove(CameraPosition position) {
    final oldZoom = _currentZoom;
    _currentZoom = position.zoom;

    // Zoom seviyesi kategori değiştirirse tile sistemini sıfırla
    final oldZoomCategory = _getZoomCategory(oldZoom);
    final newZoomCategory = _getZoomCategory(_currentZoom);

    if (oldZoomCategory != newZoomCategory) {
      _loadedTiles.clear();
      _tileVenueCache.clear();
      _lastZoom = _currentZoom;
    }

    // Optimize: Update visible bounds for tile-based loading
    if (_mapController != null) {
      _mapController!.getVisibleRegion().then((bounds) {
        _visibleBounds = bounds;
      });
    }
  }

  // Zoom categories for better tile management
  String _getZoomCategory(double zoom) {
    if (zoom >= 16) return 'high'; // Detailed view
    if (zoom >= 14) return 'medium'; // Normal view
    if (zoom >= 12) return 'low'; // Area view
    return 'very_low'; // City view
  }

  Future<void> _onCameraIdle() async {
    // Use optimized viewport-based loading instead of area-based
    await _loadVenuesInViewport();
  }

  // =================== OPTIMIZED VENUE LOADING ===================
  Future<void> _loadVenuesInViewport() async {
    if (_isDisposed || _mapController == null || _visibleBounds == null) return;

    // 🚫 MARKER LIMIT: Stop all venue loading if we already have maximum markers
    if (_markers.length >= _maxMarkersOnScreen) {
      return;
    }

    // Don't show too many markers at very low zoom levels, but don't clear all
    if (_currentZoom < 10.0) {
      // At very low zoom, show only favorites and major venues
      _showOnlyMajorVenues();
      return;
    }

    final requestId = ++_loadingRequestId;

    try {
      final tiles = _getTilesInBounds(_visibleBounds!);
      final newTiles =
          tiles.where((tile) => !_loadedTiles.contains(tile)).toList();

      if (newTiles.isEmpty) {
        return; // All tiles already loaded
      }

      for (String tileKey in newTiles) {
        if (_isDisposed || requestId != _loadingRequestId)
          break; // Cancel if disposed or newer request started

        // 🚫 MARKER LIMIT: Stop tile loading if we already have enough markers
        if (_markers.length >= _maxMarkersOnScreen) {
          break;
        }

        try {
          final tileBounds = _getBoundsFromTileKey(tileKey);
          await _loadVenuesForTile(tileKey, tileBounds);
          _loadedTiles.add(tileKey);
        } catch (tileError) {
          continue;
        }
      }

      // Clean up markers outside viewport (keep favorites)
      _cleanupMarkersOutsideViewport();
    } catch (e) {}
  }

  List<String> _getTilesInBounds(LatLngBounds bounds) {
    // 60 venue hedefi için optimize edilmiş tile boyutları (200m radius içinde 3-4 tile)
    final tileSize = _currentZoom >= 16
        ? 0.004
        : // Orta boyut tile'lar - 3-4 tile ile 60 venue
        _currentZoom >= 14
            ? 0.006
            : // Büyük tile'lar
            _currentZoom >= 12
                ? 0.008
                : 0.012; // Çok büyük tile'lar

    List<String> tiles = [];

    // 🚫 200M FILTER: Only generate tiles within 200m radius from user location
    if (_currentPosition != null) {
      final userLocation =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

      double lat = bounds.southwest.latitude;
      while (lat < bounds.northeast.latitude) {
        double lng = bounds.southwest.longitude;
        while (lng < bounds.northeast.longitude) {
          final tileCenter = LatLng(lat + tileSize / 2, lng + tileSize / 2);
          final distanceToTile = _calculateDistance(userLocation, tileCenter);

          // Only create tiles within 200m radius
          if (distanceToTile <= _maxDistance) {
            final tileKey =
                '${(lat / tileSize).floor()}_${(lng / tileSize).floor()}';
            tiles.add(tileKey);
          }

          lng += tileSize;
        }
        lat += tileSize;
      }
    } else {
      // Fallback: Generate all tiles if no user location (should not happen normally)
      double lat = bounds.southwest.latitude;
      while (lat < bounds.northeast.latitude) {
        double lng = bounds.southwest.longitude;
        while (lng < bounds.northeast.longitude) {
          final tileKey =
              '${(lat / tileSize).floor()}_${(lng / tileSize).floor()}';
          tiles.add(tileKey);
          lng += tileSize;
        }
        lat += tileSize;
      }
    }

    return tiles;
  }

  LatLngBounds _getBoundsFromTileKey(String tileKey) {
    final parts = tileKey.split('_');
    final latTile = int.parse(parts[0]);
    final lngTile = int.parse(parts[1]);

    final tileSize = _currentZoom >= 16
        ? 0.01
        : _currentZoom >= 14
            ? 0.02
            : _currentZoom >= 12
                ? 0.04
                : 0.08;

    return LatLngBounds(
      southwest: LatLng(latTile * tileSize, lngTile * tileSize),
      northeast: LatLng((latTile + 1) * tileSize, (lngTile + 1) * tileSize),
    );
  }

  Future<void> _loadVenuesForTile(
      String tileKey, LatLngBounds tileBounds) async {
    if (_isDisposed) return; // Early return if disposed

    // 🚫 MARKER LIMIT CHECK: Stop all tile loading if we already have maximum markers
    if (_markers.length >= _maxMarkersOnScreen) {
      return;
    }

    // Check cache first
    if (_tileVenueCache.containsKey(tileKey)) {
      final cachedVenues = _tileVenueCache[tileKey]!;
      for (var venue in cachedVenues) {
        if (_markers.length < _maxMarkersOnScreen) {
          _addOptimizedMarkerToMap(venue);
        }
      }
      return;
    }

    final center = LatLng(
      (tileBounds.southwest.latitude + tileBounds.northeast.latitude) / 2,
      (tileBounds.southwest.longitude + tileBounds.northeast.longitude) / 2,
    );

    // Distance check - don't load tiles too far from user (5km MAX)
    if (_currentPosition != null) {
      final tileDistance = _calculateDistance(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        center,
      );

      // 🚫 200M SINIRLAMA: 200m'den uzak tile'ları yükleme - HİÇ API İSTEĞİ ATMA
      if (tileDistance > _maxDistance) {
        return; // 200m'den uzak - tile yükleme iptal
      }
    }

    // 200m radius sabit - yakından uzağa doğru sıralama için
    double radius = _maxDistance; // 200 metre sabit
    int maxResults =
        20; // Google Places API limiti max 20 - birden fazla call ile 60'a ulaşacağız

    try {
      // 🚀 TEK API ÇAĞRISI ile 200m içindeki tüm belirlenen kategorilerdeki venue'ları getir
      final tileVenues = await _optimizedVenueService.fetchVenuesOptimized(
        center,
        radius: radius,
        maxResults: maxResults,
        sortByDistance: true, // Yakından uzağa sıralama aktif
        priorityByDistance: true, // SADECE MESAFE sıralaması
      );

      // Check if disposed after async operation
      if (_isDisposed) return;

      // 💖 Update favorite status for tile venues
      _updateVenueFavoriteStatus(tileVenues);

      // 🎯 PRIORITY SORTING: Check-in yapılan mekanları ve mesafe sıralaması
      final sortedTileVenues = _sortVenuesByPriority(tileVenues, center);

      // 🚀 BATCH LOAD: Load Firebase data for all tile venues at once
      if (sortedTileVenues.isNotEmpty) {
        await _loadVenueDataFromFirebase(sortedTileVenues);
      }

      // ⚡ PROGRESSIVE TILE MARKER CREATION: Add to current venues list for progressive rendering
      final filteredVenues = <Venue>[];
      for (var venue in sortedTileVenues) {
        if (_markers.length >= _maxMarkersOnScreen) break;

        // Distance check
        if (_currentPosition != null) {
          final distance = _calculateDistance(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            venue.location,
          );

          if (distance > _maxDistance) {
            continue; // Too far
          }
        }

        filteredVenues.add(venue);

        // Add to main venues list if not already there
        if (!_loadedVenueIds.contains(venue.id)) {
          _venues.add(venue);
        }
      }

      // Trigger progressive loading for new tile venues
      if (filteredVenues.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed && mounted) {
            _updateMapMarkers(); // This will progressively add the new venues
          }
        });
      }

      // Cache the venues for this tile
      if (filteredVenues.isNotEmpty) {
        _tileVenueCache[tileKey] = filteredVenues;
      }
    } catch (e) {}
  }

  void _addOptimizedMarkerToMap(Venue venue) async {
    if (_loadedVenueIds.contains(venue.id)) return; // Already added

    _loadedVenueIds.add(venue.id);

    // 🚀 ULTRA-OPTIMIZED: Skip individual Firebase calls - data already batch loaded
    // Venue data should already be in cache from _loadVenueDataFromFirebase
    if (!_globalVenueCache.containsKey(venue.id)) {
      await _createVenueInFirebase(venue);
    }

    // Check-ins should also be pre-loaded, but fallback for edge cases
    if (!_venueCheckIns.containsKey(venue.id)) {
      try {
        final checkedInUsers = await _checkInService.getCheckedInUsers(
          venue.id,
          isForDiscover: false,
          isPremium: _isPremium,
          userCheckedInVenues: _userCheckedInVenues,
          globalVenueCache: _globalVenueCache,
        );
        _venueCheckIns[venue.id] = checkedInUsers;
      } catch (e) {}
    }

    // 🎯 YENİ MARKER SİSTEMİ: Sponsor > Muhtar > Check-in > Normal
    BitmapDescriptor markerIcon;
    bool userCheckedIn = _userCheckedInVenues.contains(venue.id);

    // Kullanıcının bu mekanda muhtar olup olmadığını kontrol et
    bool isMayor = false;
    if (_dailyMayors.containsKey(venue.id)) {
      final mayorData = _dailyMayors[venue.id]!;
      final currentUserId = _auth.currentUser?.uid;
      isMayor = (currentUserId != null && mayorData['userId'] == currentUserId);
    }

    // DEBUG: Marker seçimi için detaylı log
    final cachedData = _globalVenueCache[venue.id];
    final cachedSponsored = cachedData?['isSponsored'];

    // 🎯 MARKER ÖNCELIK SİSTEMİ
    if (venue.isSponsored) {
      // 💎 1️⃣ Sponsor mekanlar = Diamond marker (altın)
      markerIcon = _sponsorMarkerIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    } else if (isMayor) {
      // 👑 2️⃣ Muhtar olduğu mekanlar = Taç şekli (altın)
      markerIcon = _crownMarkerIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    } else if (userCheckedIn) {
      // ⭐ 3️⃣ Check-in yapılan mekanlar = Yıldız şekli (tema rengi)
      markerIcon = _starMarkerIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
    } else {
      // 📍 4️⃣ Normal mekanlar = Kategori bazlı custom icon
      markerIcon = await _getMarkerIconForCategory(venue.category);
    }

    final marker = Marker(
      markerId: MarkerId(venue.id),
      position: venue.location,
      icon: markerIcon,
      onTap: () => _showVenueDetails(venue),
    );

    _safeSetState(() {
      _markers.add(marker);
      _venues.add(venue);
    });
  }

  void _cleanupMarkersOutsideViewport() {
    if (_visibleBounds == null) return;

    _safeSetState(() {
      _markers.removeWhere((marker) {
        final markerLat = marker.position.latitude;
        final markerLng = marker.position.longitude;

        // Keep markers within viewport bounds (with small buffer)
        const buffer = 0.01; // ~1km buffer
        return markerLat < (_visibleBounds!.southwest.latitude - buffer) ||
            markerLat > (_visibleBounds!.northeast.latitude + buffer) ||
            markerLng < (_visibleBounds!.southwest.longitude - buffer) ||
            markerLng > (_visibleBounds!.northeast.longitude + buffer);
      });
    });
  }

  // Show only major venues at very low zoom levels
  void _showOnlyMajorVenues() {
    if (_venues.isEmpty) return;

    // Filter to show only cafes, night clubs, and bars (priority categories)
    final majorVenues = _venues
        .where((venue) =>
            venue.category == 'cafe' ||
            venue.category == 'night_club' ||
            venue.category == 'bar' ||
            venue.category == 'restaurant' && venue.rating >= 4.5)
        .take(20)
        .toList(); // Limit to 20 venues

    _updateMapMarkers();
  }

  Future<void> _loadVenueDataFromFirebase(List<Venue> venues) async {
    if (_isDisposed) return; // Early return if disposed

    try {
      // 🚀 ULTRA-FAST BATCH PROCESSING: Parallel loading of venues and check-ins

      // ⚡ PARALLEL EXECUTION: Load venue data and check-ins simultaneously
      final futures = await Future.wait([
        _loadVenueBatch(venues),
        _loadCheckInBatch(venues),
      ]);

      if (_isDisposed) return;
    } catch (e) {}
  }

  Future<void> _loadVenueBatch(List<Venue> venues) async {
    if (_isDisposed) return;

    try {
      // 🚀 OPTIMIZED: Venue'ları 30'lu batch'lerde işle (Firestore whereIn limiti 30)
      const batchSize = 30; // Increased from 10 to 30 for better performance

      for (int i = 0; i < venues.length; i += batchSize) {
        if (_isDisposed) break;

        final batchVenues = venues.skip(i).take(batchSize).toList();
        final venueIds = batchVenues.map((v) => v.id).toList();

        // 🚀 SINGLE BATCH QUERY: Get all venues in one call
        final venueSnapshot = await _firestore
            .collection('venues')
            .where(FieldPath.documentId, whereIn: venueIds)
            .get();

        if (_isDisposed) break;

        // ⚡ FAST CACHE UPDATE: Bulk cache insertion
        final existingVenueIds = <String>{};
        for (final doc in venueSnapshot.docs) {
          _globalVenueCache[doc.id] = doc.data();
          existingVenueIds.add(doc.id);
        }

        // 🔧 CREATE MISSING VENUES: Only if not found in batch
        final missingVenues = batchVenues
            .where((venue) => !existingVenueIds.contains(venue.id))
            .toList();
        if (missingVenues.isNotEmpty) {
          // ⚡ PARALLEL VENUE CREATION: Create missing venues in parallel
          await Future.wait(
              missingVenues.map((venue) => _createVenueInFirebase(venue)));
        }
      }
    } catch (e) {}
  }

  Future<void> _loadCheckInBatch(List<Venue> venues) async {
    if (_isDisposed || venues.isEmpty) return;

    try {
      // 🚀 OPTIMIZED: Process all venues in multiple 30-item batches
      const batchSize = 30; // Match venue batch size

      for (int i = 0; i < venues.length; i += batchSize) {
        if (_isDisposed) break;

        final batchVenues = venues.skip(i).take(batchSize).toList();
        final venueIds = batchVenues.map((v) => v.id).toList();

        if (venueIds.isEmpty) continue;

        // 🚀 SINGLE BATCH QUERY: Get all check-ins for this batch
        final checkInsSnapshot = await _firestore
            .collection('check_ins')
            .where('venueId', whereIn: venueIds)
            .orderBy('checkInTime', descending: true)
            .limit(500) // Increased limit for better coverage
            .get();

        if (_isDisposed) break;

        // ⚡ FAST GROUPING: Group check-ins by venue ID
        final checkInsByVenue = <String, List<Map<String, dynamic>>>{};
        for (final doc in checkInsSnapshot.docs) {
          final data = doc.data();
          final venueId = data['venueId'] as String;
          checkInsByVenue.putIfAbsent(venueId, () => []).add(data);
        }

        // ⚡ PARALLEL PROCESSING: Process all venues in this batch simultaneously
        await Future.wait(batchVenues.map((venue) async {
          if (_isDisposed) return;

          final venueCheckIns = checkInsByVenue[venue.id] ?? [];
          final checkedInUsers =
              await _processCheckInsForVenue(venue.id, venueCheckIns);
          _venueCheckIns[venue.id] = checkedInUsers;
        }));
      }
    } catch (e) {}
  }

  Future<List<CheckedInUser>> _processCheckInsForVenue(
      String venueId, List<Map<String, dynamic>> checkIns) async {
    if (_isDisposed) return [];

    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final users = <CheckedInUser>[];
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      for (final checkInData in checkIns) {
        if (_isDisposed) break;

        final userId = checkInData['userId'] as String;
        final isFromFavorite = checkInData['fromFavorite'] == true;

        // Zaman kontrolü - TÜM CHECK-IN'LER İÇİN AYNI MANTIK
        if (checkInData['checkInTime'] != null) {
          final checkInTime =
              (checkInData['checkInTime'] as Timestamp).toDate();
          if (checkInTime.isBefore(todayStart)) {
            continue; // Bugünden önceki check-in'leri atla (favori dahil)
          }
        }

        // User verilerini getir
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (!userDoc.exists) continue;

        final userData = userDoc.data()!;
        final mapVisibility = userData['mapVisibility'] ?? true;
        final profileActive = userData['profileActive'] ?? true;

        if (!mapVisibility && userId != user.uid) {
          continue; // Map visibility kapalı olanları atla
        }

        if (!profileActive && userId != user.uid) {
          continue; // Profile inactive olanları atla
        }

        // CheckedInUser oluştur
        String userName = userData['name'] ?? 'İsimsiz';
        if (userData['surname'] != null &&
            userData['surname'].toString().isNotEmpty) {
          userName = '$userName ${userData['surname'].toString()[0]}.';
        }

        String? userPhoto;
        if (userData['photos'] != null && userData['photos'] is List) {
          final photos = userData['photos'] as List;
          if (photos.isNotEmpty) {
            userPhoto = photos[0].toString();
          }
        }

        // Mayor kontrolü yap
        final mayorData = _dailyMayors[venueId];
        final isMayor = mayorData != null && mayorData['userId'] == userId;

        users.add(CheckedInUser(
          userId: userId,
          userName: userName,
          userPhoto: userPhoto,
          checkInTime: checkInData['checkInTime'] != null
              ? (checkInData['checkInTime'] as Timestamp).toDate()
              : DateTime.now(),
          latitude: 0.0, // Gerekli parametreler
          longitude: 0.0, // Gerekli parametreler
          fromFavorite: isFromFavorite,
          isMayor: isMayor, // Mayor durumunu set et
          mayorType: isMayor ? (mayorData['mayorType'] as String?) : null,
        ));
      }

      return users;
    } catch (e) {
      return [];
    }
  }

  // 🚀 REAL-TIME GÜNCELLEME FONKSİYONLARI
  Future<void> _refreshMayorAndCheckInData({bool forceRefresh = false}) async {
    if (_isDisposed) return;

    try {
      // Daily mayors'ı yeniden yükle (fresh data)
      _dailyMayors =
          await _checkInService.loadDailyMayors(forceRefresh: forceRefresh);

      // Eğer current user'ın muhtarlığı olan venue'lar varsa, onları tekrar kontrol et
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        final userMayorVenues = _dailyMayors.entries
            .where((entry) => entry.value['userId'] == currentUserId)
            .map((entry) => entry.key)
            .toList();

        if (userMayorVenues.isNotEmpty) {
          for (final venueId in userMayorVenues) {
            final freshMayorData = await _checkInService
                .getDailyMayorForVenue(venueId, forceRefresh: forceRefresh);
            if (freshMayorData != null) {
              _dailyMayors[venueId] = freshMayorData;
            }
          }
        }
      }

      // UI'ı güncelle
      _safeSetState(() {
        _updateMapMarkers();
      });
    } catch (e) {}
  }

  Future<void> _refreshVenueCheckInData(String venueId) async {
    if (_isDisposed) return;

    try {
      // Venue'nin check-in'lerini yeniden yükle
      final checkedInUsers = await _checkInService.getCheckedInUsers(
        venueId,
        isForDiscover: false,
        isPremium: _isPremium,
        userCheckedInVenues: _userCheckedInVenues,
        globalVenueCache: _globalVenueCache,
      );

      // Cache'i güncelle
      _venueCheckIns[venueId] = checkedInUsers;

      // Kullanıcı sayısını da güncelle
      _venueUserCounts[venueId] = checkedInUsers.length;

      // UI'ı güncelle
      if (mounted) {
        setState(() {});
      }
    } catch (e) {}
  }

  Future<void> _createVenueInFirebase(Venue venue) async {
    try {
      // Venue'nun fotoğraflarını al (eğer varsa)
      List<String> photoUrls = [];
      if (venue.photos.isNotEmpty) {
        photoUrls = venue.photos;
      }

      // Kategori bazlı varsayılan features
      List<String> defaultFeatures = _getDefaultFeatures(venue.category);

      await _firestore.collection('venues').doc(venue.id).set({
        'placeId': venue.placeId,
        'place_id': venue.placeId, // Compatibility field
        'name': venue.name,
        'category': venue.category,
        'latitude': venue.location.latitude,
        'longitude': venue.location.longitude,
        'rating': venue.rating,
        'vicinity': venue.vicinity,
        'formattedAddress': venue.vicinity,
        'createdAt': FieldValue.serverTimestamp(),
        'closingTime': venue.closingTime ?? '02:00',
        'openingTime': venue.openingTime ?? '08:00',
        // Fotoğraf alanları
        'photos': photoUrls,
        'photoUrl': photoUrls.isNotEmpty ? photoUrls[0] : null,
        // Varsayılan features
        'features': defaultFeatures,
        // Sponsor bilgileri
        'isSponsored': venue.isSponsored,
        'sponsorLogoUrl': venue.sponsorLogoUrl,
        'sponsorBadgeText': venue.sponsorBadgeText,
      }, SetOptions(merge: true)); // Merge kullan, mevcut data'yı ezmemek için

      _globalVenueCache[venue.id] = {
        'placeId': venue.placeId,
        'name': venue.name,
        'category': venue.category,
        'closingTime': venue.closingTime ?? '02:00',
        'openingTime': venue.openingTime ?? '08:00',
        'photos': photoUrls,
        'photoUrl': photoUrls.isNotEmpty ? photoUrls[0] : null,
        'features': defaultFeatures,
      };
    } catch (e) {}
  }

  // Kategori bazlı varsayılan features
  List<String> _getDefaultFeatures(String category) {
    switch (category.toLowerCase()) {
      case 'cafe':
      case 'kafe':
        return ['Wi-Fi', 'Kahve', 'Tatlı', 'Çalışma Alanı'];
      case 'restaurant':
      case 'restoran':
        return ['Yemek', 'İçecek', 'Rezervasyon', 'Açık Alan'];
      case 'bar':
        return ['Alkol', 'Müzik', 'Kokteyl', 'Gece Hayatı'];
      case 'night_club':
        return ['Gece Hayatı', 'Dans', 'Müzik', 'Kokteyl'];
      case 'gym':
        return ['Spor Aletleri', 'Duş', 'Soyunma Odası', 'Kişisel Antrenör'];
      case 'movie_theater':
      case 'sinema':
        return ['Film Gösterimi', 'Mısır', 'Kolalı Menü', 'Konforlu Koltuklar'];
      case 'bakery':
        return ['Taze Ekmek', 'Tatlı', 'Kahve', 'Kahvaltı'];
      case 'park':
        return ['Açık Alan', 'Piknik', 'Yürüyüş', 'Doğa'];
      default:
        return ['Hoş Ortam', 'Samimi Atmosfer'];
    }
  }

  Future<void> _toggleFavorite(Venue venue) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userRef = _firestore.collection('users').doc(user.uid);
      final userDoc = await userRef.get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        List<String> favoriteVenues =
            List<String>.from(userData['favoriteVenues'] ?? []);

        if (favoriteVenues.contains(venue.id)) {
          favoriteVenues.remove(venue.id);
          _userFavoriteVenues.remove(venue.id);
          venue.isFavorite = false;
        } else {
          // Check if user has checked in to this venue
          if (!_userCheckedInVenues.contains(venue.id)) {
            // Show check-in required message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${venue.name} mekanını favorilere eklemek için önce check-in yapmalısınız.'),
                  backgroundColor: Colors.red,
                  action: SnackBarAction(
                    label: 'Check-in Yap',
                    textColor: Colors.white,
                    onPressed: () {
                      // Trigger check-in for this venue
                      _performCheckIn(venue);
                    },
                  ),
                ),
              );
            }
            return; // Don't add to favorites
          }

          // Check maximum 5 favorites rule
          if (favoriteVenues.length >= 5) {
            // Show warning message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Maksimum 5 favori mekan ekleyebilirsiniz. Önce bir favoriyi kaldırın.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return; // Don't add to favorites
          }

          favoriteVenues.add(venue.id);
          _userFavoriteVenues.add(venue.id);
          venue.isFavorite = true;
        }

        await userRef.update({'favoriteVenues': favoriteVenues});

        // Update all venues with the same ID in case there are duplicates
        for (var v in _venues) {
          if (v.id == venue.id) {
            v.isFavorite = venue.isFavorite;
          }
        }

        // UI'ı güncelle
        _safeSetState(() {});
      }
    } catch (e) {}
  }

  void _performCheckIn(Venue venue) async {
    // 🕐 Gerçek zamanlı cooldown kontrolü yap
    final cooldownStatus = await _checkInService.getCheckInCooldownStatus();
    if (!cooldownStatus.canCheckIn) {
      // Cooldown timer'ını başlat
      _startCooldownTimer();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cooldownStatus.message),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Mekan kapanış saati kontrolü (önce mekan saati, sonra varsayılan 02:00)
    if (_isVenueClosed(venue)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mekan şu anda kapalı - check-in yapılamaz'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Sadece tüm kontroller başarılıysa dialog'u aç
    _showCheckInDialog(venue);
  }

  // 🕒 Mekan kapanış saati kontrolü
  bool _isVenueClosed(Venue venue) {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute; // Dakika cinsinden

    // Check if venue is 24/7 (no closing time)
    if (venue.closingTime == null) {
      return false; // 24/7 venues are never closed
    }

    // Eğer venue'da closing time bilgisi varsa, onu kullan (opening time null olsa bile)
    if (venue.closingTime != null) {
      try {
        // Saat formatını parse et (örn: "09:00", "23:30", "+01:00" for cross-day)
        // Eğer opening time null ise, varsayılan olarak 08:00 kabul et (çoğu işletme sabah açılır)
        final openingTimeStr = venue.openingTime ?? "08:00";
        final openingParts = openingTimeStr.split(':');

        // Check for cross-day closing (starts with + OR closing time is before opening time)
        final closingTimeStr = venue.closingTime!;
        final isCrossDay = closingTimeStr.startsWith('+');
        final actualClosingTime =
            isCrossDay ? closingTimeStr.substring(1) : closingTimeStr;
        final closingParts = actualClosingTime.split(':');

        if (openingParts.length == 2 && closingParts.length == 2) {
          final openingMinutes =
              int.parse(openingParts[0]) * 60 + int.parse(openingParts[1]);
          final closingMinutes =
              int.parse(closingParts[0]) * 60 + int.parse(closingParts[1]);

          // Auto-detect cross-day if closing time is before opening time
          final isAutoCrossDay = !isCrossDay && closingMinutes < openingMinutes;
          final isFinalCrossDay = isCrossDay || isAutoCrossDay;

          bool isClosed;

          if (isFinalCrossDay) {
            // Cross-day closing logic: venue is open if current time is after opening OR before closing
            // Example: Opens at 08:00, closes at 02:00 (next day)
            // Open from 08:00-23:59 (same day) and 00:00-02:00 (next day)
            if (currentTime >= openingMinutes || currentTime < closingMinutes) {
              isClosed = false;
            } else {
              isClosed = true;
            }
          } else {
            // Normal işletme saatleri mantığı
            // Eğer şu anki saat açılış saatinden önce veya kapanış saatinden sonra ise kapalı
            if (currentTime < openingMinutes || currentTime >= closingMinutes) {
              isClosed = true;
            } else {
              isClosed = false;
            }
          }

          return isClosed;
        } else {}
      } catch (e) {}
    } else {}

    // Eğer açılış/kapanış saati bilgisi yoksa, varsayılan olarak 02:00-07:00 arası kapalı (global check-in hours)
    final isDefaultClosed = hour >= 2 && hour < 7;

    return isDefaultClosed;
  }

  void _showCheckInDialog(Venue venue) {
    // Loading state'i başlat
    setState(() {
      _isCheckingIn = true;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false, // Dialog'u manuel olarak kapatılamaz yap
      enableDrag: false, // Drag ile kapatmayı engelle
      builder: (context) => _CheckInDialogWidget(
        venue: venue,
        onCheckInWithoutPhoto: () async {
          await _performCheckInWithoutPhoto(venue);
        },
        onCheckInWithPhoto: () async {
          await _performCheckInWithPhoto(venue);
        },
        onDialogClosed: () {
          // Check-in tamamlandığında loading state'i resetle
          if (mounted) {
            setState(() {
              _isCheckingIn = false;
            });
          } else {}
        },
      ),
    ).then((_) {
      // Dialog kapatıldığında her durumda loading state'i reset et
      if (mounted) {
        setState(() {
          _isCheckingIn = false;
        });
      } else {}
    });
  }

  Future<void> _performCheckInWithoutPhoto(Venue venue) async {
    try {
      final success = await _checkInService.performCheckInWithoutPhoto(
          venue, _userCheckedInVenues);

      if (success) {
        // 🚀 REAL-TIME GÜNCELLEME: Check-in sonrası tüm veriyi refresh et (FORCE REFRESH)
        await _refreshVenueCheckInData(venue.id);
        await _refreshMayorAndCheckInData(forceRefresh: true);
        _refreshCooldownAfterCheckIn(); // 🕐 Cooldown'ı yenile

        // 🔄 CHECK-IN SUCCESS: Close all open sheets first
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // Close venue details sheet
        }
        _isVenueDetailsOpen = false; // Reset flag

        // Check-in başarılı mesajı göster
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${venue.name} mekanına check-in yaptınız!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );

        // ❌ DON'T REOPEN: Let user manually open venue details if needed
        // Future.delayed(const Duration(milliseconds: 500), () {
        //   if (!_isDisposed && mounted) {
        //     _showVenueDetails(venue);
        //   }
        // });
      } else {
        // 🔄 CHECK-IN FAILED: Close sheets on failure too
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // Close venue details sheet
        }
        _isVenueDetailsOpen = false; // Reset flag

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check-in yapılırken hata oluştu'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      // 🔄 CHECK-IN ERROR: Close sheets on error too
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close venue details sheet
      }
      _isVenueDetailsOpen = false; // Reset flag

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check-in yapılırken hata: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _performCheckInWithPhoto(Venue venue) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return;
      }

      // Direkt kamera aç ve crop et (izin kontrolü ImagePickerService içinde)
      final File? croppedImage =
          await _checkInService.selectImageFromCamera(context);

      if (croppedImage == null) {
        // Kullanıcı iptal ettiğinde veya izin sorunu olduğunda popup'lar CheckinService içinde gösterilir
        return;
      }

      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // CheckInService ile fotoğraflı check-in yap
        final success = await _checkInService.performCheckInWithPhoto(
            venue, croppedImage, _userCheckedInVenues);

        if (success) {
          // 🚀 REAL-TIME GÜNCELLEME: Fotoğraflı check-in sonrası tüm veriyi refresh et (FORCE REFRESH)
          await _refreshVenueCheckInData(venue.id);
          await _refreshMayorAndCheckInData(forceRefresh: true);
          _refreshCooldownAfterCheckIn(); // 🕐 Cooldown'ı yenile

          // Loading'i kapat
          Navigator.pop(context);

          // 🔄 PHOTO CHECK-IN SUCCESS: Close all open sheets first
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(); // Close venue details sheet
          }
          _isVenueDetailsOpen = false; // Reset flag

          // Success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${venue.name} mekanına fotoğraflı check-in yaptınız!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 2),
            ),
          );

          // ❌ DON'T REOPEN: Let user manually open venue details if needed
          // Future.delayed(const Duration(milliseconds: 500), () {
          //   if (!_isDisposed && mounted) {
          //     _showVenueDetails(venue);
          //   }
          // });
        } else {
          // Loading'i kapat
          Navigator.pop(context);

          // 🔄 PHOTO CHECK-IN FAILED: Close sheets on failure too
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(); // Close venue details sheet
          }
          _isVenueDetailsOpen = false; // Reset flag

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Check-in yapılırken hata oluştu'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.all(16),
            ),
          );
        }
      } catch (e) {
        // Loading'i kapat
        Navigator.pop(context);
        rethrow;
      }
    } catch (e) {
      // 🔄 PHOTO CHECK-IN ERROR: Close sheets on error too
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close venue details sheet if open
      }
      _isVenueDetailsOpen = false; // Reset flag

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraflı check-in yapılırken hata oluştu'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _purchaseMayorshipWithDiamonds(Venue venue) async {
    try {
      // Önce kullanıcının elmas bakiyesini kontrol et
      final user = _auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Oturum açmanız gerekiyor'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
        return;
      }

      // Elmas bakiyesini kontrol et
      final diamondBalance =
          await _checkInService.getUserDiamondBalance(user.uid);
      final requiredDiamonds =
          await _checkInService.calculateMayorshipPrice(venue.id);

      if (diamondBalance < requiredDiamonds) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Yetersiz elmas! Gerekli: $requiredDiamonds, Mevcut: $diamondBalance'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      // Onay dialog'u göster
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Elmas ile Muhtar Ol'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  '${venue.name} mekanının muhtarı olmak için $requiredDiamonds elmas harcamak istediğinizden emin misiniz?'),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.diamond, color: Color(0xFF00BCD4)),
                  const SizedBox(width: 8),
                  Text('Mevcut bakiye: $diamondBalance'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.remove, color: Colors.red),
                  const SizedBox(width: 8),
                  Text('Harcanacak: $requiredDiamonds'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('Kalan bakiye: ${diamondBalance - requiredDiamonds}'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
              ),
              child: const Text('Muhtar Ol'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // Diamond mayorship satın al
        final result = await _checkInService.purchaseMayorshipWithDiamonds(
          venue.id,
          venue.name,
        );

        // Loading'i kapat
        Navigator.pop(context);

        if (result['success'] == true) {
          // 🚀 REAL-TIME GÜNCELLEME: Muhtar listesi ve check-in'ler (FORCE REFRESH)
          await _refreshMayorAndCheckInData(forceRefresh: true);

          // Venue detail panel'i kapat (eğer açıksa)
          Navigator.of(context).popUntil((route) => route.isFirst);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Tebrikler! ${venue.name} mekanının muhtarı oldunuz! 👑'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );

          // Venue'yu tekrar aç güncel mayor bilgisi ile - Mayor bilgisinin güncellendiğinden emin ol
          await Future.delayed(const Duration(
              milliseconds:
                  1000)); // Firestore yazma işleminin tamamlanması için bekle

          // Mayor bilgisini tekrar yükle ve venue details'i aç (FORCE REFRESH)
          _dailyMayors =
              await _checkInService.loadDailyMayors(forceRefresh: true);

          // Spesifik venue için mayor bilgisini tekrar yükle (cache sorunlarını önlemek için)
          final specificMayor = await _checkInService
              .getDailyMayorForVenue(venue.id, forceRefresh: true);
          if (specificMayor != null) {
            _dailyMayors[venue.id] = specificMayor;
          }

          _showVenueDetails(venue);
        } else {
          String errorMessage;
          switch (result['error']) {
            case 'no_checkin_today':
              errorMessage = 'Önce bu mekana bugün check-in yapmalısınız!';
              break;
            case 'insufficient_diamonds':
              final required = result['required'] ?? 100;
              final available = result['available'] ?? 0;
              errorMessage =
                  'Yetersiz elmas! Gerekli: $required, Mevcut: $available';
              break;
            case 'not_authenticated':
              errorMessage = 'Oturum açmanız gerekiyor';
              break;
            case 'higher_bid_exists':
              errorMessage =
                  'Başka biri daha fazla elmas harcayarak muhtar olmuş!';
              break;
            case 'race_condition_detected':
              errorMessage =
                  'Başka bir kullanıcı aynı anda muhtarlık aldı! Lütfen tekrar deneyin.';
              // 🔄 RACE CONDITION: UI'yı fresh data ile güncelle
              await _refreshMayorAndCheckInData(forceRefresh: true);
              break;
            case 'price_changed':
              errorMessage =
                  'Fiyat değişti! Lütfen sayfayı yenileyip tekrar deneyin.';
              // 🔄 PRICE CHANGE: UI'yı fresh data ile güncelle
              await _refreshMayorAndCheckInData(forceRefresh: true);
              break;
            default:
              errorMessage = 'Muhtar olurken hata oluştu. Tekrar deneyiniz.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } catch (e) {
        // Loading'i kapat
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Muhtar olurken hata oluştu'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bir hata oluştu'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  // Buy Now ile muhtar olma (hızlı, pahalı)
  Future<void> _purchaseBuyNowMayorshipWithDiamonds(Venue venue) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Oturum açmanız gerekiyor'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
        return;
      }

      // Buy Now fiyatını hesapla
      final diamondBalance =
          await _checkInService.getUserDiamondBalance(user.uid);
      final buyNowPrice = await _checkInService.calculateBuyNowPrice(venue.id);

      if (diamondBalance < buyNowPrice) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Yetersiz elmas! Buy Now için: $buyNowPrice, Mevcut: $diamondBalance'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      // Buy Now onay dialog'u
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.flash_on, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Buy Now - Anında Muhtar Ol'),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${venue.name} mekanının ANINDA muhtarı olmak için $buyNowPrice elmas harcamak istediğinizden emin misiniz?',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.flash_on,
                                color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Text('Buy Now Avantajları:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[700])),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                            '• Anında muhtar olursun\n• Rekabet etmeye gerek yok\n• Diğer teklifleri geçer',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.diamond, color: Color(0xFF00BCD4)),
                      const SizedBox(width: 8),
                      Text('Mevcut bakiye: $diamondBalance'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.remove, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('Buy Now maliyeti: $buyNowPrice',
                          style: TextStyle(
                              color: Colors.orange[700],
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flash_on, size: 16),
                      SizedBox(width: 4),
                      Text('BUY NOW'),
                    ],
                  ),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;

      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Buy Now işlemi yapılıyor...'),
            ],
          ),
        ),
      );

      try {
        final result =
            await _checkInService.purchaseBuyNowMayorshipWithDiamonds(
          venue.id,
          venue.name,
        );

        Navigator.pop(context); // Loading'i kapat

        if (result['success'] == true) {
          await _refreshMayorAndCheckInData(forceRefresh: true);
          Navigator.of(context).popUntil((route) => route.isFirst);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '🚀 ANINDA MUHTAR! ${venue.name} mekanının muhtarı oldunuz! 👑'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 3),
            ),
          );

          await Future.delayed(const Duration(
              milliseconds:
                  3000)); // Firestore yazma işleminin tamamlanması için bekle

          // 🔧 CACHE REFRESH: Daily mayors'ı yeniden yükle (FORCE REFRESH)
          _dailyMayors =
              await _checkInService.loadDailyMayors(forceRefresh: true);

          // 🔧 SPECIFIC VENUE: Spesifik venue için mayor bilgisini tekrar yükle (multiple attempts with force refresh)
          Map<String, dynamic>? specificMayor;
          for (int attempt = 1; attempt <= 3; attempt++) {
            await Future.delayed(const Duration(milliseconds: 500));
            specificMayor = await _checkInService
                .getDailyMayorForVenue(venue.id, forceRefresh: true);
            if (specificMayor != null &&
                specificMayor['mayorType'] == 'diamond') {
              break;
            }
          }

          if (specificMayor != null) {
            _dailyMayors[venue.id] = specificMayor;
          } else {}

          // 🔧 UI REFRESH: State'i güncelle
          _safeSetState(() {
            _updateMapMarkers();
          });

          // 🔧 FRESH VENUE DETAILS: Venue details'ı fresh data ile aç
          _showVenueDetails(venue);
        } else {
          String errorMessage;
          switch (result['error']) {
            case 'no_checkin_today':
              errorMessage = 'Önce bu mekana bugün check-in yapmalısınız!';
              break;
            case 'insufficient_diamonds':
              final required = result['required'] ?? 100;
              final available = result['available'] ?? 0;
              errorMessage =
                  'Yetersiz elmas! Buy Now için: $required, Mevcut: $available';
              break;
            case 'not_authenticated':
              errorMessage = 'Oturum açmanız gerekiyor';
              break;
            case 'race_condition_detected':
              errorMessage =
                  'Başka bir kullanıcı aynı anda muhtarlık aldı! Lütfen tekrar deneyin.';
              // 🔄 RACE CONDITION: UI'yı fresh data ile güncelle
              await _refreshMayorAndCheckInData(forceRefresh: true);
              break;
            case 'price_changed':
              errorMessage =
                  'Fiyat değişti! Lütfen sayfayı yenileyip tekrar deneyin.';
              // 🔄 PRICE CHANGE: UI'yı fresh data ile güncelle
              await _refreshMayorAndCheckInData(forceRefresh: true);
              break;
            default:
              errorMessage = 'Buy Now işleminde hata oluştu. Tekrar deneyiniz.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } catch (e) {
        Navigator.pop(context); // Loading'i kapat
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buy Now işleminde hata oluştu'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bir hata oluştu'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🚀 PERFORMANCE OPTIMIZED Google Map with Custom Style
          GoogleMap(
            mapType: MapType.normal,
            style: MapStyles.customMapStyle, // Re-enabled custom style
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude)
                  : const LatLng(
                      38.4317, 27.4061), // Default Kemalpaşa location
              zoom: 18.0, // 500m radius için
            ),
            onMapCreated: (GoogleMapController controller) async {
              _mapController = controller;

              // Move to current location if available
              if (_currentPosition != null) {
                await _moveCameraToLocation(
                  LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude),
                );
              }
            },
            markers: _markers,
            myLocationEnabled: _isLocationPermissionGranted,
            myLocationButtonEnabled: false, // Keep disabled for performance
            zoomControlsEnabled: false,
            minMaxZoomPreference: const MinMaxZoomPreference(12.0, 20.0),
            mapToolbarEnabled: false,
            compassEnabled: false, // Keep disabled for performance
            rotateGesturesEnabled: true, // Re-enable for better UX
            tiltGesturesEnabled: false, // Keep disabled for performance
            buildingsEnabled: false, // Keep disabled for performance
            trafficEnabled: false, // Keep disabled for performance
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
          ),

          // My Location Button - Sağ üst köşe
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FloatingActionButton(
              heroTag: "my_location_button",
              onPressed: () async {
                await _getCurrentLocation();
                if (_currentPosition != null && _mapController != null) {
                  await _mapController!.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      18.0,
                    ),
                  );
                }
              },
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 4,
              mini: true, // Küçük boyut
              child: const Icon(Icons.my_location, size: 20),
            ),
          ),

          // Elmas satın alma butonu
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Premium butonu
                SizedBox(
                  width: 60,
                  height: 60,
                  child: FloatingActionButton(
                    heroTag: "premium_button",
                    onPressed: () => _showPremiumBottomSheet(),
                    backgroundColor: AppColors.premium,
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Colors.black87,
                      size: 24, // İkon boyutu da büyütüldü
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Elmas bakiyesi göstergesi (tema rengi)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary, // Tema rengi
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary
                            .withOpacity(0.3), // Tema rengi shadow
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.diamond,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_userDiamondBalance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Elmas satın alma butonu (tema rengi)
                FloatingActionButton(
                  heroTag: "diamond_button",
                  onPressed: () => _showPurchaseDiamondsBottomSheet(),
                  backgroundColor: AppColors.primary, // Tema rengi
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                  ),
                ),
                // REMOVED: Super Like purchase button - no longer needed with Chat Request system
                // Chat requests don't require purchasing separate items like super likes did
              ],
            ),
          ),

          // 📍 CHECK-IN LOADING OVERLAY
          if (_isCheckingIn)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Like animasyonu widget'ı
  // REMOVED: Like animation widgets no longer needed with Chat Request system

  void _showVenueDetails(Venue venue) async {
    // 🚫 PREVENT MULTIPLE SHEETS: If a venue details sheet is already open, ignore
    if (_isVenueDetailsOpen) {
      return;
    }

    _isVenueDetailsOpen = true; // Mark as open

    // � FRESH DATA: Load latest check-in data when opening venue details
    await _refreshVenueCheckInData(venue.id);

    // �🕐 SAFETY TIMEOUT: Reset flag after 30 seconds in case something goes wrong
    Timer(const Duration(seconds: 30), () {
      if (_isVenueDetailsOpen) {
        _isVenueDetailsOpen = false;
      }
    });

    // 🕐 Venue details açılırken cooldown durumunu güncelle
    await _loadCheckInCooldownStatus();

    // Venue'nun sponsor durumunu hesapla (marker oluşturulurken kullanılan aynı logic)
    final cachedData = _globalVenueCache[venue.id];
    bool isSponsored = cachedData?['isSponsored'] ?? venue.isSponsored ?? false;

    // ZINCIR MEKAN KONTROLÜ: Eğer individual sponsor değilse, chain kontrolü yap
    if (!isSponsored) {
      isSponsored = _isChainSponsored(venue.name);
    }

    // Cache'de sponsor expiry kontrolü
    if (cachedData != null && isSponsored) {
      try {
        final endDateData = cachedData['sponsorEndDate'];
        if (endDateData != null) {
          DateTime endDate;
          if (endDateData is String) {
            endDate = DateTime.parse(endDateData);
          } else if (endDateData is Timestamp) {
            endDate = endDateData.toDate();
          } else {
            endDate = DateTime.now()
                .add(const Duration(days: 30)); // Default fallback
          }

          if (endDate.isBefore(DateTime.now())) {
            isSponsored = false;
          }
        }
      } catch (e) {}
    }

    // Venue'yu güncellenmiş sponsor durumuyla yeniden oluştur
    final updatedVenue = venue.copyWith(isSponsored: isSponsored);

    final userCheckedIn = _userCheckedInVenues.contains(venue.id);
    final hasCheckedInUsers =
        _venueUserCounts[venue.id] != null && _venueUserCounts[venue.id]! > 0;
    // Sponsorlu mekanlarda herkes kullanıcı listesini görebilir
    final bool canSeeUsers = _isPremium || userCheckedIn || isSponsored;

    // Get actual user count for this venue
    final int actualUserCount = _venueUserCounts[venue.id] ?? 0;

    // Get fresh daily mayor data for this venue - use existing cache
    Map<String, dynamic>? dailyMayor = _dailyMayors[venue.id];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VenueDetailsSheet(
        venue: updatedVenue, // Güncellenmiş venue'yu kullan
        hasCheckedIn: hasCheckedInUsers,
        isCheckedIn: userCheckedIn,
        canSeeUsers: canSeeUsers,
        isPremium: _isPremium,
        isUpdatingFavorite: false,
        actualUserCount: actualUserCount,
        dailyMayor: dailyMayor,
        userCheckedInVenues:
            _userCheckedInVenues, // Yeni: Check-in yapılan mekanlar
        cooldownStatus: _cooldownStatus, // 🕐 Cooldown durumu
        isCheckingIn: _isCheckingIn, // 📍 Loading state
        onToggleFavorite: (venue) => _toggleFavorite(venue),
        onCheckIn: (venue) => _performCheckIn(venue),
        onRefreshUserData: () =>
            _refreshVenueCheckInData(venue.id), // Real-time refresh
        onShowMayorDialog: (venue) => null,
        onPurchaseMayorship: (venue) => _purchaseMayorshipWithDiamonds(venue),
        onPurchaseBuyNowMayorship: (venue) =>
            _purchaseBuyNowMayorshipWithDiamonds(venue),
        calculateMayorshipPrice: (venueId) =>
            _checkInService.calculateMayorshipPrice(venueId),
        calculateBuyNowPrice: (venueId) =>
            _checkInService.calculateBuyNowPrice(venueId),
        onShowPurchaseDiamondsPanel: () => _showPurchaseDiamondsBottomSheet(),
        userDiamondBalance: _userDiamondBalance,
        getCategoryIcon: (category) => Icons.place,
        buildCheckedInUsersList: (venue, canSee) =>
            _buildCheckedInUsersList(venue),
        // Chat request durumları ve callback'ler
        sentChatRequestUserIds: _sentChatRequestUserIds,
        onHandleChatRequest: _handleChatRequest,
      ),
    ).then((_) {
      // 🔄 RESET FLAG: Sheet closed, allow new venue details to open
      _isVenueDetailsOpen = false;
    });
  }

  // ⚡ ASYNC MARKER UPDATE - Prevents UI blocking
  // ⚡ ULTRA-PROGRESSIVE MARKER RENDERING
  void _updateMapMarkers() async {
    // 🚫 5KM FİLTRESİ: Sadece 5km içindeki mekanları renderla
    final filteredVenues = <Venue>[];
    if (_currentPosition != null) {
      final userLocation =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      for (final venue in _venues) {
        final distance = _calculateDistance(userLocation, venue.location);
        if (distance <= _maxDistance) {
          filteredVenues.add(venue);
        }
      }
    } else {
      filteredVenues.addAll(_venues);
    }

    // 🎯 CATEGORIZE VENUES BY PRIORITY (SPONSOR > CHECK-IN > MAYOR > NORMAL)
    final sponsorVenues = <Venue>[];
    final checkInVenues = <Venue>[];
    final mayorVenues = <Venue>[];
    final normalVenues = <Venue>[];

    for (final venue in filteredVenues) {
      // Firebase cache'den sponsor data'sını al
      final cachedData = _globalVenueCache[venue.id];
      bool isSponsored =
          cachedData?['isSponsored'] ?? venue.isSponsored ?? false;

      // ZINCIR MEKAN KONTROLÜ: Eğer individual sponsor değilse, chain kontrolü yap
      if (!isSponsored) {
        isSponsored = _isChainSponsored(venue.name);
      }

      // Kullanıcının bu mekanda muhtar olup olmadığını kontrol et
      bool isMayor = false;
      if (_dailyMayors.containsKey(venue.id)) {
        final mayorData = _dailyMayors[venue.id]!;
        final currentUserId = _auth.currentUser?.uid;
        isMayor =
            (currentUserId != null && mayorData['userId'] == currentUserId);
      }

      final userCheckedIn = _userCheckedInVenues.contains(venue.id);

      // Öncelik sırasına göre kategorize et
      if (isSponsored) {
        sponsorVenues.add(venue);
      } else if (userCheckedIn) {
        checkInVenues.add(venue);
      } else if (isMayor) {
        mayorVenues.add(venue);
      } else {
        normalVenues.add(venue);
      }
    }

    // 🚀 PHASE 0: SPONSOR VENUES (INSTANT - HIGHEST PRIORITY)
    if (sponsorVenues.isNotEmpty) {
      final sponsorMarkers =
          await _createMarkersForVenuesBatch(sponsorVenues, 'sponsor');
      if (!_isDisposed && mounted) {
        _safeSetState(() => _markers = sponsorMarkers);
      }
    }

    // 🚀 PHASE 1: CHECK-IN VENUES (100ms delay)
    Timer(const Duration(milliseconds: 100), () async {
      if (_isDisposed || !mounted) return;
      if (checkInVenues.isNotEmpty) {
        final checkInMarkers =
            await _createMarkersForVenuesBatch(checkInVenues, 'check-in');
        if (!_isDisposed && mounted) {
          _safeSetState(() {
            if (sponsorVenues.isNotEmpty) {
              _markers.addAll(checkInMarkers);
            } else {
              _markers = checkInMarkers;
            }
          });
        }
      }
    });
    // 🚀 PHASE 2: MAYOR VENUES (300ms delay)
    Timer(const Duration(milliseconds: 300), () async {
      if (_isDisposed || !mounted) return;

      final mayorMarkers =
          await _createMarkersForVenuesBatch(mayorVenues, 'mayor');
      if (!_isDisposed && mounted) {
        _safeSetState(() {
          _markers.addAll(mayorMarkers);
        });
      }
    });

    // 🚀 PHASE 3: NORMAL VENUES (500ms delay)
    Timer(const Duration(milliseconds: 500), () async {
      if (_isDisposed || !mounted) return;

      final normalMarkers = await _createMarkersForVenuesBatch(
          normalVenues.take(20).toList(), 'normal');
      if (!_isDisposed && mounted) {
        _safeSetState(() {
          _markers.addAll(normalMarkers);
        });
      }
    });

    // 🚀 PHASE 4: REMAINING VENUES (700ms delay)
    if (normalVenues.length > 20) {
      Timer(const Duration(milliseconds: 700), () async {
        if (_isDisposed || !mounted) return;

        final remainingMarkers = await _createMarkersForVenuesBatch(
            normalVenues.skip(20).toList(), 'remaining');
        if (!_isDisposed && mounted) {
          _safeSetState(() {
            _markers.addAll(remainingMarkers);
          });
        }
      });
    }
  }

  // 🚀 ULTRA-FAST BATCH MARKER CREATION
  Future<Set<Marker>> _createMarkersForVenuesBatch(
      List<Venue> venues, String phase) async {
    final markers = <Marker>{};
    int currentMarkerCount = _markers.length;

    for (final venue in venues) {
      if (_isDisposed) break;

      // 🚫 50 MARKER SINIRI: Maksimum marker sayısını aşma
      if (currentMarkerCount >= _maxMarkersOnScreen) {
        break;
      }

      // 🎯 SMART MARKER SELECTION (PRIORITY: MAYOR > SPONSOR > CHECK-IN > NORMAL)
      BitmapDescriptor markerIcon;

      // 1️⃣ MUHTAR KONTROLÜ (EN YÜKSEK ÖNCELİK)
      bool isMayor = false;
      if (_dailyMayors.containsKey(venue.id)) {
        final mayorData = _dailyMayors[venue.id]!;
        final currentUserId = _auth.currentUser?.uid;
        isMayor =
            (currentUserId != null && mayorData['userId'] == currentUserId);
      }

      // 2️⃣ SPONSOR KONTROLÜ (Muhtar değilse)
      bool isSponsored = false;
      if (!isMayor) {
        // Firebase cache'den güncel veri al
        final cachedData = _globalVenueCache[venue.id];
        isSponsored = cachedData?['isSponsored'] ?? venue.isSponsored ?? false;

        // SPONSOR TARİH KONTROLÜ: Sponsor ise tarih geçerliliğini kontrol et
        if (isSponsored) {
          final startDateData =
              cachedData?['sponsorStartDate'] ?? venue.sponsorStartDate;
          final endDateData =
              cachedData?['sponsorEndDate'] ?? venue.sponsorEndDate;

          if (startDateData != null || endDateData != null) {
            final now = DateTime.now();

            // Başlangıç tarihi kontrolü
            if (startDateData != null) {
              try {
                DateTime startDate;
                if (startDateData is String) {
                  startDate = DateTime.parse(startDateData);
                } else if (startDateData is Timestamp) {
                  startDate = startDateData.toDate();
                } else {
                  startDate = DateTime.now()
                      .subtract(const Duration(days: 1)); // Default to active
                }

                if (now.isBefore(startDate)) {
                  isSponsored = false;
                }
              } catch (e) {}
            }

            // Bitiş tarihi kontrolü
            if (endDateData != null && isSponsored) {
              try {
                DateTime endDate;
                if (endDateData is String) {
                  endDate = DateTime.parse(endDateData);
                } else if (endDateData is Timestamp) {
                  endDate = endDateData.toDate();
                } else {
                  endDate = DateTime.now()
                      .add(const Duration(days: 30)); // Default to active
                }

                if (now.isAfter(endDate)) {
                  isSponsored = false;
                }
              } catch (e) {}
            }
          }
        }

        // ZINCIR MEKAN KONTROLÜ: Eğer individual sponsor değilse, chain kontrolü yap
        if (!isSponsored) {
          isSponsored = _isChainSponsored(venue.name);
        }
      }

      // 3️⃣ CHECK-IN KONTROLÜ
      final bool userCheckedIn = _userCheckedInVenues.contains(venue.id);

      // DEBUG: Marker icon seçimi için log

      // MARKER SELECTION (PRIORITY ORDER)
      if (isMayor) {
        markerIcon = _crownMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      } else if (isSponsored) {
        // Her sponsor mekan için özel bubble icon oluştur
        markerIcon = await _createSponsorBubbleMarkerIcon(
          venueName: venue.name,
          logoUrl: venue.sponsorLogoUrl,
        );
      } else if (userCheckedIn) {
        markerIcon = _starMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
      } else {
        // 📍 Normal mekanlar = Kategori bazlı custom icon
        markerIcon = await _getMarkerIconForCategory(venue.category);
      }

      // 🚫 5KM FILTER: Don't create markers beyond 5km radius
      if (_currentPosition != null) {
        final userLocation =
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        final distanceToVenue =
            _calculateDistance(userLocation, venue.location);

        if (distanceToVenue > _maxDistance) {
          return markers; // Exit early for this venue
        }
      }

      markers.add(Marker(
        markerId: MarkerId(venue.id),
        position: venue.location,
        icon: markerIcon,
        onTap: () => _showVenueDetails(venue),
      ));

      currentMarkerCount++; // Marker sayısını güncelle

      // ⚡ MICRO-YIELD: Keep UI responsive
      if (markers.length % 3 == 0) {
        await Future.delayed(const Duration(microseconds: 1));
      }
    }

    return markers;
  }

  // ASYNC MARKER CREATION - Aggressive yielding for smoothness
  Widget _buildCheckedInUsersList(Venue venue) {
    final users = _venueCheckIns[venue.id] ?? [];

    // Update venue user count
    _venueUserCounts[venue.id] = users.length;

    // Create a new venue with updated checked in users for the component
    final updatedVenue = Venue(
      id: venue.id,
      placeId: venue.placeId,
      name: venue.name,
      category: venue.category,
      location: venue.location,
      rating: venue.rating,
      vicinity: venue.vicinity,
      isFavorite: venue.isFavorite,
      mayorUserId: venue.mayorUserId,
      mayorName: venue.mayorName,
      mayorPhoto: venue.mayorPhoto,
      mayorCheckIns: venue.mayorCheckIns,
      mayorDiamonds: venue.mayorDiamonds,
      checkedInUsers: users,
      totalCheckIns: venue.totalCheckIns,
      logoUrl: venue.logoUrl,
      closingTime: venue.closingTime,
      openingTime: venue.openingTime,
      photos: venue.photos,
    );

    return CheckedInUsersList(
      venue: updatedVenue,
      canSeeUsers: _isPremium || users.isNotEmpty,
      sentChatRequestUserIds: _sentChatRequestUserIds,
      isPremium: _isPremium,
      onHandleChatRequest: (String userId, String userName,
          {bool isSuper = false}) {
        _handleChatRequest(userId, userName, isSuper: isSuper);
      },
      getTimeAgo: _getTimeAgo,
      onShowOverlayMessage: _showAlreadyLikedMessage,
    );
  }

  void _showSuccessMessage(String message) {
    // Venue details sheet açıksa overlay mesaj göster, kapalıysa SnackBar kullan
    if (_isVenueDetailsOpen) {
      _showLikeOverlayMessage(isSuper: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    // Venue details sheet açıksa overlay mesaj göster, kapalıysa SnackBar kullan
    if (_isVenueDetailsOpen) {
      _showAlreadyLikedMessage(message: message, isSuper: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Premium bottom sheet göster
  void _showPremiumBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        // 🔧 SAFE AREA: Premium bottom sheet wrapper
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: PremiumSubscriptionWidget(
                  onPurchaseSuccess: (type) {
                    Navigator.pop(context);
                    _onPremiumPurchaseSuccess(type);
                  },
                  onError: (error) {
                    _onPremiumPurchaseError(error);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Premium satın alma başarılı
  void _onPremiumPurchaseSuccess(PremiumSubscriptionType type) {
    // Premium durumunu hemen güncelle
    _safeSetState(() {
      _isPremium = true;
    });

    // Cache'i temizle ve yeni veriyi yükle
    _lastDataRefresh = null;
    _loadUserData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.white),
            const SizedBox(width: 8),
            Text('${type.displayName} başarıyla aktive edildi! 🌟'),
          ],
        ),
        backgroundColor: AppColors.premium,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Premium satın alma hatası
  void _onPremiumPurchaseError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Premium satın alma hatası: $error')),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Elmas satın alma bottom sheet'ini göster
  Future<void> _showPurchaseDiamondsBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        // 🔧 SAFE AREA: Diamond purchase sheet wrapper
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle çubuğu
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withOpacity(0.2),
                                  AppColors.primaryLight.withOpacity(0.1)
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.diamond,
                                color: AppColors.primary, size: 28),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Elmas Satın Al',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          // tek renk olsun gradiyent yerine

                          color: AppColors.primary.withOpacity(0.15),
                          // gradient: LinearGradient(
                          //   colors: [AppColors.primary.withOpacity(0.15), AppColors.primaryLight.withOpacity(0.1)],
                          //   begin: Alignment.centerLeft,
                          //   end: Alignment.centerRight,
                          // ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet,
                                color: AppColors.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Mevcut Bakiye',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.grey600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_userDiamondBalance 💎',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Refresh butonu
                            IconButton(
                              onPressed: _loadUserDiamondBalance,
                              icon: Icon(
                                Icons.refresh,
                                color: AppColors.primary.withOpacity(0.7),
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Horizontal Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
                    child: Row(
                      children: [
                        // IAPConfig'den elmas paketlerini al
                        ...IAPConfig.diamondPackages
                            .asMap()
                            .entries
                            .map((entry) {
                          final index = entry.key;
                          final package = entry.value;

                          // Icon ve renk ayarları
                          final icons = ['⚡', '🏆', '💎', '🌟', '👑', '🔥'];
                          final colors = [
                            AppColors.primaryLight,
                            AppColors.primary,
                            AppColors.primaryDark,
                            Colors.purple,
                            Colors.orange,
                            Colors.deepPurple,
                          ];

                          return Padding(
                            padding: EdgeInsets.only(
                              right:
                                  index < IAPConfig.diamondPackages.length - 1
                                      ? 14.0
                                      : 20.0,
                            ),
                            child: _buildDiamondPackageCard(
                              title:
                                  '${icons[index % icons.length]} ${package['title']}',
                              diamonds: package['quantity'],
                              price: package['originalPrice'],
                              description: package['description'],
                              color: colors[index % colors.length],
                              gradientIntensity: 0.1 + (index * 0.1),
                              onTap: () =>
                                  _handleDiamondPurchase(package['quantity']),
                              isPopular: package['isPopular'] ?? false,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ), // 🔧 SAFE AREA: Close Container
        ), // 🔧 SAFE AREA: Close DraggableScrollableSheet
      ), // 🔧 SAFE AREA: Close SafeArea wrapper
    ); // 🔧 SAFE AREA: Close showModalBottomSheet
  }

  /// Elmas paketi kartı oluştur
  Widget _buildDiamondPackageCard({
    required String title,
    required int diamonds,
    required double price,
    required String description,
    required Color color,
    required VoidCallback onTap,
    double gradientIntensity = 0.1,
    bool isPopular = false,
  }) {
    return Stack(
      children: [
        Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.8), // Daha koyu arka plan
                color.withOpacity(0.6) // Daha koyu gradient
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPopular
                  ? AppColors.premium
                  : color.withOpacity(0.8), // Border da koyulaştırıldı
              width: isPopular ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white, // Hep beyaz yapıldı
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70, // Hep beyaz70 yapıldı
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$diamonds 💎',
                            style: const TextStyle(
                              fontSize: 22, // Biraz büyütüldü
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  // Gölge eklendi - daha okunabilir
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 2.0,
                                  color: Colors.black26,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₺${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18, // Biraz büyütüldü
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  // Gölge eklendi - daha okunabilir
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 2.0,
                                  color: Colors.black26,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Satın Al Butonu
                  Container(
                    width: double.infinity,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart,
                              color: color,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Satın Al',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Popular badge
        if (isPopular)
          Positioned(
            top: -8,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.premium,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.premium.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'EN POPÜLER',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Elmas satın alma başarılı (Firebase'e ekleme)
  Future<void> _onDiamondPurchaseSuccess(int diamondAmount) async {
    try {
      // Firebase'e elmas ekle
      final success = await _muhtarService.addUserDiamonds(diamondAmount);

      if (success) {
        // Bakiyeyi yenile
        await _loadUserDiamondBalance();

        // Başarı mesajı
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.diamond, color: Colors.white),
                const SizedBox(width: 8),
                Text('$diamondAmount elmas başarıyla satın alındı! 💎'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        _onDiamondPurchaseError('Firebase\'e elmas eklenemedi');
      }
    } catch (e) {
      _onDiamondPurchaseError('Elmas ekleme işlemi başarısız: $e');
    }
  }

  /// Asıl diamond purchase işlemini handle et (Artık kullanılmıyor - GooglePayButton direkt çalışıyor)
  Future<void> _handleDiamondPurchase(int diamondAmount) async {
    // Direkt IAP ile satın alma (Google Pay yok)
    String? productId;
    switch (diamondAmount) {
      case 10:
        productId = 'diamonds_10';
        break;
      case 50:
        productId = 'diamonds_50';
        break;
      case 100:
        productId = 'diamonds_100';
        break;
      case 250:
        productId = 'diamonds_250';
        break;
      case 500:
        productId = 'diamonds_500';
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geçersiz elmas paketi'),
            backgroundColor: Colors.red,
          ),
        );
        return;
    }

    try {
      final success = await IAPService().buyProduct(
        productId,
        onSuccess: () {
          if (!mounted) return;

          // Bakiyeyi yenile
          _loadUserDiamondBalance();

          // Bottom sheet'i kapat
          Navigator.pop(context);

          // Başarı mesajı
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('$diamondAmount Elmas satın alındı! 💎'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        },
        onError: (error) {
          if (!mounted) return;

          _onDiamondPurchaseError(error);
        },
      );
    } catch (e) {
      if (!mounted) return;

      _onDiamondPurchaseError(e.toString());
    }
  }

  /// Elmas satın alma hatası
  void _onDiamondPurchaseError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Satın alma hatası: $error')),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Toplam super like sayısını al
  // REMOVED: Super Like counter no longer needed with Chat Request system

  /// 💕 Like/Super Like İşleyici
  // CHAT REQUEST HANDLER - Opens modal for normal or super chat
  Future<void> _handleChatRequest(String userId, String userName,
      {bool isSuper = false}) async {
    // Show chat request modal (handles all validation internally)
    final result = await showChatRequestModal(
      context: context,
      targetUserId: userId,
      targetUserName: userName,
      isSuperChat: isSuper,
    );

    if (result == true) {
      // Show success message
      _showSuccessMessage(isSuper
          ? '⭐ Süper sohbet isteği gönderildi!'
          : '💬 Sohbet isteği gönderildi!');

      // Track sent request locally
      _safeSetState(() {
        _sentChatRequestUserIds.add(userId);
      });
    }
  }

  // REMOVED: Validation error handler for old Like system

  /// Super Like satın alma panelini göster
  // REMOVED: Super Like/Super Chat purchase methods - IAP system handles this separately
  // Super Chat will be purchased through standard IAP flow, not through these methods

  /// 💕 Time ago formatter
  String _getTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Az önce';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dakika önce';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} saat önce';
    } else {
      return '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

// 🎭 CHECK-IN DIALOG WIDGET
class _CheckInDialogWidget extends StatefulWidget {
  final Venue venue;
  final Future<void> Function() onCheckInWithoutPhoto;
  final Future<void> Function() onCheckInWithPhoto;
  final VoidCallback onDialogClosed;

  const _CheckInDialogWidget({
    required this.venue,
    required this.onCheckInWithoutPhoto,
    required this.onCheckInWithPhoto,
    required this.onDialogClosed,
  });

  @override
  State<_CheckInDialogWidget> createState() => _CheckInDialogWidgetState();
}

class _CheckInDialogWidgetState extends State<_CheckInDialogWidget> {
  bool _isProcessing = false;
  bool _isCompleted = false; // Prevent multiple completion calls

  void _performCheckInWithoutPhoto() async {
    if (_isProcessing || _isCompleted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.onCheckInWithoutPhoto();

      // Check-in başarılı oldu, dialog'u kapat
      if (mounted && !_isCompleted) {
        _isCompleted = true;
        Navigator.of(context).pop();
        widget.onDialogClosed();
      } else {}
    } catch (e) {
      // Hata durumunda da dialog'u kapat
      if (mounted && !_isCompleted) {
        _isCompleted = true;
        Navigator.of(context).pop();
        widget.onDialogClosed();
      }
    }
  }

  void _performCheckInWithPhoto() async {
    if (_isProcessing || _isCompleted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.onCheckInWithPhoto();

      // Check-in başarılı oldu, dialog'u kapat
      if (mounted && !_isCompleted) {
        _isCompleted = true;
        Navigator.of(context).pop();
        widget.onDialogClosed();
      }
    } catch (e) {
      // Hata durumunda da dialog'u kapat
      if (mounted && !_isCompleted) {
        _isCompleted = true;
        Navigator.of(context).pop();
        widget.onDialogClosed();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isProcessing ? 'Check-in Yapılıyor...' : 'Check-in Türü Seçin',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _performCheckInWithoutPhoto,
                      icon:
                          const Icon(Icons.location_on, color: AppColors.white),
                      label: const Text(
                        'Fotoğrafsız',
                        style: TextStyle(color: AppColors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _performCheckInWithPhoto,
                      icon:
                          const Icon(Icons.camera_alt, color: AppColors.white),
                      label: const Text(
                        'Fotoğraflı',
                        style: TextStyle(color: AppColors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
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
