import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import 'dart:math';
import '../../../core/theme/app_colors.dart';
import 'user_profile_provider.dart';
import 'profile_setup_step6_page.dart';

class ProfileSetupStep5Page extends ConsumerStatefulWidget {
  const ProfileSetupStep5Page({super.key});

  @override
  ConsumerState<ProfileSetupStep5Page> createState() => _ProfileSetupStep5PageState();
}

class _ProfileSetupStep5PageState extends ConsumerState<ProfileSetupStep5Page> 
    with SingleTickerProviderStateMixin {
  late final TextEditingController _emailController;
  final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  
  bool isCodeSent = false;
  bool isVerifying = false;
  bool isResending = false;
  bool canEditEmail = false;
  String generatedCode = '';
  int resendTimer = 60;
  Timer? _timer;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));
    
    _animationController.forward();
    
    final profile = ref.read(userProfileProvider);
    _emailController = TextEditingController(text: profile.email ?? '');
    canEditEmail = profile.email == null || profile.email!.isEmpty;
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email gerekli';
    }
    
    final trimmedEmail = value.trim().toLowerCase();
    
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    );
    
    if (!emailRegex.hasMatch(trimmedEmail)) {
      return 'Geçerli bir email giriniz';
    }
    
    // Yasaklı domain kontrolü
    final blockedDomains = [
      'tempmail.com', 
      'guerrillamail.com', 
      '10minutemail.com',
      'mailinator.com',
      'throwaway.email',
      'yopmail.com'
    ];
    final domain = trimmedEmail.split('@').last;
    if (blockedDomains.contains(domain)) {
      return 'Geçici email adresleri kabul edilmemektedir';
    }
    
    return null;
  }

  // Production: Firebase Functions ile email gönder
  Future<void> _sendEmailViaFirebase(String email, String code) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('sendVerificationEmail');
      
      await callable.call({
        'email': email,
        'code': code,
        'userName': ref.read(userProfileProvider).name ?? 'Kullanıcı',
      });
    } catch (e) {
      throw Exception('Email gönderilemedi. Lütfen tekrar deneyin.');
    }
  }

  // Kod oluştur ve gönder
  Future<void> _generateAndSendCode() async {
    final random = Random();
    generatedCode = (100000 + random.nextInt(900000)).toString();
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Kullanıcı oturumu bulunamadı');
      return;
    }
    
    try {
      final trimmedEmail = _emailController.text.trim().toLowerCase();
      
      // Email benzersizlik kontrolü
      final existingUsers = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: trimmedEmail)
          .limit(1)
          .get();
      
      if (existingUsers.docs.isNotEmpty && 
          existingUsers.docs.first.id != user.uid) {
        _showError('Bu email adresi zaten kullanımda');
        return;
      }
      
      // Firestore'a kodu kaydet
      await FirebaseFirestore.instance
        .collection('email_verifications')
        .doc(user.uid)
        .set({
          'email': trimmedEmail,
          'code': generatedCode,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
          'verified': false,
          'attempts': 0,
          'maxAttempts': 5,
        }, SetOptions(merge: true));
      
      // Production'da gerçek email gönder
      await _sendEmailViaFirebase(trimmedEmail, generatedCode);
      
      setState(() {
        isCodeSent = true;
        resendTimer = 60;
      });
      
      _startResendTimer();
      
      _showSuccess('Doğrulama kodu $trimmedEmail adresine gönderildi');
      
      // İlk input'a focus
      _focusNodes[0].requestFocus();
      
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _sendCode() async {
    final trimmedEmail = _emailController.text.trim();
    final validationResult = _validateEmail(trimmedEmail);
    
    if (validationResult != null) {
      _showError(validationResult);
      return;
    }
    
    ref.read(userProfileProvider.notifier).updateEmail(trimmedEmail);
    
    setState(() {
      canEditEmail = false;
    });
    
    await _generateAndSendCode();
  }

  void _startResendTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (resendTimer > 0) {
          setState(() {
            resendTimer--;
          });
        } else {
          timer.cancel();
        }
      }
    });
  }

  void _resendCode() async {
    if (resendTimer > 0) return;
    
    setState(() {
      isResending = true;
    });
    
    for (var controller in _codeControllers) {
      controller.clear();
    }
    
    await _generateAndSendCode();
    
    setState(() {
      isResending = false;
    });
    
    _focusNodes[0].requestFocus();
  }

  // Kodu doğrula
  void _verifyCode() async {
    String enteredCode = _codeControllers.map((c) => c.text).join();
    
    if (enteredCode.length != 6) {
      _showWarning('Lütfen 6 haneli kodu tam giriniz');
      return;
    }
    
    setState(() {
      isVerifying = true;
    });
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        isVerifying = false;
      });
      _showError('Kullanıcı oturumu bulunamadı');
      return;
    }
    
    try {
      final doc = await FirebaseFirestore.instance
        .collection('email_verifications')
        .doc(user.uid)
        .get();
      
      if (!doc.exists) {
        throw Exception('Doğrulama kodu bulunamadı');
      }
      
      final data = doc.data()!;
      final storedCode = data['code'];
      final attempts = data['attempts'] ?? 0;
      final maxAttempts = data['maxAttempts'] ?? 5;
      final expiresAt = data['expiresAt'];
      
      // Süre kontrolü
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        if (DateTime.now().isAfter(expiry)) {
          setState(() {
            isVerifying = false;
            isCodeSent = false;
          });
          throw Exception('Doğrulama kodunun süresi dolmuş. Yeni kod gönderin.');
        }
      }
      
      // Deneme sayısı kontrolü
      if (attempts >= maxAttempts) {
        setState(() {
          isVerifying = false;
          isCodeSent = false;
        });
        throw Exception('Çok fazla hatalı deneme. Yeni kod gönderin.');
      }
      
      if (enteredCode == storedCode) {
        // Başarılı doğrulama
        await FirebaseFirestore.instance
          .collection('email_verifications')
          .doc(user.uid)
          .update({
            'verified': true,
            'verifiedAt': FieldValue.serverTimestamp(),
          });
        
        // User collection'ını güncelle
        await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'isEmailVerified': true,
            'email': _emailController.text.trim().toLowerCase(),
            'emailVerifiedAt': FieldValue.serverTimestamp(),
          });
        
        ref.read(userProfileProvider.notifier).setEmailVerified(true);
        
        _showSuccess('Email başarıyla doğrulandı! ✅');
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const ProfileSetupStep6Page(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
            ),
          );
        }
      } else {
        // Hatalı kod - deneme sayısını arttır
        await FirebaseFirestore.instance
          .collection('email_verifications')
          .doc(user.uid)
          .update({
            'attempts': FieldValue.increment(1),
            'lastAttemptAt': FieldValue.serverTimestamp(),
          });
        
        setState(() {
          isVerifying = false;
        });
        
        final remainingAttempts = maxAttempts - attempts - 1;
        _showError('Doğrulama kodu hatalı! $remainingAttempts deneme hakkınız kaldı');
        
        for (var controller in _codeControllers) {
          controller.clear();
        }
        _shakeInputs();
        _focusNodes[0].requestFocus();
      }
    } catch (e) {
      setState(() {
        isVerifying = false;
      });
      
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _shakeInputs() {
    HapticFeedback.mediumImpact();
  }

  void _onCodeChanged(String value, int index) {
    if (value.length == 1) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _verifyCode();
      }
    }
  }

  void _onKeyPressed(RawKeyEvent event, int index) {
    if (event is RawKeyDownEvent && 
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _codeControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _codeControllers[index - 1].clear();
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildCodeInput(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 45,
      height: 55,
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(
          _codeControllers[index].text.isNotEmpty ? 0.2 : 0.1
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNodes[index].hasFocus 
              ? AppColors.white 
              : AppColors.white.withOpacity(0.3),
          width: _focusNodes[index].hasFocus ? 2 : 1,
        ),
        boxShadow: _focusNodes[index].hasFocus
            ? [
                BoxShadow(
                  color: AppColors.white.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Center(
        child: RawKeyboardListener(
          focusNode: FocusNode(),
          onKey: (event) => _onKeyPressed(event, index),
          child: TextField(
            controller: _codeControllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: (value) => _onCodeChanged(value, index),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final hasEmail = profile.email != null && profile.email!.isNotEmpty;
    
    return Scaffold(
      backgroundColor: AppColors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryRegisterGradient,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  
                  // Progress Indicator
                  Row(
                    children: List.generate(7, (index) {
                      final isCompleted = index < 5;
                      return Expanded(
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isCompleted 
                                    ? AppColors.white 
                                    : AppColors.white.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (index < 6)
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: 2,
                                  color: isCompleted 
                                      ? AppColors.white 
                                      : AppColors.white.withOpacity(0.3),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Icon
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.white.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.email,
                            size: 50,
                            color: AppColors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Title
                  const Text(
                    'Email Doğrulama',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    '5/7 - Email adresini doğrula',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.white.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Email Input Section
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: !isCodeSent
                        ? _buildEmailInputSection(hasEmail, profile)
                        : _buildCodeVerificationSection(),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Back Button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Geri',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailInputSection(bool hasEmail, UserProfile profile) {
    return Column(
      key: const ValueKey('email-input'),
      children: [
        if (hasEmail && !canEditEmail) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.white.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.email,
                  color: AppColors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kayıtlı Email Adresiniz',
                        style: TextStyle(
                          color: AppColors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.email!,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      canEditEmail = true;
                    });
                  },
                  icon: const Icon(
                    Icons.edit,
                    color: AppColors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
        
        if (!hasEmail || canEditEmail) ...[
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
              labelText: 'Email Adresi',
              labelStyle: TextStyle(color: AppColors.white.withOpacity(0.8)),
              hintText: 'ornek@email.com',
              hintStyle: TextStyle(color: AppColors.white.withOpacity(0.4)),
              prefixIcon: const Icon(Icons.email, color: AppColors.white),
              filled: true,
              fillColor: AppColors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.white, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.error, width: 2),
              ),
            ),
          ),
        ],
        
        const SizedBox(height: 24),
        
        ElevatedButton(
          onPressed: _sendCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonWhite,
            foregroundColor: AppColors.buttonWhiteText,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.send),
              SizedBox(width: 8),
              Text(
                'Doğrulama Kodu Gönder',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeVerificationSection() {
    return Column(
      key: const ValueKey('code-verification'),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.email,
                color: AppColors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _emailController.text,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    isCodeSent = false;
                    canEditEmail = false;
                    for (var controller in _codeControllers) {
                      controller.clear();
                    }
                    _timer?.cancel();
                  });
                },
                icon: const Icon(
                  Icons.edit,
                  color: AppColors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        
        Text(
          'Doğrulama kodunu giriniz',
          style: TextStyle(
            color: AppColors.white.withOpacity(0.9),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 24),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (index) => _buildCodeInput(index)),
        ),
        
        const SizedBox(height: 32),
        
        ElevatedButton(
          onPressed: isVerifying ? null : _verifyCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonWhite,
            foregroundColor: AppColors.buttonWhiteText,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            disabledBackgroundColor: AppColors.buttonDisabled,
          ),
          child: isVerifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.buttonWhiteText,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle),
                    SizedBox(width: 8),
                    Text(
                      'Doğrula',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
        
        const SizedBox(height: 24),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Kod gelmedi mi?',
              style: TextStyle(
                color: AppColors.white.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: resendTimer > 0 || isResending ? null : _resendCode,
              child: isResending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : Text(
                      resendTimer > 0 
                          ? 'Tekrar gönder ($resendTimer)'
                          : 'Tekrar gönder',
                      style: TextStyle(
                        color: resendTimer > 0 
                            ? AppColors.white.withOpacity(0.5)
                            : AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}