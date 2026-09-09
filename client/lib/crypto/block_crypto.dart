import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import '../services/friends_repository.dart';
import 'crypto_service.dart';

String encryptBlock(String text, List<FriendKey> recipients) {
  if (recipients.length > 257 || utf8.encode(text).length > 16384) {
    throw const FormatException(
      'Maximum 256 friends plus yourself and 16 KiB of text',
    );
  }
  if (recipients.isEmpty) {
    throw StateError('Add a received public key before sending');
  }
  final plaintext = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'text': text,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }),
    ),
  );
  final copies = recipients.map((friend) {
    final envelope = encryptForPeer(
      decodeRsaSpki(base64.decode(friend.publicKey)),
      plaintext,
    );
    return {
      'key': base64.encode(envelope.encryptedKey),
      'iv': base64.encode(envelope.iv),
      'ciphertext': base64.encode(envelope.ciphertext),
      'tag': base64.encode(envelope.tag),
    };
  }).toList();
  return base64.encode(
    utf8.encode(jsonEncode({'version': 1, 'copies': copies})),
  );
}

class DecodedBlock {
  final String friendKey;
  final String text;
  final DateTime timestamp;
  const DecodedBlock(this.friendKey, this.text, this.timestamp);
}

DecodedBlock? decryptBlock(String block, List<FriendKey> friends) {
  try {
    final json =
        jsonDecode(utf8.decode(base64.decode(block))) as Map<String, dynamic>;
    if (json['version'] != 1) return null;
    final copies = json['copies'] as List;
    if (copies.length > 257) return null;
    for (final friend in friends) {
      if (friend.pair == null) continue;
      for (final copy in copies) {
        try {
          final bytes = decryptEnvelope(
            friend.pair!.privateKey,
            base64.decode(copy['key'] as String),
            base64.decode(copy['iv'] as String),
            base64.decode(copy['ciphertext'] as String),
            base64.decode(copy['tag'] as String),
          );
          final payload =
              jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          return DecodedBlock(
            friend.id,
            payload['text'] as String,
            DateTime.parse(payload['timestamp'] as String),
          );
        } catch (_) {
          /* Try the next local key. */
        }
      }
    }
  } catch (_) {
    /* Unknown or malformed blocks have no readable content. */
  }
  return null;
}

String blockDigest(String block) => base64.encode(
  SHA256Digest().process(Uint8List.fromList(utf8.encode(block))),
);
