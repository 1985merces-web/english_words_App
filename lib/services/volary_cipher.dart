import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart cryptographic cipher for Volary proprietary assets using ChaCha20.
/// Zero external dependencies; runs identically in Flutter, Dart CLI, and background isolates.
class VolaryCipher {
  // 8-byte magic header: 'VOL_ENC1'
  static const List<int> magicHeader = [0x56, 0x4F, 0x4C, 0x5F, 0x45, 0x4E, 0x43, 0x31];

  // 32-byte secret key embedded in compiled binary
  static const List<int> _key = [
    0x56, 0x6F, 0x6C, 0x61, 0x72, 0x79, 0x53, 0x65, // VolarySe
    0x63, 0x72, 0x65, 0x74, 0x4B, 0x65, 0x79, 0x32, // cretKey2
    0x30, 0x32, 0x36, 0x5F, 0x53, 0x65, 0x74, 0x73, // 026_Sets
    0x5F, 0x41, 0x73, 0x73, 0x65, 0x74, 0x73, 0x21, // _Assets!
  ];

  static bool isEncrypted(Uint8List bytes) {
    if (bytes.length < 20) return false; // 8-byte header + 12-byte nonce
    for (int i = 0; i < magicHeader.length; i++) {
      if (bytes[i] != magicHeader[i]) return false;
    }
    return true;
  }

  static String decodeString(Uint8List bytes) {
    if (isEncrypted(bytes)) {
      final decrypted = decrypt(bytes);
      return utf8.decode(decrypted, allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Uint8List encrypt(Uint8List plaintext, {Uint8List? customNonce}) {
    final nonce = customNonce ?? _generateNonce(plaintext.length);
    final ciphertext = _chacha20(
      Uint8List.fromList(_key),
      nonce,
      plaintext,
    );

    final out = Uint8List(magicHeader.length + nonce.length + ciphertext.length);
    out.setRange(0, magicHeader.length, magicHeader);
    out.setRange(magicHeader.length, magicHeader.length + nonce.length, nonce);
    out.setRange(magicHeader.length + nonce.length, out.length, ciphertext);
    return out;
  }

  static Uint8List decrypt(Uint8List encryptedData) {
    if (!isEncrypted(encryptedData)) {
      return encryptedData;
    }

    final nonce = Uint8List.sublistView(
      encryptedData,
      magicHeader.length,
      magicHeader.length + 12,
    );
    final ciphertext = Uint8List.sublistView(
      encryptedData,
      magicHeader.length + 12,
    );

    return _chacha20(
      Uint8List.fromList(_key),
      nonce,
      ciphertext,
    );
  }

  static Uint8List _generateNonce(int seed) {
    final nonce = Uint8List(12);
    int s = seed ^ 0x5A5A5A5A;
    for (int i = 0; i < 12; i++) {
      s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
      nonce[i] = (s >> 16) & 0xFF;
    }
    return nonce;
  }

  static int _rotl(int v, int c) => ((v << c) | (v >>> (32 - c))) & 0xFFFFFFFF;

  static void _quarterRound(List<int> x, int a, int b, int c, int d) {
    x[a] = (x[a] + x[b]) & 0xFFFFFFFF;
    x[d] = _rotl(x[d] ^ x[a], 16);
    x[c] = (x[c] + x[d]) & 0xFFFFFFFF;
    x[b] = _rotl(x[b] ^ x[c], 12);
    x[a] = (x[a] + x[b]) & 0xFFFFFFFF;
    x[d] = _rotl(x[d] ^ x[a], 8);
    x[c] = (x[c] + x[d]) & 0xFFFFFFFF;
    x[b] = _rotl(x[b] ^ x[c], 7);
  }

  static Uint8List _chacha20(Uint8List key, Uint8List nonce, Uint8List input, {int counter = 1}) {
    final out = Uint8List(input.length);
    final state = List<int>.filled(16, 0);

    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;

    final keyBd = ByteData.sublistView(key);
    for (int i = 0; i < 8; i++) {
      state[4 + i] = keyBd.getUint32(i * 4, Endian.little);
    }

    final nonceBd = ByteData.sublistView(nonce);
    state[12] = counter & 0xFFFFFFFF;
    state[13] = nonceBd.getUint32(0, Endian.little);
    state[14] = nonceBd.getUint32(4, Endian.little);
    state[15] = nonceBd.getUint32(8, Endian.little);

    final working = List<int>.filled(16, 0);
    final blockBytes = Uint8List(64);
    final blockBd = ByteData.sublistView(blockBytes);

    int offset = 0;
    int currentCounter = counter;

    while (offset < input.length) {
      state[12] = currentCounter & 0xFFFFFFFF;

      for (int i = 0; i < 16; i++) {
        working[i] = state[i];
      }

      for (int i = 0; i < 10; i++) {
        _quarterRound(working, 0, 4, 8, 12);
        _quarterRound(working, 1, 5, 9, 13);
        _quarterRound(working, 2, 6, 10, 14);
        _quarterRound(working, 3, 7, 11, 15);
        _quarterRound(working, 0, 5, 10, 15);
        _quarterRound(working, 1, 6, 11, 12);
        _quarterRound(working, 2, 7, 8, 13);
        _quarterRound(working, 3, 4, 9, 14);
      }

      for (int i = 0; i < 16; i++) {
        blockBd.setUint32(i * 4, (working[i] + state[i]) & 0xFFFFFFFF, Endian.little);
      }

      final int take = (input.length - offset < 64) ? (input.length - offset) : 64;
      for (int i = 0; i < take; i++) {
        out[offset + i] = input[offset + i] ^ blockBytes[i];
      }

      offset += take;
      currentCounter++;
    }

    return out;
  }
}
