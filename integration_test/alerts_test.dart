// "Ready to watch" notifications against the real Seerr: the first look only takes note,
// and a request that becomes available afterwards is announced once.
//   flutter test integration_test/alerts_test.dart -d linux
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/state/alerts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('request alerts', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 6));
    final prefs = await SharedPreferences.getInstance();
    final key = 'alerted:${prefs.getString('userId')}';
    final before = prefs.getStringList(key);
    await prefs.remove(key);
    expect(await checkRequests(), 0, reason: 'first look only takes note');
    final seen = prefs.getStringList(key)!;
    debugPrint('ALERTS available requests: ${seen.length}');
    if (seen.isNotEmpty) {
      // Pretend the newest one just became available.
      await prefs.setStringList(key, seen.sublist(1));
      expect(await checkRequests(), 1, reason: 'one new arrival, one notification');
      expect(await checkRequests(), 0, reason: 'never twice');
    }
    if (before != null) await prefs.setStringList(key, before);
  });
}
