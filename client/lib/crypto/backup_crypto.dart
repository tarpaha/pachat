import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

Uint8List _random(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Uint8List _derive(String password, Uint8List salt) {
  final derivation = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, 600000, 32));
  return derivation.process(Uint8List.fromList(utf8.encode(password)));
}

// Run these functions in a worker isolate: password derivation is intentionally costly.
String encryptBackup((String, String) input) {
  final (json, password) = input;
  if (password.length < 12)
    throw const FormatException('Use a password of at least 12 characters');
  final salt = _random(16), nonce = _random(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(_derive(password, salt)),
        128,
        nonce,
        Uint8List.fromList(utf8.encode('pachat-backup-v1')),
      ),
    );
  final encrypted = cipher.process(Uint8List.fromList(utf8.encode(json)));
  return jsonEncode({
    'version': 1,
    'salt': base64.encode(salt),
    'nonce': base64.encode(nonce),
    'data': base64.encode(encrypted),
  });
}

String decryptBackup((String, String) input) {
  final (backup, password) = input;
  final json = jsonDecode(backup) as Map<String, dynamic>;
  if (json['version'] != 1) throw const FormatException('Unsupported backup');
  final salt = base64.decode(json['salt'] as String),
      nonce = base64.decode(json['nonce'] as String);
  if (salt.length != 16 || nonce.length != 12)
    throw const FormatException('Invalid backup');
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(_derive(password, salt)),
        128,
        nonce,
        Uint8List.fromList(utf8.encode('pachat-backup-v1')),
      ),
    );
  return utf8.decode(cipher.process(base64.decode(json['data'] as String)));
}
