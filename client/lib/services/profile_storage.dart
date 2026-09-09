import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../crypto/block_crypto.dart';
import '../crypto/windows_storage_crypto.dart';
import 'friends_repository.dart';

String storageId(String value) =>
    blockDigest(value).replaceAll('/', '_').replaceAll('+', '-');

class AtomicFileStorage implements PrivateStorage {
  final File file;
  AtomicFileStorage(this.file);
  @override
  Future<String?> read() async {
    final exists = await file.exists();
    if (!exists) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}

class ProfileKeysStorage implements PrivateStorage {
  final String id;
  final AtomicFileStorage file;
  ProfileKeysStorage(this.id, Directory directory)
    : file = AtomicFileStorage(File('${directory.path}/friends.dpapi'));
  FlutterSecureStorage get secure => FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'pachat_profile_$id'),
  );
  @override
  Future<String?> read() async {
    if (!Platform.isWindows) return secure.read(key: 'friends.$id');
    final value = await file.read();
    if (value == null) return null;
    return unprotectWindows(value);
  }

  @override
  Future<void> write(String value) async {
    if (!Platform.isWindows) {
      await secure.write(key: 'friends.$id', value: value);
      return;
    }
    final encrypted = protectWindows(value);
    await file.write(encrypted);
  }
}

class ProfileCatalog {
  final Directory root;
  ProfileCatalog(this.root);
  static Future<ProfileCatalog> device() async {
    final support = await getApplicationSupportDirectory();
    return ProfileCatalog(Directory('${support.path}/profiles'));
  }

  Future<List<String>> names() async {
    await root.create(recursive: true);
    final names = <String>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final metadata = File('${entry.path}/profile.json');
      final exists = await metadata.exists();
      if (!exists) continue;
      final data =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      names.add(data['name'] as String);
    }
    names.sort();
    return names;
  }

  Future<LocalProfile> open(String name) async {
    name = name.trim();
    if (name.isEmpty) throw const FormatException('Enter a profile name');
    final id = storageId(name.toLowerCase());
    final directory = Directory('${root.path}/$id');
    await directory.create(recursive: true);
    if (!LocalProfile.active.add(directory.absolute.path)) {
      throw StateError('Profile is already open');
    }
    RandomAccessFile? lock;
    try {
      lock = await File(
        '${directory.path}/session.lock',
      ).open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final meta = AtomicFileStorage(File('${directory.path}/profile.json'));
      final previous = await meta.read();
      if (previous == null) {
        await meta.write(jsonEncode({'name': name}));
      } else {
        name = (jsonDecode(previous) as Map<String, dynamic>)['name'] as String;
      }
      final friends = FriendsRepository(ProfileKeysStorage(id, directory));
      await friends.load();
      return LocalProfile(name, directory, friends, lock);
    } catch (e) {
      await lock?.close();
      LocalProfile.active.remove(directory.absolute.path);
      rethrow;
    }
  }
}

class LocalProfile {
  static final active = <String>{};
  final String name;
  final Directory directory;
  final FriendsRepository friends;
  final RandomAccessFile _lock;
  bool _closed = false;
  LocalProfile(this.name, this.directory, this.friends, this._lock);
  PrivateStorage history(String server) => AtomicFileStorage(
    File('${directory.path}/history-${storageId(server)}.json'),
  );
  PrivateStorage get settings =>
      AtomicFileStorage(File('${directory.path}/settings.json'));
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await friends.flush();
    friends.dispose();
    await _lock.close();
    active.remove(directory.absolute.path);
  }
}
