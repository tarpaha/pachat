import 'dart:convert';
import 'dart:math';

import 'package:asn1lib/asn1lib.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class KeyMaterial {
  final BigInt n;
  final BigInt e;
  final BigInt d;
  final BigInt p;
  final BigInt q;
  const KeyMaterial(this.n, this.e, this.d, this.p, this.q);
}

class PaCrypto {
  final RSAPublicKey publicKey;
  final RSAPrivateKey privateKey;
  final String publicKeyBase64;

  PaCrypto._(this.publicKey, this.privateKey, this.publicKeyBase64);

  static Future<PaCrypto> generate() async {
    final mat = await compute(_generateRsaKeyPair, 2048);
    return PaCrypto._fromMaterial(mat);
  }

  factory PaCrypto._fromMaterial(KeyMaterial mat) {
    final pub = RSAPublicKey(mat.n, mat.e);
    final priv = RSAPrivateKey(mat.n, mat.d, mat.p, mat.q);
    final spki = encodeRsaSpki(pub);
    return PaCrypto._(pub, priv, base64.encode(spki));
  }
}

KeyMaterial _generateRsaKeyPair(int bits) {
  final secureRandom = FortunaRandom();
  final seedSrc = Random.secure();
  final seed = Uint8List(32);
  for (var i = 0; i < seed.length; i++) {
    seed[i] = seedSrc.nextInt(256);
  }
  secureRandom.seed(KeyParameter(seed));

  final keyGen = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
        secureRandom,
      ),
    );
  final pair = keyGen.generateKeyPair();
  final pub = pair.publicKey as RSAPublicKey;
  final priv = pair.privateKey as RSAPrivateKey;
  return KeyMaterial(
    pub.modulus!,
    pub.exponent!,
    priv.privateExponent!,
    priv.p!,
    priv.q!,
  );
}

Uint8List encodeRsaSpki(RSAPublicKey pubKey) {
  final algoSeq = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromComponents([1, 2, 840, 113549, 1, 1, 1]))
    ..add(ASN1Null());

  final keySeq = ASN1Sequence()
    ..add(ASN1Integer(pubKey.modulus!))
    ..add(ASN1Integer(pubKey.exponent!));

  final keyBits = ASN1BitString(keySeq.encodedBytes);

  final spki = ASN1Sequence()
    ..add(algoSeq)
    ..add(keyBits);

  return spki.encodedBytes;
}

RSAPublicKey decodeRsaSpki(Uint8List bytes) {
  final spki = ASN1Parser(bytes).nextObject() as ASN1Sequence;
  final keyBits = spki.elements[1] as ASN1BitString;
  final keyParser = ASN1Parser(Uint8List.fromList(keyBits.stringValue));
  final keySeq = keyParser.nextObject() as ASN1Sequence;
  final modulus = (keySeq.elements[0] as ASN1Integer).valueAsBigInteger;
  final exponent = (keySeq.elements[1] as ASN1Integer).valueAsBigInteger;
  return RSAPublicKey(modulus, exponent);
}

class EncryptedEnvelope {
  final Uint8List encryptedKey;
  final Uint8List iv;
  final Uint8List ciphertext;
  final Uint8List tag;
  EncryptedEnvelope(this.encryptedKey, this.iv, this.ciphertext, this.tag);
}

EncryptedEnvelope encryptForPeer(RSAPublicKey peerKey, Uint8List plaintext) {
  final aesKey = _randomBytes(32);
  final iv = _randomBytes(12);

  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
  final encrypted = gcm.process(plaintext);
  final ciphertext = encrypted.sublist(0, encrypted.length - 16);
  final tag = encrypted.sublist(encrypted.length - 16);

  final rsa = OAEPEncoding.withSHA256(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(peerKey));
  final wrappedKey = rsa.process(aesKey);

  return EncryptedEnvelope(wrappedKey, iv, ciphertext, tag);
}

Uint8List decryptEnvelope(
  RSAPrivateKey privKey,
  Uint8List wrappedKey,
  Uint8List iv,
  Uint8List ciphertext,
  Uint8List tag,
) {
  final rsa = OAEPEncoding.withSHA256(RSAEngine())
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(privKey));
  final aesKey = rsa.process(wrappedKey);

  final gcm = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
  final combined = Uint8List(ciphertext.length + tag.length)
    ..setRange(0, ciphertext.length, ciphertext)
    ..setRange(ciphertext.length, ciphertext.length + tag.length, tag);
  return gcm.process(combined);
}

final _secureRandom = Random.secure();

Uint8List _randomBytes(int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = _secureRandom.nextInt(256);
  }
  return out;
}
