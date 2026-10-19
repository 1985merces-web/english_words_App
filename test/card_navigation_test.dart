import 'package:english_words_app/models/card_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty sets never trigger completion', () {
    expect(nextCardPage(currentIndex: 0, wordCount: 0, pageSize: 1),
        (index: 0, finishedSet: false));
    expect(nextCardPage(currentIndex: 0, wordCount: 0, pageSize: 10),
        (index: 0, finishedSet: false));
  });

  test('single-card mode completes only after the last card', () {
    expect(nextCardPage(currentIndex: 198, wordCount: 200, pageSize: 1),
        (index: 199, finishedSet: false));
    expect(nextCardPage(currentIndex: 199, wordCount: 200, pageSize: 1),
        (index: 0, finishedSet: true));
  });

  test('grid mode includes one-page and partially filled sets', () {
    expect(nextCardPage(currentIndex: 0, wordCount: 3, pageSize: 10),
        (index: 0, finishedSet: true));
    expect(nextCardPage(currentIndex: 0, wordCount: 11, pageSize: 10),
        (index: 1, finishedSet: false));
    expect(nextCardPage(currentIndex: 1, wordCount: 11, pageSize: 10),
        (index: 0, finishedSet: true));
    expect(nextCardPage(currentIndex: 19, wordCount: 200, pageSize: 10),
        (index: 0, finishedSet: true));
  });

  test('only a free user who completed a set may request an ad', () {
    for (final finished in [false, true]) {
      for (final premium in [false, true]) {
        expect(
          shouldRequestSetCompletionAd(
              finishedSet: finished, hasPremiumAccess: premium),
          finished && !premium,
        );
      }
    }
  });
}
