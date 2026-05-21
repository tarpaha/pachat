import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../crypto/crypto_service.dart';
import '../models/chat_event.dart';
import '../protocol/messages.dart';
import '../protocol/serializer.dart';

class LoginException implements Exception {
  final String code;
  final String text;
  const LoginException(this.code, this.text);
  @override
  String toString() => '$code: $text';
}

class ChatService {
  final String nickname;
  final PaCrypto _crypto;
  final Socket _socket;
  final Map<String, RSAPublicKey> _peers = {};
  final StreamController<ChatEvent> _events =
      StreamController<ChatEvent>.broadcast();
  StreamSubscription<String>? _sub;
  bool _disconnected = false;

  ChatService._(this.nickname, this._crypto, this._socket);

  Stream<ChatEvent> get events => _events.stream;
  bool get isDisconnected => _disconnected;

  static Future<ChatService> connectAndRegister({
    required String host,
    required int port,
    required String nickname,
  }) async {
    final crypto = await PaCrypto.generate();

    final Socket socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
    } on SocketException catch (e) {
      throw LoginException(
        'CONNECTION_FAILED',
        e.message.isEmpty ? 'Cannot connect to $host:$port' : e.message,
      );
    } on TimeoutException {
      throw LoginException(
        'CONNECTION_TIMEOUT',
        'Timed out connecting to $host:$port',
      );
    }
    socket.setOption(SocketOption.tcpNoDelay, true);

    final svc = ChatService._(nickname, crypto, socket);

    var loginDone = false;
    final completer = Completer<void>();

    svc._sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final msg = decodeLine(line);
            if (msg == null) return;
            if (!loginDone) {
              if (msg is ErrorMessage) {
                if (!completer.isCompleted) {
                  completer.completeError(LoginException(msg.code, msg.text));
                }
                return;
              }
              loginDone = true;
              if (!completer.isCompleted) completer.complete();
            }
            svc._handleMessage(msg);
          },
          onError: (Object err) {
            if (!loginDone && !completer.isCompleted) {
              completer.completeError(
                LoginException('CONNECTION_ERROR', err.toString()),
              );
            }
            svc._handleDisconnect('connection error');
          },
          onDone: () {
            if (!loginDone && !completer.isCompleted) {
              completer.completeError(
                const LoginException(
                  'CONNECTION_CLOSED',
                  'Server closed the connection',
                ),
              );
            }
            svc._handleDisconnect('connection closed');
          },
        );

    svc._sendRaw(
      ConnectMessage(nickname: nickname, publickey: crypto.publicKeyBase64),
    );

    try {
      await completer.future.timeout(const Duration(milliseconds: 1500));
    } on TimeoutException {
      // No error within window — treat as success.
    } on LoginException {
      await svc._teardown();
      rethrow;
    }
    loginDone = true;
    return svc;
  }

  Future<void> sendChat(String text) async {
    if (_disconnected) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final plaintext = Uint8List.fromList(utf8.encode(text));

    for (final entry in _peers.entries) {
      final envelope = encryptForPeer(entry.value, plaintext);
      _sendRaw(
        ChatMessage(
          to: entry.key,
          timestamp: timestamp,
          encryptedkey: base64.encode(envelope.encryptedKey),
          iv: base64.encode(envelope.iv),
          ciphertext: base64.encode(envelope.ciphertext),
          tag: base64.encode(envelope.tag),
        ),
      );
    }

    _events.add(
      ChatLineEvent(
        from: nickname,
        timestamp: DateTime.parse(timestamp),
        text: text,
        fromSelf: true,
      ),
    );
  }

  Future<void> disconnect() async {
    await _teardown();
  }

  void _handleMessage(BaseMessage msg) {
    switch (msg) {
      case PeerJoinedMessage(:final nickname, :final publickey):
        if (_addPeer(nickname, publickey)) {
          _events.add(PeerJoinedEvent(nickname));
        }
        _sendRaw(
          PeerHelloMessage(
            to: nickname,
            nickname: this.nickname,
            publickey: _crypto.publicKeyBase64,
          ),
        );
      case PeerHelloMessage(:final nickname, :final publickey):
        if (_addPeer(nickname, publickey)) {
          _events.add(PeerJoinedEvent(nickname));
        }
      case PeerLeftMessage(:final nickname):
        if (_peers.remove(nickname) != null) {
          _events.add(PeerLeftEvent(nickname));
        }
      case ChatMessage chat:
        final from = chat.from;
        if (from == null) return;
        try {
          final plain = decryptEnvelope(
            _crypto.privateKey,
            base64.decode(chat.encryptedkey),
            base64.decode(chat.iv),
            base64.decode(chat.ciphertext),
            base64.decode(chat.tag),
          );
          final text = utf8.decode(plain);
          _events.add(
            ChatLineEvent(
              from: from,
              timestamp: DateTime.parse(chat.timestamp),
              text: text,
              fromSelf: false,
            ),
          );
        } catch (_) {
          // Ignore malformed/undecryptable chat envelopes.
        }
      case ErrorMessage(:final code, :final text):
        _events.add(SystemErrorEvent(code, text));
      case ConnectMessage():
        // Should not arrive from server.
        break;
    }
  }

  bool _addPeer(String nick, String publicKeyBase64) {
    if (_peers.containsKey(nick)) return false;
    try {
      final key = decodeRsaSpki(base64.decode(publicKeyBase64));
      _peers[nick] = key;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _sendRaw(BaseMessage msg) {
    if (_disconnected) return;
    try {
      final line = encodeLine(msg);
      _socket.add(utf8.encode('$line\n'));
    } catch (_) {
      // Socket errors surface via onError/onDone handlers.
    }
  }

  void _handleDisconnect(String reason) {
    if (_disconnected) return;
    _disconnected = true;
    _events.add(DisconnectedEvent(reason));
  }

  Future<void> _teardown() async {
    _handleDisconnect('client closed');
    await _sub?.cancel();
    _sub = null;
    try {
      await _socket.flush();
    } catch (_) {}
    try {
      _socket.destroy();
    } catch (_) {}
    await _events.close();
  }
}
