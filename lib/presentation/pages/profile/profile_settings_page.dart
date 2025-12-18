// lib/presentation/pages/profile/profile_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/auto_login_service.dart';
import '../auth/login_page.dart';
import '../../widgets/premium/premium_subscription_widget.dart';
import '../safety/community_guidelines_page.dart';
// Production Components - Profile Settings için
import '../../../widgets/production_button.dart';
import '../../../core/utils/loading_state_manager.dart';
import '../../../core/utils/form_validation_helper.dart';

class ProfileSettingsPage extends ConsumerStatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  ConsumerState<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends ConsumerState<ProfileSettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Production Components
  late final LoadingStateManager _loadingManager;
  
  // Ayarlar - varsayılan değerler
  bool mapVisibility = true;
  bool profileActive = true;
  bool notifications = true;
  bool matchNotifications = true;
  bool messageNotifications = true;
  
  // Cinsiyet tercihleri (Eşleşme için)
  List<String> genderPreferences = [];
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
        
        final doc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (doc.exists) {
          final data = doc.data()!;
          
          setState(() {
            userData = data;
            
            // Ayarları yükle - null kontrolü ile
            mapVisibility = data['mapVisibility'] ?? true;
            profileActive = data['profileActive'] ?? true;
            notifications = data['notifications'] ?? true;
            matchNotifications = data['matchNotifications'] ?? true;
            messageNotifications = data['messageNotifications'] ?? true;
            isPremium = data['isPremium'] ?? false;
            
            // Cinsiyet tercihleri
            if (data['genderPreferences'] != null && data['genderPreferences'] is List) {
              genderPreferences = List<String>.from(data['genderPreferences']);
            } else {
              // Varsayılan olarak herkesi göster
              genderPreferences = ['Erkek', 'Kadın', 'Diğer'];
            }
            
            // Engellenen kullanıcılar
            if (data['blockedUsers'] != null && data['blockedUsers'] is List) {
              blockedUsers = List<String>.from(data['blockedUsers']);
            }
          });
        } else {
          // Varsayılan tercihler
          genderPreferences = ['Erkek', 'Kadın', 'Diğer'];
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
        
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set({
          'mapVisibility': mapVisibility,
          'profileActive': profileActive,
          'notifications': notifications,
          'matchNotifications': matchNotifications,
          'messageNotifications': messageNotifications,
          'genderPreferences': genderPreferences, // Cinsiyet tercihleri
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)); // merge: true ile mevcut verileri koruyoruz
        
        
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
  void _showGenderPreferencesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.people, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Kimleri Görmek İstersin?'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Keşfet sayfasında hangi cinsiyetteki kullanıcıları görmek istersin?',
                    style: TextStyle(fontSize: 14, color: AppColors.grey600),
                  ),
                  const SizedBox(height: 20),
                  ...preferenceOptions.map((option) {
                    final isSelected = genderPreferences.contains(option);
                    return CheckboxListTile(
                      title: Text(option),
                      value: isSelected,
                      activeColor: AppColors.primary,
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            if (!genderPreferences.contains(option)) {
                              genderPreferences.add(option);
                            }
                          } else {
                            // En az bir seçenek seçili kalmalı
                            if (genderPreferences.length > 1) {
                              genderPreferences.remove(option);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('En az bir tercih seçili olmalı'),
                                  backgroundColor: AppColors.warning,
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          }
                        });
                      },
                    );
                  }),
                  const Divider(),
                  // Hepsini seç/kaldır butonu
                  TextButton.icon(
                    onPressed: () {
                      setDialogState(() {
                        if (genderPreferences.length == 3) {
                          // Hepsi seçiliyse sadece ilkini bırak
                          genderPreferences = [preferenceOptions[0]];
                        } else {
                          // Hepsini seç
                          genderPreferences = List.from(preferenceOptions);
                        }
                      });
                    },
                    icon: Icon(
                      genderPreferences.length == 3 
                          ? Icons.check_box 
                          : Icons.check_box_outline_blank,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      genderPreferences.length == 3 
                          ? 'Tümünü Kaldır' 
                          : 'Tümünü Seç',
                      style: const TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // İptal edilirse eski haline döndür
                    _loadUserSettings();
                    Navigator.pop(context);
                  },
                  child: const Text('İptal'),
                ),
                ProductionButton(
                  text: 'Kaydet',
                  onPressed: () {
                    setState(() {}); // Ana sayfayı güncelle
                    _saveSettings(); // Firebase'e kaydet
                    Navigator.pop(context);
                  },
                  isLoading: _loadingManager.isLoading('save_gender_preferences'),
                  width: 100,
                  height: 40,
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  // EMAIL DEĞİŞTİR
  void _showChangeEmailDialog() {
    final TextEditingController emailController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController codeController = TextEditingController();
    bool showCodeInput = false;
    String? pendingEmail;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(showCodeInput ? 'Doğrulama Kodu' : 'Email Değiştir'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!showCodeInput) ...[
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Yeni Email',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mevcut Şifren',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Doğrulama kodu ${emailController.text} adresine gönderildi.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '6 haneli doğrulama kodu',
                      prefixIcon: Icon(Icons.security),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              if (!showCodeInput)
                ProductionButton(
                  text: 'Kod Gönder',
                  onPressed: () async {
                    // Kod gönderme işlemi
                    await _sendEmailChangeCode(
                      emailController.text,
                      passwordController.text,
                      setDialogState,
                      () {
                        setDialogState(() {
                          showCodeInput = true;
                          pendingEmail = emailController.text;
                        });
                      }
                    );
                  },
                  isLoading: _loadingManager.isLoading('send_code'),
                  width: 120,
                  height: 40,
                )
              else
                ProductionButton(
                  text: 'Doğrula',
                  onPressed: () => _verifyEmailChange(codeController.text, pendingEmail!),
                  isLoading: _loadingManager.isLoading('verify_email'),
                  width: 120,
                  height: 40,
                ),
            ],
          );
        }
      ),
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
        final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
        
        // Cloud Function ile kod gönder
        final result = await FirebaseFunctions.instance.httpsCallable('sendEmailChangeVerification').call({
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
          errorMessage = 'Bu email adresi zaten başka bir hesap tarafından kullanılıyor.';
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
        await _firestore.collection('email_verifications').doc(user.uid).delete();
        
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email güncellendi! Firebase doğrulama emaili de gönderildi.'),
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
    final TextEditingController currentPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    final TextEditingController codeController = TextEditingController();
    bool showCodeInput = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(showCodeInput ? 'Doğrulama Kodu' : 'Şifre Değiştir'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!showCodeInput) ...[
                  TextField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mevcut Şifre',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Yeni Şifre',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Yeni Şifre (Tekrar)',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Doğrulama kodu email adresinize gönderildi.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '6 haneli doğrulama kodu',
                      prefixIcon: Icon(Icons.security),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              if (!showCodeInput)
                ProductionButton(
                  text: 'Kod Gönder',
                  onPressed: () async {
                    // Şifre eşleştirme kontrolü
                    if (newPasswordController.text != confirmPasswordController.text) {
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
                      setDialogState,
                      () {
                        setDialogState(() {
                          showCodeInput = true;
                        });
                      }
                    );
                  },
                  isLoading: _loadingManager.isLoading('send_password_code'),
                  width: 120,
                  height: 40,
                )
              else
                ProductionButton(
                  text: 'Doğrula',
                  onPressed: () => _verifyPasswordChange(codeController.text, newPasswordController.text),
                  isLoading: _loadingManager.isLoading('verify_password'),
                  width: 120,
                  height: 40,
                ),
            ],
          );
        }
      ),
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
        final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
        
        // Cloud Function ile kod gönder
        final result = await FirebaseFunctions.instance.httpsCallable('sendPasswordChangeVerification').call({
          'email': user.email!,
          'code': code,
          'userName': userData?['name'] ?? 'Kullanıcı',
        });

        if (result.data['success'] == true) {
          // Doğrulama kodunu geçici olarak sakla (10 dakika)
          await _firestore.collection('password_verifications').doc(user.uid).set({
            'code': code,
            'newPassword': newPassword,
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
        final storedPassword = verificationData['newPassword'];
        final expiresAt = (verificationData['expiresAt'] as Timestamp).toDate();

        if (DateTime.now().isAfter(expiresAt)) {
          throw 'Doğrulama kodu süresi dolmuş. Lütfen yeni kod talep edin.';
        }

        if (storedCode != code) {
          throw 'Geçersiz doğrulama kodu.';
        }

        // Şifreyi güncelle
        await user.updatePassword(storedPassword);

        // Doğrulama kodunu sil
        await _firestore.collection('password_verifications').doc(user.uid).delete();
        
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
        
        if (data['surname'] != null && data['surname'].toString().isNotEmpty) {
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
                                backgroundColor: AppColors.error.withOpacity(0.1),
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
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('İptal'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.success,
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
      await _firestore
          .collection('users')
          .doc(user.uid)
          .update({
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
        await _firestore
            .collection('users')
            .doc(user.uid)
            .update({
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
        await _firestore
            .collection('users')
            .doc(user.uid)
            .update({
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
          content: Text('Hesap dondurma işlemi tamamlanamadı. Lütfen tekrar deneyiniz.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
  
  // HESABI SİL
  Future<void> _deleteAccount() async {
    try {
      await _loadingManager.executeOperation(
        LoadingOperations.deleteAccount,
        () async {
          final user = _auth.currentUser;
          if (user == null) return;

          final uid = user.uid;
          
          // 1. Firestore'dan kullanıcı verilerini sil
          final batch = _firestore.batch();
          
          // Kullanıcı dokümanını sil
          batch.delete(_firestore.collection('users').doc(uid));
          
          // Matches koleksiyonundan kullanıcıyı sil
          final matchesQuery = await _firestore
              .collection('matches')
              .where('users', arrayContains: uid)
              .get();
          
          for (var doc in matchesQuery.docs) {
            batch.delete(doc.reference);
          }
          
          // Messages koleksiyonundan mesajları sil
          final messagesQuery = await _firestore
              .collection('messages')
              .where('participants', arrayContains: uid)
              .get();
          
          for (var doc in messagesQuery.docs) {
            batch.delete(doc.reference);
          }
          
          // Likes koleksiyonundan beğenileri sil
          final likesQuery1 = await _firestore
              .collection('likes')
              .where('from', isEqualTo: uid)
              .get();
          
          final likesQuery2 = await _firestore
              .collection('likes')
              .where('to', isEqualTo: uid)
              .get();
          
          for (var doc in likesQuery1.docs) {
            batch.delete(doc.reference);
          }
          
          for (var doc in likesQuery2.docs) {
            batch.delete(doc.reference);
          }
          
          // Blocked users koleksiyonundan kayıtları sil
          final blockedQuery1 = await _firestore
              .collection('blocked_users')
              .where('blocker', isEqualTo: uid)
              .get();
          
          final blockedQuery2 = await _firestore
              .collection('blocked_users')
              .where('blocked', isEqualTo: uid)
              .get();
          
          for (var doc in blockedQuery1.docs) {
            batch.delete(doc.reference);
          }
          
          for (var doc in blockedQuery2.docs) {
            batch.delete(doc.reference);
          }
          
          // Reports koleksiyonundan raporları sil
          final reportsQuery1 = await _firestore
              .collection('reports')
              .where('reporter', isEqualTo: uid)
              .get();
          
          final reportsQuery2 = await _firestore
              .collection('reports')
              .where('reported', isEqualTo: uid)
              .get();
          
          for (var doc in reportsQuery1.docs) {
            batch.delete(doc.reference);
          }
          
          for (var doc in reportsQuery2.docs) {
            batch.delete(doc.reference);
          }
          
          // Firestore batch işlemini gerçekleştir
          await batch.commit();
          
          // 2. Firebase Storage'dan fotoğrafları sil
          try {
            final storageRef = FirebaseStorage.instance.ref('user_photos/$uid');
            final listResult = await storageRef.listAll();
            
            for (var item in listResult.items) {
              await item.delete();
            }
          } catch (storageError) {
            // Storage silme hatası - devam et
          }
          
          // 3. Auto login verilerini temizle
          final autoLoginService = AutoLoginService();
          await autoLoginService.clearAutoLoginData();
          
          // 4. Auth hesabını sil
          await user.delete();
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hesabınız ve tüm verileri başarıyla silindi'),
            backgroundColor: AppColors.success,
          ),
        );
        
        // Login sayfasına yönlendir
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        // Yeniden kimlik doğrulama gerekebilir
        if (e.toString().contains('requires-recent-login')) {
          _showReauthenticateDialog(onSuccess: _deleteAccount);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hesap silme işlemi tamamlanamadı: ${e.toString()}'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }
  
  // YENİDEN KİMLİK DOĞRULAMA
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
  String _getGenderPreferencesText() {
    if (genderPreferences.isEmpty) {
      return 'Tercih seçilmemiş';
    } else if (genderPreferences.length == 3) {
      return 'Herkes';
    } else if (genderPreferences.length == 2) {
      return genderPreferences.join(' ve ');
    } else {
      return genderPreferences.first;
    }
  }
  
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
        title: Text('Ayarlar', style: AppTextStyles.h4.copyWith(color: AppColors.white)),
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
            
            // EŞLEŞME TERCİHLERİ - YENİ!
            _buildSection(
              title: 'Eşleşme Tercihleri',
              icon: Icons.favorite,
              color: AppColors.primary,
              children: [
                _buildListTile(
                  title: 'Cinsiyet Tercihleri',
                  subtitle: 'Kimleri görmek istiyorsun: ${_getGenderPreferencesText()}',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getGenderPreferencesText(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  onTap: _showGenderPreferencesDialog,
                ),
              ],
            ),
            
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
                _buildSwitchTile(
                  title: 'Profil Aktif',
                  subtitle: 'Profilin keşfette görünsün',
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
                    title: 'Eşleşme Bildirimleri',
                    subtitle: 'Yeni eşleşmelerde bildirim al',
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
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              // Auto-login verilerini temizle
              final autoLoginService = AutoLoginService();
              await autoLoginService.handleLogout();
              
              // Firebase'den çıkış yap
              await FirebaseAuth.instance.signOut();
              
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
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
            Text('• Mesajlarınız ve eşleşmeleriniz'),
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
                onPressed: _loadingManager.isLoading(LoadingOperations.deleteAccount)
                  ? null
                  : () {
                      Navigator.pop(context);
                      _deleteAccount();
                    },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: _loadingManager.isLoading(LoadingOperations.deleteAccount)
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
                        subtitle: 'Gazi Osman Paşa Mahallesi\n5499/1 Sokak No:9 Kat:1\nBornova / İzmir',
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
    return '''
Lovenme Gizlilik Politikası
Güncelleme: 13/09/2025

Bu gizlilik politikasının amacı, Lovenme tarafından işlenen kişisel verileriniz hakkında sizi şeffaf biçimde bilgilendirmektir. Lütfen dikkatle okuyunuz.

Önemli not: Aşağıdaki metin, AB GDPR ve Türkiye KVKK (6698) ile uyum gözetilerek hazırlanmıştır. Üçüncü taraf servisler (ör. Apple/Google/ödeme altyapıları, harita/analitik/bildirim sağlayıcıları) için kendi gizlilik politikaları geçerlidir.

TANIMLAR

Uygulama (Lovenme): iOS/Android mağazalarında Lovenme.
Beğeni: Bir profili beğendiğinizi gösteren eylem.
Süper Beğeni: Öne çıkan beğeni.
Check-in: Bir mekâna girişinizi/ziyaretinizi uygulamada bildirmeniz.
Muhtar: Belirli bir süre için mekânın "lideri" unvanı.
Harita: Yakınınızdaki/sponsorlu mekânları keşfetmeyi sağlayan görünüm.
Feed (Akış): Check-in paylaşımlarının göründüğü alan.
Crush/Match (Eşleşme): İki profilin karşılıklı beğenmesi ile oluşan durum.
Mesajlar: Eşleşme sonrası açılan özel sohbet.
Favori Mekânlar: Kullanıcının yıldızladığı mekânlar.
Hesap: Üyeye ait kişisel alan.
Üye: Uygulamaya kayıtlı gerçek kişi.
Veri Sorumlusu: BURAK OHRİLİ – Gazi Osman Paşa Mah. 5499/1 Sokak No:9 D:2 Bornova / İzmir.
İrtibat: support@lovenme.app, KVKK için: kvkk@lovenme.app

1. Bu Politikanın Kapsamı
Bu politika, Lovenme tarafından sunulan tüm hizmetler için geçerlidir. Üçüncü taraf servislerine (haritalar, ödeme altyapıları, bildirim/analitik sağlayıcıları) ait veri işleme faaliyetleri kendi politikalarına tabidir.

2. Topladığımız Veriler

2.1 Zorunlu Veriler
- Tanımlama verileri: Ad, yaş, cinsiyet, en az 1 yüz fotoğrafı
- İletişim: E-posta ve/veya telefon numarası
- Hesap/etkileşim verileri: Kayıt/oturum tarihleri, beğeni/eşleşme/mesaj kayıtları
- Cihaz/teknik veriler: Uygulama sürümü, işletim sistemi, IP, hata kayıtları
- Konum: Konum izni ile coğrafi konum

2.2 Hizmet Fonksiyonları İçin Gerekli Veriler
- Check-in ve karşılaşma noktaları
- Harita görünümü ve sıralamalar
- Arama tercihleri: Yaş aralığı, cinsiyet filtreleri
- Mesaj içerikleri meta verileri
- Satın alma/abonelik kayıtları

2.3 İsteğe Bağlı Veriler
- Favori mekânlar ve hobiler

3. Verileri Nasıl Topluyoruz?
- Doğrudan sizden: Kayıt, profil düzenleme, tercih yönetimi
- Otomatik: Uygulama kullanımı, cihaz/teknik veriler, konum
- Üçüncü taraflardan: Apple/Google kimlik doğrulama, harita/analitik sağlayıcıları

4. İşleme Amaçları ve Hukuki Dayanaklar

4.1 Sözleşmenin ifası
- Hesap açma/kapama, profil oluşturma
- Temel hizmetlerin sunulması (beğeni, eşleşme, mesaj, check-in)
- Abonelik/ücretli özelliklerin işletimi

4.2 Rıza
- Konum verisiyle yakınınızdaki profillerin önerilmesi
- Profil doğrulama için biyometri
- Uygulama içi kişiselleştirilmiş reklam

4.3 Meşru menfaat
- Profil önerileri
- Sponsorlu mekân önerileri
- Kötüye kullanım/sahtecilik tespiti
- Hizmeti geliştirmek için analiz

4.4 Yasal yükümlülük
- Adli/idarî mercilerden gelen taleplere yanıt
- KVKK ve GDPR kapsamındaki hak başvurularının yönetimi

5. Reklam, Pazarlama ve Bildirimler
- Bülten ve uygulama içi öneriler
- Uygulama içi reklam (onay ile)
- Push bildirimler (tercihlerden yönetilebilir)

6. Güvenlik, Sahtecilik ve Tacizle Mücadele
- Otomatik ve manuel denetimler
- Profil doğrulama (opsiyonel)
- Askıya alma/engelleme/silme

7. Verilerin Paylaşımı
- Yetkili Lovenme personeli
- Hizmet sağlayıcılar/iş ortakları
- Resmî makamlar/mahkemeler (yasal talepler)
- Şirket işlemleri (birleşme/devralma)

8. Yurt Dışına Aktarım
Veriler, Türkiye, AB/AEA veya güvenli üçüncü ülkelerde saklanıp işlenebilir. AB dışına aktarımlarda gerekli koruma araçları uygulanır.

9. Saklama Süreleri
- Hesap süresi + 24 ay pasiflikte hesap silinir
- Silinen/banlanan hesap verileri 24 ay aktif, ardından 12 ay arşivde
- Konum ve karşılaşma noktaları: Son konum 1 ay, karşılaşma 6 ay

10. Haklarınız (KVKK & GDPR)
- Erişim / Bilgi talebi
- Düzeltme / Güncelleme
- Silme ("unutulma")
- İşlemenin kısıtlanması
- İtiraz
- Veri taşınabilirliği
- Açık rızanın geri çekilmesi

Başvuru: support@lovenme.app, KVKK/GDPR için: kvkk@lovenme.app

11. Reşit Olmayanlar
Lovenme 18 yaş altı kişilere yönelik değildir. Bu durumu tespit edersek hesap kapatılır.

12. Güvenlik
Endüstri standardı teknik ve idari önlemler (şifreleme, erişim kontrolleri) uygularız.

13. Politika Değişiklikleri
Bu politika güncellenebilir. Önemli değişiklikleri uygulama içi bildirim ve/veya e-posta ile duyururuz.

14. İletişim
Genel destek: support@lovenme.app
KVKK/GDPR: kvkk@lovenme.app
Posta: Veri Koruma İrtibatı – Lovenme, Gazi Osman Paşa Mah. 5499/1 Sokak No: 9 D:2 Bornova / İzmir / Türkiye
''';
  }

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
3.1. Lovenme; mekân/check-in temelli keşif ve eşleştirme mantığıyla kullanıcıları bir araya getiren bir sosyal tanışma uygulamasıdır.
3.2. Bazı özellikler ücretsiz; bazıları Premium abonelik veya Sanal Ürün satın alımı ile sunulur.
3.3. Konum: Çalışma, favori/ziyaret ettiğiniz check-in yaptığınız mekânlara göre öneriler üretilmesine dayanır. Uygulama, cihazınızın konum izinlerine dayalı yaklaşık/kesin konum verilerini yalnızca açık rızanızla işler.
3.4. Mesajlaşma: Eşleşme/karşılıklı ilgi sonrasında iletişim kurulabilir. Mesaj ve ses notları, iletimi sağlamak ve güvenlik/şikâyet süreçleri için makul süreyle saklanabilir.

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
}