import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_settings.dart';
import '../services/chat_settings_service.dart';
import 'auth_providers.dart';

final chatSettingsServiceProvider = Provider<ChatSettingsService>((ref) {
  final fs = ref.watch(firestoreServiceProvider);
  return ChatSettingsService(fs);
});

final chatSettingsMapProvider = StreamProvider<Map<String, ChatSettings>>((ref) {
  ref.keepAlive();
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final service = ref.watch(chatSettingsServiceProvider);
  return service.streamAll(uid);
});

final chatSettingsForChatProvider = Provider.family<ChatSettings, String>((
  ref,
  chatId,
) {
  final map = ref.watch(chatSettingsMapProvider).maybeWhen(
        data: (m) => m,
        orElse: () => const <String, ChatSettings>{},
      );
  return map[chatId] ?? ChatSettings.empty;
});
