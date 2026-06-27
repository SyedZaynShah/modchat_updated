import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/group_call_service.dart';

final groupCallServiceProvider = Provider<GroupCallService>((ref) {
  return GroupCallService();
});

/// Stream provider for incoming group calls
/// Listens globally for group calls where current user is a participant
final incomingGroupCallsStreamProvider = StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final groupCallService = ref.watch(groupCallServiceProvider);
  return groupCallService.listenToIncomingGroupCalls();
});
