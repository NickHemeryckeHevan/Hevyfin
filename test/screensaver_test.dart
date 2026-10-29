import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hevyfin/ui/shell.dart' show Wordmark;
import 'package:hevyfin/ui/widgets/screensaver.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('an empty library gets the logo screensaver, and it moves', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogoSaver(index: 0)));
    expect(find.byType(Wordmark), findsOneWidget);
    final first = tester.getCenter(find.byType(Wordmark));
    await tester.pumpWidget(const MaterialApp(home: LogoSaver(index: 1)));
    await tester.pump(const Duration(seconds: 4));
    expect(tester.getCenter(find.byType(Wordmark)), isNot(first));
  });
}
