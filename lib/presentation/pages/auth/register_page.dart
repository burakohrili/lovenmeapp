import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/form_validation_helper.dart';
import '../../../core/utils/loading_state_manager.dart';
import '../../../widgets/production_button.dart';
import '../onboarding/profile_setup_step1_page.dart';
import '../onboarding/user_profile_provider.dart';
import '../../widgets/legal/legal_document_bottom_sheet.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _loadingManager = LoadingStateManager();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;

  // Real-time validation states
  PasswordValidationResult? _passwordValidation;

  @override
  void initState() {
    super.initState();

    // Real-time validation listeners
    _emailController.addListener(_validateEmailRealTime);
    _passwordController.addListener(_validatePasswordRealTime);
    _confirmPasswordController.addListener(_validateConfirmPasswordRealTime);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _loadingManager.dispose();
    FormValidationHelper.dispose();
    super.dispose();
  }

  void _validateEmailRealTime() {
    // Real-time validation kaldırıldı - sadece form submit'te validasyon
  }

  void _validatePasswordRealTime() {
    FormValidationHelper.debounceValidation(onValidate: () {
      setState(() {
        _passwordValidation =
            FormValidationHelper.validatePassword(_passwordController.text);
      });
    });
  }

  void _validateConfirmPasswordRealTime() {
    // Real-time validation kaldırıldı - sadece form submit'te validasyon
  }

  String? _validateEmail(String? value) {
    return FormValidationHelper.validateEmail(value);
  }

  String? _validatePassword(String? value) {
    // Sadece temel kontroller - minimum uzunluk
    if (value == null || value.isEmpty) {
      return 'Şifre gerekli';
    }
    if (value.length < 6) {
      return 'Şifre en az 6 karakter olmalı';
    }
    // Gücü register butonunda kontrol edeceğiz
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    return FormValidationHelper.validateConfirmPassword(
        value, _passwordController.text);
  }

  // FIREBASE İLE KAYIT
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    // Şifre gücü kontrolü - En az "fair" seviyesi gerekli
    if (_passwordValidation == null || _passwordValidation!.score < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _passwordValidation?.error ??
                'Şifre çok zayıf. Lütfen daha güçlü bir şifre seçin.',
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanım koşullarını kabul etmelisiniz'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      await _loadingManager.executeOperation(
        LoadingOperations.register,
        () async {
          // Firebase Authentication ile kullanıcı oluştur
          UserCredential userCredential =
              await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

          if (userCredential.user != null) {
            // Firestore'a temel kullanıcı kaydı oluştur
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userCredential.user!.uid)
                .set({
              'uid': userCredential.user!.uid,
              'email': _emailController.text.trim(),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'isProfileComplete': false,
              'isActive': true,
              'isPremium': false,
              'dailyLikesRemaining': 5,
              'superLikesRemaining': 0,
              'dailyRewindsRemaining': 0,
              // Muhtar sistemi için elmas sayısı
              'diamonds': 0, //
              'diamondCount': 0, // Backup field
              'totalDiamondsEarned': 0,
              'totalDiamondsSpent': 0,
              // Platform bilgisi
              'platform': 'mobile',
              'deviceType': Theme.of(context).platform.name,
            });

            // Email doğrulama gönder
            await userCredential.user!.sendEmailVerification();

            // Provider'a email'i kaydet
            ref
                .read(userProfileProvider.notifier)
                .updateEmail(_emailController.text.trim());

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kayıt başarılı! Profilini tamamla.'),
                  backgroundColor: AppColors.success,
                ),
              );

              // Onboarding'e yönlendir (ProfileSetupStep1Page)
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
        },
        onError: (error) {
          String errorMessage = '';

          if (error.contains('weak-password')) {
            errorMessage = 'Şifre çok zayıf';
          } else if (error.contains('email-already-in-use')) {
            // 🔥 YENİ: Email kullanımda hatası için daha açıklayıcı mesaj
            errorMessage =
                'Bu email adresi zaten kayıtlı. Lütfen giriş yapın veya şifrenizi sıfırlayın.';
          } else if (error.contains('invalid-email')) {
            errorMessage = 'Geçersiz email formatı';
          } else {
            errorMessage =
                'Kayıt hatası: ${error.replaceAll('Exception: ', '')}';
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 5), // 🔥 5 saniye göster
              ),
            );
          }
        },
      );
    } catch (e) {
      // Error already handled in executeOperation
    }
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Back Button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back,
                              color: AppColors.white),
                        ),
                      ),

                      // Logo
                      // const Icon(
                      //   Icons.favorite,
                      //   size: 60,
                      //   color: AppColors.white,
                      // ),
                      // const SizedBox(height: 16),

                      // Title
                      Hero(
                        tag: 'app_logo',
                        child: Container(
                          height: 200,
                          width: double.infinity,
                          alignment: Alignment.center,
                          child: Image.asset(
                            'assets/images/logos/white_logo.png',
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      // const SizedBox(height: 8),
                      // Text(
                      //   'Mekanında aşkını bul',
                      //   style: TextStyle(
                      //     fontSize: 14,
                      //     color: AppColors.white.withOpacity(0.7),
                      //   ),
                      //   textAlign: TextAlign.center,
                      // ),
                      const SizedBox(height: 32),

                      // Email Field

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
                            prefixIconConstraints:
                                BoxConstraints(minWidth: 0, minHeight: 0),
                            contentPadding: EdgeInsets.only(bottom: 12.0),
                            prefixIcon: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 18.0, vertical: 8),
                              child:
                                  Icon(Icons.email, color: AppColors.primary),
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
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                            contentPadding: const EdgeInsets.only(bottom: 12.0),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 18.0, vertical: 8),
                              child: Icon(Icons.lock, color: AppColors.primary),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
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

                      // Password Strength Indicator
                      if (_passwordValidation != null &&
                          _passwordController.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _passwordValidation!.strength.color
                                  .withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Şifre Gücü: ',
                                    style: TextStyle(
                                      color: AppColors.white.withOpacity(0.8),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _passwordValidation!.strength.label,
                                    style: TextStyle(
                                      color:
                                          _passwordValidation!.strength.color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: (_passwordValidation!.score / 6)
                                    .clamp(0.0, 1.0),
                                backgroundColor:
                                    AppColors.white.withOpacity(0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _passwordValidation!.strength.color,
                                ),
                              ),

                              // Requirements list
                              if (_passwordValidation!
                                  .requirements.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...(_passwordValidation!.requirements
                                    .map((req) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            req,
                                            style: TextStyle(
                                              color: AppColors.white
                                                  .withOpacity(0.9),
                                              fontSize: 10,
                                              height: 1.2,
                                            ),
                                          ),
                                        ))),
                              ],

                              // Suggestions for improvement
                              if (_passwordValidation!.suggestions.isNotEmpty &&
                                  _passwordValidation!.score < 4) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: _passwordValidation!.suggestions
                                        .map(
                                          (suggestion) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 2),
                                            child: Text(
                                              suggestion,
                                              style: TextStyle(
                                                color: AppColors.white
                                                    .withOpacity(0.8),
                                                fontSize: 10,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Confirm Password Field
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          validator: _validateConfirmPassword,
                          obscureText: _obscureConfirmPassword,
                          style: const TextStyle(color: AppColors.grey800),
                          decoration: InputDecoration(
                            labelText: 'Şifre Tekrar',
                            hintText: 'Şifreyi Tekrar Girin',
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                            contentPadding: const EdgeInsets.only(bottom: 12.0),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 18.0, vertical: 8),
                              child: Icon(Icons.lock, color: AppColors.primary),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.primary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
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
                      const SizedBox(height: 16),

                      // Terms Checkbox
                      Row(
                        children: [
                          Checkbox(
                            value: _acceptTerms,
                            onChanged: (value) {
                              setState(() {
                                _acceptTerms = value ?? false;
                              });
                            },
                            fillColor: WidgetStateProperty.all(AppColors.white),
                            checkColor: AppColors.primary,
                          ),
                          Expanded(
                            child: Wrap(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    _showTermsOfService();
                                  },
                                  child: const Text(
                                    'Kullanım Koşulları',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  ' ve ',
                                  style: TextStyle(
                                    color: AppColors.white.withOpacity(0.9),
                                    fontSize: 13,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    _showPrivacyPolicy();
                                  },
                                  child: const Text(
                                    'Gizlilik Politikası',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  "nı kabul ediyorum",
                                  style: TextStyle(
                                    color: AppColors.white.withOpacity(0.9),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Register Button
                      ListenableBuilder(
                        listenable: _loadingManager,
                        builder: (context, child) {
                          return ProductionButton(
                            onPressed: _handleRegister,
                            text: 'Kayıt Ol',
                            isLoading: _loadingManager
                                .isLoading(LoadingOperations.register),
                            isDisabled: !_acceptTerms,
                            backgroundColor: AppColors.white,
                            textColor: AppColors.primary,
                            debounceTime: const Duration(
                                seconds: 3), // 3 seconds for register
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Info Text
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
                                const Icon(
                                  Icons.info_outline,
                                  color: AppColors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Kayıt olduktan sonra 7 adımda profilini tamamlayacaksın',
                                    style: TextStyle(
                                      color: AppColors.white.withOpacity(0.9),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.security,
                                  color: AppColors.white.withOpacity(0.7),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Bilgilerin güvende ve gizli tutulur',
                                    style: TextStyle(
                                      color: AppColors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Already have account
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Zaten hesabın var mı? ',
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Giriş Yap',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Loading Overlay
              ListenableBuilder(
                listenable: _loadingManager,
                builder: (context, child) {
                  if (!_loadingManager.isAnyLoading)
                    return const SizedBox.shrink();

                  return Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // KULLANIM KOŞULLARI GÖSTER
  void _showTermsOfService() {
    showLegalDocument(
      context: context,
      documentType: 'terms',
      title: 'Kullanım Koşulları',
      content: _getTermsOfServiceContent(),
      onAccept: () {
        setState(() {
          _acceptTerms = true;
        });
      },
    );
  }

  // GİZLİLİK POLİTİKASI GÖSTER
  void _showPrivacyPolicy() {
    showLegalDocument(
      context: context,
      documentType: 'privacy',
      title: 'Gizlilik Politikası',
      content: _getPrivacyPolicyContent(),
      onAccept: () {
        setState(() {
          _acceptTerms = true;
        });
      },
    );
  }

  // KULLANIM KOŞULLARI İÇERİĞİ
  String _getTermsOfServiceContent() {
    return '''
LOVENME KULLANIM ŞARTLARI (HİZMET KOŞULLARI)

Yürürlük Tarihi: 21.09.2025
Son Güncelleme: 21.09.2025
Hizmet Sağlayıcı (Veri Sorumlusu): Burak Ohrili
Adres: Gazi Osman Paşa Mahallesi 5499/1 Sokak No:9 Kat:1 Bornova / İzmir
MERSİS / Ticaret Sicil No: TC 35509755908
Vergi Dairesi ve No: EGE VD 6360302767
lovenmeapp@gmail.com

Barındırma/Hizmet Altyapısı: Apple App Store, Google Play, Google Ads/AdMob, Google Cloud/Firebase, Google Maps API, Resend Mail, Google Workspace, NetGSM

Bu Kullanım Şartları ("Şartlar"), Lovenme mobil uygulaması ve ilgili web/servisleri (hep birlikte "Hizmet") kullanımınıza ilişkin yasal sözleşmeyi oluşturur. Hizmeti indirerek, hesap oluşturarak veya kullanarak bu Şartlar ile Gizlilik Politikası ve Çerez/İzleme Teknolojileri Politikasını kabul etmiş sayılırsınız. Şartları kabul etmiyorsanız Hizmeti kullanmayınız.

1. Tanımlar
Lovenme / Biz: Burak Ohrili.
Kullanıcı / Siz: 18 yaşını doldurmuş, Hizmeti kullanan gerçek kişi.
Hesap: Uygulamada oluşturduğunuz üyelik profili.
Premium: Ücretli abonelik paketi/leri.
Sanal Ürünler: Uygulama içinde satılan Super Like, Elmas vb. dijital hak/öğe.
İçerik: Profil fotoğrafı, yazı, ses kaydı, video, mesajlar ve diğer kullanıcı paylaşımları.
Üçüncü Taraflar: Apple App Store, Google Play, Google Ads/AdMob, Google Cloud/Firebase, Google Maps API, Resend Mail, Google Workspace, NetGSM vb. hizmet sağlayıcılar.

2. Uygunluk ve Hesap
2.1. Yaş Sınırı: Hizmet yalnızca 18+ içindir. 18 yaş altı kullanım kesinlikle yasaktır.
2.2. Kayıt: Hesap; telefon numarası/e-posta/Apple-Google girişi ile oluşturulabilir. Verdiğiniz tüm bilgilerin doğru, güncel ve size ait olduğunu beyan edersiniz.
2.3. Tek Hesap: Her kullanıcı sadece 1 (bir) hesap oluşturabilir; hesabınızı devredemez, kiralayamaz, satamazsınız.
2.4. Güvenlik: Giriş bilgilerinizi gizli tutmakla yükümlüsünüz. Hesabınızın yetkisiz kullanımından doğan sonuçlardan siz sorumlusunuz.
2.5. Kimlik/Doğrulama: Güvenlik amacıyla gerektiğinde ek doğrulama (ör. SMS doğrulama, fotoğraf/yüz doğrulama) talep edebiliriz; sağlamazsanız hesabınız askıya alınabilir.

3. Hizmetin Kapsamı ve Özellikler
3.1. Lovenme; mekân/check-in temelli keşif ve bağlantı mantığıyla kullanıcıları ortak mekanlarda buluşturan bir sosyal keşif uygulamasıdır.
3.2. Bazı özellikler ücretsiz; bazıları Premium abonelik veya Sanal Ürün satın alımı ile sunulur.
3.3. Konum: Çalışma, favori/ziyaret ettiğiniz check-in yaptığınız mekânlara göre öneriler üretilmesine dayanır. Uygulama, cihazınızın konum izinlerine dayalı yaklaşık/kesin konum verilerini yalnızca açık rızanızla işler.
3.4. Mesajlaşma: Karşılıklı bağlantı isteği kabul edildikten sonra iletişim kurulabilir. Mesaj ve ses notları, iletimi sağlamak ve güvenlik/şikâyet süreçleri için makul süreyle saklanabilir.

4. Davranış Kuralları (Topluluk İlkeleri)
4.1. Saygı ve Doğruluk: Profilinizde gerçek sizi yansıtan bir yüz fotoğrafı bulundurmalı; başkasını taklit etmemeli, sahte/AI üretimi aldatıcı görseller kullanmamalısınız.
4.2. Yasak İçerik ve Eylemler:
a) Hukuka aykırı, tehditkâr, hakaret/iftira, müstehcen, cinsel istismar içeren, nefret/ayrımcılık barındıran içerikler;
b) Şiddet, intihar/öz zarar teşviki;
c) Başkasının kişisel verisini/özel hayatını izinsiz ifşa;
d) Fikri mülkiyet ihlali (foto/video/müzik vs. izinsiz paylaşım);
e) Spam, dolandırıcılık, "catfishing", kimlik avı;
f) Seks işçiliği/escortluk, narkotik/illegal ürün/servis teşviki;
g) Otomatik araç/bot/scraper, tersine mühendislik, güvenlik zafiyeti istismarı;
h) Reklam/ticari tanıtım, platform dışına yönlendirme ve veri kazıma;
i) 18 yaş altı bireylerle herhangi bir cinsel içerik/temas veya reşit olmayanların cinselleştirilmesine yönelik her türlü paylaşım.

4.3. Raporlama/Engelleme: Uygunsuz davranış veya güvenlik endişenizde bildir ve/veya engelle araçlarını kullanın.
4.4. Offline Görüşmeler: Tanışmalarınız ve fiziksel buluşmalarınız tamamen kendi sorumluluğunuzdadır. İlk buluşmaları kamusal alanda yapmanızı, yakınınıza bilgi vermenizi öneririz.

5. Moderasyon, Askıya Alma ve Fesih
5.1. Şartlara aykırılık, güvenlik riski, sahte profil şüphesi, yargı mercilerinden gelen talepler veya uzun süreli inaktivite hâlinde hesabı uyarma/özellik kısıtlama/askıya alma veya feshetme hakkımız saklıdır.
5.2. Ağır ihlallerde derhal ve süresiz yasak uygulanabilir.
5.3. Sizin fesih hakkınız: Hesabınızı dilediğiniz an "Ayarlar > Hesabımı Sil" üzerinden kalıcı olarak silebilirsiniz.

6. Premium Abonelikler
6.1. Premium; sınırsız chat isteği, check-in yapanların profillerini görme, check-in yapmadan kişileri görebilme, Süper Chat hakları vb. avantajlar içerebilir.
6.2. Satın Alma ve Faturalama: Mobil abonelikler; Apple App Store / Google Play üzerinden, ilgili platformun kullanım/ödeme şartlarına tabi olarak tahsil edilir.
6.3. Otomatik Yenileme: Premium, aksi belirtilmedikçe otomatik yenilenir. İptal etmek için dönem bitiminden en az 24 saat önce App Store/Google Play üzerinden abonelik yenilemeyi kapatınız.

7. Sanal Ürünler: Süper Chat ve Elmas
7.1. Süper Chat, Elmas vb. sanal ürünler yalnızca uygulama içi kullanım amaçlı, parasal karşılığı olmayan dijital değerlerdir.
7.2. Sanal ürün alımları kesindir, iade edilemez; nakde çevrilemez, devredilemez.

8. Fikri Mülkiyet
8.1. Lovenme ve logoları, tasarım, yazılım, veri tabanı dahil tüm unsurların mali/sınai hakları Burak Ohrili'ye aittir.
8.2. Kullanıcı İçerikleri: İçeriklerin sahibi sizsiniz; Hizmeti sağlamak/geliştirmek amacıyla dünya çapında, münhasır olmayan, bedelsiz kullanım lisansı sağlarsınız.

9. Sorumluluk Reddi ve Sınırlamalar
9.1. Hizmet "olduğu gibi" sunulur; kesintisiz, hatasız çalışacağına dair garanti verilmez.
9.2. Kullanıcı davranışlarından (çevrimiçi/çevrimdışı etkileşimler) doğacak zararlardan sorumluluk kabul edilmez.

10. Uyuşmazlık Çözümü
10.1. Öncelikle lovenmeapp@gmail.com üzerinden bize ulaşarak uyuşmazlıklara dostane çözüm arayınız.
10.2. Uygulanacak hukuk: Türkiye Cumhuriyeti Hukuku.

11. İletişim
Burak Ohrili
Adres: Gazi Osman Paşa Mahallesi 5499/1 Sokak No:9 Kat:1 Bornova / İzmir
E-posta: lovenmeapp@gmail.com
''';
  }

  // GİZLİLİK POLİTİKASI İÇERİĞİ
  String _getPrivacyPolicyContent() {
    return '''
LOVENME GİZLİLİK POLİTİKASI
Son Güncelleme Tarihi: 19.12.2025

Bu Gizlilik Politikası, Lovenme mobil uygulamasının ("Uygulama") kullanımı sırasında işlenen kişisel verilere ilişkin olarak kullanıcıları bilgilendirmek amacıyla hazırlanmıştır.

Lovenme, kişisel verilerinizi yürürlükteki mevzuata uygun olarak; başta 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) ve Avrupa Birliği Genel Veri Koruma Tüzüğü (GDPR) olmak üzere ilgili düzenlemelere uygun şekilde işler.

1. Veri Sorumlusu
Unvan: Noesis Social
Yetkili: Burak Ohrili
Adres: Gazi Osman Paşa Mah. 5499/1 Sokak No:9 D:2 Bornova / İzmir / Türkiye
E-posta: support@lovenme.app

2. İşlenen Kişisel Veriler
Uygulama kapsamında aşağıdaki kişisel veriler işlenmektedir:

2.1. Kimlik ve İletişim Bilgileri
• Görünen ad (profil adı)
• E-posta adresi
• Telefon numarası

Bu veriler, kullanıcı hesabının oluşturulması, doğrulanması ve güvenliğinin sağlanması amacıyla işlenir.

2.2. Kullanıcı İçerikleri
• Profil fotoğrafları
• Mesajlaşma (DM) içerikleri
• Check-in paylaşımları ve açıklamaları

Mesaj içerikleri yalnızca hizmetin sunulması amacıyla saklanır ve üçüncü kişilerle paylaşılmaz.

2.3. Konum Bilgisi
• Kesin konum bilgisi (precise location)

Konum bilgisi yalnızca:
• Yakındaki mekânları göstermek,
• Check-in yapılmasını sağlamak,
• Son 24 saatlik check-in'leri görüntülemek

amaçlarıyla, kullanıcının açık izniyle işlenir.
Uygulama, arka planda sürekli konum takibi yapmaz.

2.4. Kullanım ve Teknik Veriler
• Kullanıcı kimliği (User ID)
• Uygulama içi etkileşimler (bağlantı isteği, mesajlaşma, check-in)
• Hata ve çökme kayıtları (varsa)

Bu veriler, uygulamanın güvenli ve düzgün çalışmasını sağlamak amacıyla kullanılır.

2.5. Satın Alma Bilgileri
• Abonelik ve satın alma durumu

Ödeme kartı veya banka bilgileri Lovenme tarafından toplanmaz veya saklanmaz. Tüm ödeme işlemleri ilgili uygulama mağazaları (Apple App Store vb.) üzerinden gerçekleştirilir.

3. Kişisel Verilerin Toplanma Yöntemi
Kişisel veriler;
• Kullanıcı tarafından doğrudan sağlanan bilgiler,
• Uygulama kullanımı sırasında otomatik olarak oluşan veriler,
• Kimlik doğrulama ve bildirim hizmetleri aracılığıyla
toplanmaktadır.

4. Kişisel Verilerin İşlenme Amaçları
Kişisel veriler aşağıdaki amaçlarla işlenmektedir:
• Kullanıcı hesabının oluşturulması ve yönetilmesi
• Mesajlaşma, mekan bağlantısı ve check-in hizmetlerinin sunulması
• Yakındaki mekânların ve kullanıcıların gösterilmesi
• Güvenlik, sahtecilik ve kötüye kullanımın önlenmesi
• Uygulamanın teknik olarak sorunsuz çalışmasının sağlanması
• Yasal yükümlülüklerin yerine getirilmesi

5. Üçüncü Taraf Hizmet Sağlayıcılar
Uygulama kapsamında aşağıdaki hizmet sağlayıcılardan yararlanılmaktadır:
• Google Firebase (Authentication, Firestore, Cloud Messaging)
• NETGSM Telekomünikasyon A.Ş. (SMS doğrulama hizmetleri)

Bu hizmet sağlayıcılar, kişisel verileri yalnızca ilgili hizmeti sunmak amacıyla ve gizlilik yükümlülükleri çerçevesinde işler.

6. Reklam, Pazarlama ve Takip
Lovenme uygulamasında:
• Üçüncü taraf reklam hizmetleri,
• Kişiselleştirilmiş reklam,
• Pazarlama veya yeniden hedefleme,
• Uygulamalar arası kullanıcı takibi
bulunmamaktadır.

Kişisel veriler, reklam veya pazarlama amacıyla kullanılmaz ve paylaşılmaz.

7. Kişisel Verilerin Saklama Süresi
Kişisel veriler:
• Kullanıcı hesabı aktif olduğu sürece,
• Hesap silme talebi sonrasında ise yasal yükümlülükler saklı kalmak kaydıyla
makul süre boyunca saklanır ve ardından silinir veya anonim hale getirilir.

8. Kullanıcı Hakları
KVKK ve GDPR kapsamında kullanıcılar:
• Kişisel verilerine erişme,
• Düzeltme talep etme,
• Silme veya yok edilmesini isteme,
• Veri işlemeye itiraz etme,
• Açık rızayı geri çekme
haklarına sahiptir.

Bu haklara ilişkin talepler support@lovenme.app adresi üzerinden iletilebilir.

9. Hesap Silme
Kullanıcılar, uygulama içindeki ilgili ayarlar aracılığıyla:
• Hesaplarını geçici olarak dondurabilir,
• Hesaplarını kalıcı olarak silebilir.

Hesap silme işlemi sonrası kişisel veriler, yasal zorunluluklar dışında sistemlerden kaldırılır.

10. Çocukların Gizliliği
Lovenme, 18 yaşından küçük kullanıcılara yönelik değildir. Reşit olmayan kullanıcılara ait hesaplar tespit edilmesi halinde silinir.

11. Güvenlik
Lovenme, kişisel verilerin gizliliğini ve güvenliğini sağlamak amacıyla teknik ve idari güvenlik önlemleri uygular. Ancak internet üzerinden yapılan veri iletimlerinin %100 güvenli olduğu garanti edilemez.

12. Politika Değişiklikleri
Bu Gizlilik Politikası zaman zaman güncellenebilir. Önemli değişiklikler uygulama içinden veya uygun iletişim kanallarıyla kullanıcılara bildirilir.

13. İletişim
Gizlilik politikası ve kişisel verilerle ilgili her türlü soru ve talep için:
📧 support@lovenme.app
''';
  }
}
