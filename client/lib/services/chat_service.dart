import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../crypto/block_crypto.dart';
import '../models/chat_event.dart';
import '../protocol/messages.dart';
import 'friends_repository.dart';
import 'message_repository.dart';

String _encrypt((String, List<FriendKey>) args) =>
    encryptBlock(args.$1, args.$2);

/// Connection and catch-up coordinator; the profile owns its lifetime.
class ChatService extends ChangeNotifier {
  final MessageRepository messages;
  final String profileName;
  final String host;
  final int port;
  final Duration reconnectDelay;
  Socket? _socket;
  late final Future<void> _receiving;
  Future<void> _sending = Future.value();
  final Completer<void> _stopped = Completer<void>();
  Completer<void>? _wake;
  Completer<void> _ready = Completer<void>();
  bool _connecting = true, _disconnected = false, _disposed = false;
  String? _error;

  ChatService._(
    this.messages,
    this.profileName,
    this.host,
    this.port,
    this.reconnectDelay,
  );
  FriendsRepository get friends => messages.friends;
  List<ChatEntry> get entries => messages.entries;
  bool get databaseVerified => messages.databaseVerified;
  bool get isDisconnected => _disconnected;
  bool get isStopped => _stopped.isCompleted;
  bool get isConnecting => _connecting;
  String? get error => _error ?? messages.processingError;
  String? get storageError => messages.storageError;

  static Future<ChatService> connect({
    required String host,
    required int port,
    required FriendsRepository friends,
    required PrivateStorage historyStorage,
    String profileName = '',
    Duration reconnectDelay = const Duration(seconds: 1),
  }) async {
    final messages = await MessageRepository.open(
      friends: friends,
      storage: historyStorage,
    );
    final service = ChatService._(
      messages,
      profileName,
      host,
      port,
      reconnectDelay,
    );
    messages.addListener(service._notify);
    service._receiving = service._run();
    return service;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run() async {
    var failures = 0;
    while (!_stopped.isCompleted) {
      StreamIterator<String>? lines;
      _connecting = true;
      _notify();
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 5),
        );
        if (_stopped.isCompleted) {
          socket.destroy();
          break;
        }
        _socket = socket;
        socket.setOption(SocketOption.tcpNoDelay, true);
        lines = StreamIterator(readLines(socket));
        if (!await lines.moveNext().timeout(const Duration(seconds: 10))) {
          throw const FormatException(
            'Server closed before providing its database ID',
          );
        }
        final databaseId = decodeDatabaseId(lines.current);
        await messages.selectDatabase(databaseId);
        socket.add(utf8.encode(encodeHistory(messages.cursor)));
        await socket.flush();
        var syncing = true;
        while (!_stopped.isCompleted) {
          final available = syncing
              ? await lines.moveNext().timeout(const Duration(seconds: 30))
              : await lines.moveNext();
          if (!available) break;
          final line = lines.current;
          if (syncing) {
            // Live events before our request are covered by history. They must
            // not advance the cursor past missing historical blocks.
            if ((jsonDecode(line) as Map)['type'] == 'new_block') continue;
            final page = HistoryPage.decode(line, messages.cursor);
            await messages.ingest(page.blocks, throughId: page.afterId);
            if (!page.hasMore) {
              syncing = false;
              failures = 0;
              _disconnected = false;
              _connecting = false;
              _error = null;
              if (!_ready.isCompleted) _ready.complete();
              _notify();
            }
          } else {
            final block = NewBlock.decode(line);
            if (block.id < messages.cursor) {
              throw const FormatException('Live message IDs moved backwards');
            }
            await messages.ingest([block], throughId: block.id);
          }
        }
        if (!_stopped.isCompleted) _error = 'Connection closed. Reconnecting…';
      } catch (e) {
        if (!_stopped.isCompleted) _error = 'Connection interrupted: $e';
      } finally {
        _socket?.destroy();
        _socket = null;
        await lines?.cancel();
        _disconnected = true;
        _connecting = false;
        if (!_ready.isCompleted) _ready.complete();
        _ready = Completer<void>();
        _notify();
      }
      if (_stopped.isCompleted) break;
      final multiplier = 1 << failures.clamp(0, 5);
      failures++;
      _wake = Completer<void>();
      final timer = Timer(reconnectDelay * multiplier, () {
        if (!(_wake?.isCompleted ?? true)) _wake!.complete();
      });
      await Future.any([_wake!.future, _stopped.future]);
      timer.cancel();
      _wake = null;
    }
  }

  /// Called on app resume or by an explicit retry; independent of navigation.
  void reconnect() {
    if (_stopped.isCompleted) return;
    if (_wake != null) {
      if (!_wake!.isCompleted) _wake!.complete();
    } else {
      _socket?.destroy();
    }
  }

  Future<void> retrySave() => messages.retrySave();

  Future<void> sendChat(String text) {
    final next = _sending.then((_) async {
      if (_stopped.isCompleted) throw StateError('Disconnected');
      if (_connecting) await _ready.future;
      if (_disconnected || _socket == null) throw StateError('Disconnected');
      if (text.trim().isEmpty) return;
      final socket = _socket!;
      final block = await compute(_encrypt, (text, friends.recipients));
      if (_stopped.isCompleted ||
          _connecting ||
          _disconnected ||
          _socket != socket) {
        throw StateError('Connection changed while preparing message');
      }
      socket.add(utf8.encode(encodePublish(block)));
      await socket.flush();
    });
    _sending = next.catchError((Object _) {});
    return next;
  }

  void _stop() {
    if (!_stopped.isCompleted) _stopped.complete();
    _disconnected = true;
    if (!_ready.isCompleted) _ready.complete();
    _socket?.destroy();
  }

  Future<void> disconnect() async {
    _stop();
    await _receiving;
    await _sending;
    await messages.flush();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    messages.removeListener(_notify);
    unawaited(disconnect().then((_) => messages.dispose()));
    super.dispose();
  }
}
