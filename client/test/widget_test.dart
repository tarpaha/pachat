import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pachat_client/screens/profiles_screen.dart';
import 'package:pachat_client/screens/device_profile_screen.dart';
import 'package:pachat_client/services/profile_storage.dart';
import 'package:pachat_client/services/prefs.dart';
import 'package:pachat_client/screens/chat_screen.dart';

void main() {
  testWidgets(
    'Back from chat closes connection and returns to profiles',
    (tester) async {
      late Directory root;
      late ServerSocket server;
      final sockets = <Socket>[];
      var disconnected = false;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('pachat-back-');
        server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((socket) {
          sockets.add(socket);
          socket.add(
            utf8.encode(
              '${jsonEncode({'type': 'server_info', 'database_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'history_version': 2})}\n',
            ),
          );
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                if (jsonDecode(line)['type'] == 'history') {
                  socket.add(
                    utf8.encode(
                      '${jsonEncode({'type': 'history_page', 'blocks': [], 'after_id': 0, 'has_more': false})}\n',
                    ),
                  );
                }
              }, onDone: () => disconnected = true);
        });
        final profile = await ProfileCatalog(root).open('Alice');
        await Prefs.save(
          profile.settings,
          LoginPrefs(host: '127.0.0.1', port: server.port),
        );
        await profile.close();
      });
      try {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(home: ProfilesScreen(catalog: ProfileCatalog(root))),
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Alice'));
          for (var i = 0; i < 30; i++) {
            await tester.pump();
            if (find.byType(ChatScreen).evaluate().isNotEmpty &&
                !tester
                    .widget<ChatScreen>(find.byType(ChatScreen))
                    .service
                    .isConnecting) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        await tester.runAsync(() async {
          await tester.pageBack();
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(find.text('PaChat — Profiles'), findsOneWidget);
        expect(find.text('Connect'), findsNothing);
        expect(disconnected, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          for (final socket in sockets) {
            socket.destroy();
          }
          await server.close();
          await root.delete(recursive: true);
        });
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'Device opens login directly without profile selection',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('pachat-device-widget-'),
      ))!;
      final catalog = ProfileCatalog(root);
      await tester.runAsync(() async {
        final profile = await catalog.openDeviceProfile();
        await profile.close();
        await tester.pumpWidget(
          MaterialApp(home: DeviceProfileScreen(catalog: catalog)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('PaChat'), findsOneWidget);
      expect(find.text('PaChat — default'), findsNothing);
      expect(find.text('Create / open profile'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await root.delete(recursive: true);
      });
    },
    skip: !Platform.isWindows,
  );

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
