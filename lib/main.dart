import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'presentation/pages/splash/splash_page.dart';
import 'core/services/notification_service.dart';
import 'core/services/iap_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

// Background handler - main fonksiyonunun dışında olmalı
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase zaten başlatılmış mı kontrol et
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  
  // Background'da da local notification göster
  try {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await flutterLocalNotificationsPlugin.initialize(initSettings);
    
    // Notification details
    const androidDetails = AndroidNotificationDetails(
      'lovenme_channel',
      'LoveNMe Notifications',
      channelDescription: 'Notifications for LoveNMe app',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      enableLights: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? 'LoveNMe',
      message.notification?.body ?? 'Yeni bildirim',
      details,
      payload: message.data.toString(),
    );
  } catch (e) {
    // Notification error - production mode
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Firebase'i sadece bir kez başlat
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    
    // Firebase App Check'i aktifleştir (Production)
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttest,
      webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),
    );
    
    // Background notification handler'ı kaydet
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    
    // Bildirim servisini başlat - ZORUNLU ve SENKRON
    try {
      await NotificationService().initialize();
    } catch (e) {
      // Hata olsa bile devam et ama yeniden dene
      Timer(const Duration(seconds: 3), () async {
        try {
          await NotificationService().initialize();
        } catch (e2) {
          // Üçüncü deneme
          Timer(const Duration(seconds: 5), () async {
            try {
              await NotificationService().initialize();
            } catch (e3) {
              // Final attempt failed
            }
          });
        }
      });
    }
    
    // Crashlytics'i başlat
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    
  } catch (e) {
    // Firebase initialization error
  }

  // In-App Purchase servisini başlat (Firebase'den bağımsız)
  try {
    await IAPService().initialize();
  } catch (e) {
    // IAP service error
  }

  // Asenkron hataları da Crashlytics'e gönder
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoveNMe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      home: const SplashPage(), // Normal splash page akışı
      // Alternatif olarak gelişmiş video splash sistemi:
      // home: SplashDecisionManager(
      //   nextScreen: const SplashPage(),
      //   showOnlyFirstTime: true, // İlk açılışta video göster
      // ),
    );
  }
}