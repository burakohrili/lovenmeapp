// lib/core/services/analytics_service.dart

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Ürün olaylarının tek giriş noktası.
///
/// NEDEN VAR:
/// `firebase_analytics` paketi bağımlılıklarda duruyordu ama kod tabanında
/// **tek bir `logEvent` çağrısı yoktu**. Yani "uygulama kullanıcı çekiyor mu"
/// sorusuna cevap verecek hiçbir veri toplanmıyordu.
///
/// Bu artık yalnızca bir ürün konforu değil: App Store Guideline 4.3(b),
/// doymuş kategorilerdeki uygulamalar için "…or do not attract customers"
/// ifadesiyle kullanıcı çekmeyi kuralın parçası hâline getirdi. Ayrıca bir
/// mekana kampanya faturası kesebilmek için "gösterim → check-in → kullanım"
/// hunisinin ölçülmesi gerekiyor.
///
/// Hiçbir çağrı hata fırlatmaz; ölçüm asla kullanıcı akışını bozmamalı.
class AnalyticsService {
  const AnalyticsService._();

  static FirebaseAnalytics get _fa => FirebaseAnalytics.instance;

  static Future<void> _log(String name,
      [Map<String, Object>? params]) async {
    try {
      await _fa.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('Analytics olayi gonderilemedi ($name): $e');
    }
  }

  // --- Çekirdek döngü ---

  static Future<void> checkInCompleted({
    required String venueId,
    required bool withPhoto,
    required bool isNewVenue,
  }) =>
      _log('checkin_completed', {
        'venue_id': venueId,
        'with_photo': withPhoto ? 1 : 0,
        'is_new_venue': isNewVenue ? 1 : 0,
      });

  static Future<void> savedVenueAdded(String venueId) =>
      _log('saved_venue_added', {'venue_id': venueId});

  /// "Gitmek İstiyorum" kaydı gerçek bir ziyaretle kapandı.
  static Future<void> savedVenueClosed(String venueId) =>
      _log('saved_venue_closed', {'venue_id': venueId});

  static Future<void> nudgeShown(String venueId) =>
      _log('nudge_shown', {'venue_id': venueId});

  static Future<void> nudgeTapped(String venueId) =>
      _log('nudge_tapped', {'venue_id': venueId});

  // --- Görev / kampanya hunisi (mekana fatura dayanağı) ---

  static Future<void> questViewed(String questId, String type) =>
      _log('quest_viewed', {'quest_id': questId, 'quest_type': type});

  static Future<void> questJoined(String questId, String type) =>
      _log('quest_joined', {'quest_id': questId, 'quest_type': type});

  static Future<void> questCompleted(String questId, String type) =>
      _log('quest_completed', {'quest_id': questId, 'quest_type': type});

  static Future<void> campaignImpression(String questId, String venueId) =>
      _log('campaign_impression',
          {'quest_id': questId, 'venue_id': venueId});

  static Future<void> campaignCheckIn(String questId, String venueId) =>
      _log('campaign_checkin', {'quest_id': questId, 'venue_id': venueId});

  static Future<void> campaignRedeemed(String questId, String venueId) =>
      _log('campaign_redeemed', {'quest_id': questId, 'venue_id': venueId});

  // --- Sosyal (rızaya dayalı) ---

  static Future<void> friendRequestSent() => _log('friend_request_sent');

  static Future<void> friendAccepted() => _log('friend_accepted');

  // --- Gelir ---

  static Future<void> premiumViewed(String source) =>
      _log('premium_view', {'source': source});

  static Future<void> premiumPurchased(String productId) =>
      _log('premium_purchase', {'product_id': productId});
}
