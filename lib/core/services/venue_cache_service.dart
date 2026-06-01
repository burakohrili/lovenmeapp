import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../presentation/models/venue.dart';

class VenueCacheService {
  static const String _cacheKeyPrefix = 'venue_cache_';
  static const String _cacheTimestamp = 'cache_timestamp_';
  static const String _lastLocationKey = 'last_cache_location';
  static const Duration _cacheExpiry = Duration(hours: 6); // 6 saat cache
  static const double _significantMovementThreshold = 500.0; // 500m hareket = cache invalidation
  
  // Kullanıcı konumuna göre cache key oluştur
  static String _getCacheKey(LatLng location, double radius) {
    // 200m grid sistemi - daha hassas cache
    final latGrid = (location.latitude * 500).round(); // 0.002° = ~200m
    final lngGrid = (location.longitude * 500).round();
    final radiusKey = (radius / 100).round(); // 100m cinsinden
    return '$_cacheKeyPrefix${latGrid}_${lngGrid}_$radiusKey';
  }
  
  // İki konum arası mesafeyi hesapla (metre)
  static double _calculateDistance(LatLng pos1, LatLng pos2) {
    const double earthRadius = 6371000; // metre
    final lat1Rad = pos1.latitude * (math.pi / 180);
    final lat2Rad = pos2.latitude * (math.pi / 180);
    final deltaLatRad = (pos2.latitude - pos1.latitude) * (math.pi / 180);
    final deltaLngRad = (pos2.longitude - pos1.longitude) * (math.pi / 180);

    final a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLngRad / 2) *
            math.sin(deltaLngRad / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
  
  // Son cache konumunu kaydet
  static Future<void> _saveLastLocation(LatLng location) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastLocationKey, '${location.latitude},${location.longitude}');
    } catch (e) {
      // Hata ignore
    }
  }
  
  // Son cache konumunu al
  static Future<LatLng?> _getLastLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationStr = prefs.getString(_lastLocationKey);
      if (locationStr == null) return null;
      
      final parts = locationStr.split(',');
      if (parts.length != 2) return null;
      
      return LatLng(
        double.parse(parts[0]),
        double.parse(parts[1]),
      );
    } catch (e) {
      return null;
    }
  }
  
  // Kullanıcı konumu önemli ölçüde değişti mi kontrol et
  static Future<bool> _hasUserMovedSignificantly(LatLng currentLocation) async {
    final lastLocation = await _getLastLocation();
    if (lastLocation == null) return true; // İlk açılış - cache yok
    
    final distance = _calculateDistance(lastLocation, currentLocation);
    return distance > _significantMovementThreshold;
  }
  
  // Cache'den venue'ları yükle
  static Future<List<Venue>?> getCachedVenues(LatLng location, double radius) async {
    try {
      // 🔥 YENİ: Kullanıcı önemli ölçüde hareket ettiyse cache'i invalidate et
      final hasMoved = await _hasUserMovedSignificantly(location);
      if (hasMoved) {
        print('📍 Kullanıcı 500m+ hareket etti - cache invalidation'); // Debug log
        await clearCache(); // Eski konum cache'ini temizle
        await _saveLastLocation(location); // Yeni konumu kaydet
        return null; // Fresh data çek
      }
      
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(location, radius);
      final timestampKey = '$_cacheTimestamp$cacheKey';
      
      // Cache expire kontrolü
      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) {
        print('📍 Cache yok - fresh data çekiliyor'); // Debug log
        return null;
      }
      
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        // Cache expired - temizle
        print('⏰ Cache expire olmuş - temizleniyor'); // Debug log
        await prefs.remove(cacheKey);
        await prefs.remove(timestampKey);
        return null;
      }
      
      // 🔥 YENİ: Cached venue'ların hala yakında olup olmadığını kontrol et
      final cachedData = prefs.getString(cacheKey);
      if (cachedData == null) return null;
      
      final List<dynamic> venueList = jsonDecode(cachedData);
      final venues = venueList.map((json) => Venue.fromJson(json)).toList();
      
      // Cached venue'ları filtrele - sadece 1km içindekileri al
      final nearbyVenues = venues.where((venue) {
        final distance = _calculateDistance(location, venue.location);
        return distance <= 1000.0; // 1km içindeki venue'lar
      }).toList();
      
      // Eğer cached venue'ların çoğu uzakta kalmışsa cache'i invalidate et
      if (nearbyVenues.length < venues.length * 0.3) { // %30'dan az venue yakındaysa
        print('📍 Cached venue\'lar çok uzakta - cache invalidation (${nearbyVenues.length}/${venues.length})'); // Debug log
        await clearCache();
        return null; // Fresh data çek
      }
      
      print('✅ Cache hit - ${nearbyVenues.length} venue yüklendi'); // Debug log
      return nearbyVenues.isNotEmpty ? nearbyVenues : null;
    } catch (e) {
      print('❌ Cache okuma hatası: $e'); // Debug log
      return null;
    }
  }
  
  // Venue'ları cache'e kaydet
  static Future<void> cacheVenues(LatLng location, double radius, List<Venue> venues) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(location, radius);
      final timestampKey = '$_cacheTimestamp$cacheKey';
      
      // Venue'ları JSON'a çevir
      final venueJsonList = venues.map((venue) => venue.toJson()).toList();
      final jsonString = jsonEncode(venueJsonList);
      
      // Cache'e kaydet
      await prefs.setString(cacheKey, jsonString);
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
      
      // 🔥 YENİ: Son cache konumunu kaydet
      await _saveLastLocation(location);
      
    } catch (e) {
    }
  }
  
  // Cache'i temizle (manuel temizlik için)
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      int clearedCount = 0;
      for (String key in keys) {
        if (key.startsWith(_cacheKeyPrefix) || key.startsWith(_cacheTimestamp)) {
          await prefs.remove(key);
          clearedCount++;
        }
      }
      
      print('🧹 Cache temizlendi: $clearedCount key silindi'); // Debug log
      
    } catch (e) {
      print('❌ Cache temizleme hatası: $e'); // Debug log
    }
  }
  
  // Cache boyutunu kontrol et
  static Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int totalSize = 0;
      
      for (String key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          final data = prefs.getString(key);
          if (data != null) {
            totalSize += data.length;
          }
        }
      }
      
      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}
