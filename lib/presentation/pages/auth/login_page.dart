import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/native_auto_login_service.dart';
import '../home/home_page.dart';
import '../onboarding/user_profile_provider.dart';
import 'register_page.dart';
import '../onboarding/profile_setup_step1_page.dart';
import '../../widgets/auth/forgot_password_bottom_sheet.dart';
import '../../widgets/common/app_logo_widget.dart';
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final NativeAutoLoginService _autoLoginService = NativeAutoLoginService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  // _rememberMe kaldırıldı - artık her zaman otomatik giriş aktif

  @override
  void initState() {
    super.initState();
    // Auto-login için email'i önceden doldurma - kaldırıldı
    // _loadSavedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email gerekli';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Geçerli bir email giriniz';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Şifre gerekli';
    }
    if (value.length < 6) {
      return 'Şifre en az 6 karakter olmalı';
    }
    return null;
  }

  // GERÇEK FIREBASE LOGIN
  Future<void> _handleFirebaseLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Firebase Authentication ile giriş yap
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (userCredential.user != null) {
        // Otomatik giriş bilgilerini kaydet (her zaman aktif)
        await _autoLoginService.setRememberMe(
          true, // Her zaman true - otomatik giriş aktif
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        // Firestore'dan kullanıcı bilgilerini al
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();

        if (userDoc.exists) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          
          // Profil tamamlanma durumunu kontrol et
          bool isProfileComplete = userData['isProfileComplete'] ?? false;
          
          // Provider'a kullanıcı bilgilerini yükle
          _loadUserDataToProvider(userData);
          
          if (mounted) {
            if (isProfileComplete) {
              // Profil tamamsa HomePage'e git (Map sayfası)
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomePage(), // Default index (Map page)
                ),
              );
            } else {
              // Profil eksikse Onboarding'e yönlendir
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Profilini tamamlaman gerekiyor'),
                  backgroundColor: AppColors.warning,
                ),
              );
              
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileSetupStep1Page(),
                  settings: const RouteSettings(name: '/profile-setup-step1'),
                ),
                (route) => false,
              );
            }
          }
        } else {
          // Kullanıcı dokümanı yoksa oluştur ve onboarding'e yönlendir
          await _createUserDocument(userCredential.user!);
          
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfileSetupStep1Page(),
                settings: const RouteSettings(name: '/profile-setup-step1'),
              ),
              (route) => false,
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = '';
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'Bu email ile kayıtlı kullanıcı bulunamadı';
          break;
        case 'wrong-password':
          errorMessage = 'Hatalı şifre';
          break;
        case 'invalid-email':
          errorMessage = 'Geçersiz email formatı';
          break;
        case 'user-disabled':
          errorMessage = 'Bu hesap devre dışı bırakılmış';
          break;
        case 'too-many-requests':
          errorMessage = 'Çok fazla başarısız deneme. Lütfen bekleyin';
          break;
        default:
          errorMessage = 'Giriş bilgilerinizi kontrol edip tekrar deneyiniz';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giriş işlemi tamamlanamadı. Lütfen tekrar deneyiniz.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Provider'a kullanıcı bilgilerini yükle
  void _loadUserDataToProvider(Map<String, dynamic> userData) {
    final profileNotifier = ref.read(userProfileProvider.notifier);
    
    // Temel bilgiler
    if (userData['name'] != null && userData['surname'] != null && userData['age'] != null) {
      profileNotifier.updateBasicInfo(
        name: userData['name'],
        surname: userData['surname'],
        age: userData['age'],
      );
    }
    
    // Fotoğraflar
    if (userData['photos'] != null) {
      profileNotifier.updatePhotos(List<String>.from(userData['photos']));
    }
    
    // Hobiler
    if (userData['hobbies'] != null) {
      profileNotifier.updateHobbies(List<String>.from(userData['hobbies']));
    }
    
    // Favori mekanlar
    if (userData['favoriteVenues'] != null) {
      profileNotifier.updateFavoriteVenues(List<String>.from(userData['favoriteVenues']));
    }
    
    // İletişim bilgileri
    if (userData['email'] != null) {
      profileNotifier.updateEmail(userData['email']);
    }
    if (userData['phone'] != null) {
      profileNotifier.updatePhone(userData['phone']);
    }
    
    // Doğrulama durumları
    profileNotifier.setEmailVerified(userData['isEmailVerified'] ?? false);
    profileNotifier.setPhoneVerified(userData['isPhoneVerified'] ?? false);
    
    // Bio
    if (userData['bio'] != null) {
      profileNotifier.updateBio(userData['bio']);
    }
  }

  // Yeni kullanıcı dokümanı oluştur
  Future<void> _createUserDocument(User user) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'uid': user.uid,
      'email': user.email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isProfileComplete': false,
      'isActive': true,
      'isPremium': false,
      'dailyLikesRemaining': 5,
      'superLikesRemaining': 0,
      'dailyRewindsRemaining': 0,
    });
    
    // Provider'a email'i kaydet
    ref.read(userProfileProvider.notifier).updateEmail(user.email ?? '');
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterPage()),
      // MaterialPageRoute(builder: (context) => const ProfileSetupStep5Page()),//for api key authentication testing
    );
  }

  // Şifremi unuttum
  Future<void> _handleForgotPassword() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ForgotPasswordBottomSheet(
        initialEmail: _emailController.text.trim().isNotEmpty 
            ? _emailController.text.trim() 
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height - 
                               MediaQuery.of(context).padding.top - 
                               MediaQuery.of(context).padding.bottom - 48,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo - Responsive animated logo that plays once then freezes on last frame
                        const AppLogoWidget(
                          type: LogoType.staticFinal,
                          heroTag: 'app_logo',
                          responsive: true,
                          minHeight: 220,
                          maxHeight: 350,
                        ),
                        // const Icon(
                        //   Icons.favorite,
                        //   size: 80,
                        //   color: AppColors.white,
                        // ),
                        
                        // Title
                        // const Text(
                        //   'LoveNMe',
                        //   style: TextStyle(
                        //     fontSize: 40,
                        //     fontWeight: FontWeight.bold,
                        //     color: AppColors.white,
                        //     letterSpacing: 1,
                        //   ),
                        //   textAlign: TextAlign.center,
                        // ),
                        // const SizedBox(height: 8),
                        // Text(
                        //   'Mekanında topluluğunu keşfet',
                        //   style: TextStyle(
                        //     fontSize: 16,
                        //     color: AppColors.white.withOpacity(0.8),
                        //   ),
                        //   textAlign: TextAlign.center,
                        // ),
                        
                        const SizedBox(height: 48),
                        
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextFormField(
                            controller: _emailController,
                            validator: _validateEmail,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: AppColors.grey800),
                            
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'ornek@email.com',
                              // errorText: 'Lütfen geçerli bir email giriniz',
                              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                              contentPadding: EdgeInsets.only(bottom:12.0),
                              prefixIcon: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                                child: Icon(Icons.email, color: AppColors.primary),
                              ),
                              border: InputBorder.none,
                              floatingLabelStyle: TextStyle(
                                  color: AppColors.grey600,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                            ),
                          ),
                        ),
                        // Email Field
                        
                        
                        const SizedBox(height: 16),
                        
                        // Password Field
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextFormField(
                            controller: _passwordController,
                            validator: _validatePassword,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: AppColors.grey800),
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              hintText: '******',
                              // errorText: 'Lütfen geçerli bir şifre giriniz',
                              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              contentPadding: const EdgeInsets.only(bottom: 12.0),
                              prefixIcon: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                                child: Icon(Icons.lock, color: AppColors.primary),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  color: AppColors.primary,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: InputBorder.none,
                              floatingLabelStyle: const TextStyle(
                                color: AppColors.grey600,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        
                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _handleForgotPassword,
                            child: Text(
                              'Şifremi Unuttum',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Login Button
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleFirebaseLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.white,
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: AppColors.primary,
                                  )
                                : const Text(
                                    'Giriş Yap',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Divider
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AppColors.white.withOpacity(0.3),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'veya',
                                style: TextStyle(
                                  color: AppColors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AppColors.white.withOpacity(0.3),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Register Button
                        OutlinedButton(
                          onPressed: _navigateToRegister,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: AppColors.white,
                            side: const BorderSide(color: AppColors.white, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Yeni Hesap Oluştur',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Test Buttons Row (Development only)
                        // Row(
                        //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        //   children: [
                        //     // Test User Button
                        //     TextButton.icon(
                        //       onPressed: _isLoading ? null : _createTestUser,
                        //       icon: const Icon(Icons.person_add, color: AppColors.white, size: 18),
                        //       label: Text(
                        //         'Test Kullanıcı',
                        //         style: TextStyle(
                        //           color: AppColors.white.withOpacity(0.7),
                        //           fontSize: 12,
                        //         ),
                        //       ),
                        //     ),
                            
                        //     // Firebase Test Button
                        //     TextButton.icon(
                        //       onPressed: () {
                        //         Navigator.push(
                        //           context,
                        //           MaterialPageRoute(
                        //             builder: (context) => const TestFirebasePage(),
                        //           ),
                        //         );
                        //       },
                        //       icon: const Icon(Icons.bug_report, color: AppColors.white, size: 18),
                        //       label: Text(
                        //         'Firebase Test',
                        //         style: TextStyle(
                        //           color: AppColors.white.withOpacity(0.7),
                        //           fontSize: 12,
                        //         ),
                        //       ),
                        //     ),
                        //   ],
                        // ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Loading Overlay
              if (_isLoading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
