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
    'Cached history opens before reply; cursor, ordering and duplicates',
    () async {
      final listener = await ServerSocket.bind('127.0.0.1', 0);
      final accepted = listener.first;
      final disk = MemoryStorage()
        ..value = jsonEncode({
          'version': 2,
          'blocks': [
            {'id': 8, 'block': 'cached'},
          ],
        });
      final service = await ChatService.connect(
        host: '127.0.0.1',
        port: listener.port,
        friends: FriendsRepository(MemoryStorage()),
        historyStorage: disk,
      );
      expect(service.entries.single.serverId, 8);
      final peer = await accepted;
      addTearDown(() async {
        peer.destroy();
        await service.disconnect();
        service.dispose();
        await listener.close();
      });
      expect(jsonDecode(await readLines(peer).first), {
        'type': 'history',
        'after_id': 8,
      });
      for (final id in [10, 9, 9, 11]) {
        peer.add(
          utf8.encode(
            '${jsonEncode({'type': 'new_block', 'id': id, 'block': 'block$id'})}\n',
          ),
        );
      }
      await peer.flush();
      await until(() => service.entries.any((e) => e.serverId == 11));
      await service.retrySave();
      expect(service.entries.map((e) => e.serverId), [8, 9, 10, 11]);
      expect((jsonDecode(disk.value!)['blocks'] as List), hasLength(4));
    },
  );

  test('Connection failure leaves cached history readable', () async {
    final listener = await ServerSocket.bind('127.0.0.1', 0);
    final port = listener.port;
    await listener.close();
    final service = await ChatService.connect(
      host: '127.0.0.1',
      port: port,
      friends: FriendsRepository(MemoryStorage()),
      historyStorage: MemoryStorage()
        ..value = jsonEncode({
          'version': 2,
          'blocks': [
            {'id': 1, 'block': 'cached'},
          ],
        }),
    );
    addTearDown(service.dispose);
    await until(() => service.isDisconnected);
    expect(service.entries.single.block, 'cached');
    expect(service.error, isNotNull);
  });
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
      final databaseDir = await Directory.systemTemp.createTemp(
        'pachat-server-',
      );
      addTearDown(() => databaseDir.delete(recursive: true));
      final server = await Process.start(executable, [
        '--host',
        '127.0.0.1',
        '--port',
        '0',
        '--database',
        '${databaseDir.path}/pachat.db',
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
      await until(() => empty.entries.length == 3);
      expect(empty.entries.first.text, 'Hello Bob 🔐');
    },
    skip: executable.isEmpty
        ? 'Build Rust server and pass --dart-define=PACHAT_SERVER_BIN=<path>'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
