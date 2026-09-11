import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/screens/options_screen.dart';
import 'package:pachat_client/services/friends_repository.dart';
import 'package:pachat_client/services/prefs.dart';

class MemoryStorage implements PrivateStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

void main() {
  testWidgets('Options validates the port and persists the new server', (
    tester,
  ) async {
    final storage = MemoryStorage();
    await Prefs.save(storage, const LoginPrefs(host: '127.0.0.1', port: 9000));
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => OptionsScreen(storage: storage),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('127.0.0.1'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '10.0.2.2');
    await tester.enterText(find.byType(TextFormField).last, '70000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid port'), findsOneWidget);
    expect((await Prefs.load(storage)).host, '127.0.0.1');
    await tester.enterText(find.byType(TextFormField).last, '9001');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    final saved = await Prefs.load(storage);
    expect(saved.host, '10.0.2.2');
    expect(saved.port, 9001);
  });
}
