/// Advances a card or grid page and reports completion of a non-empty set.
({int index, bool finishedSet}) nextCardPage({
  required int currentIndex,
  required int wordCount,
  required int pageSize,
}) {
  assert(pageSize > 0);
  if (wordCount <= 0) return (index: 0, finishedSet: false);
  final pageCount = (wordCount + pageSize - 1) ~/ pageSize;
  final index = currentIndex.clamp(0, pageCount - 1);
  if (index == pageCount - 1) return (index: 0, finishedSet: true);
  return (index: index + 1, finishedSet: false);
}

bool shouldRequestSetCompletionAd({
  required bool finishedSet,
  required bool hasPremiumAccess,
}) =>
    finishedSet && !hasPremiumAccess;
