import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/netgsm_sms_service.dart';
import 'user_profile_provider.dart';
import 'profile_setup_step7_page.dart';

class ProfileSetupStep6Page extends ConsumerStatefulWidget {
  const ProfileSetupStep6Page({super.key});

  @override
  ConsumerState<ProfileSetupStep6Page> createState() =>
      _ProfileSetupStep6PageState();
}

class _ProfileSetupStep6PageState extends ConsumerState<ProfileSetupStep6Page> {
  final _phoneController = TextEditingController();
  final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String selectedCountryCode = '+90';
  bool isCodeSent = false;
  bool isVerifying = false;
  bool isResending = false;
  int resendTimer = 60;
  Timer? _timer;

  // Firebase Phone Auth değişkenleri
  String? _verificationId;
  int? _resendToken;

  final List<Map<String, String>> countryCodes = [
    {'name': 'Türkiye', 'code': '+90', 'flag': '🇹🇷'},
    {'name': 'ABD', 'code': '+1', 'flag': '🇺🇸'},
    {'name': 'İngiltere', 'code': '+44', 'flag': '🇬🇧'},
    {'name': 'Almanya', 'code': '+49', 'flag': '🇩🇪'},
    {'name': 'Fransa', 'code': '+33', 'flag': '🇫🇷'},
    {'name': 'İtalya', 'code': '+39', 'flag': '🇮🇹'},
    {'name': 'İspanya', 'code': '+34', 'flag': '🇪🇸'},
    {'name': 'Rusya', 'code': '+7', 'flag': '🇷🇺'},
    {'name': 'Japonya', 'code': '+81', 'flag': '🇯🇵'},
    {'name': 'Çin', 'code': '+86', 'flag': '🇨🇳'},
  ];

  @override
  void initState() {
    super.initState();

    // 🔥 YENİ: Daha önce gönderilmiş SMS kodu var mı kontrol et
    _checkExistingSmsVerification();
  }

  // 🔥 YENİ: Mevcut SMS doğrulama kodunu kontrol et
  Future<void> _checkExistingSmsVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final verificationDoc =
          await _firestore.collection('sms_verifications').doc(user.uid).get();

      if (verificationDoc.exists) {
        final data = verificationDoc.data()!;
        final sentAtTimestamp = data['sentAt'] as Timestamp?;

        if (sentAtTimestamp != null) {
          final sentAt = sentAtTimestamp.toDate();
          final expiresAt = sentAt.add(const Duration(minutes: 10));

          // Kod hala geçerli mi (10 dakika içinde)
          if (DateTime.now().isBefore(expiresAt)) {
            setState(() {
              isCodeSent = true;
              _phoneController.text = (data['phoneNumber'] as String?)
                      ?.replaceFirst(selectedCountryCode, '') ??
                  '';
              // Kalan süreyi hesapla
              final remainingSeconds =
                  expiresAt.difference(DateTime.now()).inSeconds;
              resendTimer = (remainingSeconds % 60).clamp(0, 60);
            });

            _startResendTimer();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Daha önce gönderilen SMS kodu hala geçerli'),
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      // Hata olsa bile devam et
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Telefon numarası gerekli';
    }

    // Sadece rakam kontrolü
    if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
      return 'Sadece rakam giriniz';
    }

    // Ülke koduna göre validasyon
    switch (selectedCountryCode) {
      case '+90': // Türkiye
        if (!value.startsWith('5') || value.length != 10) {
          return '5XX XXX XX XX formatında giriniz (10 hane)';
        }
        break;
      case '+1': // ABD
        if (value.length != 10) {
          return '10 haneli telefon numarası giriniz';
        }
        break;
      case '+44': // İngiltere
        if (value.length < 10 || value.length > 11) {
          return '10-11 haneli telefon numarası giriniz';
        }
        break;
      case '+49': // Almanya
        if (value.length < 10 || value.length > 12) {
          return '10-12 haneli telefon numarası giriniz';
        }
        break;
      default:
        if (value.length < 8 || value.length > 15) {
          return '8-15 haneli telefon numarası giriniz';
        }
    }

    return null;
  }

