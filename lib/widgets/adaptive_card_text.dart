import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class AdaptiveCardText extends StatelessWidget {
  const AdaptiveCardText({
    super.key,
    required this.text,
    required this.style,
    required this.maxLines,
    required this.maxHeight,
    required this.minFontSize,
    this.preferSingleLine = false,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final double maxHeight;
  final double minFontSize;
  final bool preferSingleLine;

  static bool _hasMidWordBreak(TextPainter painter, String text) {
    final metrics = painter.computeLineMetrics();
    if (metrics.length <= 1) return false;
    int offset = 0;
    for (int i = 0; i < metrics.length - 1; i++) {
      final range = painter.getLineBoundary(TextPosition(offset: offset));
      final end = range.end;
      if (end > 0 && end < text.length) {
        final prevChar = text[end - 1];
        final nextChar = text[end];
        final isPrevBreak = RegExp(r'[\s\-\—\–\/]').hasMatch(prevChar);
        final isNextBreak = RegExp(r'[\s\-\—\–\/]').hasMatch(nextChar);
        if (!isPrevBreak && !isNextBreak) {
          return true;
        }
      }
      offset = range.end;
    }
    return false;
  }

  double _fontSizeFor(BuildContext context, double maxWidth) {
    final initialFontSize = style.fontSize ?? 14;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final effectiveStyle =
        style.inherit ? DefaultTextStyle.of(context).style.merge(style) : style;
    final usableWidth = math.max(0.0, maxWidth);

    double? fit(int lineLimit, {bool disallowMidWordBreak = true}) {
      for (double size = initialFontSize; size >= minFontSize; size -= 0.5) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: effectiveStyle.copyWith(fontSize: size),
          ),
          textAlign: TextAlign.center,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: Localizations.maybeLocaleOf(context),
          textWidthBasis: TextWidthBasis.parent,
          maxLines: lineLimit,
        )..layout(maxWidth: usableWidth);

        final fitsBasic =
            !painter.didExceedMaxLines && painter.height <= maxHeight;
        final midBreak =
            disallowMidWordBreak && _hasMidWordBreak(painter, text);
        final fits = fitsBasic && !midBreak;
        painter.dispose();
        if (fits) return size;
      }

      return null;
    }

    return (preferSingleLine ? fit(1, disallowMidWordBreak: true) : null) ??
        fit(maxLines, disallowMidWordBreak: true) ??
        fit(maxLines, disallowMidWordBreak: false) ??
        minFontSize;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
          return Text(text, style: style, textAlign: TextAlign.center);
        }

        return SizedBox(
          width: constraints.maxWidth,
          child: Text(
            text,
            style: style.copyWith(
              fontSize: _fontSizeFor(context, constraints.maxWidth),
            ),
            textAlign: TextAlign.center,
            softWrap: true,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textWidthBasis: TextWidthBasis.parent,
          ),
        );
      },
    );
  }
}
