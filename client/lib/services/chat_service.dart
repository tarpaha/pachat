import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/block_crypto.dart';
import '../models/chat_event.dart';
import '../protocol/messages.dart';
import 'friends_repository.dart';

class HistoryStorage implements PrivateStorage {
  final String server;
  const HistoryStorage(this.server);
  String get key =>
      'pachat.history.v1.${blockDigest(server).replaceAll('/', '_').replaceAll('+', '-')}';
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
}

String _encrypt((String, List<FriendKey>) args) =>
    encryptBlock(args.$1, args.$2);
DecodedBlock? _decrypt((String, List<FriendKey>) args) =>
    decryptBlock(args.$1, args.$2);

class ChatService extends ChangeNotifier {
  final FriendsRepository friends;
  final PrivateStorage historyStorage;
  final Socket _socket;
  List<ChatEntry> _entries;
  Future<void> _work = Future.value();
  late final Future<void> _receiving;
  bool _disconnected = false;
  bool _disposed = false;
  String? error;
  ChatService._(this.friends, this.historyStorage, this._socket, this._entries);
  List<ChatEntry> get entries => List.unmodifiable(_entries);
  bool get isDisconnected => _disconnected;

  static Future<ChatService> connect({
    required String host,
    required int port,
    required FriendsRepository friends,
    PrivateStorage? historyStorage,
  }) async {
    final storage = historyStorage ?? HistoryStorage('$host:$port');
    final saved = await storage.read();
    var entries = <ChatEntry>[];
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      if (data['version'] != 1) {
        throw const FormatException('Unsupported history version');
      }
      entries = (data['entries'] as List)
          .map((e) => ChatEntry.fromJson(Map<String, dynamic>.from(e)))
          .map((e) => e.status == 'pending' ? e.uncertain() : e)
          .toList();
    }
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    final service = ChatService._(friends, storage, socket, entries);
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

  Future<void> _save(List<ChatEntry> next) async {
    await historyStorage.write(
      jsonEncode({
        'version': 1,
        'entries': next.map((e) => e.toJson()).toList(),
      }),
    );
    _entries = next;
    _notify();
  }

  Future<void> sendChat(String text) => _serial(() async {
    if (_disconnected) throw StateError('Disconnected');
    if (text.trim().isEmpty) return;
    final block = await compute(_encrypt, (text, friends.received));
    final line = encodePublish(block);
    if (_disconnected) throw StateError('Disconnected');
    await _save([
      ..._entries,
      ChatEntry(
        digest: blockDigest(block),
        block: block,
        text: text,
        timestamp: DateTime.now(),
        fromSelf: true,
        status: 'pending',
      ),
    ]);
    try {
      _socket.add(utf8.encode(line));
      await _socket.flush();
    } catch (_) {
      _socket.destroy();
      rethrow;
    }
  });

  Future<void> _receive() async {
    try {
      await for (final line in boundedLines(_socket)) {
        final event = NewBlock.decode(line);
        await _serial(() async {
          final digest = blockDigest(event.block);
          final index = _entries.indexWhere((e) => e.digest == digest);
          if (index >= 0) {
            if (_entries[index].fromSelf) {
              final next = List<ChatEntry>.of(_entries);
              next[index] = next[index].delivered(event.id);
              await _save(next);
            }
            return;
          }
          final decoded = await compute(_decrypt, (
            event.block,
            friends.created,
          ));
          await _save([
            ..._entries,
            ChatEntry(
              digest: digest,
              block: event.block,
              serverId: event.id,
              friendKey: decoded?.friendKey,
              text: decoded?.text,
              timestamp: decoded?.timestamp ?? DateTime.now(),
            ),
          ]);
        });
      }
    } catch (e) {
      error = 'Receiving stopped: $e';
    } finally {
      _disconnected = true;
      _socket.destroy();
      try {
        await _serial(
          () => _save(
            _entries
                .map((e) => e.status == 'pending' ? e.uncertain() : e)
                .toList(),
          ),
        );
      } catch (e) {
        error = 'Could not save history: $e';
      }
      _notify();
    }
  }

  Future<void> disconnect() async {
    _disconnected = true;
    _socket.destroy();
    _notify();
    await _receiving;
  }

  @override
  void dispose() {
    _disposed = true;
    _socket.destroy();
    super.dispose();
  }
}
