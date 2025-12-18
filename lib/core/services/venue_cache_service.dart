import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../presentation/models/venue.dart';

class VenueCacheService {
  static const String _cacheKeyPrefix = 'venue_cache_';
  static const String _cacheTimestamp = 'cache_timestamp_';
  static const Duration _cacheExpiry = Duration(hours: 6); // 6 saat cache
  
  // Kullanıcı konumuna göre cache key oluştur
  static String _getCacheKey(LatLng location, double radius) {
    // 1km grid sistemi - daha geniş cache alanı
    final latGrid = (location.latitude * 100).round(); // 0.01° = ~1km
    final lngGrid = (location.longitude * 100).round();
    final radiusKey = (radius / 1000).round(); // km cinsinden
    return '$_cacheKeyPrefix${latGrid}_${lngGrid}_$radiusKey';
  }
  
  // Cache'den venue'ları yükle
  static Future<List<Venue>?> getCachedVenues(LatLng location, double radius) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(location, radius);
      final timestampKey = '$_cacheTimestamp$cacheKey';
      
      // Cache expire kontrolü
      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) return null;
      
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        // Cache expired - temizle
        await prefs.remove(cacheKey);
        await prefs.remove(timestampKey);
        return null;
      }
      
      // Cache'den veri oku
      final cachedData = prefs.getString(cacheKey);
      if (cachedData == null) return null;
      
      final List<dynamic> venueList = jsonDecode(cachedData);
      final venues = venueList.map((json) => Venue.fromJson(json)).toList();
      
      return venues;
    } catch (e) {
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
      
    } catch (e) {
    }
  }
  
  // Cache'i temizle (manuel temizlik için)
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (String key in keys) {
        if (key.startsWith(_cacheKeyPrefix) || key.startsWith(_cacheTimestamp)) {
          await prefs.remove(key);
        }
      }
      
    } catch (e) {
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
