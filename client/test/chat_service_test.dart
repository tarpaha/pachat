import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/services/chat_service.dart';
import 'package:pachat_client/services/friends_repository.dart';
import 'package:pachat_client/protocol/messages.dart';
import 'friends_test.dart' show MemoryStorage;

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Expected chat state not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Framing handles split Unicode, multiple lines and truncated frames',
    () async {
      final bytes = utf8.encode('привет\nnext\n');
      expect(
        await readLines(
          Stream.fromIterable([bytes.sublist(0, 1), bytes.sublist(1)]),
        ).toList(),
        ['привет', 'next'],
      );
      await expectLater(
        readLines(Stream.value(utf8.encode('partial'))).toList(),
        throwsFormatException,
      );
    },
  );

  const executable = String.fromEnvironment('PACHAT_SERVER_BIN');
  test(
    'Real Rust server: encrypted exchange, unknown block, echo, restart and local history',
    () async {
      final server = await Process.start(executable, [
        '--host',
        '127.0.0.1',
        '--port',
        '0',
      ]);
      addTearDown(() async {
        server.kill();
        await server.exitCode;
      });
      final startup = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      final port = int.parse(startup.split(':').last);
      final alice = FriendsRepository(MemoryStorage());
      final bob = FriendsRepository(MemoryStorage());
      await alice.create('Bob');
      await bob.create('Alice');
      await bob.importKey('Alice', alice.created.single.publicKey);
      await alice.importKey('Bob', bob.created.single.publicKey);
      final aliceDisk = MemoryStorage();
      final a = await ChatService.connect(
        host: '127.0.0.1',
        port: port,
        friends: alice,
        historyStorage: aliceDisk,
      );
      final b = await ChatService.connect(
        host: '127.0.0.1',
        port: port,
        friends: bob,
        historyStorage: MemoryStorage(),
      );
      final c = await ChatService.connect(
        host: '127.0.0.1',
        port: port,
        friends: FriendsRepository(MemoryStorage()),
        historyStorage: MemoryStorage(),
      );
      addTearDown(() async {
        await a.disconnect();
        await b.disconnect();
        await c.disconnect();
        a.dispose();
        b.dispose();
        c.dispose();
      });
      await a.sendChat('Hello Bob 🔐');
      await until(
        () =>
            b.entries.length == 1 &&
            c.entries.length == 1 &&
            a.entries.length == 1,
      );
      expect(b.entries.single.text, 'Hello Bob 🔐');
      expect(b.entries.single.friendKey, bob.created.single.id);
      expect(c.entries.single.text, isNull);
      expect(a.entries, hasLength(1));
      expect(a.entries.single.serverId, 1);
      expect(aliceDisk.value!.contains('Hello Bob'), isFalse);
      expect(aliceDisk.value!.contains('friendKey'), isFalse);
      expect(a.entries.single.text, 'Hello Bob 🔐');
      expect(a.entries.single.fromSelf, isTrue);
      expect(b.entries.single.fromSelf, isFalse);
      aliceDisk.fail = true;
      await b.sendChat('Привет, Алиса');
      await until(() => a.entries.length == 2 && b.entries.length == 2);
      expect(a.entries.last.text, 'Привет, Алиса');
      expect(a.isDisconnected, isFalse);
      expect(a.storageError, isNotNull);
      aliceDisk.fail = false;
      await a.retrySave();
      expect(a.storageError, isNull);
      expect(aliceDisk.value!.contains('Привет'), isFalse);
      final raw = await Socket.connect('127.0.0.1', port);
      raw.add(utf8.encode(encodePublish('invalid encrypted payload')));
      await raw.flush();
      await until(() => a.entries.length == 3);
      expect(a.entries.last.text, isNull);
      raw.destroy();
      await a.disconnect();
      final restored = await ChatService.connect(
        host: '127.0.0.1',
        port: port,
        friends: alice,
        historyStorage: aliceDisk,
      );
      addTearDown(() {
        restored.dispose();
      });
      expect(restored.entries, hasLength(3));
      expect(restored.entries.first.text, 'Hello Bob 🔐');
      expect(restored.entries.first.fromSelf, isTrue);
      expect(restored.entries[1].text, 'Привет, Алиса');
      final noKeys = await ChatService.connect(
        host: '127.0.0.1',
        port: port,
        friends: FriendsRepository(MemoryStorage()),
        historyStorage: aliceDisk,
      );
      expect(noKeys.entries.every((e) => e.text == null), isTrue);
      await noKeys.disconnect();
      noKeys.dispose();
      final empty = await ChatService.connect(
        host: '127.0.0.1',
        port: port,
        friends: alice,
        historyStorage: MemoryStorage(),
      );
      addTearDown(() {
        empty.dispose();
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(empty.entries, isEmpty);
    },
    skip: executable.isEmpty
        ? 'Build Rust server and pass --dart-define=PACHAT_SERVER_BIN=<path>'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
