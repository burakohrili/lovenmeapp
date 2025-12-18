import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_splash_screen.dart';

class SplashDecisionManager extends StatefulWidget {
  final Widget nextScreen;
  final bool showOnlyFirstTime;
  
  const SplashDecisionManager({
    super.key,
    required this.nextScreen,
    this.showOnlyFirstTime = false, // İsteğe bağlı: Her seferinde göster
  });

  @override
  State<SplashDecisionManager> createState() => _SplashDecisionManagerState();
}

class _SplashDecisionManagerState extends State<SplashDecisionManager> {
  bool _shouldShowVideo = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkShouldShowVideo();
  }

  Future<void> _checkShouldShowVideo() async {
    if (!widget.showOnlyFirstTime) {
      // Her zaman göster
      setState(() {
        _shouldShowVideo = true;
        _isChecking = false;
      });
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenSplash = prefs.getBool('has_seen_video_splash') ?? false;
      
      if (!hasSeenSplash) {
        // İlk kez görüyor, video göster
        await prefs.setBool('has_seen_video_splash', true);
        setState(() {
          _shouldShowVideo = true;
          _isChecking = false;
        });
      } else {
        // Daha önce görmüş, direkt ana sayfaya geç
        setState(() {
          _shouldShowVideo = false;
          _isChecking = false;
        });
      }
    } catch (e) {
      // Hata durumunda video göster
      setState(() {
        _shouldShowVideo = true;
        _isChecking = false;
      });
    }
  }

  void _onVideoCompleted() {
    setState(() {
      _shouldShowVideo = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      // Kontrol edilirken loading göster
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.pink,
          ),
        ),
      );
    }

    if (_shouldShowVideo) {
      return VideoSplashScreen(
        onCompleted: _onVideoCompleted,
      );
    }

    return widget.nextScreen;
  }
}
