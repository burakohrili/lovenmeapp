-keep class com.google.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.maps.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.**

# SharedPreferences için gerekli
-keep class androidx.** { *; }
-keep class android.content.SharedPreferences { *; }
-keep class android.content.SharedPreferences$Editor { *; }

# Flutter SecureStorage için gerekli
-keep class androidx.security.crypto.** { *; }
-keep class androidx.security.** { *; }
-dontwarn androidx.security.**

# SQLite için gerekli
-keep class io.flutter.plugins.sqflite.** { *; }
-keep class org.sqlite.** { *; }

# Flutter için gerekli
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Your app
-keep class com.lovenme.** { *; }

# Google Play Billing (prevent obfuscation issues)
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**