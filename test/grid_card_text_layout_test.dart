import 'dart:math' as math;

import 'package:english_words_app/widgets/adaptive_card_text.dart';
import 'package:english_words_app/widgets/grid_card_text_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cardHeight in [110.0, 66.0]) {
    testWidgets('grid words share a vertical anchor at height $cardHeight',
        (tester) async {
      Widget card(String key, {String? secondary}) {
        return SizedBox(
          width: 140,
          height: cardHeight,
          child: Center(
            child: GridCardTextLayout(
              mainBuilder: (_) => Text(
                'Word',
                key: ValueKey(key),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22),
              ),
              secondaryBuilder: secondary == null
                  ? null
                  : (_) =>
                      Text(secondary, style: const TextStyle(fontSize: 14)),
            ),
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                card('with-synonym', secondary: '(synonym)'),
                card('without-synonym'),
                card('translation'),
              ],
            ),
          ),
        ),
      );

      final withSynonym =
          tester.getCenter(find.byKey(const ValueKey('with-synonym')));
      expect(tester.getCenter(find.byKey(const ValueKey('without-synonym'))).dy,
          closeTo(withSynonym.dy, 0.01));
      expect(tester.getCenter(find.byKey(const ValueKey('translation'))).dy,
          closeTo(withSynonym.dy, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (text: 'чинний (про посадовця)', width: 115.0, height: 66.0),
    (text: 'перевозити контрабандою', width: 115.0, height: 66.0),
    (text: 'чинний директор', width: 90.0, height: 51.0),
  ]) {
    final phrase = scenario.text;
    testWidgets('both lines are visible for $phrase', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: scenario.width,
              height: scenario.height,
              child: Center(
                child: DefaultTextStyle(
                  style: const TextStyle(height: 1.5),
                  child: GridCardTextLayout(
                    mainBuilder: (maxHeight) => AdaptiveCardText(
                      text: phrase,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      maxHeight: math.min(52, maxHeight),
                      minFontSize: 9,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final paragraph = tester.renderObject<RenderParagraph>(find.text(phrase));
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: phrase.length),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(boxes.length, greaterThanOrEqualTo(2));
      for (final box in boxes) {
        expect(box.top, greaterThanOrEqualTo(0));
        expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
