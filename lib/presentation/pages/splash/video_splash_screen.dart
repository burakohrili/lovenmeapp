import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'splash_video_config.dart';

class VideoSplashScreen extends StatefulWidget {
  final VoidCallback onCompleted;
  final bool loopUntilCompleted; // Yeni parametre
  
  const VideoSplashScreen({
    super.key,
    required this.onCompleted,
    this.loopUntilCompleted = false,
  });

  @override
  State<VideoSplashScreen> createState() => VideoSplashScreenState();
}

class VideoSplashScreenState extends State<VideoSplashScreen> {
  late VideoPlayerController _controller;
  bool _isVideoReady = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // Video dosyasını config'den al
      _controller = VideoPlayerController.asset(
        SplashVideoConfig.videoPath,
      );
      
      // Video hazırlandığında
      await _controller.initialize();
      
      // Video hızını config'den al
      await _controller.setPlaybackSpeed(SplashVideoConfig.playbackSpeed);
      
      // Ses seviyesini config'den al
      await _controller.setVolume(SplashVideoConfig.volume);
      
      // Video bittiğinde callback
      _controller.addListener(() {
        if (_controller.value.position >= _controller.value.duration) {
          if (widget.loopUntilCompleted) {
            // Tekrar başlat
            _controller.seekTo(Duration.zero);
            _controller.play();
          } else {
            _onVideoCompleted();
          }
        }
        
        // Error handling
        if (_controller.value.hasError) {
          setState(() => _hasError = true);
          _fallbackToNextScreen();
        }
      });

      setState(() => _isVideoReady = true);
      
      // Video'yu oynat
      await _controller.play();
      
      
    } catch (e) {
      setState(() => _hasError = true);
      _fallbackToNextScreen();
    }
  }

  void _onVideoCompleted() {
    widget.onCompleted();
  }

  void stopLoopAndComplete() {
    // Loop'u durdur ve tamamla
    widget.onCompleted();
  }

  void _fallbackToNextScreen() {
    // Video yüklenemezse config'deki süre kadar bekle ve geç
    Future.delayed(const Duration(seconds: SplashVideoConfig.fallbackDurationSeconds), () {
      widget.onCompleted();
    });
  }

  void _skipVideo() {
    _controller.pause();
    widget.onCompleted();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Player
          if (_isVideoReady && !_hasError)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          
          // Error/Loading fallback
          if (!_isVideoReady || _hasError)
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Fallback logo/animation
                    Icon(
                      Icons.favorite,
                      color: Colors.pink[300],
                      size: 80,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'MyDateApp',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!_hasError) ...[
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(
                        color: Colors.pink,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          
          // Skip button (config'e göre göster)
          if (SplashVideoConfig.showSkipButton)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              right: 20,
              child: GestureDetector(
                onTap: _skipVideo,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Atla',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
