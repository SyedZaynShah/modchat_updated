import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/call_service.dart';

final callServiceProvider = Provider<CallService>((ref) {
  return CallService();
});

final incomingCallsStreamProvider = StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final callService = ref.watch(callServiceProvider);
  return callService.listenToIncomingCalls();
});
