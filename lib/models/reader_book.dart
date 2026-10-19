import 'dart:convert';

import 'package:flutter/services.dart';

class ReaderBookInfo {
  const ReaderBookInfo(this.id, this.title, this.author);

  final int id;
  final String title;
  final String author;

  static const englishBooks = <ReaderBookInfo>[
    ReaderBookInfo(55, 'The Wonderful Wizard of Oz', 'L. Frank Baum'),
    ReaderBookInfo(11, "Alice's Adventures in Wonderland", 'Lewis Carroll'),
    ReaderBookInfo(113, 'The Secret Garden', 'Frances Hodgson Burnett'),
    ReaderBookInfo(
        1661, 'The Adventures of Sherlock Holmes', 'Arthur Conan Doyle'),
    ReaderBookInfo(215, 'The Call of the Wild', 'Jack London'),
  ];
}

class ReaderBookChapter {
  const ReaderBookChapter({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class ReaderBook {
  const ReaderBook(this.chapters);

  final List<ReaderBookChapter> chapters;

  static Future<ReaderBook> load(ReaderBookInfo book) async {
    final raw =
        await rootBundle.loadString('assets/data/reader/${book.id}.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final chapters = (data['chapters'] as List<dynamic>).map((value) {
      final chapter = value as Map<String, dynamic>;
      return ReaderBookChapter(
        title: chapter['title'] as String,
        paragraphs: (chapter['paragraphs'] as List<dynamic>).cast<String>(),
      );
    }).toList(growable: false);
    if (chapters.isEmpty ||
        chapters.any((chapter) => chapter.paragraphs.isEmpty)) {
      throw const FormatException('Reader book contains an empty chapter.');
    }
    return ReaderBook(chapters);
  }
}
