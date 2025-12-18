import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlatformHelper {
  // Platform kontrolleri
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isWeb => kIsWeb;
  
  // iOS specifik kontroller
  static bool get isIOSSimulator {
    if (!isIOS) return false;
    // iOS Simulator'da konum servisleri mock olabilir
    return true; // Bu kısım cihaz bazında test edilmeli
  }
  
  // Google Maps için platform uyumluluğu
  static void checkGoogleMapsCompatibility() {
    if (kDebugMode) {
      
      if (isIOS) {
      }
      
      if (isAndroid) {
      }
    }
  }
  
  // iOS için özel marker ayarları
  static Widget getIOSCompatibleMarkerIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF06292),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.favorite,
        color: Colors.white,
        size: 24,
      ),
    );
  }
  
  // iOS için kamera animasyon ayarları
  static Duration getIOSCameraAnimationDuration() {
    // iOS'ta daha yumuşak animasyonlar için
    return const Duration(milliseconds: 800);
  }
  
  // iOS için zoom seviyeleri
  static double getIOSOptimalZoomLevel() {
    // iOS'ta daha iyi performans için optimize edilmiş zoom
    return 16.0;
  }
}

// iOS Google Maps Test Sınıfı
class IOSGoogleMapsTest {
  static void runDiagnostics() {
    if (kDebugMode && PlatformHelper.isIOS) {
      
      // 1. Platform kontrolü
      
      // 2. API Key kontrolü
      
      // 3. Izin kontrolleri
      
      // 4. Pod kontrolleri
      
      // 5. Test önerileri
      
    }
  }
}
