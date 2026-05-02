import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_settings.dart';
import 'firestore_service.dart';

class ChatSettingsService {
  ChatSettingsService(this._fs);

  final FirestoreService _fs;

  CollectionReference<Map<String, dynamic>> _col(String uid) {
    return _fs.users.doc(uid).collection('chatSettings');
  }

  Stream<Map<String, ChatSettings>> streamAll(String uid) {
    return _col(uid).snapshots().map((s) {
      final out = <String, ChatSettings>{};
      for (final d in s.docs) {
        out[d.id] = ChatSettings.fromMap(d.data());
      }
      return out;
    });
  }

  Future<ChatSettings> getOne(String uid, String chatId) async {
    final snap = await _col(uid).doc(chatId).get();
    if (!snap.exists) return ChatSettings.empty;
    return ChatSettings.fromMap(snap.data());
  }

  Future<int> getPinnedCount(String uid) async {
    final s = await _col(uid).where('pinned', isEqualTo: true).limit(3).get();
    return s.size;
  }

  Future<void> setPinned({
    required String uid,
    required String chatId,
    required bool pinned,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _col(uid).doc(chatId).set({
      'pinned': pinned,
      'pinnedAt': pinned ? nowMs : 0,
      'hidden': false,
    }, SetOptions(merge: true));
  }

  Future<void> setArchived({
    required String uid,
    required String chatId,
    required bool archived,
  }) async {
    await _col(uid).doc(chatId).set({
      'archived': archived,
      'hidden': false,
    }, SetOptions(merge: true));
  }

  Future<void> setHidden({
    required String uid,
    required String chatId,
    required bool hidden,
  }) async {
    await _col(uid).doc(chatId).set({
      'hidden': hidden,
    }, SetOptions(merge: true));
  }

  Future<void> setUnread({
    required String uid,
    required String chatId,
    required bool unread,
  }) async {
    await _col(uid).doc(chatId).set({
      'unread': unread,
    }, SetOptions(merge: true));
  }

  Future<void> setMutedUntil({
    required String uid,
    required String chatId,
    required Timestamp? mutedUntil,
  }) async {
    await _col(uid).doc(chatId).set({
      'mutedUntil': mutedUntil,
    }, SetOptions(merge: true));
  }
}
