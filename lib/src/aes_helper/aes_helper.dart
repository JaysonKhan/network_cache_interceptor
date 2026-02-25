import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

class AESHelper {
  final Key key;

  /// Fixed IV derived from the key — used only for deterministic encryption.
  late final IV _fixedIv;

  AESHelper(String secretKey) : key = Key.fromUtf8(secretKey.padRight(32, '0')) {
    _fixedIv = IV(Uint8List.fromList(key.bytes.sublist(0, 16)));
  }

  /// Encrypts with a random IV (non-deterministic).
  /// Suitable for response data where each encryption should be unique.
  String encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    final combined = iv.bytes + encrypted.bytes;

    return base64Encode(combined);
  }

  /// Encrypts deterministically — same input always produces the same output.
  /// Suitable for cache keys that need consistent DB lookup.
  /// Uses AES-CBC with a fixed IV derived from the key.
  String encryptDeterministic(String plainText) {
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    return encrypter.encrypt(plainText, iv: _fixedIv).base64;
  }

  String decrypt(String encryptedText) {
    final combined = base64Decode(encryptedText);

    final iv = IV(combined.sublist(0, 16));
    final cipherText = combined.sublist(16);

    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

    return encrypter.decrypt(Encrypted(cipherText), iv: iv);
  }
}

// void main() {
//   /// 🔹 Katta JSON (sen yuborgan response)
//   final originalJson = {
//     "data": {
//       "success": true,
//       "data": [
//         {
//           "id": "EXAMPLEID347",
//           "isMain": true,
//           "phone": "998941234567",
//           "balance": 447531000,
//           "expiry": "2099-06",
//           "cardType": "HUMO",
//           "cardHolderName": "JAHONGIR KUZIBOEV",
//           "cardName": "Sherdor HUMO",
//           "bankName": "AGROBANK",
//           "panMasked": "986035********9367",
//           "status": "ACTIVE",
//           "description": "OK",
//         },
//       ],
//     },
//     "timestamp": "2026-02-24T13:03:23.126686",
//   };
//
//   /// 1️⃣ JSON encode
//   final jsonString = jsonEncode(originalJson);
//
//   print("Original JSON length: ${jsonString.length}");
//
//   /// 2️⃣ AES helper
//   final aes = AESHelper("my_super_secret_key_123");
//
//   /// 3️⃣ Encrypt
//   final encrypted = aes.encrypt(jsonString);
//   print("\nEncrypted (base64):\n$encrypted");
//
//   /// 4️⃣ Decrypt
//   final decrypted = aes.decrypt(encrypted);
//   print("\nDecrypted JSON:\n$decrypted");
//
//   /// 5️⃣ Parse va field olish
//   final decodedMap = jsonDecode(decrypted);
//
//   final cards = decodedMap["data"]["data"] as List;
//   final firstCard = cards.first;
//
//   final balance = firstCard["balance"];
//   final holderName = firstCard["cardHolderName"];
//
//   print("\nExtracted values:");
//   print("Card Holder: $holderName");
//   print("Balance: $balance");
// }
