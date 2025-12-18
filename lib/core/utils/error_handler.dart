import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';

class ErrorHandler {
  static String getErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'Kullanıcı bulunamadı';
        case 'wrong-password':
          return 'Hatalı şifre';
        case 'email-already-in-use':
          return 'Bu email zaten kullanımda';
        case 'weak-password':
          return 'Şifre çok zayıf';
        case 'network-request-failed':
          return 'İnternet bağlantısı yok';
        case 'too-many-requests':
          return 'Çok fazla deneme. Lütfen bekleyin';
        default:
          return 'Bir hata oluştu: ${error.message}';
      }
    }
    return error.toString();
  }
  
  static void showErrorSnackBar(BuildContext context, dynamic error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getErrorMessage(error)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Tamam',
          textColor: AppColors.white,
          onPressed: () {},
        ),
      ),
    );
  }
}