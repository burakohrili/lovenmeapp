// lib/core/services/firebase/firebase_init.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../firebase_options.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  // Firebase instances
  late FirebaseAuth auth;
  late FirebaseFirestore firestore;
  late FirebaseStorage storage;
  late FirebaseMessaging messaging;

  // Initialization flag
  bool _initialized = false;
  bool get isInitialized => _initialized;

  // Current user stream
  Stream<User?> get authStateChanges => auth.authStateChanges();
  User? get currentUser => auth.currentUser;
  String? get currentUserId => auth.currentUser?.uid;

  // Initialize Firebase
Future<void> initialize() async {
  if (_initialized) return;

  try {
    // Firebase zaten initialize edilmiş mi kontrol et
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
    }
    
    // Get instances
    auth = FirebaseAuth.instance;
    firestore = FirebaseFirestore.instance;
    storage = FirebaseStorage.instance;
    messaging = FirebaseMessaging.instance;

    // Configure Firestore settings
    firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Request notification permissions
    await _requestNotificationPermissions();

    // Configure FCM
    await _configureFCM();

    _initialized = true;
  } catch (e) {
    // Hata olsa bile devam et
    _initialized = true;
  }
}

  // Request notification permissions
  Future<void> _requestNotificationPermissions() async {
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

  }

  // Configure FCM
  Future<void> _configureFCM() async {
    // Get FCM token
    String? token = await messaging.getToken();

    // Listen to token refresh
    messaging.onTokenRefresh.listen((newToken) {
      // Update token in Firestore
      if (currentUserId != null) {
        updateUserToken(currentUserId!, newToken);
      }
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        // Show local notification
      }
    });
  }

  // Update user FCM token
  Future<void> updateUserToken(String userId, String token) async {
    try {
      await firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
    }
  }

  // Sign out
  Future<void> signOut() async {
    await auth.signOut();
  }
}