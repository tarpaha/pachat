import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/services/profile_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Delete removes only the selected profile, including when open',
    () async {
      final root = await Directory.systemTemp.createTemp('pachat-delete-');
      final catalog = ProfileCatalog(root);
      final alice = await catalog.open('Alice');
      final bob = await catalog.open('Bob');
      final bobKey = bob.friends.ownPublicKeys.single;
      try {
        await alice.history('server').write('encrypted blocks');
        await catalog.delete('alice');
        expect(await alice.directory.exists(), isFalse);
        expect(await catalog.names(), ['Bob']);
        await bob.close();
        final reopened = await catalog.open('Bob');
        expect(reopened.friends.ownPublicKeys.single, bobKey);
        await reopened.close();
      } finally {
        await alice.close();
        await bob.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test('Device profile is created once on a fresh install', () async {
    final root = await Directory.systemTemp.createTemp('pachat-device-new-');
    final catalog = ProfileCatalog(root);
    try {
      final first = await catalog.openDeviceProfile();
      final key = first.friends.ownPublicKeys.single;
      await first.close();
      final next = await catalog.openDeviceProfile();
      expect(next.friends.ownPublicKeys.single, key);
      expect(await catalog.names(), ['default']);
      await next.close();
    } finally {
      await root.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
  test(
    'Profiles isolate persisted keys and history; corrupted keys are preserved',
    () async {
      final root = await Directory.systemTemp.createTemp('pachat-profiles-');
      final catalog = ProfileCatalog(root);
      final alice = await catalog.open('Alice');
      final bob = await catalog.open('Bob');
      final ownKey = alice.friends.ownPublicKeys.single;
      try {
        await alice.friends.create('Bob');
        final key = alice.friends.created.single.publicKey;
        await bob.friends.importKey('Alice', key);
        await alice.history('server:9000').write('{"version":2,"blocks":[]}');
        expect(await bob.history('server:9000').read(), isNull);
        await alice.close();
        final reopened = await catalog.open('Alice');
        expect(reopened.friends.ownPublicKeys.single, ownKey);
        expect(reopened.friends.created.single.publicKey, key);
        expect(reopened.friends.created.single.name, 'Bob');
        expect(await catalog.names(), ['Alice', 'Bob']);
        await reopened.close();
        await bob.close();
        final reopenedBob = await catalog.open('Bob');
        expect(reopenedBob.friends.received.single.publicKey, key);
        await reopenedBob.close();
        if (Platform.isWindows) {
          final file = File('${alice.directory.path}/friends.dpapi');
          final encrypted = await file.readAsString();
          expect(encrypted.contains(key), isFalse);
          await file.writeAsString('corrupted');
          await expectLater(catalog.open('Alice'), throwsA(anything));
          expect(await file.readAsString(), 'corrupted');
        }
      } finally {
        await alice.close();
        await bob.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
