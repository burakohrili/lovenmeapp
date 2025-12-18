import 'package:flutter/foundation.dart';

class LoadingStateManager extends ChangeNotifier {
  final Map<String, bool> _loadingStates = {};
  final Map<String, String> _errorMessages = {};

  /// Check if specific operation is loading
  bool isLoading(String operation) {
    return _loadingStates[operation] ?? false;
  }

  /// Check if any operation is loading
  bool get isAnyLoading {
    return _loadingStates.values.any((loading) => loading);
  }

  /// Get error message for specific operation
  String? getError(String operation) {
    return _errorMessages[operation];
  }

  /// Set loading state for specific operation
  void setLoading(String operation, bool loading) {
    if (_loadingStates[operation] != loading) {
      _loadingStates[operation] = loading;
      
      // Clear error when starting new operation
      if (loading) {
        _errorMessages.remove(operation);
      }
      
      notifyListeners();
    }
  }

  /// Set error for specific operation
  void setError(String operation, String? error) {
    if (error != null) {
      _errorMessages[operation] = error;
      _loadingStates[operation] = false;
    } else {
      _errorMessages.remove(operation);
    }
    notifyListeners();
  }

  /// Clear specific operation state
  void clear(String operation) {
    _loadingStates.remove(operation);
    _errorMessages.remove(operation);
    notifyListeners();
  }

  /// Clear all states
  void clearAll() {
    _loadingStates.clear();
    _errorMessages.clear();
    notifyListeners();
  }

  /// Execute operation with automatic loading state management
  Future<T> executeOperation<T>(
    String operation,
    Future<T> Function() task, {
    Function(String error)? onError,
  }) async {
    try {
      setLoading(operation, true);
      final result = await task();
      setLoading(operation, false);
      return result;
    } catch (e) {
      final errorMessage = e.toString();
      setError(operation, errorMessage);
      onError?.call(errorMessage);
      rethrow;
    }
  }

  @override
  void dispose() {
    clearAll();
    super.dispose();
  }
}

/// Common operation names for consistency
class LoadingOperations {
  static const String register = 'register';
  static const String login = 'login';
  static const String sendSms = 'send_sms';
  static const String verifySms = 'verify_sms';
  static const String uploadImage = 'upload_image';
  static const String saveProfile = 'save_profile';
  static const String updateProfile = 'update_profile';
  static const String googleSignIn = 'google_sign_in';
  static const String appleSignIn = 'apple_sign_in';
  static const String sendPasswordReset = 'send_password_reset';
  static const String deleteAccount = 'delete_account';
  static const String updatePassword = 'update_password';
  static const String refreshProfile = 'refresh_profile';
}
