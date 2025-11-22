import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import 'auth_providers.dart';

final userDocProvider = StreamProvider.family<ModUser?, String>((ref, uid) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.users.doc(uid).snapshots().map((snap) {
    if (!snap.exists) return null;
    final data = snap.data()!;
    return ModUser.fromMap(data);
  });
});
