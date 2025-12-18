import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  // change to pink

  static const Color primary = Color.fromARGB(255, 250, 74, 115); 
  static const Color primaryLight = Color.fromARGB(255, 255, 140, 170);
  static const Color primaryDark = Color.fromARGB(255, 200, 30, 80);
  static const Color primaryRegister = Color.fromARGB(255, 250, 120, 170); // iwant soft pink for register 
  static const Color primaryLightRegister = Color.fromARGB(255, 255, 170, 200);
  
  // Secondary Colors
  static const Color secondary = Color.fromARGB(255, 255, 105, 150); // Pink
  static const Color secondaryLight = Color.fromARGB(255, 255, 180, 200);
  static const Color secondaryDark = Color.fromARGB(255, 220, 50, 100);
  
  // Accent Colors
  static const Color accent = Color.fromARGB(255, 255, 120, 160); // Pink accent
  static const Color warning = Color(0xFFF59E0B); // Orange
  static const Color info = Color.fromARGB(255, 255, 160, 190); // pink info
  static const Color error = Color(0xFFEF4444); // Red
  static const Color success = Color(0xFF22C55E); // Green
  
  // UI Action Colors
  static const Color like = Color(0xFF22C55E); // Green
  static const Color dislike = Color(0xFFEF4444); // Red
  static const Color superLike = Color(0xFF3B82F6); // Blue
  static const Color premium = Color(0xFFFFD700); // Gold
  
  // Status Colors
  static const Color online = Color(0xFF22C55E);
  static const Color offline = Color(0xFF9CA3AF);
  
  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey900 = Color(0xFF111827);
  static const Color grey800 = Color(0xFF1F2937);
  static const Color grey700 = Color(0xFF374151);
  static const Color grey600 = Color(0xFF4B5563);
  static const Color grey500 = Color(0xFF6B7280);
  static const Color grey400 = Color(0xFF9CA3AF);
  static const Color grey300 = Color(0xFFD1D5DB);
  static const Color grey200 = Color(0xFFE5E7EB);
  static const Color grey100 = Color(0xFFF3F4F6);
  static const Color grey50 = Color(0xFFF9FAFB);
  
  // Background Colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);
  static const Color cardBackground = Color(0xFFFFFFFF); // Card background
  
  // Transparent and overlay colors
  static const Color transparent = Colors.transparent;
  
  // Button Colors
  static const Color buttonPrimary = primary;
  static const Color buttonPrimaryText = white;
  static const Color buttonSecondary = secondary;
  static const Color buttonSecondaryText = white;
  static const Color buttonSuccess = success;
  static const Color buttonSuccessText = white;
  static const Color buttonWarning = warning;
  static const Color buttonWarningText = white;
  static const Color buttonError = error;
  static const Color buttonErrorText = white;
  static const Color buttonDisabled = grey300;
  static const Color buttonDisabledText = grey500;
  static const Color buttonOutline = primary;
  static const Color buttonOutlineText = primary;
  static const Color buttonGhost = transparent;
  static const Color buttonGhostText = primary;
  static const Color buttonWhite = white;
  static const Color buttonWhiteText = primary;
  
  // Text Colors
  static const Color textPrimary = grey900;          // Main text
  static const Color textSecondary = grey600;       // Secondary text
  static const Color textTertiary = grey500;        // Tertiary/muted text
  static const Color textDisabled = grey400;        // Disabled text
  static const Color textOnPrimary = white;         // Text on primary backgrounds
  static const Color textOnSecondary = white;       // Text on secondary backgrounds
  static const Color textOnDark = white;            // Text on dark backgrounds
  static const Color textOnLight = grey900;         // Text on light backgrounds
  static const Color textSuccess = success;         // Success text
  static const Color textWarning = warning;         // Warning text
  static const Color textError = error;             // Error text
  static const Color textInfo = superLike;          // Info text (blue)
  static const Color textLink = primary;            // Link text
  static const Color textLinkHover = primaryDark;   // Link hover text
  static const Color textPlaceholder = grey400;     // Input placeholder text
  static const Color textHint = grey500;            // Hint text
  static const Color textLabel = grey700;           // Label text
  static const Color textCaption = grey500;         // Caption text
  static const Color textSubtitle = grey600;        // Subtitle text
  static const Color textOverline = grey500;        // Overline text
  
  // Gradient Colors
  static const List<Color> primaryGradient = [
    primary,
    primaryLight,
  ];
  
  static const List<Color> primaryRegisterGradient = [
    primaryRegister,
    primaryLightRegister,
  ];
  
  static const List<Color> secondaryGradient = [
    secondary,
    secondaryLight,
  ];
  
  static const List<Color> successGradient = [
    accent,
    success,
  ];
  
  static const List<Color> premiumGradient = [
    warning,
    premium,
  ];
}