import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pachat_client/screens/profiles_screen.dart';
import 'package:pachat_client/services/profile_storage.dart';

void main() {
  testWidgets(
    'Choose a persistent profile and open friends without connecting',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('pachat-widget-'),
      ))!;
      final catalog = ProfileCatalog(root);
      late String peerKey;
      await tester.runAsync(() async {
        final profile = await catalog.open('Alice');
        await profile.friends.create('Bob');
        peerKey = profile.friends.friends.single.publicKey;
        await profile.close();
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: ProfilesScreen(catalog: catalog)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('PaChat — Profiles'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.runAsync(() async {
        await tester.tap(find.text('Create / open profile'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('PaChat — Alice'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();
      expect(find.text('Add friend'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Share public key'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Add friend’s key'));
      await tester.pumpAndSettle();
      expect(find.text('Public key — Bob'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'invalid');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save key:'), findsOneWidget);
      await tester.enterText(find.byType(TextField), peerKey);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save key'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('View / edit friend’s key'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        peerKey,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.pageBack();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => root.delete(recursive: true));
    },
    skip: !Platform.isWindows,
  );
}
