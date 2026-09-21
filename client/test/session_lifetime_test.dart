import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/screens/chat_screen.dart';
import 'package:pachat_client/screens/login_screen.dart';
import 'package:pachat_client/services/prefs.dart';
import 'package:pachat_client/services/profile_storage.dart';
import 'chat_service_test.dart' show until;
import 'history_sync_test.dart' show hello, page, send, block;

void main() {
  testWidgets(
    'Device session receives after leaving chat and reuses connection on reopening',
    (tester) async {
      late Directory root;
      late LocalProfile profile;
      late ServerSocket server;
      final peers = <Socket>[];
      var disconnected = false;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('pachat-session-');
        profile = await ProfileCatalog(root).openDeviceProfile();
        server = await ServerSocket.bind('127.0.0.1', 0);
        server.listen((peer) {
          peers.add(peer);
          hello(peer);
          peer
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                if (jsonDecode(line)['type'] == 'history') {
                  page(peer, 1, 0, false);
                }
              }, onDone: () => disconnected = true);
        });
        await Prefs.save(
          profile.settings,
          LoginPrefs(host: '127.0.0.1', port: server.port),
        );
      });
      try {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: LoginScreen(profile: profile, showProfileName: false),
            ),
          );
          await until(
            () => profile.chat != null && !profile.chat!.isConnecting,
          );
        });
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        final service = profile.chat!;
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsNothing);
        await tester.runAsync(() async {
          send(peers.single, block(1));
          await until(() => service.entries.length == 1);
          await service.messages.flush();
          expect(
            jsonDecode(
              (await profile.history.read())!,
            )['cursors'].values.single,
            1,
          );
        });
        expect(disconnected, isFalse);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Connect'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(
          identical(
            tester.widget<ChatScreen>(find.byType(ChatScreen)).service,
            service,
          ),
          isTrue,
        );
        expect(peers, hasLength(1));
        expect(service.entries.single.serverId, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          await profile.close();
          await until(() => disconnected);
          for (final peer in peers) {
            peer.destroy();
          }
          await server.close();
          await root.delete(recursive: true);
        });
      }
    },
    skip: !Platform.isWindows,
  );
}
