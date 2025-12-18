import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

enum LogoType {
  animated,
  staticFinal,
  staticImage,
}

class AppLogoWidget extends StatefulWidget {
  final double? height;
  final double? width;
  final LogoType type;
  final BoxFit fit;
  final String? heroTag;
  final bool playOnce;
  final VoidCallback? onAnimationComplete;
  final bool responsive;
  final double minHeight;
  final double maxHeight;

  const AppLogoWidget({
    super.key,
    this.height,
    this.width,
    this.type = LogoType.animated,
    this.fit = BoxFit.contain,
    this.heroTag,
    this.playOnce = false,
    this.onAnimationComplete,
    this.responsive = true,
    this.minHeight = 150,
    this.maxHeight = 300,
  });

  @override
  State<AppLogoWidget> createState() => _AppLogoWidgetState();
}

class _AppLogoWidgetState extends State<AppLogoWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    if (widget.type == LogoType.staticFinal) {
      // Son frame'de durdur
      _animationController.forward().then((_) {
        _animationController.stop();
        widget.onAnimationComplete?.call();
      });
    } else if (widget.type == LogoType.animated && widget.playOnce) {
      // Bir kez oynat
      _animationController.forward().then((_) {
        widget.onAnimationComplete?.call();
      });
    } else if (widget.type == LogoType.animated) {
      // Sürekli döngü
      _animationController.repeat();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildLogo(double calculatedHeight, double? calculatedWidth) {
    switch (widget.type) {
      case LogoType.animated:
      case LogoType.staticFinal:
        return Lottie.asset(
          'assets/animations/lovenme_logo.json',
          height: calculatedHeight,
          width: calculatedWidth,
          fit: widget.fit,
          controller: widget.type == LogoType.staticFinal 
              ? _animationController 
              : null,
          repeat: widget.type == LogoType.animated && !widget.playOnce,
          animate: true,
        );
      
      case LogoType.staticImage:
        return Image.asset(
          'lib/images/logos/LOVENME_white.png',
          height: calculatedHeight,
          width: calculatedWidth,
          fit: widget.fit,
        );
    }
  }

  double _calculateResponsiveHeight(BuildContext context) {
    if (!widget.responsive || widget.height != null) {
      return widget.height ?? 250;
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Ekran boyutuna göre dinamik hesaplama
    double responsiveHeight;
    
    if (screenHeight < 600) {
      // Küçük ekranlar (iPhone SE, küçük Android)
      responsiveHeight = screenHeight * 0.25; // %25 (was 20%)
    } else if (screenHeight < 800) {
      // Orta ekranlar (iPhone 12, 13, 14)
      responsiveHeight = screenHeight * 0.3; // %30 (was 25%)
    } else if (screenHeight < 900) {
      // Büyük ekranlar (iPhone Plus, Max)
      responsiveHeight = screenHeight * 0.33; // %33 (was 28%)
    } else {
      // Tablet boyutu ekranlar
      responsiveHeight = screenHeight * 0.35; // %35 (was 30%)
    }
    
    // Min ve max değerler arasında sınırla
    responsiveHeight = responsiveHeight.clamp(widget.minHeight, widget.maxHeight);
    
    // Aspect ratio kontrolü (genişlik çok dar ise yüksekliği azalt)
    if (screenWidth < 350) {
      responsiveHeight *= 0.8;
    }
    
    return responsiveHeight;
  }

  double? _calculateResponsiveWidth(BuildContext context) {
    if (widget.width != null) {
      return widget.width;
    }
    
    if (!widget.responsive) {
      return null;
    }
    
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Genişlik için responsive hesaplama
    double responsiveWidth = screenWidth * 0.8; // %80
    
    // Max genişlik sınırı
    responsiveWidth = responsiveWidth.clamp(200, 400);
    
    return responsiveWidth;
  }

  @override
  Widget build(BuildContext context) {
    final calculatedHeight = _calculateResponsiveHeight(context);
    final calculatedWidth = _calculateResponsiveWidth(context);
    
    Widget logo = Container(
      height: calculatedHeight,
      width: calculatedWidth ?? double.infinity,
      alignment: Alignment.center,
      child: _buildLogo(calculatedHeight, calculatedWidth),
    );

    if (widget.heroTag != null) {
      return Hero(
        tag: widget.heroTag!,
        child: logo,
      );
    }

    return logo;
  }
}
