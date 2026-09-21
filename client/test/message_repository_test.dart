import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/crypto/block_crypto.dart';
import 'package:pachat_client/protocol/messages.dart';
import 'package:pachat_client/services/friends_repository.dart';
import 'package:pachat_client/services/message_repository.dart';
import 'friends_test.dart' show MemoryStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const database = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test(
    'Headless ingestion decrypts, deduplicates and serializes durable cursor with ciphertext',
    () async {
      final friends = FriendsRepository(MemoryStorage());
      final disk = MemoryStorage();
      final repository = await MessageRepository.open(
        friends: friends,
        storage: disk,
      );
      addTearDown(repository.dispose);
      addTearDown(friends.dispose);
      await repository.selectDatabase(database);
      final encrypted = encryptBlock('private text', friends.recipients);
      await Future.wait([
        repository.ingest([NewBlock(1, encrypted)], throughId: 1),
        repository.ingest([
          NewBlock(1, encrypted),
          const NewBlock(2, 'unknown'),
        ], throughId: 2),
      ]);
      expect(repository.entries, hasLength(2));
      expect(repository.entries.first.text, 'private text');
      expect(repository.entries.first.fromSelf, isTrue);
      expect(repository.entries.last.text, isNull);
      expect(repository.cursor, 2);
      expect(disk.value, isNot(contains('private text')));
      expect(disk.value, isNot(contains('friendKey')));
      expect(jsonDecode(disk.value!)['cursors'][database], 2);
      await expectLater(
        repository.ingest([const NewBlock(2, 'different')], throughId: 2),
        throwsFormatException,
      );
      expect(repository.entries.last.block, 'unknown');

      final durable = disk.value;
      disk.fail = true;
      await repository.ingest([const NewBlock(3, 'unsaved')], throughId: 3);
      expect(repository.storageError, isNotNull);
      expect(disk.value, durable);
      final reopened = await MessageRepository.open(
        friends: friends,
        storage: disk,
      );
      addTearDown(reopened.dispose);
      expect(reopened.cursor, 2);
      expect(reopened.entries, hasLength(2));
      disk.fail = false;
      await repository.retrySave();
      expect(repository.storageError, isNull);
      expect(jsonDecode(disk.value!)['cursors'][database], 3);
    },
  );

  test(
    'Legacy holes are replayed from zero without losing cached blocks',
    () async {
      final disk = MemoryStorage()
        ..value = jsonEncode({
          'version': 3,
          'activeDatabaseId': database,
          'databases': {
            database: [
              {'id': 250, 'block': 'block250'},
            ],
          },
        });
      final friends = FriendsRepository(MemoryStorage());
      final repository = await MessageRepository.open(
        friends: friends,
        storage: disk,
      );
      addTearDown(repository.dispose);
      addTearDown(friends.dispose);
      expect(repository.cursor, 0);
      expect(repository.entries.single.serverId, 250);
      await repository.selectDatabase(database);
      for (var start = 1; start <= 250; start += 100) {
        final end = (start + 99).clamp(1, 250);
        await repository.ingest([
          for (var id = start; id <= end; id++) NewBlock(id, 'block$id'),
        ], throughId: end);
      }
      expect(
        repository.entries.map((e) => e.serverId),
        List.generate(250, (i) => i + 1),
      );
      expect(repository.cursor, 250);
      expect(jsonDecode(disk.value!)['version'], 4);
    },
  );
}