  // GERÇEK SMS GÖNDERME - NetGSM SMS Service (Firebase telefon kontrolü ile)
  void _sendRealSMS() async {
    final fullPhoneNumber = '$selectedCountryCode${_phoneController.text}';

    // Loading state başlat
    setState(() {
      isCodeSent = true;
    });

    // Önce Firebase'de bu telefon numarası var mı kontrol et
    final phoneExists = await _checkPhoneNumberExists(fullPhoneNumber);

    if (phoneExists) {
      // Telefon numarası zaten kayıtlı
      setState(() {
        isCodeSent = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Bu telefon numarası ($fullPhoneNumber) zaten kayıtlı. Lütfen farklı bir numara deneyin.'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // Telefon numarası yoksa SMS gönder
    await _sendNetGsmSMS(fullPhoneNumber);
  }

  // Firebase'de telefon numarası kontrolü (kendi numarası hariç)
  Future<bool> _checkPhoneNumberExists(String phoneNumber) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final querySnapshot = await _firestore
          .collection('users')
          .where('phone', isEqualTo: phoneNumber)
          .limit(2) // 2 limit (kendisi + başkası varsa)
          .get();

      // 🔥 YENİ: Telefon numarası kullanımda ama kullanıcının KENDİ numarası mı kontrol et
      bool isUsedByOther = false;
      for (var doc in querySnapshot.docs) {
        if (doc.id != currentUser.uid) {
          isUsedByOther = true;
          break;
        }
      }

      return isUsedByOther; // Sadece başkası kullanıyorsa true dön
    } catch (e) {
      // Hata durumunda SMS göndermeye devam et
      return false;
    }
  }

  // NetGSM SMS Gönderme Fonksiyonu
  Future<void> _sendNetGsmSMS(String phoneNumber) async {
    try {
      // NetGSM servisini kullanarak OTP SMS gönder
      final success = await NetGsmSmsService.sendOtpSms(
        phoneNumber,
        customMessage:
            'Lovenme doğrulama kodunuz: {CODE}\n\nBu kodu kimseyle paylaşmayın.',
      );

      if (success) {
        setState(() {
          isCodeSent = true; // Kod girme ekranını göster
          resendTimer = 60;
        });

        _startResendTimer();

        // Provider'a telefonu kaydet
        ref.read(userProfileProvider.notifier).updatePhone(phoneNumber);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ SMS kodu $phoneNumber numarasına gönderildi'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );

        // Kısa bir gecikme sonra ilk input'a focus ver (UI güncellenmesi için)
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _focusNodes[0].requestFocus();
          }
        });
      } else {
        setState(() {
          isCodeSent = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS gönderilemedi. Lütfen tekrar deneyin.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      setState(() {
        isCodeSent = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS gönderilemedi. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 5),
        ),
      );
    }

    /* Firebase SMS geçici olarak deaktif
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        timeout: const Duration(seconds: 60),
        forceResendingToken: null, // İlk gönderim için null
        
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _linkPhoneCredential(credential);
        },
        
        verificationFailed: (FirebaseAuthException e) {
          
          setState(() {
            isCodeSent = false;
          });
          
          String errorMessage = 'SMS gönderilemedi';
          
          switch (e.code) {
            case 'invalid-phone-number':
              errorMessage = 'Geçersiz telefon numarası formatı';
              break;
            case 'too-many-requests':
              errorMessage = 'Çok fazla deneme yapıldı. 24 saat sonra tekrar deneyin';
              break;
            case 'quota-exceeded':
              errorMessage = 'Günlük SMS kotası doldu. Lütfen yarın tekrar deneyin';
              break;
            case 'app-not-authorized':
              errorMessage = 'Uygulama SMS gönderme yetkisine sahip değil. Lütfen geliştiriciyle iletişime geçin';
              break;
            case 'network-request-failed':
              errorMessage = 'İnternet bağlantınızı kontrol edin';
              break;
            case 'captcha-check-failed':
              errorMessage = 'Güvenlik doğrulaması başarısız. Lütfen tekrar deneyin';
              break;
            case 'missing-app-credential':
              errorMessage = 'Uygulama doğrulaması başarısız. Lütfen tekrar deneyin';
              break;
            case 'app-not-verified':
              errorMessage = 'Uygulama doğrulaması gerekli. Lütfen tekrar deneyin';
              break;
            case 'web-context-already-presented':
              errorMessage = 'Doğrulama işlemi devam ediyor. Lütfen bekleyin';
              break;
            case 'web-context-cancelled':
              errorMessage = 'Doğrulama iptal edildi. Tekrar deneyin';
              break;
            default:
              errorMessage = 'SMS gönderilemedi. Lütfen tekrar deneyiniz';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        },
        
        codeSent: (String verificationId, int? resendToken) {
          
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            resendTimer = 60;
          });
          
          _startResendTimer();
          
          // Provider'a telefonu kaydet
          ref.read(userProfileProvider.notifier).updatePhone(fullPhoneNumber);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ SMS kodu $fullPhoneNumber numarasına gönderildi'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // İlk input'a focus ver
          _focusNodes[0].requestFocus();
        },
        
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      
      setState(() {
        isCodeSent = false;
      });
      
      String errorMessage = 'Beklenmeyen hata oluştu';
      
      if (e.toString().contains('network')) {
        errorMessage = 'İnternet bağlantı hatası. Bağlantınızı kontrol edin';
      } else if (e.toString().contains('firebase_core')) {
        errorMessage = 'Firebase bağlantı hatası. Uygulamayı yeniden başlatın';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    */ // Firebase SMS sonu
  }

