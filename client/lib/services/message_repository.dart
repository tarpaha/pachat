import 'dart:async';
import 'package:flutter/foundation.dart';
import '../crypto/block_crypto.dart';
import '../models/chat_event.dart';
import '../protocol/messages.dart';
import 'friends_repository.dart';
import 'history_cache.dart';

List<ChatEntry> _decode((List<ChatEntry>, List<FriendKey>, Set<String>) args) =>
    args.$1.map((record) {
      final decoded = decryptBlock(record.block, args.$2);
      return ChatEntry(
        serverId: record.serverId,
        block: record.block,
        friendKey: decoded?.friendKey,
        text: decoded?.text,
        timestamp: decoded?.timestamp,
        fromSelf: decoded != null && args.$3.contains(decoded.friendKey),
      );
    }).toList();

/// One serialized writer per open profile. Usable without a socket or a screen.
/// Background entry points must acquire ownership of the profile before opening
/// another repository; this queue is not a cross-isolate file lock.
class MessageRepository extends ChangeNotifier {
  final FriendsRepository friends;
  final PrivateStorage storage;
  final HistoryCache _history;
  List<ChatEntry> _entries;
  Future<void> _work = Future.value();
  bool _disposed = false;
  bool databaseVerified = false;
  String? storageError;
  String? processingError;

  MessageRepository._(this.friends, this.storage, this._history, this._entries);

  static Future<MessageRepository> open({
    required FriendsRepository friends,
    required PrivateStorage storage,
  }) async {
    await friends.ensureOwnKey();
    final history = HistoryCache.decode(await storage.read());
    final entries = await compute(_decode, (
      history.preview,
      friends.decryptionKeys,
      friends.ownPublicKeys,
    ));
    final repository = MessageRepository._(friends, storage, history, entries);
    friends.addListener(repository._friendsChanged);
    return repository;
  }

  List<ChatEntry> get entries => List.unmodifiable(_entries);
  int get cursor => _history.cursors[_history.activeDatabaseId] ?? 0;
  String? get databaseId => _history.activeDatabaseId;

  Future<void> _serial(Future<void> Function() action) {
    if (_disposed) return Future.error(StateError('Repository is closed'));
    final next = _work.then((_) => action());
    _work = next.catchError((Object _) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> selectDatabase(String id) => _serial(() async {
    _entries = await compute(_decode, (
      _history.databases[id] ?? <ChatEntry>[],
      friends.decryptionKeys,
      friends.ownPublicKeys,
    ));
    _history.activeDatabaseId = id;
    databaseVerified = true;
    await _persist();
  });

  /// Advance only across a server-confirmed ordered prefix, never to the
  /// highest cached ID (legacy caches can contain gaps).
  Future<void> ingest(List<NewBlock> blocks, {required int throughId}) =>
      _serial(() async {
        if (!databaseVerified) throw StateError('Database is not selected');
        if (throughId < cursor) {
          throw const FormatException('Cursor moved backwards');
        }
        if (throughId != (blocks.isEmpty ? cursor : blocks.last.id)) {
          throw const FormatException('Cursor does not match message batch');
        }
        final existing = {for (final entry in _entries) entry.serverId: entry};
        final added = <ChatEntry>[];
        var previous = 0;
        for (final block in blocks) {
          if (block.id <= previous || block.id > throughId) {
            throw const FormatException('Unordered message batch');
          }
          previous = block.id;
          final old = existing[block.id];
          if (old != null) {
            if (old.block != block.block) {
              throw const FormatException(
                'Conflicting block for the same database and ID',
              );
            }
          } else {
            added.add(ChatEntry(serverId: block.id, block: block.block));
          }
        }
        final decoded = await compute(_decode, (
          added,
          friends.decryptionKeys,
          friends.ownPublicKeys,
        ));
        _entries = [..._entries, ...decoded]
          ..sort((a, b) => a.serverId.compareTo(b.serverId));
        _history.cursors[databaseId!] = throughId;
        await _persist();
      });

  void _friendsChanged() {
    unawaited(
      _serial(() async {
        _entries = await compute(_decode, (
          _entries,
          friends.decryptionKeys,
          friends.ownPublicKeys,
        ));
        processingError = null;
        _notify();
      }).catchError((Object e) {
        processingError = 'Could not refresh messages: $e';
        _notify();
      }),
    );
  }

  Future<void> _persist() async {
    try {
      if (databaseVerified) _history.databases[databaseId!] = _entries;
      // Cursor and raw blocks are saved together. A failed write leaves the
      // previous durable cursor intact, so restart replays unsaved blocks.
      await storage.write(_history.encode());
      storageError = null;
    } catch (e) {
      storageError = 'History was not saved. Messages remain in memory. $e';
    }
    _notify();
  }

  Future<void> retrySave() => _serial(_persist);
  Future<void> flush() => _work;

  @override
  void dispose() {
    _disposed = true;
    friends.removeListener(_friendsChanged);
    super.dispose();
  }
}
