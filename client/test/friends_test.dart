import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/services/friends_repository.dart';
import 'package:pachat_client/crypto/block_crypto.dart';
import 'package:pachat_client/crypto/backup_crypto.dart';

class MemoryStorage implements PrivateStorage {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (fail) throw StateError('Disk failure');
    value = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Keys survive reload; multiple recipients decrypt and strangers cannot',
    () async {
      final disk = MemoryStorage();
      final alice = FriendsRepository(disk);
      final charlie = FriendsRepository(MemoryStorage());
      await alice.create('Bob');
      await charlie.create('Bob');
      final bob = FriendsRepository(MemoryStorage());
      await bob.importKey('Alice', alice.created.single.publicKey);
      await bob.importKey('Charlie', charlie.created.single.publicKey);
      final block = encryptBlock('Привет!', bob.received);
      final restarted = FriendsRepository(disk);
      await restarted.load();
      expect(decryptBlock(block, restarted.created)!.text, 'Привет!');
      expect(decryptBlock(block, charlie.created)!.text, 'Привет!');
      expect(decryptBlock(block, bob.created), isNull);
      expect(decryptBlock('invalid', restarted.created), isNull);
      expect(encryptBlock('Привет!', bob.received), isNot(block));
      await expectLater(
        bob.importKey('duplicate', alice.created.single.publicKey),
        throwsFormatException,
      );
      disk.fail = true;
      await expectLater(alice.remove(alice.created.single), throwsStateError);
      expect(alice.created, hasLength(1));
      final backup = encryptBackup((bob.exportJson(), 'a long test password'));
      final restored = FriendsRepository(MemoryStorage());
      await restored.restore(decryptBackup((backup, 'a long test password')));
      expect(restored.received, hasLength(2));
      expect(
        () => decryptBackup((backup, 'incorrect password')),
        throwsA(anything),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
