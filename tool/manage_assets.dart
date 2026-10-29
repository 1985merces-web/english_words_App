import 'dart:io';
import '../lib/services/volary_cipher.dart';

void main(List<String> args) {
  final setsDir = Directory('assets/data/sets');
  final sourceDir = Directory('assets_source/sets');

  if (!setsDir.existsSync()) {
    print('Error: assets/data/sets does not exist');
    exit(1);
  }

  final bool isRestore = args.contains('--restore') || args.contains('--decrypt');

  if (isRestore) {
    print('Restoring plaintext files to assets/data/sets from assets_source/sets...');
    if (!sourceDir.existsSync()) {
      print('Error: assets_source/sets does not exist');
      exit(1);
    }
    for (final file in sourceDir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      file.copySync('${setsDir.path}/$name');
      print('Restored: $name');
    }
    print('Done restoring.');
    return;
  }

  // Backup / sync plaintext to assets_source/sets first if plain
  if (!sourceDir.existsSync()) {
    sourceDir.createSync(recursive: true);
  }

  print('Syncing plaintext source files to assets_source/sets/ ...');
  for (final file in setsDir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.csv') || name.endsWith('.jsonl') || name.endsWith('.json')) {
      final bytes = file.readAsBytesSync();
      if (!VolaryCipher.isEncrypted(bytes)) {
        File('${sourceDir.path}/$name').writeAsBytesSync(bytes);
        print('Saved plain source: $name');
      }
    }
  }

  print('\nEncrypting assets in assets/data/sets/ ...');
  int encryptedCount = 0;
  for (final file in sourceDir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.csv') || name.endsWith('.jsonl') || name.endsWith('.json')) {
      final plainBytes = file.readAsBytesSync();
      final encBytes = VolaryCipher.encrypt(plainBytes);
      File('${setsDir.path}/$name').writeAsBytesSync(encBytes);
      print('Encrypted: $name (${plainBytes.length} -> ${encBytes.length} bytes)');
      encryptedCount++;
    }
  }

  print('\nSuccessfully encrypted $encryptedCount files in assets/data/sets/.');
}
