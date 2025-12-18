class SplashVideoConfig {
  // Video dosya yolu - Değiştirilebilir
  static const String videoPath = 'assets/animations/high_res_splash_vid.mp4';
  
  // Video hızı - Değiştirilebilir (1.0 = normal, 1.4 = hızlı)
  static const double playbackSpeed = 1.4;
  
  // Ses seviyesi - Değiştirilebilir (0.0 = sessiz, 1.0 = tam ses)
  static const double volume = 0.8;
  
  // Skip butonu görünür mü? - Değiştirilebilir
  static const bool showSkipButton = true;
  
  // Fallback süre (video yüklenemezse beklenecek süre)
  static const int fallbackDurationSeconds = 2;
}
