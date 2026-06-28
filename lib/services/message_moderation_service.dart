import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Thrown by the group send handler when the AI moderation model decides a
/// message is abusive / swear / threat. The [InputField] catches this to
/// restore the user's draft without showing a generic "Send failed" error
/// (the group screen already shows a friendly explanation).
class MessageBlockedException implements Exception {
  final String label;
  const MessageBlockedException(this.label);

  @override
  String toString() => 'MessageBlockedException($label)';
}

/// Result of running a message through the moderation model.
class ModerationResult {
  /// Predicted label, e.g. 'normal', 'abusive', 'swear', 'threat'.
  final String label;

  /// True if the message must NOT be sent (anything other than normal).
  final bool blocked;

  /// Confidence of the predicted label (0..1).
  final double confidence;

  const ModerationResult({
    required this.label,
    required this.blocked,
    required this.confidence,
  });

  /// Used when the model server is unreachable and we fail open.
  const ModerationResult.allowed()
      : label = 'normal',
        blocked = false,
        confidence = 0;
}

/// Calls the Python FastAPI moderation server (see `moderation_api/`) to decide
/// whether a group message is allowed to be sent.
class MessageModerationService {
  MessageModerationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// If true and the model server can't be reached, messages are ALLOWED to
  /// send (so the app keeps working when the server is down). Flip to `false`
  /// to instead block all messages until the server is reachable.
  static const bool _failOpen = true;

  static const Duration _timeout = Duration(seconds: 6);

  /// Base URL of the moderation API, from `.env` (MODERATION_API_URL).
  /// Falls back to localhost for desktop/web development.
  String get _baseUrl {
    final raw = dotenv.maybeGet('MODERATION_API_URL')?.trim();
    final url = (raw == null || raw.isEmpty) ? 'http://127.0.0.1:8000' : raw;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Runs [text] through the model. Never throws on network errors — it
  /// returns an allowed/blocked result based on [_failOpen] instead.
  Future<ModerationResult> classify(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const ModerationResult.allowed();

    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl/predict'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'text': trimmed}),
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        debugPrint('[moderation] HTTP ${res.statusCode}: ${res.body}');
        return _onError();
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return ModerationResult(
        label: (data['label'] ?? 'normal').toString(),
        blocked: data['blocked'] == true,
        confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      debugPrint('[moderation] request failed: $e');
      return _onError();
    }
  }

  ModerationResult _onError() {
    if (_failOpen) return const ModerationResult.allowed();
    return const ModerationResult(
      label: 'unavailable',
      blocked: true,
      confidence: 0,
    );
  }
}

final messageModerationServiceProvider =
    Provider<MessageModerationService>((ref) {
  final service = MessageModerationService();
  ref.onDispose(service._client.close);
  return service;
});
