class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.label,
    required this.nativeLabel,
    required this.flag,
    required this.isReady,
  });

  final String code;
  final String label;
  final String nativeLabel;
  final String flag;

  /// A ready language has a CSV aligned to the active canonical wordbase.
  final bool isReady;
}

/// Single source of truth for language availability and display metadata.
///
/// The four launch candidates stay visible in code but unavailable until their
/// rebuilt translation files pass alignment and linguistic QA.
abstract final class LanguageCatalog {
  static const all = <AppLanguage>[
    AppLanguage(
      code: 'en',
      label: 'English',
      nativeLabel: 'English',
      flag: '\u{1F1FA}\u{1F1F8}',
      isReady: true,
    ),
    AppLanguage(
      code: 'uk',
      label: 'Ukrainian',
      nativeLabel:
          '\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430',
      flag: '\u{1F1FA}\u{1F1E6}',
      isReady: true,
    ),
    AppLanguage(
      code: 'de',
      label: 'German',
      nativeLabel: 'Deutsch',
      flag: '\u{1F1E9}\u{1F1EA}',
      isReady: true,
    ),
    AppLanguage(
      code: 'es',
      label: 'Spanish',
      nativeLabel: 'Espa\u00F1ol',
      flag: '\u{1F1EA}\u{1F1F8}',
      isReady: true,
    ),
    AppLanguage(
      code: 'fr',
      label: 'French',
      nativeLabel: 'Fran\u00E7ais',
      flag: '\u{1F1EB}\u{1F1F7}',
      isReady: false,
    ),
    AppLanguage(
      code: 'it',
      label: 'Italian',
      nativeLabel: 'Italiano',
      flag: '\u{1F1EE}\u{1F1F9}',
      isReady: false,
    ),
    AppLanguage(
      code: 'pt',
      label: 'Portuguese',
      nativeLabel: 'Portugu\u00EAs',
      flag: '\u{1F1F5}\u{1F1F9}',
      isReady: false,
    ),
    AppLanguage(
      code: 'tr',
      label: 'Turkish',
      nativeLabel: 'T\u00FCrk\u00E7e',
      flag: '\u{1F1F9}\u{1F1F7}',
      isReady: false,
    ),
  ];

  static List<AppLanguage> get available =>
      all.where((language) => language.isReady).toList(growable: false);

  static bool isAvailable(String code) =>
      available.any((language) => language.code == code);

  static AppLanguage byCode(String code) => all.firstWhere(
        (language) => language.code == code,
        orElse: () => all.first,
      );
}
