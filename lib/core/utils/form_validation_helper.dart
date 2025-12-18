import 'dart:async';
import 'package:flutter/material.dart';

class FormValidationHelper {
  static Timer? _debounceTimer;

  /// Email validation with real-time feedback
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email gerekli';
    }
    
    value = value.trim();
    
    // Basic format check
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value)) {
      return 'Geçerli bir email giriniz';
    }
    
    // Length check
    if (value.length > 254) {
      return 'Email çok uzun';
    }
    
    // Domain check
    final domain = value.split('@')[1];
    if (domain.length > 253) {
      return 'Email domain çok uzun';
    }
    
    return null;
  }

  /// Password validation with strength indication
  static PasswordValidationResult validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return PasswordValidationResult(
        error: 'Şifre gerekli',
        strength: PasswordStrength.veryWeak,
        suggestions: ['Lütfen bir şifre girin'],
      );
    }

    String error = '';
    PasswordStrength strength = PasswordStrength.veryWeak;
    int score = 0;
    List<String> suggestions = [];
    List<String> requirements = [];

    // Length check
    if (value.length < 8) {
      error = 'Şifre en az 8 karakter olmalı';
      requirements.add('❌ En az 8 karakter');
    } else {
      score += 1;
      requirements.add('✅ En az 8 karakter');
    }
    
    if (value.length >= 12) {
      score += 1;
      requirements.add('✅ 12+ karakter (bonus)');
    } else if (value.length >= 8) {
      suggestions.add('💡 12+ karakter için bonus puan');
    }

    // Character variety checks
    if (value.contains(RegExp(r'[a-z]'))) {
      score += 1;
      requirements.add('✅ Küçük harf');
    } else {
      requirements.add('❌ Küçük harf gerekli');
      suggestions.add('Küçük harf ekleyin (a-z)');
    }

    if (value.contains(RegExp(r'[A-Z]'))) {
      score += 1;
      requirements.add('✅ Büyük harf');
    } else {
      requirements.add('❌ Büyük harf gerekli');
      suggestions.add('Büyük harf ekleyin (A-Z)');
    }

    if (value.contains(RegExp(r'[0-9]'))) {
      score += 1;
      requirements.add('✅ Rakam');
    } else {
      requirements.add('❌ Rakam gerekli');
      suggestions.add('Rakam ekleyin (0-9)');
    }

    if (value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      score += 1;
      requirements.add('✅ Özel karakter');
    } else {
      requirements.add('❌ Özel karakter gerekli');
      suggestions.add('Özel karakter ekleyin (!@#\$%^&*)');
    }

    // Common password check
    if (_isCommonPassword(value)) {
      score = 0;
      error = 'Bu şifre çok yaygın kullanılan bir şifre';
      suggestions = ['Daha özgün bir şifre seçin', 'Yaygın şifrelerden kaçının'];
    }

    // Determine strength and provide specific guidance
    switch (score) {
      case 0:
      case 1:
        strength = PasswordStrength.veryWeak;
        if (error.isEmpty) error = 'Şifre çok zayıf - Güvenlik açığı riski';
        break;
      case 2:
        strength = PasswordStrength.weak;
        if (error.isEmpty) error = 'Şifre zayıf - Daha güçlü yapın';
        break;
      case 3:
        strength = PasswordStrength.fair;
        error = ''; // Fair is acceptable
        if (suggestions.isEmpty) suggestions.add('İyi! Daha güçlü için özel karakter ekleyebilirsiniz');
        break;
      case 4:
        strength = PasswordStrength.good;
        error = '';
        if (suggestions.isEmpty) suggestions.add('Güzel! Uzun şifre için bonus puan alabilirsiniz');
        break;
      case 5:
      case 6:
        strength = PasswordStrength.strong;
        error = '';
        if (suggestions.isEmpty) suggestions.add('Mükemmel! Güçlü bir şifre');
        break;
    }

    return PasswordValidationResult(
      error: error.isEmpty ? null : error,
      strength: strength,
      score: score,
      suggestions: suggestions,
      requirements: requirements,
    );
  }

  /// Confirm password validation
  static String? validateConfirmPassword(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'Şifre tekrarı gerekli';
    }
    
    if (value != password) {
      return 'Şifreler eşleşmiyor';
    }
    
    return null;
  }

  /// Debounced validation for real-time feedback
  static void debounceValidation({
    required VoidCallback onValidate,
    Duration delay = const Duration(milliseconds: 500),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, onValidate);
  }

  /// Check if password is in common passwords list
  static bool _isCommonPassword(String password) {
    final commonPasswords = [
      '12345678',
      '123456789',
      'password',
      'qwerty123',
      'abc12345',
      '12345abc',
      'password123',
      '123qwerty',
    ];
    
    return commonPasswords.contains(password.toLowerCase());
  }

  /// Clean up resources
  static void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}

class PasswordValidationResult {
  final String? error;
  final PasswordStrength strength;
  final int score;
  final List<String> suggestions;
  final List<String> requirements;

  PasswordValidationResult({
    this.error,
    required this.strength,
    this.score = 0,
    this.suggestions = const [],
    this.requirements = const [],
  });

  bool get isValid => error == null;
}

enum PasswordStrength {
  veryWeak,
  weak,
  fair,
  good,
  strong,
}

extension PasswordStrengthExtension on PasswordStrength {
  String get label {
    switch (this) {
      case PasswordStrength.veryWeak:
        return 'Çok Zayıf';
      case PasswordStrength.weak:
        return 'Zayıf';
      case PasswordStrength.fair:
        return 'Orta';
      case PasswordStrength.good:
        return 'İyi';
      case PasswordStrength.strong:
        return 'Güçlü';
    }
  }

  Color get color {
    switch (this) {
      case PasswordStrength.veryWeak:
      case PasswordStrength.weak:
        return const Color(0xFFE53E3E); // Red
      case PasswordStrength.fair:
        return const Color(0xFFDD6B20); // Orange
      case PasswordStrength.good:
        return const Color(0xFF38A169); // Green
      case PasswordStrength.strong:
        return const Color(0xFF00A86B); // Strong Green
    }
  }
}
