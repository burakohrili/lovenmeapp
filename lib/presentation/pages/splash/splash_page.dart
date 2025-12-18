import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/native_auto_login_service.dart';
import '../../../core/theme/app_colors.dart';
import '../auth/login_page.dart';
import '../home/home_page.dart';
import '../onboarding/profile_setup_step1_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> 
    with TickerProviderStateMixin {
  final NativeAutoLoginService _autoLoginService = NativeAutoLoginService();
  late AnimationController _lottieController;
  bool _isAnimationInitialized = false;
  bool _isAuthCheckComplete = false;
  bool _animationPlayedOnce = false;
  AutoLoginResult? _authResult;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _checkAuthState();
  }

  _initializeAnimation() async {
    try {
      _lottieController = AnimationController(
        duration: const Duration(seconds: 3), // 3 saniye animasyon
        vsync: this,
      );
      
      setState(() {
        _isAnimationInitialized = true;
      });
      
      // Animasyon listener'ı ekle
      _lottieController.addStatusListener(_onAnimationStatusChanged);
      
      // Animasyonu başlat
      _lottieController.forward();
    } catch (e) {
      if (kDebugMode) {
      }
      setState(() {
        _isAnimationInitialized = false;
      });
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // Animasyon tamamen oynadı
      setState(() {
        _animationPlayedOnce = true;
      });
      
      if (_isAuthCheckComplete) {
        // Auth işlemler de tamamlandı, yönlendir
        _proceedToNextScreen();
      } else {
        // Auth işlemler henüz tamamlanmadı, animasyonu tekrarla
        if (kDebugMode) {
        }
        _lottieController.reset();
        _lottieController.forward();
      }
    }
  }

  @override
  void dispose() {
    if (_isAnimationInitialized) {
      _lottieController.removeStatusListener(_onAnimationStatusChanged);
      _lottieController.dispose();
    }
    super.dispose();
  }

  _checkAuthState() async {
    if (kDebugMode) {
    }
    
    // Minimum splash süresini bekle (kullanıcı deneyimi için)
    await Future.delayed(const Duration(milliseconds: 1500));
    
    try {
      // Auto-login kontrolü yap (Firebase'e otomatik giriş yapar)
      final result = await _autoLoginService.checkAutoLogin();
      if (kDebugMode) {
      }
      
      _authResult = result;
      
      // Auth işlemler tamamlandı
      setState(() {
        _isAuthCheckComplete = true;
      });
      
      // Video en az bir kez oynadıysa hemen yönlendir
      if (_animationPlayedOnce || !_isAnimationInitialized) {
        _proceedBasedOnAuthResult(result);
      }
      
    } catch (e) {
      if (kDebugMode) {
      }
      setState(() {
        _isAuthCheckComplete = true;
      });
      
      if (_animationPlayedOnce || !_isAnimationInitialized) {
        _navigateToLogin();
      }
    }
  }

  void _proceedToNextScreen() {
    // Bu noktada hem video oynadı hem de auth tamamlandı
    if (_authResult != null) {
      _proceedBasedOnAuthResult(_authResult!);
    } else {
      _navigateToLogin();
    }
  }

  void _proceedBasedOnAuthResult(AutoLoginResult result) async {
    switch (result) {
      case AutoLoginResult.success:
        if (kDebugMode) {
        }
        await _loadUserDataAndNavigate();
        break;
        
      case AutoLoginResult.emailNotVerified:
        if (kDebugMode) {
        }
        _navigateToLogin();
        break;
        
      case AutoLoginResult.disabled:
        if (kDebugMode) {
        }
        _navigateToLogin();
        break;
        
      case AutoLoginResult.failed:
        if (kDebugMode) {
        }
        _navigateToLogin();
        break;
    }
  }

  // Kullanıcı verilerini yükle ve ana sayfaya yönlendir
  Future<void> _loadUserDataAndNavigate() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
        }
        _navigateToLogin();
        return;
      }

      // Firestore'dan kullanıcı bilgilerini al
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists && mounted) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final isProfileComplete = userData['isProfileComplete'] ?? false;
        
        if (kDebugMode) {
        }
        
        if (isProfileComplete) {
          if (kDebugMode) {
          }
          // Ana sayfaya direkt git, izinler HomePage'de istenecek
          await _navigateToMainDirectly();
        } else {
          if (kDebugMode) {
          }
          _navigateToProfileSetup();
        }
      } else {
        if (kDebugMode) {
        }
        _navigateToLogin();
      }
    } catch (e) {
      if (kDebugMode) {
      }
      _navigateToLogin();
    }
  }

  /// Ana sayfaya direkt yönlendir
  Future<void> _navigateToMainDirectly() async {
    try {
      // Kısa bir delay ekle (kullanıcı deneyimi için)
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Ana sayfaya yönlendir
      _navigateToMain();
    } catch (e) {
      if (kDebugMode) {
      }
      // Hata olsa bile ana sayfaya git
      _navigateToMain();
    }
  }

  _navigateToMain() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  _navigateToLogin() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  _navigateToProfileSetup() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ProfileSetupStep1Page()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    
    // Animasyon boyutunu ekran boyutuna göre ayarla
    double animationSize = screenWidth > screenHeight 
        ? screenHeight * 0.8  // Landscape modda yüksekliğe göre
        : screenWidth * 0.8;  // Portrait modda genişliğe göre
    
    // Minimum ve maksimum boyut sınırları
    animationSize = animationSize.clamp(200.0, 400.0);
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primaryLight,
            ],
          ),
        ),
        child: SafeArea(
          child: SizedBox.expand(
            child: _isAnimationInitialized
                ? Center(
                    child: SizedBox(
                      width: animationSize,
                      height: animationSize,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcATop,
                        ),
                        child: Lottie.asset(
                          'assets/animations/love_splash.json',
                          controller: _lottieController,
                          fit: BoxFit.contain, // Animasyonun oranını koru
                          repeat: false, // Tekrar etmesin, biz kontrol edelim
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary,
                          AppColors.primaryLight,
                        ],
                      ),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
