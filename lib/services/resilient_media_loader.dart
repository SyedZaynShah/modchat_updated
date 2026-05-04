import 'dart:io';

/// Resilient HTTP loader with retry, backoff, and fallback behavior.
/// Ensures media widgets never get stuck in infinite loading.
class ResilientMediaLoader {
  static Future<HttpClientResponse?> get(Uri url) async {
    var attempts = 0;
    var delay = const Duration(seconds: 2);

    while (attempts < 3) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        final request = await client.getUrl(url);
        final response = await request.close();

        if (response.statusCode == 200) {
          return response;
        }
      } on SocketException {
        // Network unstable - increase delay and retry
        delay = const Duration(seconds: 5);
      } on HandshakeException {
        // SSL issues - increase delay and retry
        delay = const Duration(seconds: 5);
      } catch (_) {
        // Other errors - standard retry
      }

      attempts++;
      if (attempts < 3) {
        await Future.delayed(delay);
        delay = const Duration(seconds: 10);
      }
    }

    return null;
  }
}
