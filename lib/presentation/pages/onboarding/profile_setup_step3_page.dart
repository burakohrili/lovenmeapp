import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import 'profile_setup_step4_page.dart';
import 'user_profile_provider.dart';

class ProfileSetupStep3Page extends ConsumerStatefulWidget {
  const ProfileSetupStep3Page({super.key});

  @override
  ConsumerState<ProfileSetupStep3Page> createState() => _ProfileSetupStep3PageState();
}

class _ProfileSetupStep3PageState extends ConsumerState<ProfileSetupStep3Page> {
  final Set<String> selectedHobbies = {};
  final int minHobbies = 3;
  final int maxHobbies = 10;

  // Hobi kategorileri ve hobileri - Türkçe karakterler düzeltildi
  final Map<String, List<Map<String, dynamic>>> hobbyCategories = {
    'Tümü': [],
    'Spor': [
      {'name': 'Fitness', 'icon': Icons.fitness_center},
      {'name': 'Koşu', 'icon': Icons.directions_run},
      {'name': 'Yoga', 'icon': Icons.self_improvement},
      {'name': 'Yüzme', 'icon': Icons.pool},
      {'name': 'Basketbol', 'icon': Icons.sports_basketball},
      {'name': 'Futbol', 'icon': Icons.sports_soccer},
      {'name': 'Voleybol', 'icon': Icons.sports_volleyball},
      {'name': 'Tenis', 'icon': Icons.sports_tennis},
      {'name': 'Bisiklet', 'icon': Icons.directions_bike},
      {'name': 'Dans', 'icon': Icons.music_note},
    ],
    'Sanat': [
      {'name': 'Resim', 'icon': Icons.palette},
      {'name': 'Müzik', 'icon': Icons.music_note},
      {'name': 'Fotoğrafçılık', 'icon': Icons.camera_alt},
      {'name': 'Yazı Yazma', 'icon': Icons.edit},
      {'name': 'Sinema', 'icon': Icons.movie},
      {'name': 'Tiyatro', 'icon': Icons.theater_comedy},
    ],
    'Teknoloji': [
      {'name': 'Kodlama', 'icon': Icons.code},
      {'name': 'Gaming', 'icon': Icons.sports_esports},
      {'name': 'Robotik', 'icon': Icons.smart_toy},
      {'name': '3D Tasarım', 'icon': Icons.view_in_ar},
    ],
    'Doğa': [
      {'name': 'Kamp', 'icon': Icons.cabin},
      {'name': 'Doğa Yürüyüşü', 'icon': Icons.hiking},
      {'name': 'Balık Tutma', 'icon': Icons.set_meal},
      {'name': 'Botanik', 'icon': Icons.local_florist},
    ],
    'Sosyal': [
      {'name': 'Seyahat', 'icon': Icons.flight},
      {'name': 'Yemek', 'icon': Icons.restaurant},
      {'name': 'Kahve', 'icon': Icons.coffee},
      {'name': 'Konserler', 'icon': Icons.music_note},
    ],
  };

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    if (profile.hobbies.isNotEmpty) {
      selectedHobbies.addAll(profile.hobbies);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<Map<String, dynamic>> getAllHobbies() {
    final allHobbies = <Map<String, dynamic>>[];
    for (var category in hobbyCategories.entries) {
      if (category.key != 'Tümü') {
        allHobbies.addAll(category.value);
      }
    }
    return allHobbies;
  }

  List<Map<String, dynamic>> getFilteredHobbies() {
    List<Map<String, dynamic>> allHobbies = [];
    
    // Tüm kategorilerden hobileri topla
    hobbyCategories.forEach((category, hobbies) {
      if (category != 'Tümü') {
        allHobbies.addAll(hobbies);
      }
    });
    
    return allHobbies;
  }

  void _toggleHobby(String hobby) {
    setState(() {
      if (selectedHobbies.contains(hobby)) {
        selectedHobbies.remove(hobby);
      } else {
        if (selectedHobbies.length < maxHobbies) {
          selectedHobbies.add(hobby);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('En fazla $maxHobbies hobi seçebilirsiniz'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    });
  }

  void _handleNext() {
    if (selectedHobbies.length < minHobbies) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('En az $minHobbies hobi seçmelisiniz'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    ref.read(userProfileProvider.notifier).updateHobbies(selectedHobbies.toList());
    
    // 🔥 YENİ: Hobileri Firebase'e kaydet
    _saveHobbiesToFirestore(selectedHobbies.toList());
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileSetupStep4Page(),
      ),
    );
  }
  
  // 🔥 YENİ: Hobileri Firestore'a kaydet
  Future<void> _saveHobbiesToFirestore(List<String> hobbies) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'hobbies': hobbies,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Hata olsa bile devam et
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryRegisterGradient,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Küçük ekranlar için header padding'i azalt
              final isSmallScreen = constraints.maxHeight < 700;
              final headerPadding = isSmallScreen ? 16.0 : 24.0;
              
              return Column(
                children: [
                  // Header - Compact
                  Container(
                    padding: EdgeInsets.fromLTRB(headerPadding, headerPadding, headerPadding, headerPadding / 2),
                    child: Column(
                      children: [
                        // Progress Indicator
                        Row(
                          children: List.generate(7, (index) {
                            final isCompleted = index < 3;
                            final isCurrent = index == 2;
                        
                            return Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isCompleted || isCurrent
                                          ? AppColors.white
                                          : AppColors.white.withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  if (index < 6)
                                    Expanded(
                                      child: Container(
                                        height: 2,
                                        color: isCompleted && !isCurrent
                                            ? AppColors.white
                                            : AppColors.white.withOpacity(0.3),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ),
                    
                        const SizedBox(height: 32),
                    
                        // Title
                        const Text(
                          'İlgi Alanlarınız',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '3/7 - En az $minHobbies, en fazla $maxHobbies hobi seçin',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.white.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                    
                        // Selection Counter
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedHobbies.length >= minHobbies 
                                ? Colors.green.withOpacity(0.3)
                                : AppColors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selectedHobbies.length >= minHobbies 
                                  ? Colors.green
                                  : AppColors.white.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selectedHobbies.length >= minHobbies
                                    ? Icons.check_circle
                                    : Icons.interests,
                                color: AppColors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${selectedHobbies.length} / $maxHobbies seçildi',
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              
              const SizedBox(height: 24),
              
              // Hobbies Grid
              Expanded(
                flex: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hobbies = getFilteredHobbies();
                    
                    if (hobbies.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.interests, size: 48, color: AppColors.white.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            Text(
                              'Bu kategoride hobi bulunamadı',
                              style: TextStyle(fontSize: 16, color: AppColors.white.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    // Responsive grid - ekran genişliğine göre sütun sayısı
                    int crossAxisCount = 2;
                    if (constraints.maxWidth > 600) {
                      crossAxisCount = 4;
                    } else if (constraints.maxWidth > 400) {
                      crossAxisCount = 3;
                    }
                    
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.9, // Biraz daha uzun kartlar
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: hobbies.length,
                      itemBuilder: (context, index) {
                        final hobby = hobbies[index];
                        final isSelected = selectedHobbies.contains(hobby['name']);
                        
                        return GestureDetector(
                          onTap: () => _toggleHobby(hobby['name']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? AppColors.white.withOpacity(0.3)
                                  : AppColors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected 
                                    ? AppColors.white
                                    : AppColors.white.withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected ? [
                                BoxShadow(
                                  color: AppColors.white.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ] : null,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    flex: 2,
                                    child: Icon(
                                      hobby['icon'] as IconData,
                                      size: constraints.maxWidth > 400 ? 28 : 24,
                                      color: isSelected 
                                          ? AppColors.white
                                          : AppColors.white.withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Flexible(
                                    flex: 1,
                                    child: Text(
                                      hobby['name'],
                                      style: TextStyle(
                                        fontSize: constraints.maxWidth > 400 ? 11 : 10,
                                        fontWeight: isSelected 
                                            ? FontWeight.bold 
                                            : FontWeight.w500,
                                        color: isSelected 
                                            ? AppColors.white
                                            : AppColors.white.withOpacity(0.8),
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              
              // Bottom Actions
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Next Button
                    ElevatedButton(
                      onPressed: selectedHobbies.length >= minHobbies
                          ? _handleNext
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedHobbies.length >= minHobbies
                            ? AppColors.white
                            : AppColors.white.withOpacity(0.3),
                        foregroundColor: selectedHobbies.length >= minHobbies
                            ? AppColors.primary
                            : AppColors.white.withOpacity(0.7),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: selectedHobbies.length >= minHobbies ? 2 : 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            selectedHobbies.length >= minHobbies
                                ? 'Devam Et'
                                : 'En az $minHobbies hobi seçin',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (selectedHobbies.length >= minHobbies) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Back Button
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Geri Dön',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  )
    );
  }
}