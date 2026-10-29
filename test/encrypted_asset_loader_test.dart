import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_words_app/services/encrypted_asset_loader.dart';

void main() {
  group('EncryptedAssetLoader', () {
    test('encrypts and decrypts string correctly with magic header', () {
      const sample = 'A1,A1L1,word,translation,example\nA1,A1L1,apple,яблуко,red apple';
      final plainBytes = Uint8List.fromList(utf8.encode(sample));

      final encrypted = EncryptedAssetLoader.encrypt(plainBytes);
      expect(EncryptedAssetLoader.isEncrypted(encrypted), isTrue);
      // Ensure the content is scrambled and starts with VOL_ENC1
      expect(encrypted.sublist(0, 8), equals(EncryptedAssetLoader.magicHeader));
      expect(utf8.decode(encrypted.sublist(8), allowMalformed: true), isNot(contains('apple')));

      final decrypted = EncryptedAssetLoader.decrypt(encrypted);
      expect(utf8.decode(decrypted), equals(sample));
    });

    test('isEncrypted returns false for plaintext CSV or short data', () {
      final plain = Uint8List.fromList(utf8.encode('A1,A1L1,book,книга'));
      expect(EncryptedAssetLoader.isEncrypted(plain), isFalse);
      expect(EncryptedAssetLoader.decrypt(plain), equals(plain));
    });

    test('handles large data block (2MB) quickly', () {
      final largeText = 'A1,A1L1,test,тест,example sentence\n' * 50000;
      final plainBytes = Uint8List.fromList(utf8.encode(largeText));

      final sw = Stopwatch()..start();
      final encrypted = EncryptedAssetLoader.encrypt(plainBytes);
      final encTime = sw.elapsedMilliseconds;
      expect(encTime, lessThan(2000));

      sw.reset();
      final decrypted = EncryptedAssetLoader.decrypt(encrypted);
      final decTime = sw.elapsedMilliseconds;

      expect(utf8.decode(decrypted), equals(largeText));
      expect(decTime, lessThan(500)); // Should decrypt ~2MB in < 500ms in debug test runner
    });
  });
}
