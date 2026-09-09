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
  const FriendKey(this.name, this.publicKey, [this.pair]);
  String get id => publicKey;
  Map<String, dynamic> toJson() => {
    'name': name,
    'publicKey': publicKey,
    if (pair != null) 'pair': pair!.toJson(),
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
    return FriendKey(name, key, pair);
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
  List<FriendKey> get received =>
      List.unmodifiable(_friends.where((e) => e.pair == null));

  Future<void> load() async {
    final value = await storage.read();
    if (value != null) {
      final friends = decode(value);
      final ownKeys = _decodeOwnKeys(value);
      _friends = friends;
      _ownKeys = ownKeys;
    }
    notifyListeners();
  }

  static List<FriendKey> decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['version'] != 1 && json['version'] != 2) {
      throw const FormatException('Unsupported friends version');
    }
    final entries = (json['friends'] as List)
        .map((e) => FriendKey.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (entries.map((e) => e.id).toSet().length != entries.length) {
      throw const FormatException('Duplicate keys');
    }
    return entries;
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
        'version': 2,
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
      final next = await edit(List.of(_friends));
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
      if (items.any((e) => e.id == key)) {
        throw const FormatException('Key already exists');
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
                ? FriendKey(name.trim(), e.publicKey, e.pair)
                : e,
          )
          .toList(),
    );
  }

  Future<void> remove(FriendKey friend) =>
      _change((items) => items.where((e) => e.id != friend.id).toList());

  Future<void> restore(String value) async {
    final restored = decode(value);
    final ownKeys = _decodeOwnKeys(value);
    await _change(
      (items) {
        final ids = items.map((e) => e.id).toSet();
        return [...items, ...restored.where((e) => ids.add(e.id))];
      },
      editOwnKeys: (keys) {
        final ids = keys.map((e) => e.publicKeyBase64).toSet();
        return [...keys, ...ownKeys.where((e) => ids.add(e.publicKeyBase64))];
      },
    );
  }
}