  // SMS GÖNDER - Retry mekanizması ile
  void _sendCode() async {
    final validation = _validatePhone(_phoneController.text);
    if (validation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // İnternet bağlantısı kontrolü
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      _sendRealSMS();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İnternet bağlantınızı kontrol edin'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // GERÇEK SMS DOĞRULAMA
  void _verifyRealSMS() async {
    String enteredCode = _codeControllers.map((c) => c.text).join();

    if (enteredCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen 6 haneli kodu tam giriniz'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      isVerifying = true;
    });

    try {
      // NetGSM OTP doğrulaması (Cloud Function üzerinden)
      final phoneNumber = '$selectedCountryCode${_phoneController.text}';
      final isValid = await NetGsmSmsService.verifyOtpCode(phoneNumber, enteredCode);

      if (isValid) {
        // Doğrulama başarılı - kullanıcı profilini güncelle ve devam et
        await _savePhoneToProfile(phoneNumber);
      } else {
        setState(() {
          isVerifying = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hatalı doğrulama kodu veya kod süresi dolmuş'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        isVerifying = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Doğrulama kodu hatalı. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
        ),
      );

      // Kod alanlarını temizle
      for (var controller in _codeControllers) {
        controller.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }

  // TELEFON BİLGİSİNİ PROFİLE KAYDET (NetGSM için)
  Future<void> _savePhoneToProfile(String phoneNumber) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Firestore'a telefon numarasını kaydet
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'phone': phoneNumber,
          'isPhoneVerified': true,
          'phoneVerifiedAt': FieldValue.serverTimestamp(),
          'phoneVerificationMethod':
              'netgsm', // netgsm ile doğrulandığını belirt
        });

        ref.read(userProfileProvider.notifier).setPhoneVerified(true);

        setState(() {
          isVerifying = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telefon başarıyla doğrulandı! ✅'),
            backgroundColor: AppColors.success,
          ),
        );

        // Sonraki adıma geç
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileSetupStep7Page(),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        isVerifying = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil güncellenemedi. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // TELEFON CREDENTIAL'I BAĞLA
  Future<void> _linkPhoneCredential(PhoneAuthCredential credential) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Telefonu kullanıcıya bağla
        await user.linkWithCredential(credential);

        // Firestore'a telefon numarasını kaydet
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'phone': '$selectedCountryCode${_phoneController.text}',
          'isPhoneVerified': true,
          'phoneVerifiedAt': FieldValue.serverTimestamp(),
        });

        ref.read(userProfileProvider.notifier).setPhoneVerified(true);

        setState(() {
          isVerifying = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telefon başarıyla doğrulandı! ✅'),
            backgroundColor: AppColors.success,
          ),
        );

