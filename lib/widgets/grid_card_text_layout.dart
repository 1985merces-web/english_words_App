import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class GridCardTextLayout extends StatelessWidget {
  const GridCardTextLayout({
    super.key,
    required this.mainBuilder,
    this.secondaryBuilder,
  });

  final Widget Function(double maxHeight) mainBuilder;
  final Widget Function(double maxHeight)? secondaryBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final secondaryHeight = constraints.hasBoundedHeight
            ? math.min(21.0, constraints.maxHeight / 2)
            : 21.0;
        final mainHeight = constraints.hasBoundedHeight
            ? math.max(0.0, constraints.maxHeight - secondaryHeight)
            : double.infinity;
        final secondaryGap = math.min(3.0, secondaryHeight);
        final main = mainBuilder(mainHeight);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.hasBoundedHeight) Flexible(child: main) else main,
            SizedBox(
              height: secondaryHeight,
              child: secondaryBuilder == null
                  ? null
                  : Padding(
                      padding: EdgeInsets.only(top: secondaryGap),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child:
                            secondaryBuilder!(secondaryHeight - secondaryGap),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
