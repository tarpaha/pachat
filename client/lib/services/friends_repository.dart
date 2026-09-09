import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../crypto/crypto_service.dart';

abstract interface class PrivateStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class FriendKey {
  final String name;
  final String publicKey;
  final PaCrypto? pair;
  final String? peerPublicKey;
  const FriendKey(this.name, this.publicKey, [this.pair, this.peerPublicKey]);
  String get id => publicKey;
  Map<String, dynamic> toJson() => {
    'name': name,
    'publicKey': publicKey,
    if (pair != null) 'pair': pair!.toJson(),
    if (peerPublicKey != null) 'peerPublicKey': peerPublicKey,
  };
  factory FriendKey.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String).trim();
    final key = validatePublicKey(json['publicKey'] as String);
    final pair = json['pair'] == null
        ? null
        : PaCrypto.fromJson(Map<String, dynamic>.from(json['pair']));
    if (name.isEmpty || (pair != null && pair.publicKeyBase64 != key)) {
      throw const FormatException('Invalid friend entry');
    }
    final peerKey = json['peerPublicKey'] == null
        ? null
        : validatePublicKey(json['peerPublicKey'] as String);
    return FriendKey(name, key, pair, peerKey);
  }
}

String validatePublicKey(String value) {
  final bytes = base64.decode(value.replaceAll(RegExp(r'\s'), ''));
  final key = decodeRsaSpki(bytes);
  if (key.modulus!.bitLength != 2048 || key.exponent != BigInt.from(65537)) {
    throw const FormatException('Expected a PaChat RSA-2048 public key');
  }
  return base64.encode(encodeRsaSpki(key));
}

class FriendsRepository extends ChangeNotifier {
  final PrivateStorage storage;
  List<FriendKey> _friends = [];
  List<PaCrypto> _ownKeys = [];
  Future<void> _writes = Future.value();
  FriendsRepository(this.storage);
  Future<void> flush() => _writes;
  List<FriendKey> get friends => List.unmodifiable(_friends);
  List<FriendKey> get decryptionKeys => [
    for (final pair in _ownKeys) FriendKey('You', pair.publicKeyBase64, pair),
    ...created,
  ];
  Set<String> get ownPublicKeys =>
      _ownKeys.map((e) => e.publicKeyBase64).toSet();
  List<FriendKey> get recipients => [
    if (_ownKeys.isNotEmpty) FriendKey('You', _ownKeys.first.publicKeyBase64),
    ...received,
  ];
  List<FriendKey> get created =>
      List.unmodifiable(_friends.where((e) => e.pair != null));
  List<FriendKey> get received => List.unmodifiable(
    _friends
        .where((e) => e.peerPublicKey != null)
        .map((e) => FriendKey(e.name, e.peerPublicKey!)),
  );

  Future<void> load() async {
    final value = await storage.read();
    if (value != null) {
      final friends = await _prepare(decode(value));
      final ownKeys = _decodeOwnKeys(value);
      if ((jsonDecode(value) as Map<String, dynamic>)['version'] != 3) {
        await storage.write(_encode(friends, ownKeys));
      }
      _friends = friends;
      _ownKeys = ownKeys;
    }
    notifyListeners();
  }

