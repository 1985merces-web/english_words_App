import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:xml/xml.dart';

class ImportedDocument {
  const ImportedDocument({
    required this.name,
    required this.text,
  });

  final String name;
  final String text;
}

enum DocumentTextExtractionError {
  fileTooLarge,
  unsupportedFormat,
  noText,
  pdfAccess,
  pdfRead,
  docxRead,
  docxNoText,
  docxInvalid,
  txtRead,
}

class DocumentTextExtractionException implements Exception {
  const DocumentTextExtractionException(this.error);

  final DocumentTextExtractionError error;
}

abstract final class DocumentTextExtractor {
  static const _maxBytes = 10 * 1024 * 1024;

  static Future<ImportedDocument?> pickAndExtract() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    return extract(result.files.single);
  }

  static Future<ImportedDocument> extract(PlatformFile file) async {
    if (file.size > _maxBytes) {
      throw const DocumentTextExtractionException(
        DocumentTextExtractionError.fileTooLarge,
      );
    }

    final extension = file.extension?.toLowerCase();
    final text = switch (extension) {
      'pdf' => await _extractPdf(file),
      'docx' => _extractDocx(file.bytes),
      'txt' => _extractPlainText(file.bytes),
      _ => throw const DocumentTextExtractionException(
          DocumentTextExtractionError.unsupportedFormat,
        ),
    };

    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      throw const DocumentTextExtractionException(
        DocumentTextExtractionError.noText,
      );
    }

    return ImportedDocument(name: file.name, text: normalized);
  }

  static Future<String> _extractPdf(PlatformFile file) async {
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const DocumentTextExtractionException(
        DocumentTextExtractionError.pdfAccess,
      );
    }

    try {
      return await ReadPdfText.getPDFtext(path);
    } on PlatformException {
      throw const DocumentTextExtractionException(
        DocumentTextExtractionError.pdfRead,
      );
    }
  }

  static String _extractDocx(Uint8List? bytes) {
    if (bytes == null) {
      throw const DocumentTextExtractionException(
        DocumentTextExtractionError.docxRead,
      );
    }

    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final documentXml = archive.findFile('word/document.xml');
      final Uint8List? content = documentXml?.content;
      if (content == null) {
        throw const DocumentTextExtractionException(
          DocumentTextExtractionError.docxNoText,
        );
      }

      final document = XmlDocument.parse(utf8.decode(content));
      final paragraphs = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'p')
          .map((paragraph) => paragraph.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 't')
              .map((element) => element.innerText)
              .join())
          .where((paragraph) => paragraph.trim().isNotEmpty);
      return paragraphs.join('\n\n');
    } on DocumentTextExtractionException {
      rethrow;
    } catch (_) {
      throw const DocumentTextExtractionException(
        DocumentTextExtractionError.docxInvalid,
      );
    }
  }

  static String _extractPlainText(Uint8List? bytes) {
    if (bytes == null) {
      throw const DocumentTextExtractionException(
        DocumentTextExtractionError.txtRead,
      );
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
