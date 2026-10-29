import 'dart:convert';

import 'package:http/http.dart' as http;

import '../host.dart';
import 'jellyfin.dart';

/// Niql's answer: a line of chat and up to three titles from the library, with a reason each.
class NiqlAnswer {
  final String answer;
  final List<({String id, String why})> picks;
  const NiqlAnswer(this.answer, this.picks);
}

/// "Ask": an optional recommendation service of your own picks something to watch from the
/// library (the API is in docs/niql.md). It is off unless an address is set, in Settings or
/// at build time with --dart-define=NIQL_URL=…, because each question carries the user's
/// Jellyfin token (so the service can check who is asking).
abstract final class Niql {
  /// The address from Settings (AppState sets it).
  static String configured = '';

  /// Settings first, then the build's default. "/niql" means the web version's own address.
  static String get url {
    var u = configured.trim();
    if (u.isEmpty) u = const String.fromEnvironment('NIQL_URL');
    if (u.startsWith('/')) u = '${Host.origin}$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static bool get enabled => url.isNotEmpty;

  static Future<NiqlAnswer> ask(JellyfinClient c, String text) async {
    if (!enabled) throw 'No recommendation service is set up';
    final res = await http
        .post(
          Uri.parse('$url/api/hevyfin/ask'),
          headers: {'Content-Type': 'application/json', 'X-Emby-Token': c.token},
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(seconds: 120));
    final body = res.body.isEmpty ? const {} : jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    if (res.statusCode != 200) throw '${body['error'] ?? 'The recommendation service is unavailable (${res.statusCode})'}';
    return NiqlAnswer('${body['answer'] ?? ''}', [
      for (final p in (body['picks'] as List? ?? const []).cast<Map>()) (id: '${p['id']}', why: '${p['why'] ?? ''}'),
    ]);
  }
}
