import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import '../../providers/auth_providers.dart';

final userDocProvider = StreamProvider.family<ModUser?, String>((ref, uid) {
  if (uid.isEmpty) return const Stream.empty();
  final current = ref.watch(currentUserProvider);
  if (current == null) return const Stream.empty();
  final fs = ref.watch(firestoreServiceProvider);
  return fs.users.doc(uid).snapshots().map((snap) {
    if (!snap.exists) return null;
    final data = snap.data()!;
    return ModUser.fromMap(data);
  });
});