  static List<FriendKey> decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['version'] != 1 && json['version'] != 2 && json['version'] != 3) {
      throw const FormatException('Unsupported friends version');
    }
    final entries = (json['friends'] as List)
        .map((e) => FriendKey.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (entries.map((e) => e.id).toSet().length != entries.length) {
      throw const FormatException('Duplicate keys');
    }
    if (json['version'] == 3) {
      if (entries.any((e) => e.pair == null)) {
        throw const FormatException('Missing local friend keys');
      }
      return entries;
    }
    // Join only unambiguous opposite-direction legacy entries with the same label.
    final contacts = entries.where((e) => e.pair != null).toList();
    for (final remote in entries.where((e) => e.pair == null)) {
      final label = remote.name.trim().toLowerCase();
      final localMatches = contacts
          .where((e) => e.pair != null && e.name.trim().toLowerCase() == label)
          .toList();
      final remoteMatches = entries
          .where((e) => e.pair == null && e.name.trim().toLowerCase() == label)
          .length;
      if (localMatches.length == 1 && remoteMatches == 1) {
        final local = localMatches.single;
        contacts[contacts.indexOf(local)] = FriendKey(
          local.name,
          local.publicKey,
          local.pair,
          remote.publicKey,
        );
      } else {
        contacts.add(FriendKey(remote.name, remote.publicKey));
      }
    }
    return contacts;
  }

  static Future<List<FriendKey>> _prepare(List<FriendKey> entries) async {
    final result = <FriendKey>[];
    for (final entry in entries) {
      if (entry.pair != null) {
        result.add(entry);
        continue;
      }
      final pair = await PaCrypto.generate();
      result.add(
        FriendKey(entry.name, pair.publicKeyBase64, pair, entry.publicKey),
      );
    }
    final localIds = result.map((e) => e.id).toSet();
    final remoteIds = result
        .where((e) => e.peerPublicKey != null)
        .map((e) => e.peerPublicKey!)
        .toList();
    if (localIds.length != result.length ||
        remoteIds.toSet().length != remoteIds.length) {
      throw const FormatException('Duplicate friend keys');
    }
    return result;
  }

  static List<PaCrypto> _decodeOwnKeys(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['version'] == 1) return [];
    return (json['ownKeys'] as List)
        .map((e) => PaCrypto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  String _encode(List<FriendKey> friends, List<PaCrypto> ownKeys) =>
      jsonEncode({
        'version': 3,
        'friends': friends.map((e) => e.toJson()).toList(),
        'ownKeys': ownKeys.map((e) => e.toJson()).toList(),
      });

  String exportJson() => _encode(_friends, _ownKeys);

  Future<void> ensureOwnKey() {
    if (_ownKeys.isNotEmpty) return Future.value();
    return _change(
      (items) => items,
      editOwnKeys: (keys) async =>
          keys.isEmpty ? [await PaCrypto.generate()] : keys,
    );
  }

  Future<void> _change(
    FutureOr<List<FriendKey>> Function(List<FriendKey>) edit, {
    FutureOr<List<PaCrypto>> Function(List<PaCrypto>)? editOwnKeys,
  }) {
    final operation = _writes.then((_) async {
      final next = await _prepare(await edit(List.of(_friends)));
      final ownKeys = editOwnKeys == null
          ? _ownKeys
          : await editOwnKeys(List.of(_ownKeys));
      await storage.write(_encode(next, ownKeys));
      _friends = next;
      _ownKeys = ownKeys;
      notifyListeners();
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> create(String name) async {
    if (name.trim().isEmpty) throw const FormatException('Enter a name');
    await _change((items) async {
      final pair = await PaCrypto.generate();
      return [...items, FriendKey(name.trim(), pair.publicKeyBase64, pair)];
    });
  }

  Future<void> importKey(String name, String value) async {
    if (name.trim().isEmpty) throw const FormatException('Enter a name');
    final key = validatePublicKey(value);
    await _change((items) {
      if (items.any((e) => e.peerPublicKey == key)) {
        throw const FormatException('Key already exists');
      }
      final matches = items
          .where(
            (e) =>
                e.name.toLowerCase() == name.trim().toLowerCase() &&
                e.peerPublicKey == null,
          )
          .toList();
      if (matches.length == 1) {
        final match = matches.single;
        return items
            .map(
              (e) => e.id == match.id
                  ? FriendKey(e.name, e.publicKey, e.pair, key)
                  : e,
            )
            .toList();
      }
      return [...items, FriendKey(name.trim(), key)];
    });
  }

  Future<void> rename(FriendKey friend, String name) async {
    if (name.trim().isEmpty) throw const FormatException('Enter a name');
    await _change(
      (items) => items
          .map(
            (e) => e.id == friend.id
                ? FriendKey(name.trim(), e.publicKey, e.pair, e.peerPublicKey)
                : e,
          )
          .toList(),
    );
  }

  Future<void> remove(FriendKey friend) =>
      _change((items) => items.where((e) => e.id != friend.id).toList());

  Future<void> setPeerKey(FriendKey friend, String value) async {
    final key = validatePublicKey(value);
    await _change((items) {
      if (items.any((e) => e.id != friend.id && e.peerPublicKey == key)) {
        throw const FormatException('Key already belongs to another friend');
      }
      if (!items.any((e) => e.id == friend.id)) {
        throw StateError('Friend no longer exists');
      }
      return items
          .map(
            (e) => e.id == friend.id
                ? FriendKey(e.name, e.publicKey, e.pair, key)
                : e,
          )
          .toList();
    });
  }

  Future<void> restore(String value) async {
    final restored = decode(value);
    final ownKeys = _decodeOwnKeys(value);
    await _change(
      (items) {
        for (final entry in restored) {
          // An old received-only backup has no local pair to preserve. Its
          // imported key may already belong to a migrated unified contact.
          if (entry.pair == null &&
              items.any((e) => e.peerPublicKey == entry.publicKey)) {
            continue;
          }
          final index = items.indexWhere((e) => e.id == entry.id);
          if (index < 0) {
            items.add(entry);
            continue;
          }
          final current = items[index];
          if (current.peerPublicKey != null &&
              entry.peerPublicKey != null &&
              current.peerPublicKey != entry.peerPublicKey) {
            throw const FormatException(
              'Backup contains a conflicting friend key',
            );
          }
          items[index] = FriendKey(
            current.name,
            current.publicKey,
            current.pair,
            current.peerPublicKey ?? entry.peerPublicKey,
          );
        }
        return items;
      },
      editOwnKeys: (keys) {
        final ids = keys.map((e) => e.publicKeyBase64).toSet();
        return [...keys, ...ownKeys.where((e) => ids.add(e.publicKeyBase64))];
      },
    );
  }
}
