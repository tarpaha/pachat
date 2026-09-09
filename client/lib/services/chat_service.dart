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
  final Socket _socket;
  List<ChatEntry> _entries;
  Future<void> _work = Future.value();
  late final Future<void> _receiving;
  bool _disconnected = false, _disposed = false;
  String? error;
  String? storageError;
  ChatService._(
    this.friends,
    this.historyStorage,
    this._socket,
    this._entries,
    this.profileName,
  );
  List<ChatEntry> get entries => List.unmodifiable(_entries);
  bool get isDisconnected => _disconnected;

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
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    final service = ChatService._(
      friends,
      historyStorage,
      socket,
      entries,
      profileName,
    );
    friends.addListener(service._friendsChanged);
    service._receiving = service._receive();
    return service;
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
    if (_disconnected) throw StateError('Disconnected');
    if (text.trim().isEmpty) return;
    final block = await compute(_encrypt, (text, friends.recipients));
    final line = encodePublish(block);
    if (_disconnected) throw StateError('Disconnected');
    _socket.add(utf8.encode(line));
    await _socket.flush();
  });
  Future<void> _receive() async {
    try {
      await for (final line in readLines(_socket)) {
        final event = NewBlock.decode(line);
        await _serial(() async {
          final decoded = await compute(_decode, (
            [ChatEntry(serverId: event.id, block: event.block)],
            friends.decryptionKeys,
            friends.ownPublicKeys,
          ));
          _entries = [..._entries, ...decoded];
          _notify();
          await _persist();
        });
      }
    } catch (e) {
      error = 'Receiving stopped: $e';
    } finally {
      _disconnected = true;
      _socket.destroy();
      _notify();
    }
  }

  Future<void> disconnect() async {
    _disconnected = true;
    _socket.destroy();
    await _receiving;
    await _work;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    friends.removeListener(_friendsChanged);
    _socket.destroy();
    super.dispose();
  }
}
