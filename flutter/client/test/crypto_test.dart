import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/crypto/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RSA-OAEP-SHA256 + AES-256-GCM round-trip', () async {
    final crypto = await PaCrypto.generate();

    // Round-trip the SPKI: decode our own base64 public key and ensure it
    // matches the source RSAPublicKey by re-encoding.
    final spkiBytes = base64.decode(crypto.publicKeyBase64);
    final decodedPub = decodeRsaSpki(spkiBytes);
    expect(decodedPub.modulus, crypto.publicKey.modulus);
    expect(decodedPub.exponent, crypto.publicKey.exponent);

    final plaintext = Uint8List.fromList(utf8.encode('Привет, PaChat! 🔐'));
    final envelope = encryptForPeer(decodedPub, plaintext);

    final decrypted = decryptEnvelope(
      crypto.privateKey,
      envelope.encryptedKey,
      envelope.iv,
      envelope.ciphertext,
      envelope.tag,
    );
    expect(utf8.decode(decrypted), 'Привет, PaChat! 🔐');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
