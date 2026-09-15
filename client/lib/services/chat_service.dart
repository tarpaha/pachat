import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../crypto/block_crypto.dart';
import '../models/chat_event.dart';
import '../protocol/messages.dart';
import 'friends_repository.dart';

String _encrypt((String, List<FriendKey>) args) =>
    encryptBlock(args.$1, args.$2);
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

class ChatService extends ChangeNotifier {
  final FriendsRepository friends;
  final PrivateStorage historyStorage;
  final String profileName;
  Socket? _socket;
  List<ChatEntry> _entries;
  Future<void> _work = Future.value();
  late final Future<void> _receiving;
  final Completer<void> _ready = Completer<void>();
  bool _connecting = true;
  bool _disconnected = false, _disposed = false;
  String? error;
  String? storageError;
  ChatService._(
    this.friends,
    this.historyStorage,
    this._entries,
    this.profileName,
  );
  List<ChatEntry> get entries => List.unmodifiable(_entries);
  bool get isDisconnected => _disconnected;
  bool get isConnecting => _connecting;

  static Future<ChatService> connect({
    required String host,
    required int port,
    required FriendsRepository friends,
    required PrivateStorage historyStorage,
    String profileName = '',
  }) async {
    await friends.ensureOwnKey();
    final saved = await historyStorage.read();
    var records = <ChatEntry>[];
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      if (data['version'] != 2) {
        throw const FormatException('Unsupported history version');
      }
      records = (data['blocks'] as List)
          .map((e) => ChatEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final entries = await compute(_decode, (
      records,
      friends.decryptionKeys,
      friends.ownPublicKeys,
    ));
    final service = ChatService._(
      friends,
      historyStorage,
      entries,
      profileName,
    );
    friends.addListener(service._friendsChanged);
    service._receiving = service._connectAndReceive(host, port);
    return service;
  }

  Future<void> _connectAndReceive(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      if (_disposed || _disconnected) {
        socket.destroy();
        return;
      }
      _socket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);
      final lastId = _entries.fold<int>(
        0,
        (id, e) => e.serverId > id ? e.serverId : id,
      );
      socket.add(utf8.encode(encodeHistory(lastId)));
      await socket.flush();
      _connecting = false;
      _ready.complete();
      _notify();
      await _receive();
    } catch (e) {
      error = 'Could not connect: $e';
      _disconnected = true;
      _socket?.destroy();
    } finally {
      _connecting = false;
      if (!_ready.isCompleted) _ready.complete();
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _work.then((_) => action());
    _work = next.catchError((Object _) {});
    return next;
  }

  void _friendsChanged() {
    unawaited(
      _serial(() async {
        _entries = await compute(_decode, (
          _entries,
          friends.decryptionKeys,
          friends.ownPublicKeys,
        ));
        _notify();
      }).catchError((Object e) {
        error = 'Could not refresh messages: $e';
        _notify();
      }),
    );
  }

  Future<void> _persist() async {
    try {
      await historyStorage.write(
        jsonEncode({
          'version': 2,
          'blocks': _entries.map((e) => e.toJson()).toList(),
        }),
      );
      storageError = null;
    } catch (e) {
      storageError =
          'History was not saved. Messages remain in this window. $e';
    }
    _notify();
  }

  Future<void> retrySave() => _serial(_persist);
  Future<void> sendChat(String text) => _serial(() async {
    await _ready.future;
    if (_disconnected) throw StateError('Disconnected');
    if (text.trim().isEmpty) return;
    final block = await compute(_encrypt, (text, friends.recipients));
    final line = encodePublish(block);
    if (_disconnected) throw StateError('Disconnected');
    _socket!.add(utf8.encode(line));
    await _socket!.flush();
  });
  Future<void> _receive() async {
    try {
      await for (final line in readLines(_socket!)) {
        final event = NewBlock.decode(line);
        await _serial(() async {
          if (_entries.any(
            (e) => e.serverId == event.id && e.block == event.block,
          )) {
            return;
          }
          final decoded = await compute(_decode, (
            [ChatEntry(serverId: event.id, block: event.block)],
            friends.decryptionKeys,
            friends.ownPublicKeys,
          ));
          _entries = [..._entries, ...decoded]
            ..sort((a, b) => a.serverId.compareTo(b.serverId));
          _notify();
          await _persist();
        });
      }
    } catch (e) {
      error = 'Receiving stopped: $e';
    } finally {
      _disconnected = true;
      _socket?.destroy();
      _notify();
    }
  }

  Future<void> disconnect() async {
    _disconnected = true;
    _socket?.destroy();
    await _receiving;
    await _work;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnected = true;
    friends.removeListener(_friendsChanged);
    _socket?.destroy();
    super.dispose();
  }
}
