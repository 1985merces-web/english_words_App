import 'dart:typed_data';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'volary_cipher.dart';

/// Transparent loader for encrypted Volary assets.
/// Automatically detects encrypted files by magic header 'VOL_ENC1' and decrypts in memory.
/// Falls back to plaintext if the file is unencrypted (e.g. during local tests or dev).
class EncryptedAssetLoader {
  static Future<String> loadString(String assetPath) async {
    final ByteData byteData = await rootBundle.load(assetPath);
    final Uint8List bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return VolaryCipher.decodeString(bytes);
  }

  static bool isEncrypted(Uint8List bytes) => VolaryCipher.isEncrypted(bytes);
  static Uint8List encrypt(Uint8List plaintext, {Uint8List? customNonce}) =>
      VolaryCipher.encrypt(plaintext, customNonce: customNonce);
  static Uint8List decrypt(Uint8List encryptedData) =>
      VolaryCipher.decrypt(encryptedData);
  static List<int> get magicHeader => VolaryCipher.magicHeader;
}
