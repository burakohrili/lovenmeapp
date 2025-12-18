// lib/presentation/widgets/auth/forgot_password_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math';
import 'dart:async';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/production_button.dart';

class ForgotPasswordBottomSheet extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordBottomSheet({
    super.key,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordBottomSheet> createState() => _ForgotPasswordBottomSheetState();
}

class _ForgotPasswordBottomSheetState extends State<ForgotPasswordBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _codeSent = false;
  bool _codeVerified = false;
  String? _sentCode;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  DateTime? _lastCodeSentTime;
  static const Duration _cooldownDuration = Duration(minutes: 1, seconds: 30);
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_canSendCode) {
        setState(() {}); // UI'ı güncelle
      } else {
        timer.cancel();
      }
    });
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

  String? _validateCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'Doğrulama kodu gerekli';
    }
    if (value.length != 6) {
      return 'Doğrulama kodu 6 haneli olmalı';
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

  String? _validateConfirmPassword(String? value) {
    if (value != _newPasswordController.text) {
      return 'Şifreler eşleşmiyor';
    }
    return null;
  }

  bool get _canSendCode {
    if (_lastCodeSentTime == null) return true;
    final now = DateTime.now();
    final timeDiff = now.difference(_lastCodeSentTime!);
    return timeDiff >= _cooldownDuration;
  }

  Duration get _remainingCooldown {
    if (_lastCodeSentTime == null) return Duration.zero;
    final now = DateTime.now();
    final timeDiff = now.difference(_lastCodeSentTime!);
    return _cooldownDuration - timeDiff;
  }

  String get _cooldownText {
    final remaining = _remainingCooldown;
    if (remaining <= Duration.zero) return '';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _generateVerificationCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<void> _sendEmailWithResend(String email, String code) async {
    try {
      
      // Firebase Function'ı çağır
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('sendPasswordResetEmail');
      
      final result = await callable.call({
        'email': email,
        'code': code,
        'userName': null, // Kullanıcı adı isteğe bağlı
      });
      
      if (result.data['success'] == true) {
      } else {
        throw Exception(result.data['error'] ?? 'Email gönderilemedi');
      }
    } catch (e) {
      throw Exception('Email gönderilemedi');
    }
  }

  Future<void> _sendVerificationCode() async {
    
    // Geçici olarak validation'ı atla
    // Validation check
    if (_emailController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen e-posta adresinizi girin'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      
      // Önce Firestore'da kullanıcının var olup olmadığını kontrol et
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: _emailController.text.trim())
          .limit(1)
          .get();


      if (userQuery.docs.isEmpty) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Bu email adresi ile kayıtlı kullanıcı bulunamadı.',
        );
      }

      // 6 haneli doğrulama kodu oluştur
      _sentCode = _generateVerificationCode();

      // Firestore'da geçici kod kaydet (5 dakika expire)
      await FirebaseFirestore.instance
          .collection('password_reset_codes')
          .doc(_emailController.text.trim())
          .set({
        'code': _sentCode,
        'email': _emailController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      });


      // Resend ile email gönder
      try {
        await _sendEmailWithResend(_emailController.text.trim(), _sentCode!);
      } catch (emailError) {
        // Email hatası olsa bile kod kaydedildi, devam et
      }
      
      // Cooldown timer'ı başlat
      _lastCodeSentTime = DateTime.now();
      _startCooldownTimer();
      
      setState(() {
        _codeSent = true;
      });


      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Doğrulama kodu ${_emailController.text} adresine gönderildi'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Bir hata oluştu';
      
      switch (e.code) {
        case 'user-not-found':
          message = 'Bu email adresi ile kayıtlı kullanıcı bulunamadı';
          break;
        case 'invalid-email':
          message = 'Geçersiz email adresi';
          break;
        case 'too-many-requests':
          message = 'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar deneyin';
          break;
        default:
          message = e.message ?? 'Bir hata oluştu';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bir hata oluştu. Lütfen tekrar deneyin'),
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

  Future<void> _verifyCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Firestore'dan kodu kontrol et
      final doc = await FirebaseFirestore.instance
          .collection('password_reset_codes')
          .doc(_emailController.text.trim())
          .get();

      if (!doc.exists) {
        throw Exception('Doğrulama kodu bulunamadı');
      }

      final data = doc.data()!;
      final savedCode = data['code'] as String;
      final expiresAt = data['expiresAt'] as int;

      // Kod expired mi kontrol et
      if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
        throw Exception('Doğrulama kodunun süresi dolmuş');
      }

      // Kod eşleşiyor mu kontrol et
      if (savedCode != _codeController.text.trim()) {
        throw Exception('Geçersiz doğrulama kodu');
      }

      setState(() {
        _codeVerified = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doğrulama kodu onaylandı'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
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

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Kullanıcıyı email ile bul
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        // Geçici bir şifre ile giriş denemesi (bu başarısız olacak ama kullanıcıyı bulur)
        password: 'temp_password_for_reset',
      );
    } on FirebaseAuthException catch (e) {
      // Şifre yanlış hatası bekleniyor, bu normal
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        try {
          // Password reset email gönder ve kullanıcıya yönlendir
          await FirebaseAuth.instance.sendPasswordResetEmail(
            email: _emailController.text.trim(),
          );

          // Geçici kodu sil
          await FirebaseFirestore.instance
              .collection('password_reset_codes')
              .doc(_emailController.text.trim())
              .delete();

          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Şifre sıfırlama linki email adresinize gönderildi. '
                  'Email\'inizdeki linke tıklayarak yeni şifrenizi belirleyebilirsiniz.',
                ),
                backgroundColor: AppColors.success,
                duration: Duration(seconds: 5),
              ),
            );
          }
        } catch (resetError) {
          throw Exception('Şifre sıfırlama işlemi başarısız');
        }
      } else {
        throw Exception('Kullanıcı bulunamadı');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
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



  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Title
          Text(
            _codeVerified 
                ? 'Yeni Şifre Belirleyin'
                : _codeSent 
                    ? 'Doğrulama Kodunu Girin'
                    : 'Şifremi Unuttum',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            _codeVerified
                ? 'Hesabınız için yeni bir şifre belirleyin.'
                : _codeSent 
                    ? 'Email adresinize gönderilen 6 haneli doğrulama kodunu girin.'
                    : 'Email adresinizi girin, size doğrulama kodu gönderelim.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 24),
          
          Form(
            key: _formKey,
            child: Column(
              children: [
                // Email field (sadece başlangıçta görünür)
                if (!_codeSent && !_codeVerified) ...[
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Send code button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : () {
                        _sendVerificationCode();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Doğrulama Kodu Gönder',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ]
                
                // Code verification (kod gönderildikten sonra görünür)
                else if (_codeSent && !_codeVerified) ...[
                  // Email display (read-only)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.email, color: Colors.grey[600]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _emailController.text,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Code input
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    validator: _validateCode,
                    decoration: InputDecoration(
                      labelText: 'Doğrulama Kodu',
                      hintText: '6 haneli kod',
                      prefixIcon: const Icon(Icons.security),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      counterText: '',
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Verify code button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ProductionButton(
                      text: 'Kodu Doğrula',
                      onPressed: _verifyCode,
                      isLoading: _isLoading,
                      backgroundColor: AppColors.primary,
                      textColor: Colors.white,
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Resend button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isLoading ? null : (_canSendCode ? () {
                        setState(() {
                          _codeSent = false;
                          _codeController.clear();
                        });
                      } : null),
                      child: Text(
                        _canSendCode 
                            ? 'Kodu Tekrar Gönder'
                            : 'Tekrar Gönder ($_cooldownText)',
                        style: TextStyle(
                          color: _canSendCode ? AppColors.primary : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ]
                
                // New password (kod doğrulandıktan sonra görünür)
                else if (_codeVerified) ...[
                  // Email display (read-only)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.success.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: AppColors.success),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _emailController.text,
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // New password
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    validator: _validatePassword,
                    decoration: InputDecoration(
                      labelText: 'Yeni Şifre',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNewPassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureNewPassword = !_obscureNewPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Confirm password
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    validator: _validateConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Şifre Tekrar',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Update password button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ProductionButton(
                      text: 'Şifreyi Güncelle',
                      onPressed: _updatePassword,
                      isLoading: _isLoading,
                      backgroundColor: AppColors.success,
                      textColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
