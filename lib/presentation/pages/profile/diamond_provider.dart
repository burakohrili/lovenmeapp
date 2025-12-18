// lib/presentation/pages/profile/diamond_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/diamond_service.dart';

class DiamondState {
  final int balance;
  final int totalEarned;
  final int totalSpent;
  final List<Map<String, dynamic>> purchaseHistory;
  final List<Map<String, dynamic>> spendingHistory;
  final List<Map<String, dynamic>> activeMayorships;
  final bool isLoading;

  DiamondState({
    this.balance = 0,
    this.totalEarned = 0,
    this.totalSpent = 0,
    this.purchaseHistory = const [],
    this.spendingHistory = const [],
    this.activeMayorships = const [],
    this.isLoading = false,
  });

  DiamondState copyWith({
    int? balance,
    int? totalEarned,
    int? totalSpent,
    List<Map<String, dynamic>>? purchaseHistory,
    List<Map<String, dynamic>>? spendingHistory,
    List<Map<String, dynamic>>? activeMayorships,
    bool? isLoading,
  }) {
    return DiamondState(
      balance: balance ?? this.balance,
      totalEarned: totalEarned ?? this.totalEarned,
      totalSpent: totalSpent ?? this.totalSpent,
      purchaseHistory: purchaseHistory ?? this.purchaseHistory,
      spendingHistory: spendingHistory ?? this.spendingHistory,
      activeMayorships: activeMayorships ?? this.activeMayorships,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class DiamondNotifier extends StateNotifier<DiamondState> {
  DiamondNotifier() : super(DiamondState()) {
    _loadDiamondData();
  }

  final DiamondService _diamondService = DiamondService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _loadDiamondData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    state = state.copyWith(isLoading: true);

    try {
      final balance = await _diamondService.getUserDiamondBalance(user.uid);
      final spendingHistory = await _diamondService.getDiamondSpendingHistory(user.uid);
      final activeMayorships = await _diamondService.getUserActiveMayorships(user.uid);

      state = state.copyWith(
        balance: balance,
        spendingHistory: spendingHistory,
        activeMayorships: activeMayorships,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> purchaseDiamonds(DiamondPackageInfo package) async {
    state = state.copyWith(isLoading: true);
    
    try {
      final success = await _diamondService.purchaseDiamonds(package);
      if (success) {
        await _loadDiamondData(); // Verileri yenile
      }
      
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<bool> bidForMayorship(String venueId, String venueName, int diamonds) async {
    try {
      final success = await _diamondService.bidForMayorship(venueId, venueName, diamonds);
      if (success) {
        await _loadDiamondData(); // Verileri yenile
      }
      return success;
    } catch (e) {
      rethrow;
    }
  }

  void refreshData() {
    _loadDiamondData();
  }

  // Getter'lar
  bool canAfford(int diamonds) => state.balance >= diamonds;
  int get activeMayorshipCount => state.activeMayorships.length;
  int get totalMayorshipValue => state.activeMayorships.fold(0, 
      (sum, mayoreship) => sum + (mayoreship['highestBid'] as int? ?? 0));
}

// Provider tanımları
final diamondProvider = StateNotifierProvider<DiamondNotifier, DiamondState>((ref) {
  return DiamondNotifier();
});

// Convenience provider'lar
final diamondBalanceProvider = Provider<int>((ref) {
  return ref.watch(diamondProvider).balance;
});

final activeMayorshipsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(diamondProvider).activeMayorships;
});

final canAffordProvider = Provider.family<bool, int>((ref, diamonds) {
  final balance = ref.watch(diamondProvider).balance;
  return balance >= diamonds;
});
