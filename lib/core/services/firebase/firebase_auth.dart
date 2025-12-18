// lib/core/services/firebase/auth_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_init.dart';
import '../../models/firestore_models.dart';

class AuthService {
  final FirebaseService _firebase = FirebaseService();
  
  // Get current user
  User? get currentUser => _firebase.currentUser;
  String? get currentUserId => _firebase.currentUserId;
  Stream<User?> get authStateChanges => _firebase.authStateChanges;

  // Register with email and password
  Future<UserModel?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required int age,
  }) async {
    try {
      // Create auth user
      UserCredential result = await _firebase.auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = result.user;
      if (user == null) throw Exception('User creation failed');

      // Create user document in Firestore
      UserModel newUser = UserModel(
        uid: user.uid,
        email: email,
        name: name,
        age: age,
        photos: [],
        hobbies: [],
        favoriteVenues: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _firebase.firestore
        .collection('users')
        .doc(user.uid)
        .set(newUser.toFirestore());

      // Send email verification
      await sendEmailVerification();

      return newUser;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with email and password
  Future<UserModel?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _firebase.auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = result.user;
      if (user == null) throw Exception('Sign in failed');

      // Get user data from Firestore
      DocumentSnapshot doc = await _firebase.firestore
        .collection('users')
        .doc(user.uid)
        .get();

      if (!doc.exists) {
        throw Exception('User data not found');
      }

      // Update last active
      await updateLastActive();

      UserModel userModel = UserModel.fromFirestore(doc);
      return userModel;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      rethrow;
    }
  }

  // Send email verification
  Future<void> sendEmailVerification() async {
    try {
      User? user = currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
    } catch (e) {
      rethrow;
    }
  }

  // Check email verification status
  Future<bool> checkEmailVerification() async {
    try {
      User? user = currentUser;
      if (user != null) {
        await user.reload();
        user = _firebase.auth.currentUser;
        
        if (user!.emailVerified) {
          // Update Firestore
          await _firebase.firestore
            .collection('users')
            .doc(user.uid)
            .update({'isEmailVerified': true});
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebase.auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  // Update password
  Future<void> updatePassword(String newPassword) async {
    try {
      User? user = currentUser;
      if (user != null) {
        await user.updatePassword(newPassword);
      }
    } catch (e) {
      rethrow;
    }
  }

  // Update email
  Future<void> updateEmail(String newEmail) async {
    try {
      User? user = currentUser;
      if (user != null) {
        await user.verifyBeforeUpdateEmail(newEmail);
        
        // Update in Firestore
        await _firebase.firestore
          .collection('users')
          .doc(user.uid)
          .update({'email': newEmail});
        
      }
    } catch (e) {
      rethrow;
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      User? user = currentUser;
      if (user != null) {
        // Delete user data from Firestore
        await _firebase.firestore
          .collection('users')
          .doc(user.uid)
          .delete();
        
        // Delete auth account
        await user.delete();
        
      }
    } catch (e) {
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _firebase.signOut();
    } catch (e) {
      rethrow;
    }
  }

  // Update last active time
  Future<void> updateLastActive() async {
    try {
      if (currentUserId != null) {
        await _firebase.firestore
          .collection('users')
          .doc(currentUserId)
          .update({
            'lastActiveAt': FieldValue.serverTimestamp(),
          });
      }
    } catch (e) {
    }
  }

  // Get user data
  Future<UserModel?> getUserData(String userId) async {
    try {
      DocumentSnapshot doc = await _firebase.firestore
        .collection('users')
        .doc(userId)
        .get();
      
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get current user data
  Future<UserModel?> getCurrentUserData() async {
    if (currentUserId != null) {
      return getUserData(currentUserId!);
    }
    return null;
  }

  // Update user profile
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    try {
      if (currentUserId != null) {
        data['updatedAt'] = FieldValue.serverTimestamp();
        
        await _firebase.firestore
          .collection('users')
          .doc(currentUserId)
          .update(data);
        
      }
    } catch (e) {
      rethrow;
    }
  }

  // Handle auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Şifre çok zayıf';
      case 'email-already-in-use':
        return 'Bu email zaten kullanımda';
      case 'invalid-email':
        return 'Geçersiz email adresi';
      case 'user-not-found':
        return 'Kullanıcı bulunamadı';
      case 'wrong-password':
        return 'Hatalı şifre';
      case 'user-disabled':
        return 'Kullanıcı devre dışı';
      case 'too-many-requests':
        return 'Çok fazla deneme. Lütfen bekleyin';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok';
      default:
        return e.message ?? 'Bir hata oluştu';
    }
  }
}