        // Sonraki adıma geç
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileSetupStep7Page(),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        isVerifying = false;
      });

      if (e.toString().contains('credential-already-in-use')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu telefon numarası zaten kullanımda'),
            backgroundColor: AppColors.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil kaydedilemedi. Lütfen tekrar deneyiniz.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // FIRESTORE'A TELEFON NUMARASINI KAYDET
  Future<void> _updatePhoneInFirestore(String phoneNumber) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'phone': phoneNumber,
          'isPhoneVerified': true,
          'phoneVerifiedAt': FieldValue.serverTimestamp(),
        });

        ref.read(userProfileProvider.notifier).setPhoneVerified(true);
      }
    } catch (e) {
      rethrow;
    }
  }

  // DOĞRULA
  void _verifyCode() {
    _verifyRealSMS();
  }

  // TEKRAR GÖNDER
  void _resendCode() async {
    if (resendTimer > 0) return;

    setState(() {
      isResending = true;
    });

    // Kod alanlarını temizle
    for (var controller in _codeControllers) {
      controller.clear();
    }

    _sendCode();

    setState(() {
      isResending = false;
    });
  }

  void _startResendTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendTimer > 0) {
        setState(() {
          resendTimer--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _onCodeChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    // Tüm alanlar doluysa otomatik doğrula
    bool allFilled = _codeControllers.every((c) => c.text.length == 1);
    if (allFilled) {
      _verifyCode();
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

  Widget _buildCodeInput(int index) {
    return Container(
      width: 45,
      height: 55,
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNodes[index].hasFocus
              ? AppColors.white
              : AppColors.white.withOpacity(0.3),
          width: _focusNodes[index].hasFocus ? 2 : 1,
        ),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // Progress Indicator (6/7)
                Row(
                  children: List.generate(7, (index) {
                    final isCompleted = index < 6;
                    return Expanded(
                      child: Row(
                        children: [
                          Container(
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
                              child: Container(
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
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone_android,
                    size: 50,
                    color: AppColors.white,
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                const Text(
                  'Telefon Doğrulama',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                Text(
                  '6/7 - Telefon numaranı doğrula',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.white.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Phone Input Section
                if (!isCodeSent) ...[
                  // Country Code Selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.white.withOpacity(0.3),
                      ),
                    ),
                    child: DropdownButton<String>(
                      value: selectedCountryCode,
                      isExpanded: true,
                      dropdownColor: AppColors.primary,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: AppColors.white),
                      underline: const SizedBox(),
                      style:
                          const TextStyle(color: AppColors.white, fontSize: 16),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedCountryCode = newValue!;
                        });
                      },
                      items:
                          countryCodes.map<DropdownMenuItem<String>>((country) {
                        return DropdownMenuItem<String>(
                          value: country['code'],
                          child: Row(
                            children: [
                              Text(country['flag']!,
                                  style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Text('${country['name']} ${country['code']}'),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Phone Input
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: selectedCountryCode == '+90' ? 10 : 15,
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      labelText: 'Telefon Numarası',
                      labelStyle:
                          TextStyle(color: AppColors.white.withOpacity(0.8)),
                      hintText: selectedCountryCode == '+90'
                          ? '5XX XXX XX XX'
                          : 'Phone number',
                      hintStyle:
                          TextStyle(color: AppColors.white.withOpacity(0.5)),
                      prefixIcon:
                          const Icon(Icons.phone, color: AppColors.white),
                      prefixText: '$selectedCountryCode ',
                      prefixStyle: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      counterStyle:
                          TextStyle(color: AppColors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: AppColors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.white.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.white.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.white, width: 2),
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),

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
                    ),
                    child: const Text(
                      'SMS Kodu Gönder',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...[
                  // Code Verification Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.phone_android,
                              color: AppColors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$selectedCountryCode ${_phoneController.text}',
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
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'SMS kodunu giriniz',
                    style: TextStyle(
                      color: AppColors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // Code Input Fields
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children:
                        List.generate(6, (index) => _buildCodeInput(index)),
                  ),

                  const SizedBox(height: 32),

                  // Verify Button
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
                        : const Text(
                            'Doğrula',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),

                  const SizedBox(height: 24),

                  // Resend Code
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
                        onPressed: resendTimer > 0 ? null : _resendCode,
                        child: Text(
                          resendTimer > 0
                              ? 'Tekrar gönder ($resendTimer)'
                              : 'Tekrar gönder',
                          style: TextStyle(
                            color: resendTimer > 0
                                ? AppColors.white.withOpacity(0.5)
                                : AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 40),

                // Info Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.white.withOpacity(0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'SMS kodunuz birkaç saniye içinde gelecek',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Telefon doğrulama atla butonu - her zaman göster
                // OutlinedButton(
                //   onPressed: () {
                //     // Provider'da telefon doğrulandı olarak işaretle
                //     ref.read(userProfileProvider.notifier).setPhoneVerified(true);

                //     Navigator.pushReplacement(
                //       context,
                //       MaterialPageRoute(
                //         builder: (context) => const ProfileSetupStep7Page(),
                //       ),
                //     );
                //   },
                //   style: OutlinedButton.styleFrom(
                //     foregroundColor: AppColors.white,
                //     side: BorderSide(color: AppColors.white.withOpacity(0.5)),
                //     padding: const EdgeInsets.symmetric(vertical: 12),
                //     shape: RoundedRectangleBorder(
                //       borderRadius: BorderRadius.circular(12),
                //     ),
                //   ),
                //   child: const Text(
                //     'Şimdilik Atla',
                //     style: TextStyle(
                //       fontSize: 16,
                //       fontWeight: FontWeight.w500,
                //     ),
                //   ),
                // ),

                const SizedBox(height: 16),

                // PRODUCTION: Atla butonu yok

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
    );
  }
}
