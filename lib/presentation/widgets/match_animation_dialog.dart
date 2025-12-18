// lib/presentation/widgets/match_animation_dialog.dart

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../pages/messages/models/match_model.dart';
import '../pages/messages/chat_detail_page.dart';

class MatchAnimationDialog extends StatefulWidget {
  final MatchModel match;
  final VoidCallback? onClose;

  const MatchAnimationDialog({
    super.key,
    required this.match,
    this.onClose,
  });

  @override
  State<MatchAnimationDialog> createState() => _MatchAnimationDialogState();
}

class _MatchAnimationDialogState extends State<MatchAnimationDialog>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    // Animasyonları başlat
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _scaleController.forward();
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goToChat() {
    Navigator.of(context).pop(); // Dialog'u kapat
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailPage(match: widget.match),
      ),
    );
  }

  void _keepSwiping() {
    Navigator.of(context).pop(); // Dialog'u kapat
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          color: Colors.black.withOpacity(0.8),
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Başlık
                    const Text(
                      "🎉 IT'S A MATCH! 🎉",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFA4458),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Chat wink animasyonu
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(60),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFA4458), Color(0xFFFF6B7A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Lottie.asset(
                        'assets/animations/chat_wink.json',
                        width: 80,
                        height: 80,
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
                    
                    const SizedBox(height: 25),
                    
                    // Kullanıcı bilgileri
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Mevcut kullanıcı avatarı (placeholder)
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFA4458), width: 3),
                            color: Colors.grey[300],
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 30,
                            color: Colors.grey,
                          ),
                        ),
                        
                        const SizedBox(width: 20),
                        
                        // Kalp ikonu
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFA4458),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.favorite,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        
                        const SizedBox(width: 20),
                        
                        // Eşleşen kullanıcı avatarı
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFA4458), width: 3),
                            image: widget.match.profileImage.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(widget.match.profileImage),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: widget.match.profileImage.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 30,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Kullanıcı ismi
                    Text(
                      "${widget.match.name}, ${widget.match.age}",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 10),
                    
                    // Ortak mekanlar
                    if (widget.match.commonVenues.isNotEmpty)
                      Text(
                        "Ortak mekan: ${widget.match.commonVenues.first}",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    
                    const SizedBox(height: 30),
                    
                    // Butonlar
                    Row(
                      children: [
                        // Keşfetmeye devam et butonu
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _keepSwiping,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFA4458)),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: const Text(
                              "Keşfetmeye Devam",
                              style: TextStyle(
                                color: Color(0xFFFA4458),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 15),
                        
                        // Mesaj gönder butonu
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _goToChat,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFA4458),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                              elevation: 3,
                            ),
                            child: const Text(
                              "Mesaj Gönder",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
