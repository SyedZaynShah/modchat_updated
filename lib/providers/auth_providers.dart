import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>(
  (ref) => FirebaseAuthService(),
);
final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(),
);

final authStateProvider = StreamProvider<fb_auth.User?>((ref) {
  final auth = ref.watch(firebaseAuthServiceProvider);
  return auth.authStateChanges;
});

final currentUserProvider = Provider<fb_auth.User?>((ref) {
  final auth = fb_auth.FirebaseAuth.instance;
  return auth.currentUser;
});
