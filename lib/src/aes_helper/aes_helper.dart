import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

/// Small AES helper used to encrypt and decrypt cached data and cache keys.
///
/// Two encryption modes are provided:
/// * [encrypt]/[decrypt] use AES-GCM with a random IV per call, so identical
///   inputs produce different ciphertexts — used for response bodies.
/// * [encryptDeterministic] uses AES-CBC with a fixed IV derived from the key,
///   so identical inputs always produce the same ciphertext — used for cache
///   keys, which must stay stable for database lookups.
class AESHelper {
  /// The 32-byte key derived from the user-supplied secret.
  final Key key;

  /// Fixed IV derived from the key — used only for deterministic encryption.
  late final IV _fixedIv;

  /// Creates a helper from [secretKey]. The key is right-padded to 32 bytes.
  AESHelper(String secretKey)
      : key = Key.fromUtf8(secretKey.padRight(32, '0')) {
    _fixedIv = IV(Uint8List.fromList(key.bytes.sublist(0, 16)));
  }

  /// Encrypts [plainText] with a random IV (non-deterministic).
  ///
  /// The IV is prepended to the ciphertext and the whole payload is base64
  /// encoded, so [decrypt] can recover the IV.
  String encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    final combined = iv.bytes + encrypted.bytes;

    return base64Encode(combined);
  }

  /// Encrypts [plainText] deterministically — the same input always produces the
  /// same output. Suitable for cache keys that need consistent lookups.
  String encryptDeterministic(String plainText) {
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    return encrypter.encrypt(plainText, iv: _fixedIv).base64;
  }

  /// Decrypts a payload produced by [encrypt].
  String decrypt(String encryptedText) {
    final combined = base64Decode(encryptedText);

    final iv = IV(combined.sublist(0, 16));
    final cipherText = combined.sublist(16);

    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

    return encrypter.decrypt(Encrypted(cipherText), iv: iv);
  }
}
