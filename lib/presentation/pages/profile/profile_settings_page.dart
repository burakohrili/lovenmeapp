// lib/presentation/pages/profile/profile_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/native_auto_login_service.dart';
import '../auth/login_page.dart';
import '../../widgets/premium/premium_subscription_widget.dart';
import '../safety/community_guidelines_page.dart';
// Production Components - Profile Settings için
import '../../../widgets/production_button.dart';
import '../../../core/utils/loading_state_manager.dart';
import '../../../core/utils/form_validation_helper.dart';
import '../../../core/legal/legal_documents.dart';
import '../../../core/services/iap_service.dart';

class ProfileSettingsPage extends ConsumerStatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  ConsumerState<ProfileSettingsPage> createState() =>
      _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends ConsumerState<ProfileSettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Production Components
  late final LoadingStateManager _loadingManager;

  // Ayarlar - varsayılan değerler
  bool mapVisibility = true;
  /// Arkadaşlarım check-in'lerimi "Bugün" sekmesinde görsün mü?
  bool shareActivityWithFriends = true;
  bool profileActive = true;
  bool notifications = true;
  bool matchNotifications = true;
  bool messageNotifications = true;

  // Cinsiyet tercihleri (Eşleşme için)
  final List<String> preferenceOptions = ['Erkek', 'Kadın', 'Diğer'];

  // Kullanıcı bilgileri
  Map<String, dynamic>? userData;
  bool isLoading = true;
  bool isPremium = false;
  List<String> blockedUsers = [];

  @override
  void initState() {
    super.initState();
    _loadingManager = LoadingStateManager();
    _loadUserSettings();
  }

  @override
  void dispose() {
    _loadingManager.dispose();
    FormValidationHelper.dispose();
    super.dispose();
  }

  // KULLANICI AYARLARINI YÜKLE
  Future<void> _loadUserSettings() async {
    try {
      setState(() => isLoading = true);

      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();

        if (doc.exists) {
          final data = doc.data()!;

          setState(() {
            userData = data;

            // Ayarları yükle - null kontrolü ile
            mapVisibility = data['mapVisibility'] ?? true;
            shareActivityWithFriends =
                data['shareActivityWithFriends'] ?? true;
            profileActive = data['profileActive'] ?? true;
            notifications = data['notifications'] ?? true;
            matchNotifications = data['matchNotifications'] ?? true;
            messageNotifications = data['messageNotifications'] ?? true;
            isPremium = data['isPremium'] ?? false;


            // Engellenen kullanıcılar
            if (data['blockedUsers'] != null && data['blockedUsers'] is List) {
              blockedUsers = List<String>.from(data['blockedUsers']);
            }
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ayarlar yüklenemedi: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  // AYARLARI KAYDET
  // AYARLARI KAYDET - LoadingStateManager ile güncellenmiş
  Future<void> _saveSettings() async {
    await _loadingManager.executeOperation(
      'save_settings',
      () async {
        final user = _auth.currentUser;
        if (user == null) {
          throw 'Kullanıcı oturumu bulunamadı';
        }

        await _firestore.collection('users').doc(user.uid).set(
            {
              'mapVisibility': mapVisibility,
              'shareActivityWithFriends': shareActivityWithFriends,
              'profileActive': profileActive,
              'notifications': notifications,
              'matchNotifications': matchNotifications,
              'messageNotifications': messageNotifications,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(
                merge: true)); // merge: true ile mevcut verileri koruyoruz

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ayarlar kaydedildi ✅'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ayarlar kaydedilemedi. Lütfen tekrar deneyiniz.'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  // CİNSİYET TERCİHLERİ DİYALOGU

  // EMAIL DEĞİŞTİR
  void _showChangeEmailDialog() {
    final TextEditingController emailController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController codeController = TextEditingController();
    bool showCodeInput = false;
    String? pendingEmail;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(showCodeInput ? 'Doğrulama Kodu' : 'Email Değiştir'),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
                minWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!showCodeInput) ...[
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Email',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mevcut Şifren',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Doğrulama kodu ${emailController.text} adresine gönderildi.',
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '6 haneli doğrulama kodu',
                        prefixIcon: Icon(Icons.security),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            const SizedBox(width: 8),
            if (!showCodeInput)
              Flexible(
                child: ProductionButton(
                  text: 'Kod Gönder',
                  onPressed: () async {
                    // Kod gönderme işlemi
                    await _sendEmailChangeCode(emailController.text,
                        passwordController.text, setDialogState, () {
                      setDialogState(() {
                        showCodeInput = true;
                        pendingEmail = emailController.text;
                      });
                    });
                  },
                  isLoading: _loadingManager.isLoading('send_code'),
                  width: 120,
                  height: 40,
                ),
              )
            else
              Flexible(
                child: ProductionButton(
                  text: 'Doğrula',
                  onPressed: () =>
                      _verifyEmailChange(codeController.text, pendingEmail!),
                  isLoading: _loadingManager.isLoading('verify_email'),
                  width: 120,
                  height: 40,
                ),
              ),
          ],
        );
      }),
    );
  }

  // EMAIL DEĞİŞTİRME KODU GÖNDER
  Future<void> _sendEmailChangeCode(
    String newEmail,
    String password,
    StateSetter setDialogState,
    VoidCallback onSuccess,
  ) async {
    await _loadingManager.executeOperation(
      'send_code',
      () async {
        // Validation
        if (newEmail.trim().isEmpty) {
          throw 'Email adresi boş olamaz';
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(newEmail)) {
          throw 'Geçerli bir email adresi girin';
        }
        if (password.trim().isEmpty) {
          throw 'Mevcut şifrenizi girin';
        }

        final user = _auth.currentUser;
        if (user == null || user.email == null) {
          throw 'Kullanıcı oturumu bulunamadı';
        }

        // Yeni email aynı ise işlem yapma
        if (user.email!.toLowerCase() == newEmail.toLowerCase()) {
          throw 'Yeni email adresi mevcut adresinizle aynı';
        }

        // Yeniden kimlik doğrulama
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: password,
        );
        await user.reauthenticateWithCredential(credential);

        // 6 haneli kod üret
        final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
            .toString();

        // Cloud Function ile kod gönder
        final result = await FirebaseFunctions.instance
            .httpsCallable('sendEmailChangeVerification')
            .call({
          'newEmail': newEmail,
          'code': code,
          'userName': userData?['name'] ?? 'Kullanıcı',
        });

        if (result.data['success'] == true) {
          // Doğrulama kodunu geçici olarak sakla (10 dakika)
          await _firestore.collection('email_verifications').doc(user.uid).set({
            'code': code,
            'newEmail': newEmail,
            'userId': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': DateTime.now().add(const Duration(minutes: 10)),
          });

          onSuccess();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Doğrulama kodu gönderildi!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          throw result.data['error'] ?? 'Kod gönderilemedi';
        }
      },
      onError: (error) {
        String errorMessage = 'Kod gönderilemedi. Lütfen tekrar deneyiniz.';

        if (error.toString().contains('email-already-in-use')) {
          errorMessage =
              'Bu email adresi zaten başka bir hesap tarafından kullanılıyor.';
        } else if (error.toString().contains('wrong-password')) {
          errorMessage = 'Mevcut şifreniz yanlış.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      },
    );
  }

  // EMAIL DEĞİŞTİRME DOĞRULA
  Future<void> _verifyEmailChange(String code, String newEmail) async {
    await _loadingManager.executeOperation(
      'verify_email',
      () async {
        final user = _auth.currentUser;
        if (user == null) {
          throw 'Kullanıcı oturumu bulunamadı';
        }

        // Doğrulama kodunu kontrol et
        final verificationDoc = await _firestore
            .collection('email_verifications')
            .doc(user.uid)
            .get();

        if (!verificationDoc.exists) {
          throw 'Doğrulama kodu bulunamadı. Lütfen tekrar kod talep edin.';
        }

        final verificationData = verificationDoc.data()!;
        final storedCode = verificationData['code'];
        final storedEmail = verificationData['newEmail'];
        final expiresAt = (verificationData['expiresAt'] as Timestamp).toDate();

        if (DateTime.now().isAfter(expiresAt)) {
          throw 'Doğrulama kodu süresi dolmuş. Lütfen yeni kod talep edin.';
        }

        if (storedCode != code || storedEmail != newEmail) {
          throw 'Geçersiz doğrulama kodu.';
        }

        // Email'i güncelle
        await user.verifyBeforeUpdateEmail(newEmail);

        // Firestore'da güncelle
        await _firestore.collection('users').doc(user.uid).update({
          'email': newEmail,
          'isEmailVerified': false, // Firebase verification sonrası true olacak
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Doğrulama kodunu sil
        await _firestore
            .collection('email_verifications')
            .doc(user.uid)
            .delete();

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Email güncellendi! Firebase doğrulama emaili de gönderildi.'),
            backgroundColor: AppColors.success,
          ),
        );

        setState(() {
          _loadUserSettings();
        });
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      },
    );
  }

  // ŞİFRE DEĞİŞTİR
  void _showChangePasswordDialog() {
    final TextEditingController currentPasswordController =
        TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController =
        TextEditingController();
    final TextEditingController codeController = TextEditingController();
    bool showCodeInput = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(showCodeInput ? 'Doğrulama Kodu' : 'Şifre Değiştir'),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
                minWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!showCodeInput) ...[
                    TextField(
                      controller: currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mevcut Şifre',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Şifre',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                        helperText: 'En az 6 karakter',
                        helperMaxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Şifre (Tekrar)',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Doğrulama kodu email adresinize gönderildi.',
                      style: TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '6 haneli doğrulama kodu',
                        prefixIcon: Icon(Icons.security),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            const SizedBox(width: 8),
            if (!showCodeInput)
              Flexible(
                child: ProductionButton(
                  text: 'Kod Gönder',
                  onPressed: () async {
                    // Şifre eşleştirme kontrolü
                    if (newPasswordController.text !=
                        confirmPasswordController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Şifreler eşleşmiyor!'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }

                    // Kod gönderme işlemi
                    await _sendPasswordChangeCode(
                        currentPasswordController.text,
                        newPasswordController.text,
                        setDialogState, () {
                      setDialogState(() {
                        showCodeInput = true;
                      });
                    });
                  },
                  isLoading: _loadingManager.isLoading('send_password_code'),
                  width: 120,
                  height: 40,
                ),
              )
            else
              Flexible(
                child: ProductionButton(
                  text: 'Doğrula',
                  onPressed: () => _verifyPasswordChange(
                      codeController.text, newPasswordController.text),
                  isLoading: _loadingManager.isLoading('verify_password'),
                  width: 120,
                  height: 40,
                ),
              ),
          ],
        );
      }),
    );
  }

  // ŞİFRE DEĞİŞTİRME KODU GÖNDER
  Future<void> _sendPasswordChangeCode(
    String currentPassword,
    String newPassword,
    StateSetter setDialogState,
    VoidCallback onSuccess,
  ) async {
    await _loadingManager.executeOperation(
      'send_password_code',
      () async {
        // Validation
        if (currentPassword.trim().isEmpty) {
          throw 'Mevcut şifrenizi girin';
        }
        if (newPassword.trim().isEmpty) {
          throw 'Yeni şifrenizi girin';
        }
        if (newPassword.length < 6) {
          throw 'Yeni şifre en az 6 karakter olmalıdır';
        }

        final user = _auth.currentUser;
        if (user == null || user.email == null) {
          throw 'Kullanıcı oturumu bulunamadı';
        }

        // Yeniden kimlik doğrulama
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);

        // 6 haneli kod üret
        final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
            .toString();

        // Cloud Function ile kod gönder
        final result = await FirebaseFunctions.instance
            .httpsCallable('sendPasswordChangeVerification')
            .call({
          'email': user.email!,
          'code': code,
          'userName': userData?['name'] ?? 'Kullanıcı',
        });

        if (result.data['success'] == true) {
          // Doğrulama kodunu geçici olarak sakla (10 dakika)
          // GÜVENLİK: Yeni şifre buraya YAZILMIYOR. Eskiden düz metin olarak
          // Firestore'da bekliyordu; doğrulama zaten `newPassword` parametresini
          // aldığı için saklamaya hiç gerek yok.
          await _firestore
              .collection('password_verifications')
              .doc(user.uid)
              .set({
            'code': code,
            'userId': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': DateTime.now().add(const Duration(minutes: 10)),
          });

          onSuccess();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Doğrulama kodu email adresinize gönderildi!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          throw result.data['error'] ?? 'Kod gönderilemedi';
        }
      },
      onError: (error) {
        String errorMessage = 'Kod gönderilemedi. Lütfen tekrar deneyiniz.';

        if (error.toString().contains('wrong-password')) {
          errorMessage = 'Mevcut şifreniz yanlış.';
        } else if (error.toString().contains('weak-password')) {
          errorMessage = 'Yeni şifre çok zayıf.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      },
    );
  }

  // ŞİFRE DEĞİŞTİRME DOĞRULA
  Future<void> _verifyPasswordChange(String code, String newPassword) async {
    await _loadingManager.executeOperation(
      'verify_password',
      () async {
        final user = _auth.currentUser;
        if (user == null) {
          throw 'Kullanıcı oturumu bulunamadı';
        }

        // Doğrulama kodunu kontrol et
        final verificationDoc = await _firestore
            .collection('password_verifications')
            .doc(user.uid)
            .get();

        if (!verificationDoc.exists) {
          throw 'Doğrulama kodu bulunamadı. Lütfen tekrar kod talep edin.';
        }

        final verificationData = verificationDoc.data()!;
        final storedCode = verificationData['code'];
        final expiresAt = (verificationData['expiresAt'] as Timestamp).toDate();

        if (DateTime.now().isAfter(expiresAt)) {
          throw 'Doğrulama kodu süresi dolmuş. Lütfen yeni kod talep edin.';
        }

        if (storedCode != code) {
          throw 'Geçersiz doğrulama kodu.';
        }

        // Şifreyi güncelle
        // Parametreden gelen şifre kullanılıyor; Firestore'da saklanmıyor.
        await user.updatePassword(newPassword);

        // Doğrulama kodunu sil
        await _firestore
            .collection('password_verifications')
            .doc(user.uid)
            .delete();

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şifreniz başarıyla güncellendi!'),
            backgroundColor: AppColors.success,
          ),
        );
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      },
    );
  }

  // ENGELLENEN KULLANICILAR
// ENGELLENEN KULLANICILAR - RESPONSIVE VERSİYON
  void _showBlockedUsersDialog() async {
    // Loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    // Kullanıcı bilgilerini al
    Map<String, Map<String, dynamic>> blockedUserData = {};

    for (String userId in blockedUsers) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          String userName = data['name'] ?? 'İsimsiz';

          if (data['surname'] != null &&
              data['surname'].toString().isNotEmpty) {
            userName = '$userName ${data['surname']}';
          }

          String? photoUrl;
          if (data['photos'] != null && (data['photos'] as List).isNotEmpty) {
            photoUrl = data['photos'][0];
          }

          blockedUserData[userId] = {
            'name': userName,
            'photo': photoUrl,
          };
        } else {
          blockedUserData[userId] = {
            'name': 'Silinmiş Kullanıcı',
            'photo': null,
          };
        }
      } catch (e) {
        blockedUserData[userId] = {
          'name': 'Kullanıcı',
          'photo': null,
        };
      }
    }

    // Loading'i kapat
    Navigator.pop(context);

    // Responsive dialog
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Üst çizgi
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // Başlık
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.block, color: AppColors.error, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Engellenen Kullanıcılar (${blockedUsers.length})',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // İçerik
            Expanded(
              child: blockedUsers.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.block_outlined,
                            size: 64,
                            color: AppColors.grey400,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Henüz kimseyi engellemediniz',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.grey600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: blockedUsers.length,
                      itemBuilder: (context, index) {
                        final userId = blockedUsers[index];
                        final userData = blockedUserData[userId]!;
                        final userName = userData['name'];
                        final photoUrl = userData['photo'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.grey200,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Profil resmi
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor:
                                      AppColors.error.withOpacity(0.1),
                                  backgroundImage: photoUrl != null
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child: photoUrl == null
                                      ? const Icon(
                                          Icons.person_off,
                                          color: AppColors.error,
                                        )
                                      : null,
                                ),

                                const SizedBox(width: 12),

                                // İsim - Flexible ile sarmalayarak taşmayı önle
                                Expanded(
                                  child: Text(
                                    userName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // Engeli kaldır butonu
                                TextButton(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Engeli Kaldır'),
                                        content: Text(
                                          '$userName kullanıcısının engelini '
                                          'kaldırmak istediğinize emin misiniz?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('İptal'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.success,
                                            ),
                                            child: const Text('Kaldır'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      Navigator.pop(context);
                                      await _unblockUser(userId);
                                      _showBlockedUsersDialog();
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text(
                                    'Kaldır',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // KULLANICI ENGELLE
  Future<void> blockUser(String userId) async {
    try {
      final user = _auth.currentUser;
      if (user != null && user.uid != userId) {
        await _firestore.collection('users').doc(user.uid).update({
          'blockedUsers': FieldValue.arrayUnion([userId]),
        });

        // Karşılıklı eşleşmeyi kaldır
        await _firestore
            .collection('matches')
            .where('user1Id', isEqualTo: user.uid)
            .where('user2Id', isEqualTo: userId)
            .get()
            .then((snapshot) {
          for (var doc in snapshot.docs) {
            doc.reference.update({'isActive': false});
          }
        });

        await _firestore
            .collection('matches')
            .where('user1Id', isEqualTo: userId)
            .where('user2Id', isEqualTo: user.uid)
            .get()
            .then((snapshot) {
          for (var doc in snapshot.docs) {
            doc.reference.update({'isActive': false});
          }
        });

        setState(() {
          blockedUsers.add(userId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kullanıcı engellendi'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı engellenemedi. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ENGEL KALDIR
  Future<void> _unblockUser(String userId) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'blockedUsers': FieldValue.arrayRemove([userId]),
        });

        setState(() {
          blockedUsers.remove(userId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Engel kaldırıldı'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Engel kaldırılamadı. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // HESABI DONDUR
  Future<void> _freezeAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'isActive': false,
          'profileActive': false,
          'frozenAt': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hesabınız donduruldu'),
            backgroundColor: AppColors.warning,
          ),
        );

        // Çıkış yap
        await _auth.signOut();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Hesap dondurma işlemi tamamlanamadı. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // HESABI SİL
  /// Hesabı siler.
  ///
  /// Silme işi tamamen SUNUCUDA yapılır. Eskiden burada tek bir WriteBatch
  /// vardı; atomik olduğu için tek bir alt işlem reddedilince (örneğin
  /// kullanıcıyı biri engellemişse) `users/{uid}` dahil hiçbir şey
  /// silinmiyordu ve Auth hesabı ayakta kalıyordu. Ayrıca sorguların dördü
  /// var olmayan alan adlarını kullandığı için özel mesajlar hiç silinmiyordu.
  Future<void> _deleteAccount() async {
    try {
      await _loadingManager.executeOperation(
        LoadingOperations.deleteAccount,
        () async {
          final user = _auth.currentUser;
          if (user == null) return;

          final functions =
              FirebaseFunctions.instanceFor(region: 'us-central1');
          final result =
              await functions.httpsCallable('deleteAccount').call({});

          final data = Map<String, dynamic>.from(result.data as Map);
          if (data['success'] != true) {
            throw data['error'] ?? 'Hesap silinemedi';
          }

          // Cihazdaki oturum ve tercihleri temizle.
          await NativeAutoLoginService().clearAutoLoginData();

          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hesabınız ve tüm verileriniz silindi.'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 4),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('requires-recent-login')) {
          _showReauthenticateDialog(onSuccess: _deleteAccount);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Hesap silme işlemi tamamlanamadı: ${e.toString()}'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  /// Satın alımları geri yükler (App Store 3.1.1).
  Future<void> _restorePurchases() async {
    try {
      final count = await IAPService().restorePurchases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? '$count satın alma geri yüklendi'
              : 'Geri yüklenecek satın alma bulunamadı'),
          backgroundColor:
              count > 0 ? AppColors.success : AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geri yükleme başarısız oldu'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showReauthenticateDialog({required Function onSuccess}) {
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kimlik Doğrulama Gerekli'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Güvenlik amacıyla bu hassas işlem için şifrenizi tekrar girmeniz gerekiyor.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mevcut Şifreniz',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen şifrenizi girin'),
                    backgroundColor: AppColors.warning,
                  ),
                );
                return;
              }

              try {
                final user = _auth.currentUser;
                if (user != null && user.email != null) {
                  final credential = EmailAuthProvider.credential(
                    email: user.email!,
                    password: passwordController.text,
                  );
                  await user.reauthenticateWithCredential(credential);

                  if (mounted) {
                    Navigator.pop(context);
                    onSuccess();
                  }
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().contains('wrong-password')
                            ? 'Hatalı şifre. Lütfen tekrar deneyiniz.'
                            : 'Doğrulama başarısız. Şifrenizi kontrol ediniz.',
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Doğrula ve Devam Et'),
          ),
        ],
      ),
    );
  }

  // Cinsiyet tercihlerini metin olarak göster

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.grey50,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.grey50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text('Ayarlar',
            style: AppTextStyles.h4.copyWith(color: AppColors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Premium Durum
            if (isPremium)
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: AppColors.premiumGradient,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: AppColors.white),
                    const SizedBox(width: 12),
                    Text(
                      'Premium Üye',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // "Bağlantı Tercihleri > Cinsiyet Tercihleri" bölümü KALDIRILDI.
            // Bu ayar hiçbir sorguda kullanılmıyordu: yazılıyor, geri okunup
            // yalnızca kendi etiketini çizmek için gösteriliyordu. Buna karşılık
            // ayarların en üstünde duran, "Keşfet sayfasında hangi cinsiyetteki
            // kullanıcıları görmek istersin?" diyen bir dating tercih seçicisiydi —
            // Guideline 4.3(b) incelemesinde uygulamadaki en belirgin dating izi.

            // Görünürlük Ayarları
            _buildSection(
              title: 'Görünürlük Ayarları',
              icon: Icons.visibility,
              children: [
                _buildSwitchTile(
                  title: 'Haritada Görün',
                  subtitle: 'Check-in yaptığında haritada görün',
                  value: mapVisibility,
                  onChanged: (value) {
                    setState(() {
                      mapVisibility = value;
                    });
                    _saveSettings();
                  },
                ),
                // Arkadaşlık katmanı, kapının bilinçli istisnasıdır:
                // arkadaşın hareketini o mekana gitmemiş olsan da görürsün.
                // Bu yüzden kullanıcı bunu kapatabilmeli.
                _buildSwitchTile(
                  title: 'Arkadaşlarım hareketimi görsün',
                  subtitle: "Check-in'lerin arkadaşlarının Bugün akışında görünür",
                  value: shareActivityWithFriends,
                  onChanged: (value) {
                    setState(() {
                      shareActivityWithFriends = value;
                    });
                    _saveSettings();
                  },
                ),
                _buildSwitchTile(
                  title: 'Profil Aktif',
                  subtitle: 'Profilin mekan listelerinde görünsün',
                  value: profileActive,
                  onChanged: (value) {
                    setState(() {
                      profileActive = value;
                    });
                    _saveSettings();
                  },
                ),
              ],
            ),

            // Bildirim Ayarları
            _buildSection(
              title: 'Bildirimler',
              icon: Icons.notifications,
              children: [
                _buildSwitchTile(
                  title: 'Bildirimler',
                  subtitle: 'Tüm bildirimleri aç/kapat',
                  value: notifications,
                  onChanged: (value) {
                    setState(() {
                      notifications = value;
                      if (!value) {
                        matchNotifications = false;
                        messageNotifications = false;
                      }
                    });
                    _saveSettings();
                  },
                ),
                if (notifications) ...[
                  _buildSwitchTile(
                    title: 'Bağlantı Bildirimleri',
                    subtitle: 'Yeni bağlantılarda bildirim al',
                    value: matchNotifications,
                    onChanged: (value) {
                      setState(() {
                        matchNotifications = value;
                      });
                      _saveSettings();
                    },
                  ),
                  _buildSwitchTile(
                    title: 'Mesaj Bildirimleri',
                    subtitle: 'Yeni mesajlarda bildirim al',
                    value: messageNotifications,
                    onChanged: (value) {
                      setState(() {
                        messageNotifications = value;
                      });
                      _saveSettings();
                    },
                  ),
                ],
              ],
            ),

            // Hesap Ayarları
            _buildSection(
              title: 'Hesap',
              icon: Icons.person,
              children: [
                _buildListTile(
                  title: 'Email Değiştir',
                  subtitle: userData?['email'] ?? 'Email eklenmemiş',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showChangeEmailDialog,
                ),
                // App Store Guideline 3.1.1: geri yükleme BULUNABİLİR olmalı.
                // Eskiden yalnızca premium satın alma sayfasının içindeydi;
                // aboneliği olan ama sayfayı açmayan kullanıcı bulamıyordu.
                _buildListTile(
                  title: 'Satın Alımları Geri Yükle',
                  subtitle: 'Önceki aboneliğini bu cihaza geri yükle',
                  trailing: const Icon(Icons.restore, size: 20),
                  onTap: _restorePurchases,
                ),
                _buildListTile(
                  title: 'Şifre Değiştir',
                  subtitle: 'Hesap şifreni güncelle',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showChangePasswordDialog,
                ),
              ],
            ),

            // Gizlilik
            _buildSection(
              title: 'Gizlilik',
              icon: Icons.lock,
              children: [
                _buildListTile(
                  title: 'Engellenen Kullanıcılar',
                  subtitle: '${blockedUsers.length} kullanıcı engellendi',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showBlockedUsersDialog,
                ),
              ],
            ),

            // Destek
            _buildSection(
              title: 'Destek',
              icon: Icons.support_agent,
              children: [
                _buildListTile(
                  title: 'Topluluk Kuralları',
                  subtitle: 'Güvenli topluluk standartları',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CommunityGuidelinesPage(),
                      ),
                    );
                  },
                ),
                _buildListTile(
                  title: 'Gizlilik Politikası',
                  subtitle: 'Verilerinizi nasıl koruduğumuzu öğrenin',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showPrivacyPolicyDialog,
                ),
                _buildListTile(
                  title: 'Kullanım Şartları',
                  subtitle: 'Uygulama kullanım koşulları',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showTermsOfServiceDialog,
                ),
                _buildListTile(
                  title: 'İletişim',
                  subtitle: 'Bizimle iletişime geçin',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showContactDialog,
                ),
              ],
            ),

            // Premium
            if (!isPremium)
              _buildSection(
                title: 'Premium',
                icon: Icons.star,
                children: [
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: AppColors.premiumGradient,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.star, color: AppColors.white),
                      title: Text(
                        'Premium\'a Yükselt',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Sınırsız özellikler',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.white.withOpacity(0.7),
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        color: AppColors.white,
                        size: 16,
                      ),
                      onTap: () {
                        _showPremiumDialog();
                      },
                    ),
                  ),
                ],
              ),

            // Tehlikeli Bölge
            _buildSection(
              title: 'Tehlikeli Bölge',
              icon: Icons.warning,
              color: AppColors.error,
              children: [
                _buildListTile(
                  title: 'Hesabı Dondur',
                  subtitle: 'Geçici olarak hesabını dondur',
                  textColor: AppColors.warning,
                  onTap: () {
                    _showFreezeAccountDialog();
                  },
                ),
                _buildListTile(
                  title: 'Hesabı Sil',
                  subtitle: 'Kalıcı olarak hesabını sil',
                  textColor: AppColors.error,
                  onTap: () {
                    _showDeleteAccountDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Çıkış Yap',
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text('Hesabından çıkış yap'),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Çıkış Yap'),
                        content: const Text(
                            'Çıkış yapmak istediğinize emin misiniz?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('İptal'),
                          ),
                          TextButton(
                            onPressed: () async {
                              // Auto-login verilerini temizle
                              // Eskiden AutoLoginService kullanılıyordu; o yalnızca _v2 anahtarlarını
                              // temizliyor, canlı _v3 anahtarlarına dokunmuyordu — bu yüzden
                              // çıkış yapan kullanıcı bir sonraki açılışta geri giriş yapıyordu.
                              final autoLoginService = NativeAutoLoginService();
                              await autoLoginService.handleLogout();

                              // Firebase'den çıkış yap
                              await FirebaseAuth.instance.signOut();

                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (_) => const LoginPage()),
                                (route) => false,
                              );
                            },
                            child: const Text('Çıkış Yap',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color ?? AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color ?? AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.grey600),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? textColor,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(color: textColor),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: textColor?.withOpacity(0.7) ?? AppColors.grey600,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  void _showPremiumDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: PremiumSubscriptionWidget(
          onPurchaseSuccess: (type) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Premium satın alındı!'),
                backgroundColor: Colors.green,
              ),
            );
            // Sayfayı yenile
            setState(() {
              isPremium = true;
            });
          },
          onError: (error) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Resim yüklenemedi. Lütfen tekrar deneyiniz.'),
                backgroundColor: Colors.red,
              ),
            );
          },
        ),
      ),
    );
  }

  void _showFreezeAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabı Dondur'),
        content: const Text(
          'Hesabını dondurmak istediğine emin misin? '
          'İstediğin zaman geri açabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _freezeAccount();
            },
            child: const Text(
              'Dondur',
              style: TextStyle(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            SizedBox(width: 8),
            Expanded(
              child: Text('Hesabı Kalıcı Olarak Sil'),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu işlem geri alınamaz! Hesabınızı sildiğinizde:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• Tüm profil bilgileriniz'),
            Text('• Fotoğraflarınız'),
            Text('• Mesajlarınız ve bağlantılarınız'),
            Text('• Beğeni geçmişiniz'),
            Text('• Premium abonelik durumunuz'),
            SizedBox(height: 12),
            Text(
              'kalıcı olarak silinecektir.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Devam etmek istediğinize emin misiniz?',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ListenableBuilder(
            listenable: _loadingManager,
            builder: (context, child) {
              return ElevatedButton(
                onPressed:
                    _loadingManager.isLoading(LoadingOperations.deleteAccount)
                        ? null
                        : () {
                            Navigator.pop(context);
                            _deleteAccount();
                          },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child:
                    _loadingManager.isLoading(LoadingOperations.deleteAccount)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Evet, Hesabımı Sil'),
              );
            },
          ),
        ],
      ),
    );
  }

  // DESTEK METODLARI

  void _showPrivacyPolicyDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.privacy_tip,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gizlilik Politikası',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.grey900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'KVKK & GDPR Uyumlu',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.grey700),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _getPrivacyPolicyContent(),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.grey800,
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Anladım',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTermsOfServiceDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.description,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kullanım Şartları',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.grey900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Hizmet Koşulları',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.grey700),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _getTermsOfServiceContent(),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.grey800,
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Anladım',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.contact_support,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'İletişim',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.grey900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Bizimle iletişime geçin',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.grey700),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bizimle iletişime geçmek için aşağıdaki kanalları kullanabilirsiniz:',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.grey800,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Email Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _buildContactItem(
                        icon: Icons.email,
                        title: 'Genel Destek',
                        subtitle: 'lovenmeapp@gmail.com',
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Address Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _buildContactItem(
                        icon: Icons.location_on,
                        title: 'Adres',
                        subtitle:
                            'Gazi Osman Paşa Mahallesi\n5499/1 Sokak No:9 Kat:1\nBornova / İzmir',
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.1),
                            AppColors.primary.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 24,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Destek ekibimiz 24-48 saat içinde size geri dönüş yapacaktır.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.grey800,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Kapat',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.grey600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getPrivacyPolicyContent() {
    // Metin artik tek kaynakta: lib/core/legal/legal_documents.dart
    return LegalDocuments.privacyPolicy;
  }

  String _getTermsOfServiceContent() {
    // Metin artik tek kaynakta: lib/core/legal/legal_documents.dart
    return LegalDocuments.termsOfService;
  }
}
