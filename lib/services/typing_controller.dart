import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TypingController {
  TypingController({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Timer? _debounce;
  bool _isTyping = false;
  String? _activeType;
  String? _activeChatId;

  void onTextChanged(String text, String chatId) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _stopTyping(chatId);
      return;
    }

    if (_activeChatId != null && _activeChatId != chatId) {
      _stopTyping(_activeChatId!);
    }

    _activeChatId = chatId;
    if (!_isTyping) {
      _isTyping = true;
      _activeType = 'text';
      _setTyping(chatId, true, 'text');
    } else if (_activeType != 'text') {
      _activeType = 'text';
      _setTyping(chatId, true, 'text');
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      _stopTyping(chatId);
    });
  }

  void startVoice(String chatId) {
    if (_activeChatId != null && _activeChatId != chatId) {
      _stopTyping(_activeChatId!);
    }

    _debounce?.cancel();
    _activeChatId = chatId;
    _isTyping = true;

    if (_activeType != 'voice') {
      _activeType = 'voice';
      _setTyping(chatId, true, 'voice');
      return;
    }

    // Keep timestamp warm for remote stale filtering when recording continues.
    _setTyping(chatId, true, 'voice');
  }

  void onSend(String chatId) {
    _stopTyping(chatId);
  }

  void onLeaveChat(String chatId) {
    _stopTyping(chatId);
  }

  void dispose() {
    _debounce?.cancel();
    if (_activeChatId != null) {
      _stopTyping(_activeChatId!);
    }
  }

  void _stopTyping(String chatId) {
    if (!_isTyping || _activeChatId != chatId) return;
    _isTyping = false;
    _activeType = null;
    _debounce?.cancel();
    _setTyping(chatId, false, null);
  }

  Future<void> _setTyping(String chatId, bool active, String? type) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('dmChats').doc(chatId).update({
        'typing.$uid': {
          'active': active,
          'type': type,
          'timestamp': FieldValue.serverTimestamp(),
        },
      });
    } catch (_) {
      // Non-blocking: indicator is best-effort and should not break chat UX.
    }
  }
}
