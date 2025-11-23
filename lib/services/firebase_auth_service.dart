import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestore = FirestoreService();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// ✅ Sign In with email & password
  Future<UserCredential> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Reload user to fetch latest info (like emailVerified)
    await credential.user?.reload();

    return credential;
  }

  /// ✅ Sign Up with email & password
  Future<UserCredential> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await credential.user!.updateDisplayName(name);
    await credential.user!.sendEmailVerification();

    // Create profile in Firestore with final schema
    await _firestore.users.doc(credential.user!.uid).set({
      'userId': credential.user!.uid,
      'name': name,
      'email': email,
      'profileImageUrl': null,
      'about': '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeen': null,
      'blockedUsers': <String>[],
      'messageLimitDaily': 0,
      'messageSentToday': 0,
      'dmPrivacy': 'everyone',
      'role': 'user',
    });

    return credential;
  }

  /// Send email verification
  Future<void> sendEmailVerification() async {
    final u = _auth.currentUser;
    if (u != null && !u.emailVerified) {
      await u.sendEmailVerification();
    }
  }

  /// ✅ Reload current user info
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  /// ✅ Sign Out
  Future<void> signOut() async => _auth.signOut();
}
