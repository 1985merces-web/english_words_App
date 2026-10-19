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

  double _fontSizeFor(BuildContext context, double maxWidth) {
    final initialFontSize = style.fontSize ?? 14;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final effectiveStyle =
        style.inherit ? DefaultTextStyle.of(context).style.merge(style) : style;
    final usableWidth = math.max(0.0, maxWidth);

    double? fit(int lineLimit) {
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

        final fits = !painter.didExceedMaxLines && painter.height <= maxHeight;
        painter.dispose();
        if (fits) return size;
      }

      return null;
    }

    return (preferSingleLine ? fit(1) : null) ?? fit(maxLines) ?? minFontSize;
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
