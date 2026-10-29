import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:audio_session/audio_session.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        HapticFeedback,
        SystemUiOverlayStyle,
        SystemNavigator,
        SystemSound,
        SystemSoundType;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/word_entry.dart';
import '../models/card_navigation.dart';
import '../models/language_catalog.dart';
import '../utils/system_ui.dart';
import '../services/ad_helper.dart';
import '../services/billing_service.dart';
import '../services/consent_manager.dart';
import 'reader_screen.dart';
import '../widgets/adaptive_card_text.dart';
import '../widgets/grid_card_text_layout.dart';
import '../widgets/premium_paywall_sheet.dart';
import '../services/encrypted_asset_loader.dart';
import '../services/sound_service.dart';

class _LiquidGlassSurface extends StatelessWidget {
  const _LiquidGlassSurface({
    required this.tint,
    required this.dark,
    required this.child,
  });

  final Color tint;
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(22));
    final Color darkBase = Color.lerp(const Color(0xFF0A2330), tint, 0.42)!;
    final Color darkBaseEnd = Color.lerp(darkBase, Colors.black, 0.16)!;
    final List<Color> glassColors = dark
        ? [
            darkBase.withValues(alpha: 0.94),
            darkBase.withValues(alpha: 0.97),
            darkBaseEnd.withValues(alpha: 0.98),
          ]
        : [
            Colors.white.withValues(alpha: 0.48),
            tint.withValues(alpha: 0.38),
            tint.withValues(alpha: 0.22),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: dark ? 0.18 : 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.26 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: glassColors,
                stops: const [0, 0.45, 1],
              ),
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.48 : 0.72),
                width: 1.2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GlassIconSurface extends StatelessWidget {
  const _GlassIconSurface({
    required this.size,
    required this.dark,
    required this.child,
  });

  final double size;
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: dark ? 0.16 : 0.42),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? 0.48 : 0.68),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}

class FlashcardScreen extends StatefulWidget {
  final bool showENasDefault;
  final VoidCallback onToggleDefault;

  const FlashcardScreen({
    super.key,
    required this.showENasDefault,
    required this.onToggleDefault,
  });

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with WidgetsBindingObserver {
  static const int _cardsPerGridPage = 10;
  static const bool _showContextSentenceExamples = false;
  bool showENFace = true;
  bool gridMode = false;
  int gridPage = 0;
  List<bool> gridCardENFace = List.filled(_cardsPerGridPage, true);
  List<WordEntry> allWords = [];
  List<WordEntry> currentSetWords = [];
  final math.Random _batchShuffleRandom = math.Random();
  int currentIndex = 0;
  String selectedLevel = '';
  String selectedSublist = '';
  String studyLang = 'en'; // Language being learned
  String nativeLang = 'uk'; // User's native language

  // Inline words menu state
  bool showWordsMenu = false;
  String panelActiveLevel = '';

  final FlutterTts flutterTts = FlutterTts();
  bool isPlaying = false; // Add this to your _FlashcardScreenState
  bool showSlider = false; // <-- Add this
  double sliderValue = 0; // <-- Add this
  bool showSettingsMenu = false;
  bool showSaveToSubMenu = false; // <-- ADD THIS
  bool randomSpeaking = false;
  bool allowBackgroundSpeaking = true;
  bool darkTheme = false;
  bool tapSounds = true;
  bool sleepTimerLoop = true;
  bool uiUseNative = false;
  String targetCustomSet = ''; // <-- Add this
  Timer? sleepTimer;
  Timer? sleepTicker;
  DateTime? sleepTimerEnd;
  final TextEditingController sleepTimerController = TextEditingController();
  String activeSettingsPanel = '';
  bool _sleepTimerExpiring = false;

  // Add this to track loading state
  bool isLoading = true;

  // Add this to your class variables
  Map<String, String> enUkDictionary = {};
  late final Future<void> _dictionaryReady;
  Map<String, String> englishContextSentences = {};
  List<String> allCustomListNames = [];
  List<WordEntry> _customEntries = []; // Cache for starred and custom words
  Set<String> _customWordsSet = {};

  void _updateCustomWordsSet() {
    _customWordsSet = _customEntries
        .map((e) => e.wordMain.trim().toLowerCase())
        .toSet();
  }

  bool _isWordInCustomList(WordEntry? word) {
    if (word == null) return false;
    return _customWordsSet.contains(word.wordMain.trim().toLowerCase());
  }

  Map<String, List<String>>? _groupedListsCache;
  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  bool _pausedByInterruption = false;

  void _playTapClick() {
    // Best-effort: not all devices/platforms will play a click sound.
    if (!tapSounds) return;
    try {
      Feedback.forTap(context);
    } catch (_) {}
    try {
      unawaited(SystemSound.play(SystemSoundType.click));
    } catch (_) {}
    try {
      unawaited(HapticFeedback.selectionClick());
    } catch (_) {}
  }

  Future<bool> _requirePremium(String featureName) async {
    if (BillingService().hasPremiumAccess) return true;

    final unlocked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PremiumPaywallSheet(
        featureName: featureName,
        languageCode: _uiLangCode(),
      ),
    );
    return unlocked ?? BillingService().hasPremiumAccess;
  }

  Future<void> _openReader() async {
    if (!await _requirePremium(_t('reader'))) return;
    if (!mounted) return;

    _playTapClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReaderScreen(
          darkTheme: darkTheme,
          studyLang: studyLang,
          nativeLang: nativeLang,
        ),
      ),
    );
    await loadWords();
  }

  @override
  void initState() {
    super.initState();
    AdHelper.loadInterstitialAd();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    loadWords();
    _dictionaryReady = _loadDictionary();
    _setupAudioSession();
    // Best-effort: some platforms may not support awaiting completion.
    flutterTts.awaitSpeakCompletion(true).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _saveCurrentPosition();
      // When disabled: stop any running TTS as soon as the app is backgrounded
      // (screen off/locked or app minimized).
      if (!allowBackgroundSpeaking) {
        stopPlaying();
      }
    }
  }

  @override
  void dispose() {
    _saveCurrentPosition();
    WidgetsBinding.instance.removeObserver(this);
    stopPlaying(updateUi: false);
    _audioInterruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    sleepTimer?.cancel();
    sleepTicker?.cancel();
    sleepTimerController.dispose();
    super.dispose();
  }

  Future<void> _setupAudioSession() async {
    if (kIsWeb) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _audioSession = session;
    _audioInterruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        _handleAudioInterruptionBegin();
      } else {
        _handleAudioInterruptionEnd();
      }
    });
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
      _handleAudioInterruptionBegin();
    });
  }

  Future<void> _activateAudioSession() async {
    try {
      await _audioSession?.setActive(true);
    } catch (_) {}
  }

  Future<void> _deactivateAudioSession() async {
    try {
      await _audioSession?.setActive(false);
    } catch (_) {}
  }

  void _handleAudioInterruptionBegin() {
    if (!isPlaying) return;
    _pausedByInterruption = true;
    stopPlaying(dueToInterruption: true);
  }

  void _handleAudioInterruptionEnd() {
    if (_pausedByInterruption) {
      _pausedByInterruption = false;
      if (mounted) {
        playSetWords();
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studyLang = prefs.getString('study_language') ?? 'en';
      nativeLang = prefs.getString('native_language') ?? 'uk';
      targetCustomSet = prefs.getString('targetCustomSet') ?? '';
      allowBackgroundSpeaking = true;
      tapSounds = true;
      sleepTimerLoop = prefs.getBool('sleepTimerLoop') ?? true;
      uiUseNative = prefs.getBool('uiUseNative') ?? false;
    });
  }

  Future<void> _saveCurrentPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (selectedLevel.isNotEmpty) {
        await prefs.setString('last_selected_level', selectedLevel);
      }
      if (selectedSublist.isNotEmpty) {
        await prefs.setString('last_selected_sublist', selectedSublist);
      }
      if (currentSetWords.isNotEmpty &&
          currentIndex >= 0 &&
          currentIndex < currentSetWords.length) {
        await prefs.setString(
            'last_word_main', currentSetWords[currentIndex].wordMain);
        await prefs.setInt('last_card_index', currentIndex);
      }
      await prefs.setBool('last_grid_mode', gridMode);
      await prefs.setInt('last_grid_page', gridPage);
    } catch (_) {}
  }

  static const Map<String, Map<String, String>> _uiStrings = {
    'en': {
      'cards': 'Cards',
      'set': 'Set',
      'select_list': 'Select List',
      'level': 'Level',
      'list': 'List',
      'study': 'Study',
      'native': 'Native',
      'random_speaking': 'random speaking',
      'background_speaking': 'background speaking',
      'sleep_timer': 'sleep timer',
      'dark_theme': 'dark theme',
      'tap_sound': 'tap sound',
      'interface_language': 'interface language',
      'save_to_list': 'save to list',
      'save_to_custom_list': 'save to custom list',
      'legal': 'legal',
      'privacy_policy': 'Privacy Policy',
      'terms_of_use': 'Terms of Use',
      'ad_privacy': 'Ad Privacy Settings',
      'privacy_options_unavailable':
          'Ad privacy options are not required or available in your region.',
      'reader': 'Reader',
      'autoplay': 'Autoplay',
      'repeat_list': 'repeat list',
      'play_once': 'In order',
      'off': 'off',
      'min': 'min',
      'enter_minutes': 'Enter minutes for sleep timer',
      'no_target_list':
          'No target list selected. Please choose one in Settings > Save to.',
      'create_custom_list': 'Create Custom List',
      'list_name': 'List Name',
      'custom_list_tip':
          'Tip: add words to this custom list from other lists by saving/favoriting them, then choose this list in "save to custom list".',
      'cancel': 'Cancel',
      'create': 'Create',
      'none': 'None',
      'my_custom_list': 'My Custom List',
      'processing_words': 'Processing words',
      'finding_translations': 'Finding translations...',
      'could_not_open': 'Could not open',
      'saved_to_custom': 'Saved "{word}" to custom list.',
      'removed_from_custom': 'Removed "{word}" from custom list.',
      'already_in_list': '"{word}" is already in the target list.',
      'error_creating_list': 'Error creating list',
      'delete_list': 'Delete List',
      'delete_confirm':
          'Are you sure you want to delete the list "{list}"?\nThis cannot be undone.',
      'delete': 'Delete',
    },
    'uk': {
      'cards': 'Картки',
      'set': 'Набір',
      'select_list': 'Вибрати список',
      'level': 'Рівень',
      'list': 'Список',
      'study': 'Вивчення',
      'native': 'Рідна',
      'random_speaking': 'випадкове озвучення',
      'background_speaking': 'фонове озвучення',
      'sleep_timer': 'таймер сну',
      'dark_theme': 'темна тема',
      'tap_sound': 'звук натискання',
      'interface_language': 'мова інтерфейсу',
      'save_to_list': 'зберегти у список',
      'save_to_custom_list': 'зберегти у власний список',
      'legal': 'правова інформація',
      'privacy_policy': 'Політика конфіденційності',
      'terms_of_use': 'Умови використання',
      'ad_privacy': 'Налаштування реклами',
      'privacy_options_unavailable':
          'Налаштування конфіденційності реклами недоступні для вашого регіону.',
      'reader': 'Читалка',
      'autoplay': 'Автоплей',
      'repeat_list': 'Повторювати список',
      'play_once': 'По порядку',
      'off': 'вимкнено',
      'min': 'хв',
      'enter_minutes': 'Вкажіть хвилини для таймера сну',
      'no_target_list':
          'Не вибрано список. Оберіть його в Налаштуваннях > Зберегти у список.',
      'create_custom_list': 'Створити власний список',
      'list_name': 'Назва списку',
      'custom_list_tip':
          'Порада: додавайте слова у цей список із інших списків через збереження/обране, потім виберіть цей список у "зберегти у список".',
      'cancel': 'Скасувати',
      'create': 'Створити',
      'none': 'Немає',
      'my_custom_list': 'Мій власний список',
      'processing_words': 'Опрацьовуємо слова',
      'finding_translations': 'Пошук перекладів...',
      'could_not_open': 'Не вдалося відкрити',
      'saved_to_custom': 'Збережено "{word}" до власного списку.',
      'removed_from_custom': 'Видалено "{word}" з власного списку.',
      'already_in_list': '"{word}" вже є у вибраному списку.',
      'error_creating_list': 'Помилка створення списку',
      'delete_list': 'Видалити список',
      'delete_confirm':
          'Ви впевнені, що хочете видалити список "{list}"?\nЦе не можна скасувати.',
      'delete': 'Видалити',
    },
    'es': {
      'cards': 'Tarjetas',
      'set': 'Conjunto',
      'select_list': 'Seleccionar lista',
      'level': 'Nivel',
      'list': 'Lista',
      'study': 'Aprender',
      'native': 'Nativo',
      'random_speaking': 'reproduccion aleatoria',
      'background_speaking': 'reproduccion en segundo plano',
      'sleep_timer': 'temporizador de sueno',
      'dark_theme': 'tema oscuro',
      'tap_sound': 'sonido al tocar',
      'interface_language': 'idioma de la interfaz',
      'save_to_list': 'guardar en lista',
      'save_to_custom_list': 'guardar en lista personalizada',
      'legal': 'legal',
      'privacy_policy': 'Politica de privacidad',
      'terms_of_use': 'Terminos de uso',
      'ad_privacy': 'Privacidad de anuncios',
      'privacy_options_unavailable':
          'Las opciones de privacidad de anuncios no estan disponibles en tu region.',
      'reader': 'Lector',
      'autoplay': 'Reproduccion automatica',
      'repeat_list': 'Repetir lista',
      'play_once': 'En orden',
      'off': 'apagado',
      'min': 'min',
      'enter_minutes': 'Introduce minutos para el temporizador',
      'no_target_list':
          'No se ha seleccionado una lista. Elige una en Ajustes > Guardar en lista.',
      'create_custom_list': 'Crear lista personalizada',
      'list_name': 'Nombre de la lista',
      'custom_list_tip':
          'Consejo: anade palabras a esta lista desde otras listas marcandolas, luego elige esta lista en "guardar en lista".',
      'cancel': 'Cancelar',
      'create': 'Crear',
      'none': 'Ninguna',
      'my_custom_list': 'Mi lista personalizada',
      'processing_words': 'Procesando palabras',
      'finding_translations': 'Buscando traducciones...',
      'could_not_open': 'No se pudo abrir',
      'saved_to_custom': 'Se guardo "{word}" en la lista personalizada.',
      'removed_from_custom': 'Se elimino "{word}" de la lista personalizada.',
      'error_creating_list': 'Error al crear la lista',
      'delete_list': 'Eliminar lista',
      'delete_confirm':
          'Deseas eliminar la lista "{list}"?\nNo se puede deshacer.',
      'delete': 'Eliminar',
    },
    'pt': {
      'cards': 'Cartoes',
      'set': 'Conjunto',
      'select_list': 'Selecionar lista',
      'level': 'Nivel',
      'list': 'Lista',
      'study': 'Estudo',
      'native': 'Nativo',
      'random_speaking': 'reproducao aleatoria',
      'background_speaking': 'reproducao em segundo plano',
      'sleep_timer': 'temporizador de sono',
      'dark_theme': 'tema escuro',
      'tap_sound': 'som ao toque',
      'interface_language': 'idioma da interface',
      'save_to_list': 'salvar na lista',
      'save_to_custom_list': 'salvar na lista personalizada',
      'legal': 'legal',
      'privacy_policy': 'Politica de privacidade',
      'terms_of_use': 'Termos de uso',
      'ad_privacy': 'Privacidade de anuncios',
      'privacy_options_unavailable':
          'As opcoes de privacidade de anuncios nao estao disponiveis na sua regiao.',
      'reader': 'Leitor',
      'autoplay': 'Reproducao automatica',
      'repeat_list': 'Repetir lista',
      'play_once': 'Em ordem',
      'off': 'desligado',
      'min': 'min',
      'enter_minutes': 'Informe minutos para o temporizador',
      'no_target_list':
          'Nenhuma lista selecionada. Escolha em Configuracoes > Salvar na lista.',
      'create_custom_list': 'Criar lista personalizada',
      'list_name': 'Nome da lista',
      'custom_list_tip':
          'Dica: adicione palavras a esta lista a partir de outras listas salvando/favoritando, depois escolha esta lista em "salvar na lista".',
      'cancel': 'Cancelar',
      'create': 'Criar',
      'none': 'Nenhuma',
      'my_custom_list': 'Minha lista personalizada',
      'processing_words': 'Processando palavras',
      'finding_translations': 'Procurando traducoes...',
      'could_not_open': 'Nao foi possivel abrir',
      'saved_to_custom': '"{word}" salva na lista personalizada.',
      'removed_from_custom': 'Removido "{word}" da lista personalizada.',
      'error_creating_list': 'Erro ao criar a lista',
      'delete_list': 'Excluir lista',
      'delete_confirm':
          'Tem certeza de que deseja excluir a lista "{list}"?\nIsso nao pode ser desfeito.',
      'delete': 'Excluir',
    },
    'de': {
      'cards': 'Karten',
      'set': 'Set',
      'select_list': 'Liste auswahlen',
      'level': 'Niveau',
      'list': 'Liste',
      'study': 'Lernen',
      'native': 'Muttersprache',
      'random_speaking': 'zufallige Wiedergabe',
      'background_speaking': 'Wiedergabe im Hintergrund',
      'sleep_timer': 'Schlaf-Timer',
      'dark_theme': 'Dunkles Design',
      'tap_sound': 'Tippton',
      'interface_language': 'Oberflachensprache',
      'save_to_list': 'In Liste speichern',
      'save_to_custom_list': 'In eigene Liste speichern',
      'legal': 'Rechtliches',
      'privacy_policy': 'Datenschutz',
      'terms_of_use': 'Nutzungsbedingungen',
      'ad_privacy': 'Werbeeinstellungen',
      'privacy_options_unavailable':
          'Werbeeinstellungen sind in Ihrer Region nicht erforderlich oder verfugbar.',
      'reader': 'Reader',
      'autoplay': 'Autoplay',
      'repeat_list': 'Liste wiederholen',
      'play_once': 'Der Reihe nach',
      'off': 'aus',
      'min': 'min',
      'enter_minutes': 'Minuten fur den Timer eingeben',
      'no_target_list':
          'Keine Zielliste ausgewahlt. Bitte in Einstellungen > In Liste speichern wahlen.',
      'create_custom_list': 'Eigene Liste erstellen',
      'list_name': 'Listenname',
      'custom_list_tip':
          'Tipp: Fuge Worte aus anderen Listen zu dieser Liste hinzu, dann wahlen Sie diese Liste unter "in Liste speichern".',
      'cancel': 'Abbrechen',
      'create': 'Erstellen',
      'none': 'Keine',
      'my_custom_list': 'Meine eigene Liste',
      'processing_words': 'Worter werden verarbeitet',
      'finding_translations': 'Ubersetzungen werden gesucht...',
      'could_not_open': 'Konnte nicht offnen',
      'saved_to_custom': '"{word}" zur eigenen Liste hinzugefugt.',
      'removed_from_custom': '"{word}" wurde aus der eigenen Liste entfernt.',
      'error_creating_list': 'Fehler beim Erstellen der Liste',
      'delete_list': 'Liste loschen',
      'delete_confirm':
          'Mochten Sie die Liste "{list}" wirklich loschen?\nDies kann nicht ruckgangig gemacht werden.',
      'delete': 'Loschen',
    },
    'fr': {
      'cards': 'Cartes',
      'set': 'Liste',
      'select_list': 'Choisir une liste',
      'level': 'Niveau',
      'list': 'Liste',
      'study': 'Etude',
      'native': 'Langue maternelle',
      'random_speaking': 'lecture aleatoire',
      'background_speaking': 'lecture en arriere-plan',
      'sleep_timer': 'minuteur de sommeil',
      'dark_theme': 'theme sombre',
      'tap_sound': 'son au toucher',
      'interface_language': 'langue de l\'interface',
      'save_to_list': 'enregistrer dans la liste',
      'save_to_custom_list': 'enregistrer dans la liste personnalisee',
      'legal': 'legal',
      'privacy_policy': 'Politique de confidentialite',
      'terms_of_use': 'Conditions d\'utilisation',
      'ad_privacy': 'Confidentialite des annonces',
      'privacy_options_unavailable':
          'Les parametres de confidentialite des annonces ne sont pas disponibles dans votre region.',
      'reader': 'Lecteur',
      'autoplay': 'Lecture automatique',
      'repeat_list': 'Repeter la liste',
      'play_once': 'Dans l\'ordre',
      'off': 'desactive',
      'min': 'min',
      'enter_minutes': 'Entrez les minutes du minuteur',
      'no_target_list':
          'Aucune liste selectionnee. Choisissez-en une dans Reglages > Enregistrer dans la liste.',
      'create_custom_list': 'Creer une liste personnalisee',
      'list_name': 'Nom de la liste',
      'custom_list_tip':
          'Astuce : ajoutez des mots a cette liste depuis d\'autres listes, puis choisissez cette liste dans "enregistrer dans la liste".',
      'cancel': 'Annuler',
      'create': 'Creer',
      'none': 'Aucun',
      'my_custom_list': 'Ma liste personnalisee',
      'processing_words': 'Traitement des mots',
      'finding_translations': 'Recherche de traductions...',
      'could_not_open': 'Impossible d\'ouvrir',
      'saved_to_custom': '"{word}" ajoute a la liste personnalisee.',
      'removed_from_custom':
          '"{word}" a ete supprime de la liste personnalisee.',
      'error_creating_list': 'Erreur lors de la creation de la liste',
      'delete_list': 'Supprimer la liste',
      'delete_confirm':
          'Voulez-vous supprimer la liste "{list}"?\nCette action est irreversible.',
      'delete': 'Supprimer',
    },
    'it': {
      'cards': 'Carte',
      'set': 'Set',
      'select_list': 'Seleziona lista',
      'level': 'Livello',
      'list': 'Lista',
      'study': 'Studio',
      'native': 'Madrelingua',
      'random_speaking': 'riproduzione casuale',
      'background_speaking': 'riproduzione in background',
      'sleep_timer': 'timer di sonno',
      'dark_theme': 'tema scuro',
      'tap_sound': 'suono al tocco',
      'interface_language': 'lingua dell\'interfaccia',
      'save_to_list': 'salva nella lista',
      'save_to_custom_list': 'salva nella lista personalizzata',
      'legal': 'legale',
      'privacy_policy': 'Informativa sulla privacy',
      'terms_of_use': 'Termini di utilizzo',
      'ad_privacy': 'Privacy degli annunci',
      'privacy_options_unavailable':
          'Le opzioni di privacy degli annunci non sono disponibili nella tua area geografica.',
      'reader': 'Lettore',
      'autoplay': 'Riproduzione automatica',
      'repeat_list': 'Ripeti lista',
      'play_once': 'In ordine',
      'off': 'spento',
      'min': 'min',
      'enter_minutes': 'Inserisci minuti per il timer',
      'no_target_list':
          'Nessuna lista selezionata. Scegli in Impostazioni > Salva nella lista.',
      'create_custom_list': 'Crea lista personalizzata',
      'list_name': 'Nome lista',
      'custom_list_tip':
          'Suggerimento: aggiungi parole a questa lista da altre liste salvandole, poi scegli questa lista in "salva nella lista".',
      'cancel': 'Annulla',
      'create': 'Crea',
      'none': 'Nessuna',
      'my_custom_list': 'La mia lista personalizzata',
      'processing_words': 'Elaborazione parole',
      'finding_translations': 'Ricerca traduzioni...',
      'could_not_open': 'Impossibile aprire',
      'saved_to_custom': '"{word}" aggiunta alla lista personalizzata.',
      'removed_from_custom': 'Rimosso "{word}" dalla lista personalizzata.',
      'error_creating_list': 'Errore nella creazione della lista',
      'delete_list': 'Elimina lista',
      'delete_confirm':
          'Vuoi eliminare la lista "{list}"?\nNon puo essere annullato.',
      'delete': 'Elimina',
    },
    'tr': {
      'cards': 'Kartlar',
      'set': 'Set',
      'select_list': 'Liste sec',
      'level': 'Seviye',
      'list': 'Liste',
      'study': 'Calisma',
      'native': 'Ana dil',
      'random_speaking': 'rastgele okuma',
      'background_speaking': 'arka planda okuma',
      'sleep_timer': 'uyku zamanlayicisi',
      'dark_theme': 'koyu tema',
      'tap_sound': 'dokunma sesi',
      'interface_language': 'arayuz dili',
      'save_to_list': 'listeye kaydet',
      'save_to_custom_list': 'ozel listeye kaydet',
      'legal': 'yasal',
      'privacy_policy': 'Gizlilik politikasi',
      'terms_of_use': 'Kullanim kosullari',
      'ad_privacy': 'Reklam Gizliligi',
      'privacy_options_unavailable':
          'Reklam gizliligi ayarlari bolgenizde gerekli degil veya kullanilamiyor.',
      'reader': 'Okuyucu',
      'autoplay': 'Otomatik oynatma',
      'repeat_list': 'Listeyi tekrar et',
      'play_once': 'Sirayla',
      'off': 'kapali',
      'min': 'dk',
      'enter_minutes': 'Zamanlayici icin dakika girin',
      'no_target_list':
          'Hedef liste secilmedi. Ayarlar > Listeye kaydet bolumunden secin.',
      'create_custom_list': 'Ozel liste olustur',
      'list_name': 'Liste adi',
      'custom_list_tip':
          'Ipucu: kelimeleri diger listelerden kaydederek bu listeye ekleyin, sonra "listeye kaydet"ten bu listeyi secin.',
      'cancel': 'Iptal',
      'create': 'Olustur',
      'none': 'Yok',
      'my_custom_list': 'Benim ozel listem',
      'processing_words': 'Kelimeler isleniyor',
      'finding_translations': 'Ceviriler bulunuyor...',
      'could_not_open': 'Acilamadi',
      'saved_to_custom': '"{word}" ozel listeye eklendi.',
      'removed_from_custom': '"{word}" ozel listeden kaldirildi.',
      'error_creating_list': 'Liste olusturma hatasi',
      'delete_list': 'Listeyi sil',
      'delete_confirm':
          '"{list}" listesini silmek istiyor musunuz?\nBu geri alinamaz.',
      'delete': 'Sil',
    },
  };

  String _uiLangCode() {
    if (uiUseNative && nativeLang.isNotEmpty) return nativeLang;
    return 'en';
  }

  String _t(String key) {
    final code = _uiLangCode();
    return _uiStrings[code]?[key] ?? _uiStrings['en']![key] ?? key;
  }

  // --- ADD THIS NEW METHOD ---
  Future<void> _loadCustomListNames() async {
    final prefs = await SharedPreferences.getInstance();
    allCustomListNames = prefs.getStringList('custom_list_names') ?? [];
    if (targetCustomSet.isEmpty && allCustomListNames.isNotEmpty) {
      targetCustomSet = allCustomListNames.first;
      await prefs.setString('targetCustomSet', targetCustomSet);
    }
    _invalidateGroupedLists();
  }

  Future<Map<String, String>> _loadEnglishContextSentences() async {
    if (!_showContextSentenceExamples) return const {};
    if (englishContextSentences.isNotEmpty) return englishContextSentences;

    try {
      final rawData =
          await EncryptedAssetLoader.loadString('assets/data/sets/master_en.jsonl');
      final Map<String, String> contexts = {};
      for (final line in rawData.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) continue;
        final lemma = (decoded['lemma'] ?? '').toString().trim().toLowerCase();
        final sentence = (decoded['context_sentence'] ?? '').toString().trim();
        if (lemma.isNotEmpty && sentence.isNotEmpty) {
          contexts[lemma] = sentence;
        }
      }
      englishContextSentences = contexts;
    } catch (e) {
      debugPrint('Error loading English context sentences: $e');
      englishContextSentences = {};
    }

    return englishContextSentences;
  }

  void _attachContextSentences(Map<String, String> contexts) {
    if (!_showContextSentenceExamples || contexts.isEmpty || allWords.isEmpty) return;
    var changed = false;
    for (var i = 0; i < allWords.length; i++) {
      final w = allWords[i];
      if (w.example1.isEmpty) {
        final ex = contexts[w.wordMain.toLowerCase()];
        if (ex != null && ex.isNotEmpty) {
          allWords[i] = WordEntry(
            w.level,
            w.sublist,
            w.wordMain,
            w.trans1,
            ex,
            w.example2,
            w.example3,
            w.example4,
            w.wordSyn,
            w.trans2,
          );
          changed = true;
        }
      }
    }
    if (changed) {
      filterCurrentSet();
    }
  }

  void _invalidateGroupedLists() {
    _groupedListsCache = null;
  }

  Future<void> _setTargetCustomSet(String listName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('targetCustomSet', listName);
    setState(() {
      targetCustomSet = listName;
    });
  }

  void _cancelSleepTimer() {
    _sleepTimerExpiring = false;
    sleepTimer?.cancel();
    sleepTicker?.cancel();
    sleepTimer = null;
    sleepTicker = null;
    sleepTimerEnd = null;
  }

  String _remainingSleepMinutesLabel() {
    if (sleepTimerEnd == null) return 'off';
    final remaining = sleepTimerEnd!.difference(DateTime.now());
    if (remaining.isNegative) return 'off';
    final totalSeconds = remaining.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _startSleepTimer(Duration duration) {
    _cancelSleepTimer();
    sleepTimerEnd = DateTime.now().add(duration);
    sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
    sleepTimer = Timer(duration, () {
      _onSleepTimerTriggered();
    });
  }

  void _onSleepTimerTriggered() {
    if (!mounted) return;
    if (isPlaying) {
      _sleepTimerExpiring = true;
      // Safety timeout: if speaking takes longer than 8s, force finish
      Timer(const Duration(seconds: 8), () {
        if (_sleepTimerExpiring && mounted) {
          _sleepTimerExpiring = false;
          _handleSleepTimerFinished();
        }
      });
    } else {
      _handleSleepTimerFinished();
    }
  }

  Future<void> _handleSleepTimerFinished() async {
    if (!mounted) return;

    // 1. Ensure speaking loop is stopped
    stopPlaying(updateUi: true);

    // 2. Clear timer state
    if (mounted) {
      setState(() {
        _cancelSleepTimer();
      });
    }

    // 3. Save current card position
    await _saveCurrentPosition();

    // 4. Play the calm double chime
    await SoundService.playTimerChime();

    // 5. Allow 2.1 seconds for the chime to complete naturally
    await Future.delayed(const Duration(milliseconds: 2100));

    // 6. Close the app completely as requested
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      SystemNavigator.pop();
    }
  }

  Future<void> loadWords() async {
    setState(() {
      isLoading = true;
    });

    // --- FIX: Ensure custom names are loaded ---
    await _loadCustomListNames();

    final prefs = await SharedPreferences.getInstance();
    String prefStudy = prefs.getString('study_language') ?? 'en';
    String prefNative = prefs.getString('native_language') ?? 'uk';
    if (!LanguageCatalog.isAvailable(prefStudy)) prefStudy = 'en';
    if (!LanguageCatalog.isAvailable(prefNative)) prefNative = 'uk';
    if (prefStudy == prefNative) prefNative = prefStudy == 'en' ? 'uk' : 'en';

    List<List<dynamic>> parseCsv(String data) {
      List<List<dynamic>> table = const CsvToListConverter().convert(data);
      if (table.length > 1) return table;
      table = const CsvToListConverter(eol: '\n').convert(data);
      if (table.length > 1) return table;
      table = const CsvToListConverter(eol: '\r\n').convert(data);
      if (table.length > 1) return table;
      final normalized = data.replaceAll('\r', '\n');
      return const CsvToListConverter(eol: '\n').convert(normalized);
    }

    Future<List<WordEntry>> loadPair(String sLang, String nLang) async {
      try {
        String cleanSecondaryTranslation(String primary, String rawSecondary) {
          final secondary = rawSecondary.trim();
          final normalizedPrimary =
              primary.trim().toLowerCase().replaceAll(RegExp(r's+'), ' ');
          final normalizedSecondary =
              secondary.toLowerCase().replaceAll(RegExp(r's+'), ' ');
          if (secondary.isEmpty || normalizedPrimary == normalizedSecondary) {
            return '';
          }
          if (RegExp(r'[⺀-鿿]').hasMatch(secondary)) return '';
          return secondary;
        }

        final contextSentences = englishContextSentences;
        if (sLang == 'en' && contextSentences.isEmpty) {
          unawaited(_loadEnglishContextSentences().then((contexts) {
            if (mounted && contexts.isNotEmpty) {
              setState(() => _attachContextSentences(contexts));
            }
          }));
        }
        final String studyPath = 'assets/data/sets/$sLang.csv';
        final String nativePath = 'assets/data/sets/$nLang.csv';
        final String studyData =
            await EncryptedAssetLoader.loadString(studyPath);
        final String nativeData =
            await EncryptedAssetLoader.loadString(nativePath);

        final studyTable = parseCsv(studyData);
        final nativeTable = parseCsv(nativeData);
        final int rowsToProcess =
            math.min(studyTable.length, nativeTable.length);

        List<WordEntry> loadedWords = [];
        for (int i = 1; i < rowsToProcess; i++) {
          try {
            final sRow = studyTable[i];
            final nRow = nativeTable[i];
            if (sRow.length < 3 || nRow.length < 3) continue;

            final level = sRow[0].toString().trim();
            final sublist = sRow[1].toString().trim();
            final wordMain = sRow[2].toString().trim();
            final trans1 = nRow[2].toString().trim();
            final trans2 = nRow.length > 3
                ? cleanSecondaryTranslation(trans1, nRow[3].toString())
                : '';
            if (wordMain.isEmpty || trans1.isEmpty) continue;
            final contextSentence =
                contextSentences[wordMain.toLowerCase()] ?? '';

            loadedWords.add(WordEntry(
              level,
              sublist,
              wordMain,
              trans1,
              contextSentence,
              '',
              '',
              '',
              sRow.length > 3 ? sRow[3].toString().trim() : '',
              trans2,
            ));
          } catch (rowError) {
            debugPrint('Skipping row $i due to error: $rowError');
          }
        }
        return loadedWords;
      } catch (e) {
        debugPrint('Error loading CSVs for $sLang/$nLang: $e');
        return [];
      }
    }

    List<WordEntry> loadedWords = await loadPair(prefStudy, prefNative);
    if (loadedWords.isEmpty && !(prefStudy == 'en' && prefNative == 'uk')) {
      debugPrint('Fallback to en/uk because loadedWords empty');
      loadedWords = await loadPair('en', 'uk');
      prefStudy = 'en';
      prefNative = 'uk';
    }

    studyLang = prefStudy;
    nativeLang = prefNative;
    allWords = loadedWords;

    // Load custom lists from SharedPreferences and cache them
    _customEntries = await _loadCustomLists();
    _updateCustomWordsSet();

    // Merge predefined and custom lists
    allWords.addAll(_customEntries);
    _invalidateGroupedLists();

    // Pick default by CEFR order, then numeric sublist
    final grouped = getGroupedLists();
    final levels = grouped.keys.toList()
      ..sort((a, b) => _levelOrderIndex(a).compareTo(_levelOrderIndex(b)));
    String initLevel = levels.isNotEmpty ? levels.first : '';
    String initSub = '';
    if (initLevel.isNotEmpty) {
      final subs = List<String>.from(grouped[initLevel] ?? [])
        ..sort(_compareSublists);
      if (subs.isNotEmpty) initSub = subs.first;
    }

    final savedLevel = prefs.getString('last_selected_level');
    final savedSub = prefs.getString('last_selected_sublist');
    final savedWord = prefs.getString('last_word_main');
    final savedIndex = prefs.getInt('last_card_index');
    final savedGridMode = prefs.getBool('last_grid_mode');
    final savedGridPage = prefs.getInt('last_grid_page');

    if (savedLevel != null &&
        grouped.containsKey(savedLevel) &&
        savedSub != null &&
        (grouped[savedLevel]?.contains(savedSub) ?? false)) {
      initLevel = savedLevel;
      initSub = savedSub;
    }

    setState(() {
      selectedLevel = initLevel;
      selectedSublist = initSub;
      filterCurrentSet();
      if (savedWord != null && currentSetWords.isNotEmpty) {
        final foundIdx = currentSetWords.indexWhere(
            (w) => w.wordMain.trim().toLowerCase() == savedWord.trim().toLowerCase());
        if (foundIdx != -1) {
          currentIndex = foundIdx;
        } else if (savedIndex != null &&
            savedIndex >= 0 &&
            savedIndex < currentSetWords.length) {
          currentIndex = savedIndex;
        }
      } else if (savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < currentSetWords.length) {
        currentIndex = savedIndex;
      }
      if (savedGridMode != null) {
        gridMode = savedGridMode;
      }
      if (savedGridPage != null && savedGridPage >= 0) {
        gridPage = savedGridPage;
      }
      isLoading = false;
    });

    debugPrint('Loaded ${allWords.length} words');
    debugPrint('Levels: $levels');
    debugPrint('Current: $selectedLevel / $selectedSublist');
    debugPrint('Words in current list: ${currentSetWords.length}');
  }

  String _wordPrefix(WordEntry entry) {
    final word = entry.wordMain.trim().toLowerCase();
    return word.length <= 2 ? word : word.substring(0, 2);
  }

  List<WordEntry> _shuffleBatch(List<WordEntry> words) {
    final groups = <String, List<WordEntry>>{};
    for (final word in words) {
      groups.putIfAbsent(_wordPrefix(word), () => []).add(word);
    }
    for (final group in groups.values) {
      group.shuffle(_batchShuffleRandom);
    }

    final shuffled = <WordEntry>[];
    String? previousPrefix;
    while (groups.isNotEmpty) {
      final candidates =
          groups.entries.where((group) => group.key != previousPrefix).toList();
      final pool = candidates.isEmpty ? groups.entries.toList() : candidates;
      final largestGroupSize =
          pool.map((group) => group.value.length).reduce(math.max);
      final largestGroups = pool
          .where((group) => group.value.length == largestGroupSize)
          .toList();
      final selected =
          largestGroups[_batchShuffleRandom.nextInt(largestGroups.length)];

      shuffled.add(selected.value.removeLast());
      previousPrefix = selected.key;
      if (selected.value.isEmpty) {
        groups.remove(selected.key);
      }
    }

    return shuffled;
  }

  void filterCurrentSet() {
    final batchWords = allWords
        .where((w) =>
            w.level.trim().toLowerCase() ==
                selectedLevel.trim().toLowerCase() &&
            w.sublist.trim().toLowerCase() ==
                selectedSublist.trim().toLowerCase())
        .toList();
    currentSetWords = _shuffleBatch(batchWords);
    currentIndex = 0;
    gridPage = 0;
    gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
    setState(() {});
    debugPrint(
        'Filtering for "$selectedLevel / $selectedSublist", shuffled ${currentSetWords.length} words');
  }

  void changeSet(String newSet) {
    setState(() {
      selectedSublist = newSet;
      filterCurrentSet();
    });
    _saveCurrentPosition();
  }

  @override
  void didUpdateWidget(covariant FlashcardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showENasDefault != widget.showENasDefault) {
      setState(() {
        showENFace = widget.showENasDefault;
      });
    }
  }

  void toggleCardFace() {
    setState(() {
      showENFace = !showENFace;
    });
  }

  Future<void> _speak(String text, String langCode) async {
    if (text.trim().isEmpty) return;
    String ttsLang = "en-US";
    if (langCode == 'uk') ttsLang = "uk-UA";
    if (langCode == 'es') ttsLang = "es-ES";
    if (langCode == 'pt') ttsLang = "pt-PT";
    if (langCode == 'de') ttsLang = "de-DE";
    if (langCode == 'fr') ttsLang = "fr-FR";
    if (langCode == 'it') ttsLang = "it-IT";
    if (langCode == 'tr') ttsLang = "tr-TR";

    await flutterTts.setLanguage(ttsLang);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak(text);
  }

  Future<void> _speakStudy(String text) async => _speak(text, studyLang);
  Future<void> _speakNative(String text) async => _speak(text, nativeLang);

  Future<void> speakWord(String word) async {
    await _activateAudioSession();
    await _speakStudy(word);
    await _deactivateAudioSession();
  }

  void _nextSingleCard() {
    final next = nextCardPage(
        currentIndex: currentIndex,
        wordCount: currentSetWords.length,
        pageSize: 1);
    setState(() {
      currentIndex = next.index;
      showENFace = widget.showENasDefault;
    });
    _saveCurrentPosition();
    if (shouldRequestSetCompletionAd(
        finishedSet: next.finishedSet,
        hasPremiumAccess: BillingService().hasPremiumAccess)) {
      AdHelper.showInterstitialAd(onAdClosed: () {});
    }
  }

  void _previousSingleCard() {
    setState(() {
      if (currentSetWords.isNotEmpty) {
        currentIndex =
            (currentIndex - 1 + currentSetWords.length) % currentSetWords.length;
      }
      showENFace = widget.showENasDefault;
    });
    _saveCurrentPosition();
  }

  void nextGridPage() {
    final next = nextCardPage(
        currentIndex: gridPage,
        wordCount: currentSetWords.length,
        pageSize: _cardsPerGridPage);
    setState(() {
      gridPage = next.index;
      gridCardENFace =
          List.filled(_cardsPerGridPage, showENFace); // <-- use current default
    });
    _saveCurrentPosition();
    if (shouldRequestSetCompletionAd(
        finishedSet: next.finishedSet,
        hasPremiumAccess: BillingService().hasPremiumAccess)) {
      AdHelper.showInterstitialAd(onAdClosed: () {});
    }
  }

  void prevGridPage() {
    setState(() {
      final int maxPage =
          (currentSetWords.length / _cardsPerGridPage).ceil() - 1;
      if (maxPage <= 0) {
        gridPage = 0;
      } else if (gridPage <= 0) {
        gridPage = maxPage;
      } else {
        gridPage--;
      }
      gridCardENFace =
          List.filled(_cardsPerGridPage, showENFace); // <-- use current default
    });
  }

  bool _advanceToNextListing() {
    if (selectedLevel.trim().toLowerCase() == 'custom') return false;

    final grouped = getGroupedLists();
    final levels = grouped.keys
        .where((lvl) => lvl.trim().toLowerCase() != 'custom')
        .toList()
      ..sort((a, b) => _levelOrderIndex(a).compareTo(_levelOrderIndex(b)));
    if (levels.isEmpty) return false;

    final currentLevel = selectedLevel;
    final currentSub = selectedSublist;
    var levelIdx = levels.indexWhere(
      (l) => l.trim().toLowerCase() == currentLevel.trim().toLowerCase(),
    );
    if (levelIdx == -1) levelIdx = 0;

    for (int li = levelIdx; li < levels.length; li++) {
      final lvl = levels[li];
      final subs = List<String>.from(grouped[lvl] ?? [])
        ..sort(_compareSublists);
      if (subs.isEmpty) continue;

      int startSubIdx = 0;
      if (li == levelIdx) {
        final curIdx = subs.indexWhere(
          (s) => s.trim().toLowerCase() == currentSub.trim().toLowerCase(),
        );
        startSubIdx = curIdx == -1 ? 0 : curIdx + 1;
      }

      if (startSubIdx < subs.length) {
        final nextSub = subs[startSubIdx];
        setState(() {
          selectedLevel = lvl;
          selectedSublist = nextSub;
        });
        filterCurrentSet();
        return true;
      }
    }

    return false;
  }

  Future<void> playSetWords() async {
    if (isPlaying) return;
    if (currentSetWords.isEmpty) return;
    await _activateAudioSession();
    setState(() {
      isPlaying = true;
    });
    _pausedByInterruption = false;

    // Determine start index for single or grid mode
    int startIdx = gridMode ? gridPage * _cardsPerGridPage : currentIndex;

    Future<void> speakEntry(WordEntry entry, {required bool studyFirst}) async {
      if (studyFirst) {
        await _speakStudy(entry.wordMain);
        if (!isPlaying) return;
        await Future.delayed(const Duration(milliseconds: 350));
        if (!isPlaying) return;
        await _speakNative(entry.trans1);
      } else {
        await _speakNative(entry.trans1);
        if (!isPlaying) return;
        await Future.delayed(const Duration(milliseconds: 350));
        if (!isPlaying) return;
        await _speakStudy(entry.wordMain);
      }
    }

    final rng = math.Random();
    const bool speakStudyFirst = true;

    if (randomSpeaking) {
      int? lastIdx;
      int lastLen = currentSetWords.length;
      List<int> order = [];
      int pos = 0;

      void refillOrder() {
        final len = currentSetWords.length;
        order = List<int>.generate(len, (i) => i);
        order.shuffle(rng);
        if (lastIdx != null &&
            len > 1 &&
            order.isNotEmpty &&
            order.first == lastIdx) {
          final swap = 1 + rng.nextInt(len - 1);
          final tmp = order[0];
          order[0] = order[swap];
          order[swap] = tmp;
        }
        pos = 0;
        lastLen = len;
      }

      refillOrder();

      while (isPlaying) {
        if (currentSetWords.isEmpty) break;
        if (currentSetWords.length != lastLen || pos >= order.length) {
          refillOrder();
          if (order.isEmpty) break;
        }

        final idx = order[pos++];
        lastIdx = idx;

        if (!mounted) break;
        setState(() {
          currentIndex = idx;
          if (gridMode) {
            gridPage = idx ~/ _cardsPerGridPage;
            gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
          }
        });

        final entry = currentSetWords[idx];
        try {
          await speakEntry(entry, studyFirst: speakStudyFirst);
        } catch (_) {}
        if (!isPlaying || _sleepTimerExpiring) break;
        await Future.delayed(const Duration(milliseconds: 700));
        if (!isPlaying || _sleepTimerExpiring) break;
      }
    } else {
      int i = startIdx;
      while (isPlaying) {
        if (currentSetWords.isEmpty) break;
        if (i >= currentSetWords.length) {
          if (sleepTimerLoop) {
            i = 0;
          } else {
            final advanced = _advanceToNextListing();
            if (!advanced) break;
            i = 0;
            continue;
          }
        }

        final entry = currentSetWords[i];
        if (!mounted) break;
        setState(() {
          currentIndex = i;
          if (gridMode) {
            gridPage = i ~/ _cardsPerGridPage;
            gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
          }
        });

        try {
          await speakEntry(entry, studyFirst: speakStudyFirst);
        } catch (_) {}
        if (!isPlaying || _sleepTimerExpiring) break;
        await Future.delayed(const Duration(seconds: 1));
        if (!isPlaying || _sleepTimerExpiring) break;
        i++;
      }
    }

    setState(() {
      isPlaying = false;
    });
    if (!_pausedByInterruption) {
      unawaited(_deactivateAudioSession());
    }

    if (_sleepTimerExpiring) {
      _sleepTimerExpiring = false;
      unawaited(_handleSleepTimerFinished());
    }
  }

  // Optionally, add a stop function
  void stopPlaying({bool updateUi = true, bool dueToInterruption = false}) {
    isPlaying = false;
    _sleepTimerExpiring = false;
    if (!dueToInterruption) {
      _pausedByInterruption = false;
    }
    if (updateUi && mounted) {
      setState(() {});
    }
    flutterTts.stop();
    if (!dueToInterruption) {
      unawaited(_deactivateAudioSession());
    }
  }

  // Helper for grid page count
  int get totalGridPages => (currentSetWords.length / _cardsPerGridPage).ceil();

  Future<void> _loadDictionary() async {
    try {
      final englishRaw =
          await EncryptedAssetLoader.loadString('assets/data/sets/en.csv');
      final ukrainianRaw =
          await EncryptedAssetLoader.loadString('assets/data/sets/uk.csv');
      final english = const CsvToListConverter().convert(englishRaw);
      final ukrainian = const CsvToListConverter().convert(ukrainianRaw);
      if (english.length != ukrainian.length) {
        throw FormatException('English and Ukrainian row counts differ: ${english.length} and ${ukrainian.length}');
      }
      final translations = <String, String>{};
      for (var index = 1; index < english.length; index++) {
        final source = english[index];
        final target = ukrainian[index];
        if (source.length < 3 || target.length < 3 ||
            source[0].toString().trim() != target[0].toString().trim() ||
            source[1].toString().trim() != target[1].toString().trim()) {
          throw FormatException('Dictionary rows do not align at row $index');
        }
        final word = source[2].toString().toLowerCase().trim();
        final translation = target[2].toString().trim();
        if (word.isNotEmpty && translation.isNotEmpty) {
          translations[word] = translation;
        }
      }
      enUkDictionary = translations;
      debugPrint('Dictionary loaded with ${translations.length} entries.');
    } catch (e) {
      debugPrint('Error loading dictionary from CSV: $e');
    }
  }

  List<String> _translationSegments(String translation) => translation
      .split(';')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();

  bool _hasAdditionalTranslations(String translation) =>
      _translationSegments(translation).length > 1;

  String _gridTranslation(String translation) {
    final segments = _translationSegments(translation);
    return segments.isEmpty ? translation.trim() : segments.first;
  }

  bool _needsExpandedSingleCard(String translation) =>
      _hasAdditionalTranslations(translation) && translation.trim().length > 42;

  Future<void> _showFullTranslationSheet(WordEntry entry) {
    final translation = entry.trans1.trim();
    final sheetBackground = darkTheme ? const Color(0xFF1E2A3A) : Colors.white;
    final primaryText = darkTheme ? Colors.white : const Color(0xFF172033);
    final secondaryText = darkTheme ? Colors.white70 : const Color(0xFF4B5563);

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: primaryText.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.wordMain,
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Усі значення',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрити',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: Icon(Icons.close, color: primaryText),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                translation,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator if still loading
    if (isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyleForTop(darkTop: darkTheme),
        child: Scaffold(
          backgroundColor: darkTheme ? const Color(0xFF1E2A3A) : Colors.white,
          body: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final availableWidth = screenWidth - mediaQuery.padding.horizontal;
    final double safeWidth = availableWidth > 0 ? availableWidth : screenWidth;
    final double appBarHeight = 94.0;
    final double topSafePadding = mediaQuery.padding.top;
    final double appBarTotalHeight = appBarHeight + topSafePadding;
    final double overlayPanelTop = appBarTotalHeight + 6.0;
    final singleCardTranslation =
        currentSetWords.isNotEmpty ? currentSetWords[currentIndex].trans1 : '';
    final singleCardHasExpandedTranslation =
        !showENFace && _needsExpandedSingleCard(singleCardTranslation);

    // Smaller cards for 10-word grid
    // Larger cards for single view
    final desiredCardWidth = math.max(safeWidth * 0.65, 170.0);
    final cardWidth = math.min(desiredCardWidth, safeWidth);
    final cardHeight = math.max(
      singleCardHasExpandedTranslation ? 180.0 : 140.0,
      cardWidth * 0.52,
    );
    const double singleCardGapHeight =
        _showContextSentenceExamples ? 18.0 : 0.0;
    const double singleCardExamplesHeight =
        _showContextSentenceExamples ? 56.0 : 0.0;
    final double singleCardSectionHeight =
        cardHeight + singleCardGapHeight + singleCardExamplesHeight;
    final double bottomSafePadding = mediaQuery.viewPadding.bottom;
    const double bottomBarHeight = 72.0;
    final double gridCardMinHeight = 56.0;
    final double sliderHorizontalPadding = math.max(16.0, screenWidth * 0.06);
    final double settingsWidth = math.min(safeWidth, 420.0);
    // Raise the slider overlay (~30% up from the bottom, but never below the bar)
    final enWord = currentSetWords.isNotEmpty
        ? currentSetWords[currentIndex].wordMain
        : '';
    final ukWord =
        currentSetWords.isNotEmpty ? currentSetWords[currentIndex].trans1 : '';
    final example1 = currentSetWords.isNotEmpty
        ? currentSetWords[currentIndex].example1
        : '';
    final example2 = currentSetWords.isNotEmpty
        ? currentSetWords[currentIndex].example2
        : '';
    final cardExamples = [example1, example2]
        .where((example) => example.trim().isNotEmpty)
        .toList();

    final entry =
        currentSetWords.isNotEmpty ? currentSetWords[currentIndex] : null;
    final groupedLists = getGroupedLists();
    final singleCardMain = showENFace ? enWord : ukWord;
    final singleCardIsSingleWord =
        !RegExp(r'[\s;]').hasMatch(singleCardMain.trim());

    Widget centeredWordBlock({
      required String main,
      required TextStyle mainStyle,
      required bool compact,
      int mainMaxLines = 2,
      bool preferSingleLine = false,
      String? secondary,
      TextStyle? secondaryStyle,
      List<String>? examples,
      TextStyle? exampleStyle,
    }) {
      var cleanedSecondary = (secondary ?? '').trim();
      if (cleanedSecondary.toLowerCase() == main.trim().toLowerCase()) {
        cleanedSecondary = '';
      }
      final cleanedExamples =
          (examples ?? []).where((e) => e.trim().isNotEmpty).toList();
      final mainMaxHeight = compact ? 52.0 : 84.0;
      final secondaryMaxHeight = compact ? 24.0 : 34.0;

      Widget mainText(double maxHeight) => AdaptiveCardText(
            text: main,
            style: mainStyle,
            maxLines: mainMaxLines,
            maxHeight: maxHeight,
            minFontSize: compact ? 9 : 14,
            preferSingleLine: preferSingleLine,
          );

      if (compact) {
        return GridCardTextLayout(
          mainBuilder: (maxHeight) =>
              mainText(math.min(mainMaxHeight, maxHeight)),
          secondaryBuilder: cleanedSecondary.isEmpty
              ? null
              : (maxHeight) => AdaptiveCardText(
                    text: cleanedSecondary,
                    style: secondaryStyle ?? mainStyle,
                    maxHeight: math.min(secondaryMaxHeight, maxHeight),
                    maxLines: 1,
                    minFontSize: 10,
                  ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mainText(mainMaxHeight),
          if (cleanedSecondary.isNotEmpty) ...[
            const SizedBox(height: 3),
            AdaptiveCardText(
              text: cleanedSecondary,
              style: secondaryStyle ?? mainStyle,
              maxHeight: secondaryMaxHeight,
              maxLines: 1,
              minFontSize: compact ? 10 : 12,
            ),
          ],
          if (cleanedExamples.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final ex in cleanedExamples)
              Text(
                ex,
                style: exampleStyle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ],
      );
    }

    Widget singleCardView = SizedBox(
      width: cardWidth,
      height: singleCardSectionHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              _playTapClick();
              toggleCardFace();
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < 0) {
                  _nextSingleCard();
                } else if (details.primaryVelocity! > 0) {
                  _previousSingleCard();
                }
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: SizedBox(
                key: ValueKey(
                    '$currentIndex-$showENFace'), // <-- add currentIndex to key for animation
                width: cardWidth,
                height: cardHeight,
                child: _LiquidGlassSurface(
                  tint: showENFace
                      ? const Color(0xFF4FC3F7)
                      : const Color(0xFF66BB6A),
                  dark: darkTheme,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 12,
                        left: 12,
                        child: GestureDetector(
                          onTap: () {
                            _playTapClick();
                            if (currentSetWords.isNotEmpty) {
                              final currentWord = currentSetWords[currentIndex];
                              // Check if we're in a custom list
                              if (selectedLevel == 'custom') {
                                _removeWordFromCustomList(currentWord);
                              } else {
                                _toggleCustomSetWord(currentWord);
                              }
                            }
                          },
                          child: _GlassIconSurface(
                            size: 38,
                            dark: darkTheme,
                            child: Icon(
                              selectedLevel == 'custom'
                                  ? Icons.delete_outline
                                  : (_isWordInCustomList(
                                          currentSetWords.isNotEmpty
                                              ? currentSetWords[currentIndex]
                                              : null)
                                      ? Icons.star
                                      : Icons.star_border),
                              color: selectedLevel == 'custom'
                                  ? (darkTheme
                                      ? Colors.redAccent.shade100
                                      : Colors.blueGrey.shade500)
                                  : (_isWordInCustomList(
                                          currentSetWords.isNotEmpty
                                              ? currentSetWords[currentIndex]
                                              : null)
                                      ? (darkTheme
                                          ? const Color(0xFFFFD54F)
                                          : const Color(0xFFF59E0B))
                                      : (darkTheme
                                          ? Colors.white.withValues(alpha: 0.92)
                                          : const Color(0xFF25455F))),
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48.0),
                          child: centeredWordBlock(
                            main: singleCardMain,
                            compact: false,
                            mainMaxLines: showENFace
                                ? 2
                                : (singleCardHasExpandedTranslation ? 4 : 3),
                            preferSingleLine: singleCardIsSingleWord,
                            mainStyle: TextStyle(
                              color: darkTheme
                                  ? Colors.white
                                  : (showENFace
                                      ? const Color(0xFF102A43)
                                      : const Color(0xFF164C37)),
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: showENFace ? 34 : 27,
                              height: 1.1,
                            ),
                            secondary: showENFace
                                ? (entry != null && entry.wordSyn.isNotEmpty
                                    ? '(${entry.wordSyn})'
                                    : '')
                                : '',
                            secondaryStyle: showENFace
                                ? TextStyle(
                                    color: darkTheme
                                        ? Colors.white.withValues(alpha: 0.8)
                                        : const Color(0xFF315B75),
                                    fontFamily: 'Inter',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  )
                                : TextStyle(
                                    color: darkTheme
                                        ? Colors.white.withValues(alpha: 0.8)
                                        : const Color(0xFF215A47),
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 22,
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: () {
                            if (entry != null) speakWord(entry.wordMain);
                          },
                          child: _GlassIconSurface(
                            size: 38,
                            dark: darkTheme,
                            child: SvgPicture.asset(
                              'assets/icons/Speaker.svg',
                              width: 20,
                              height: 20,
                              colorFilter: ColorFilter.mode(
                                darkTheme
                                    ? Colors.white.withValues(alpha: 0.92)
                                    : const Color(0xFF25455F),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showContextSentenceExamples) ...[
            const SizedBox(height: singleCardGapHeight),
            // Always reserve space for examples, but only show for EN card
            SizedBox(
              height: singleCardExamplesHeight,
              child: showENFace && cardExamples.isNotEmpty
                  ? Container(
                      width: cardWidth,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 14.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cardExamples.join('\n'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          height: 1.2,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
    Widget gridCard(WordEntry entry, int idx) {
      bool isEN = gridCardENFace[idx];
      return GestureDetector(
        onTap: () {
          _playTapClick();
          setState(() {
            gridCardENFace[idx] = !gridCardENFace[idx];
          });
        },
        child: _LiquidGlassSurface(
          tint: isEN ? const Color(0xFF4FC3F7) : const Color(0xFF66BB6A),
          dark: darkTheme,
          child: Container(
            constraints: BoxConstraints(minHeight: gridCardMinHeight),
            padding: const EdgeInsets.all(8),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final reserveSideControls = constraints.maxWidth >= 140;
                      final textPadding = reserveSideControls
                          ? const EdgeInsets.symmetric(horizontal: 34)
                          : const EdgeInsets.fromLTRB(10, 32, 10, 4);
                      final displayWord = isEN
                          ? entry.wordMain
                          : _gridTranslation(entry.trans1);
                      final isSingleWord =
                          !RegExp(r'\s').hasMatch(displayWord.trim());

                      return Padding(
                        padding: textPadding,
                        child: Center(
                          child: Transform.translate(
                            offset: const Offset(0, -5),
                            child: centeredWordBlock(
                              main: displayWord,
                              compact: true,
                              mainMaxLines: isEN ? 1 : 2,
                              preferSingleLine: isSingleWord,
                              mainStyle: TextStyle(
                                color: darkTheme
                                    ? Colors.white
                                    : (isEN
                                        ? const Color(0xFF102A43)
                                        : const Color(0xFF164C37)),
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 22, // +~20%
                              ),
                              secondary: isEN
                                  ? (entry.wordSyn.isNotEmpty
                                      ? '(${entry.wordSyn})'
                                      : '')
                                  : '',
                              secondaryStyle: isEN
                                  ? TextStyle(
                                      color: darkTheme
                                          ? Colors.white.withValues(alpha: 0.8)
                                          : const Color(0xFF315B75),
                                      fontFamily: 'Inter',
                                      fontStyle: FontStyle.italic,
                                      fontSize: 14,
                                    )
                                  : TextStyle(
                                      color: darkTheme
                                          ? Colors.white.withValues(alpha: 0.8)
                                          : const Color(0xFF215A47),
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 18,
                                    ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 3,
                  left: 3,
                  child: GestureDetector(
                    onTap: () {
                      _playTapClick();
                      // Check if we're in a custom list
                      if (selectedLevel == 'custom') {
                        _removeWordFromCustomList(entry);
                      } else {
                        _toggleCustomSetWord(entry);
                      }
                    },
                    child: _GlassIconSurface(
                      size: 26,
                      dark: darkTheme,
                      child: Icon(
                        selectedLevel == 'custom'
                            ? Icons.delete_outline
                            : (_isWordInCustomList(entry)
                                ? Icons.star
                                : Icons.star_border),
                        color: selectedLevel == 'custom'
                            ? (darkTheme
                                ? Colors.redAccent.shade100
                                : Colors.blueGrey.shade500)
                            : (_isWordInCustomList(entry)
                                ? (darkTheme
                                    ? const Color(0xFFFFD54F)
                                    : const Color(0xFFF59E0B))
                                : (darkTheme
                                    ? Colors.white.withValues(alpha: 0.92)
                                    : const Color(0xFF25455F))),
                        size: 16,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 3,
                  right: 3,
                  child: GestureDetector(
                    onTap: () {
                      _playTapClick();
                      speakWord(entry.wordMain);
                    },
                    child: _GlassIconSurface(
                      size: 26,
                      dark: darkTheme,
                      child: SvgPicture.asset(
                        'assets/icons/Speaker.svg',
                        width: 16,
                        height: 16,
                        colorFilter: ColorFilter.mode(
                          darkTheme
                              ? Colors.white.withValues(alpha: 0.92)
                              : const Color(0xFF25455F),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!isEN && _hasAdditionalTranslations(entry.trans1))
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Tooltip(
                      message: 'Переглянути всі переклади',
                      child: GestureDetector(
                        onTap: () {
                          _playTapClick();
                          unawaited(_showFullTranslationSheet(entry));
                        },
                        child: _GlassIconSurface(
                          size: 24,
                          dark: darkTheme,
                          child: Icon(
                            Icons.more_horiz,
                            color: darkTheme
                                ? Colors.white.withValues(alpha: 0.92)
                                : const Color(0xFF25455F),
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget bottomAction({
      required Widget child,
      required VoidCallback onTap,
      double? width,
    }) {
      return GestureDetector(
        onTap: () {
          _playTapClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          height: 54,
          child: Center(child: child),
        ),
      );
    }

    Widget buildGridView({required double availableHeight}) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final Orientation screenOrientation =
              MediaQuery.orientationOf(context);
          final bool isLandscape = screenOrientation == Orientation.landscape;

          final double maxWidth = constraints.maxWidth;
          final double viewportHeight = availableHeight;

          // Always 2 columns x 5 rows in portrait, 5 columns x 2 rows in landscape
          final int crossAxisCount = isLandscape ? 5 : 2;
          final int fullGridRows = isLandscape ? 2 : 5;

          final int startIndex = gridPage * _cardsPerGridPage;
          final int totalRemaining =
              math.max(0, currentSetWords.length - startIndex);
          final int itemsOnPage = totalRemaining > _cardsPerGridPage
              ? _cardsPerGridPage
              : totalRemaining;

          final int activeRows = itemsOnPage == 0
              ? 1
              : ((itemsOnPage + crossAxisCount - 1) ~/ crossAxisCount);

          final double horizontalPadding = isLandscape
              ? math.max(16.0, math.min(48.0, maxWidth * 0.04))
              : math.max(12.0, math.min(32.0, maxWidth * 0.04));
          final double availableWidth =
              math.max(140.0, maxWidth - horizontalPadding * 2);

          final double crossAxisSpacing = isLandscape
              ? math.max(8.0, math.min(16.0, availableWidth * 0.02))
              : math.max(8.0, math.min(16.0, availableWidth * 0.025));

          final double mainAxisSpacing = isLandscape
              ? math.max(6.0, math.min(14.0, (viewportHeight - 2 * 68.0)))
              : math.max(6.0, math.min(14.0, (viewportHeight - 5 * 72.0) / 4));

          final double usableWidth =
              availableWidth - crossAxisSpacing * (crossAxisCount - 1);
          final double cardWidth = usableWidth / crossAxisCount;

          final double availableHeightForCards =
              math.max(120.0, viewportHeight);

          // Card height based on full 10-card capacity to preserve card shape on partial page
          final double fittedCardHeight =
              (availableHeightForCards - mainAxisSpacing * (fullGridRows - 1)) /
                  fullGridRows;

          final double maxAllowedCardHeight = isLandscape
              ? fittedCardHeight
              : math.min(fittedCardHeight, cardWidth * 0.95);
          final double cardHeight =
              math.max(56.0, maxAllowedCardHeight);

          final double aspectRatio = cardWidth / cardHeight;

          final double gridContentHeight = activeRows == 0
              ? 0.0
              : activeRows * cardHeight +
                  math.max(0, activeRows - 1) * mainAxisSpacing;
          final double extraVerticalPadding = math.max(
            0.0,
            (viewportHeight - gridContentHeight) / 2,
          );

          return GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < 0) {
                  nextGridPage();
                } else if (details.primaryVelocity! > 0) {
                  prevGridPage();
                }
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: GridView.builder(
                key: const ValueKey('flashcards_grid_view'),
                padding: EdgeInsets.only(
                  top: extraVerticalPadding,
                  bottom: extraVerticalPadding,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: itemsOnPage,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisSpacing: mainAxisSpacing,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (context, i) =>
                    gridCard(currentSetWords[startIndex + i], i),
              ),
            ),
          );
        },
      );
    }

    // --- SLIDER SECTION (OVERLAY ABOVE BOTTOM BAR) ---
    Widget sliderSection = const SizedBox.shrink();
    if (currentSetWords.isNotEmpty) {
      Widget buildSlider({
        required double min,
        required double max,
        required double value,
        required int divisions,
        required ValueChanged<double> onChanged,
        required ValueChanged<double> onChangeEnd,
      }) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              sliderHorizontalPadding, 12, sliderHorizontalPadding, 8),
          child: Material(
            color: Colors.white,
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Center(
                      child: Text(
                        gridMode
                            ? '${(value * _cardsPerGridPage + 1).toInt()}'
                            : '${(value + 1).toInt()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF1A237E),
                        inactiveTrackColor: const Color(0xFFB3E5FC),
                        thumbColor: const Color(0xFF1A237E),
                        overlayColor: const Color(0x331A237E),
                        trackHeight: 6,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 10),
                      ),
                      child: Slider(
                        min: min,
                        max: max,
                        value: value.clamp(min, max),
                        divisions: divisions,
                        onChanged: onChanged,
                        onChangeEnd: onChangeEnd,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Center(
                      child: Text(
                        '${currentSetWords.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (gridMode) {
        sliderSection = buildSlider(
          min: 0,
          max: (totalGridPages - 1).toDouble(),
          value: sliderValue,
          divisions: totalGridPages > 1 ? totalGridPages - 1 : 1,
          onChanged: (v) {
            setState(() {
              sliderValue = v;
              gridPage = v.round();
              gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
            });
          },
          onChangeEnd: (v) {
            setState(() {
              gridPage = v.round();
              gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
            });
            _saveCurrentPosition();
          },
        );
      } else {
        sliderSection = buildSlider(
          min: 0,
          max: (currentSetWords.length - 1).toDouble(),
          value: sliderValue,
          divisions:
              currentSetWords.length > 1 ? currentSetWords.length - 1 : 1,
          onChanged: (v) {
            setState(() {
              sliderValue = v;
              currentIndex = v.round();
            });
          },
          onChangeEnd: (v) {
            setState(() {
              currentIndex = v.round();
            });
            _saveCurrentPosition();
          },
        );
      }
    }

    // --- SYNC SLIDER VALUE WITH CURRENT PAGE/INDEX ---
    if (gridMode) {
      if (sliderValue != gridPage.toDouble()) {
        sliderValue = gridPage.toDouble();
      }
    } else {
      if (sliderValue != currentIndex.toDouble()) {
        sliderValue = currentIndex.toDouble();
      }
    }

    // --- SETTINGS MENU ---
    Widget settingsMenu = Positioned(
      top: overlayPanelTop + 8,
      left: 0,
      right: 0,
      bottom: bottomBarHeight + bottomSafePadding + 12,
      child: IgnorePointer(
        ignoring: !showSettingsMenu,
        child: AnimatedOpacity(
          opacity: showSettingsMenu ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: showSettingsMenu ? Offset.zero : const Offset(0, -0.05),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.topCenter,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setMenuState) {
                  void togglePanel(String panel) {
                    setState(() {
                      activeSettingsPanel =
                          activeSettingsPanel == panel ? '' : panel;
                    });
                    setMenuState(() {});
                  }

                  Color tileIconColor(bool enabled) {
                    if (enabled) return Colors.black;
                    return darkTheme ? Colors.white : Colors.black;
                  }

                  Widget settingsTile({
                    required Widget icon,
                    required String label,
                    String? subLabel,
                    Color? subLabelColor,
                    required bool enabled,
                    required VoidCallback onTap,
                  }) {
                    final Color base =
                        darkTheme ? const Color(0xFF263240) : Colors.white;
                    final Color active = const Color(0xFFD6ECFF);
                    final Color border = darkTheme
                        ? Colors.white24
                        : const Color(0xFF1A237E).withValues(alpha: 0.18);
                    final Color labelColor = enabled
                        ? Colors.black
                        : (darkTheme ? Colors.white : Colors.black87);
                    final Color subColor = subLabelColor ??
                        (enabled
                            ? Colors.black54
                            : (darkTheme ? Colors.white60 : Colors.black54));
                    return GestureDetector(
                      onTap: () {
                        _playTapClick();
                        onTap();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: enabled ? active : base,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            icon,
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: labelColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (subLabel != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        subLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: subColor,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  Widget settingsPanel() {
                    const Color activePanelBorder = Color(0xFFB3E5FC);
                    Color panelBorderColor(bool isActive) {
                      if (isActive) return activePanelBorder;
                      return darkTheme
                          ? Colors.white24
                          : const Color(0xFF1A237E).withValues(alpha: 0.18);
                    }

                    if (activeSettingsPanel == 'sleep') {
                      final bool isTimerActive = sleepTimerEnd != null;
                      final Color timerActiveColor = darkTheme
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFF2E7D32);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: darkTheme
                              ? const Color(0xFF1F2B3B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: panelBorderColor(
                              isTimerActive ||
                                  activeSettingsPanel == 'sleep',
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('sleep_timer'),
                              style: TextStyle(
                                color:
                                    darkTheme ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    !isTimerActive
                                        ? _t('off')
                                        : _remainingSleepMinutesLabel(),
                                    style: TextStyle(
                                      color: isTimerActive
                                          ? timerActiveColor
                                          : (darkTheme
                                              ? Colors.white
                                              : Colors.black),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: TextField(
                                    controller: sleepTimerController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    cursorColor:
                                        darkTheme ? Colors.white : Colors.black,
                                    style: TextStyle(
                                      color: darkTheme
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 17,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: _t('min'),
                                      hintStyle: TextStyle(
                                        color: darkTheme
                                            ? Colors.white70
                                            : Colors.black45,
                                        fontSize: 14,
                                      ),
                                      filled: true,
                                      fillColor: darkTheme
                                          ? const Color(0xFF2C3E50)
                                          : const Color(0xFFF7F9FC),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: darkTheme
                                              ? Colors.white30
                                              : Colors.black26,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: darkTheme
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () {
                                    final minutes = int.tryParse(
                                      sleepTimerController.text.trim(),
                                    );
                                    if (minutes == null || minutes <= 0) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(_t('enter_minutes')),
                                        ),
                                      );
                                      return;
                                    }
                                    setState(() {
                                      _startSleepTimer(
                                          Duration(minutes: minutes));
                                    });
                                    setMenuState(() {});
                                  },
                                  icon: Icon(
                                    Icons.play_arrow,
                                    color: isTimerActive
                                        ? timerActiveColor
                                        : (darkTheme
                                            ? Colors.white
                                            : Colors.black),
                                    size: 22,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() => _cancelSleepTimer());
                                    setMenuState(() {});
                                  },
                                  icon: Icon(
                                    Icons.stop,
                                    color:
                                        darkTheme ? Colors.white : Colors.black,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _t('repeat_list'),
                                    style: TextStyle(
                                      color: darkTheme
                                          ? Colors.white70
                                          : Colors.black87,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  value: sleepTimerLoop,
                                  onChanged: (value) async {
                                    _playTapClick();
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                        'sleepTimerLoop', value);
                                    if (!mounted) return;
                                    setState(() => sleepTimerLoop = value);
                                    setMenuState(() {});
                                  },
                                  activeThumbColor:
                                      darkTheme ? Colors.white : Colors.black,
                                  activeTrackColor: const Color(0xFFB3E5FC),
                                  inactiveThumbColor: darkTheme
                                      ? Colors.white70
                                      : Colors.black54,
                                  inactiveTrackColor: darkTheme
                                      ? Colors.white24
                                      : const Color(0xFF1A237E)
                                          .withValues(alpha: 0.18),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    if (activeSettingsPanel == 'save') {
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: darkTheme
                              ? const Color(0xFF1F2B3B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: panelBorderColor(
                              targetCustomSet.isNotEmpty ||
                                  activeSettingsPanel == 'save',
                            ),
                          ),
                        ),
                        child: _buildSaveToSection(darkTheme, setMenuState),
                      );
                    }

                    if (activeSettingsPanel == 'legal') {
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: darkTheme
                              ? const Color(0xFF1F2B3B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: panelBorderColor(
                                activeSettingsPanel == 'legal'),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('legal'),
                              style: TextStyle(
                                color:
                                    darkTheme ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _settingsRow(
                              icon: Icon(
                                Icons.privacy_tip_outlined,
                                size: 32,
                                color:
                                    darkTheme ? Colors.white60 : Colors.black38,
                              ),
                              label: _t('privacy_policy'),
                              value: false,
                              onChanged: (_) =>
                                  _openLegalUrl(_privacyPolicyUrl),
                              darkTheme: darkTheme,
                              isButton: true,
                              labelColor:
                                  darkTheme ? Colors.white60 : Colors.black38,
                              chevronColor:
                                  darkTheme ? Colors.white60 : Colors.black38,
                            ),
                            const SizedBox(height: 10),
                            _settingsRow(
                              icon: Icon(
                                Icons.tune_rounded,
                                size: 32,
                                color:
                                    darkTheme ? Colors.white60 : Colors.black38,
                              ),
                              label: _t('ad_privacy'),
                              value: false,
                              onChanged: (_) async {
                                final messenger = ScaffoldMessenger.of(context);
                                final shown = await ConsentManager.instance
                                    .showPrivacyOptionsForm();
                                if (!mounted) return;
                                if (!shown) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          _t('privacy_options_unavailable')),
                                    ),
                                  );
                                }
                              },
                              darkTheme: darkTheme,
                              isButton: true,
                              labelColor:
                                  darkTheme ? Colors.white60 : Colors.black38,
                              chevronColor:
                                  darkTheme ? Colors.white60 : Colors.black38,
                            ),
                            const SizedBox(height: 10),
                            _settingsRow(
                              icon: Icon(
                                Icons.description_outlined,
                                size: 32,
                                color:
                                    darkTheme ? Colors.white60 : Colors.black38,
                              ),
                              label: _t('terms_of_use'),
                              value: false,
                              onChanged: (_) => _openLegalUrl(_termsUrl),
                              darkTheme: darkTheme,
                              isButton: true,
                              labelColor:
                                  darkTheme ? Colors.white60 : Colors.black38,
                              chevronColor:
                                  darkTheme ? Colors.white60 : Colors.black38,
                            ),
                          ],
                        ),
                      );
                    }

                    return const SizedBox.shrink();
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      onVerticalDragEnd: (details) {
                        final v = details.primaryVelocity ?? 0.0;
                        if (v < -500) {
                          setState(() => showSettingsMenu = false);
                        }
                      },
                      child: SizedBox(
                        width: settingsWidth,
                        height: constraints.maxHeight,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(34, 18, 34, 18),
                          decoration: BoxDecoration(
                            color: darkTheme
                                ? const Color(0xFF2C3E50)
                                : Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF1F6F78)
                                  .withValues(alpha: 0.24),
                            ),
                          ),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                _settingsLanguageRow(
                                  studyCode: studyLang,
                                  nativeCode: nativeLang,
                                  onStudyChanged: (code) async {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setString(
                                        'study_language', code);
                                    setState(() => studyLang = code);
                                    loadWords();
                                  },
                                  onNativeChanged: (code) async {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setString(
                                        'native_language', code);
                                    setState(() => nativeLang = code);
                                    loadWords();
                                  },
                                  darkTheme: darkTheme,
                                ),
                                const Divider(),
                                const SizedBox(height: 12),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    const tileHeight = 62.0;
                                    final tileWidth =
                                        (constraints.maxWidth - 12.0) / 2.0;
                                    final tileAspect = tileWidth / tileHeight;
                                    return GridView.count(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: tileAspect,
                                      children: [
                                        settingsTile(
                                          icon: Icon(
                                            Icons.play_arrow,
                                            size: 26,
                                            color:
                                                tileIconColor(randomSpeaking),
                                          ),
                                          label: _t('random_speaking'),
                                          enabled: randomSpeaking,
                                          onTap: () {
                                            setState(() => randomSpeaking =
                                                !randomSpeaking);
                                            setMenuState(() {});
                                          },
                                        ),
                                        settingsTile(
                                          icon: Icon(
                                            Icons.bedtime_outlined,
                                            size: 26,
                                            color: tileIconColor(
                                                sleepTimerEnd != null ||
                                                    activeSettingsPanel ==
                                                        'sleep'),
                                          ),
                                          label: _t('sleep_timer'),
                                          subLabel: sleepTimerEnd == null
                                              ? _t('off')
                                              : _remainingSleepMinutesLabel(),
                                          subLabelColor: sleepTimerEnd != null
                                              ? (darkTheme
                                                  ? const Color(0xFF4ADE80)
                                                  : const Color(0xFF2E7D32))
                                              : null,
                                          enabled: sleepTimerEnd != null ||
                                              activeSettingsPanel == 'sleep',
                                          onTap: () => togglePanel('sleep'),
                                        ),
                                        settingsTile(
                                          icon: SvgPicture.asset(
                                            'assets/icons/darkTheme.svg',
                                            width: 26,
                                            height: 26,
                                            colorFilter: ColorFilter.mode(
                                              tileIconColor(darkTheme),
                                              BlendMode.srcIn,
                                            ),
                                          ),
                                          label: _t('dark_theme'),
                                          enabled: darkTheme,
                                          onTap: () {
                                            setState(
                                                () => darkTheme = !darkTheme);
                                            setMenuState(() {});
                                          },
                                        ),
                                        settingsTile(
                                          icon: Icon(
                                            Icons.translate,
                                            size: 26,
                                            color: tileIconColor(uiUseNative),
                                          ),
                                          label: _t('interface_language'),
                                          subLabel: uiUseNative
                                              ? '${_t('native')}: ${LanguageCatalog.byCode(nativeLang).label}'
                                              : LanguageCatalog.byCode('en')
                                                  .label,
                                          enabled: uiUseNative,
                                          onTap: () async {
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            final v = !uiUseNative;
                                            await prefs.setBool(
                                                'uiUseNative', v);
                                            if (!mounted) return;
                                            setState(() => uiUseNative = v);
                                            setMenuState(() {});
                                          },
                                        ),
                                        settingsTile(
                                          icon: Icon(
                                            Icons.edit_note,
                                            size: 26,
                                            color: tileIconColor(targetCustomSet
                                                    .isNotEmpty ||
                                                activeSettingsPanel == 'save'),
                                          ),
                                          label: _t('save_to_list'),
                                          subLabel: targetCustomSet.isEmpty
                                              ? _t('none')
                                              : targetCustomSet,
                                          enabled: targetCustomSet.isNotEmpty ||
                                              activeSettingsPanel == 'save',
                                          onTap: () => togglePanel('save'),
                                        ),
                                        settingsTile(
                                          icon: Icon(
                                            Icons.privacy_tip_outlined,
                                            size: 26,
                                            color: tileIconColor(
                                                activeSettingsPanel == 'legal'),
                                          ),
                                          label: _t('legal'),
                                          subLabel:
                                              '${_t('privacy_policy')} & ${_t('terms_of_use')}',
                                          enabled:
                                              activeSettingsPanel == 'legal',
                                          onTap: () => togglePanel('legal'),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: settingsPanel(),
                                ),
                                const SizedBox(height: 10),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyleForTop(darkTop: true),
      child: WillPopScope(
        onWillPop: () async {
          if (showSettingsMenu) {
            setState(() => showSettingsMenu = false);
            return false;
          }
          if (showWordsMenu) {
            setState(() => showWordsMenu = false);
            return false;
          }
          return true;
        },
        child: Scaffold(
          backgroundColor: darkTheme ? const Color(0xFF1E2A3A) : Colors.white,
          // [MODIFIED] Removed SafeArea wrapper to allow edge-to-edge content
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              // --- LAYER 1: CONTENT (SCROLLABLE GRID/CARD) ---
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final contentPadding = EdgeInsets.only(
                      top: appBarTotalHeight + 12.0,
                      bottom: bottomBarHeight + bottomSafePadding + 16.0,
                    );
                    final contentMinHeight = math.max(
                      0.0,
                      constraints.maxHeight -
                          contentPadding.top -
                          contentPadding.bottom,
                    );

                    if (gridMode) {
                      return Padding(
                        padding: contentPadding,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: contentMinHeight),
                          child: Center(
                            child: buildGridView(
                                availableHeight: contentMinHeight),
                          ),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: contentPadding,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: contentMinHeight),
                        child: Center(
                          child: GestureDetector(
                            onHorizontalDragEnd: (details) {
                              if (details.primaryVelocity != null) {
                                if (details.primaryVelocity! < 0) {
                                  _nextSingleCard();
                                } else if (details.primaryVelocity! > 0) {
                                  _previousSingleCard();
                                }
                              }
                            },
                            child: singleCardView,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // --- LAYER 2: TOP BAR (PINNED) ---
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  width: double.infinity,
                  height: appBarTotalHeight,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, topSafePadding + 8, 12, 8),
                    child: _LiquidGlassSurface(
                      tint: const Color(0xFF1F6F78),
                      dark: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                gridMode
                                    ? '${_t('cards')} ${currentSetWords.isEmpty ? 0 : (gridPage * _cardsPerGridPage + 1)} / ${currentSetWords.length}'
                                    : '${_t('cards')} ${currentSetWords.isEmpty ? 0 : (currentIndex + 1)} / ${currentSetWords.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: sleepTimerEnd == null
                                    ? const SizedBox.shrink()
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.timer_outlined,
                                            size: 16,
                                            color: Color(0xFF4ADE80),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _remainingSleepMinutesLabel(),
                                            style: const TextStyle(
                                              color: Color(0xFF4ADE80),
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            Tooltip(
                              message: 'Reader',
                              child: GestureDetector(
                                onTap: _openReader,
                                child: const _GlassIconSurface(
                                  size: 44,
                                  dark: true,
                                  child: Icon(
                                    Icons.menu_book_rounded,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Tooltip(
                              message: 'Settings',
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    showSettingsMenu = !showSettingsMenu;
                                  });
                                },
                                child: _GlassIconSurface(
                                  size: 44,
                                  dark: true,
                                  child: SvgPicture.asset(
                                    'assets/icons/settings.svg',
                                    width: 24,
                                    height: 24,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _WordsMenuButton(
                              groupedLists: groupedLists,
                              currentLevel: selectedLevel,
                              currentSublist: selectedSublist,
                              setLabel: _t('set'),
                              selectListLabel: _t('select_list'),
                              dark: true,
                              onOpen: () {
                                setState(() {
                                  panelActiveLevel = selectedLevel.isNotEmpty
                                      ? selectedLevel
                                      : (groupedLists.keys.isNotEmpty
                                          ? groupedLists.keys.first
                                          : '');
                                  showWordsMenu = !showWordsMenu;
                                  showSettingsMenu = false;
                                });
                              },
                              onSelect: (level, sublist) {
                                setState(() {
                                  selectedLevel = level;
                                  selectedSublist = sublist;
                                  filterCurrentSet();
                                  showWordsMenu = false;
                                });
                                _saveCurrentPosition();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // --- LAYER 3: BOTTOM BAR (PINNED) ---
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  width: double.infinity,
                  height: bottomBarHeight + bottomSafePadding,
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 6,
                        bottom:
                            bottomSafePadding > 0 ? bottomSafePadding + 6 : 6),
                    child: _LiquidGlassSurface(
                      tint: const Color(0xFF1F6F78),
                      dark: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: 'Cards grid',
                              child: bottomAction(
                                onTap: () {
                                  setState(() {
                                    gridMode = !gridMode;
                                  });
                                  _saveCurrentPosition();
                                },
                                child: _GlassIconSurface(
                                  size: 42,
                                  dark: true,
                                  child: SvgPicture.asset(
                                    'assets/icons/Grid.svg',
                                    width: 24,
                                    height: 24,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Tooltip(
                              message: 'Card language',
                              child: bottomAction(
                                onTap: () {
                                  widget.onToggleDefault();
                                  setState(() {
                                    showENFace = !showENFace;
                                    gridCardENFace = List.filled(
                                      _cardsPerGridPage,
                                      showENFace,
                                    );
                                  });
                                },
                                child: Container(
                                  width: 50,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.36),
                                    ),
                                  ),
                                  child: Text(
                                    showENFace
                                        ? studyLang.toUpperCase()
                                        : nativeLang.toUpperCase(),
                                    strutStyle: const StrutStyle(
                                      forceStrutHeight: true,
                                      height: 1.0,
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      height: 1.0,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Tooltip(
                              message: isPlaying ? 'Stop playback' : 'Play set',
                              child: bottomAction(
                                onTap: () async {
                                  if (!isPlaying) {
                                    if (!await _requirePremium(_t('autoplay'))) {
                                      return;
                                    }
                                    playSetWords();
                                  } else {
                                    stopPlaying();
                                  }
                                },
                                child: _GlassIconSurface(
                                  size: 42,
                                  dark: true,
                                  child: SvgPicture.asset(
                                    'assets/icons/Play circle.svg',
                                    width: 25,
                                    height: 25,
                                    colorFilter: ColorFilter.mode(
                                      isPlaying
                                          ? Colors.greenAccent.shade100
                                          : Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Tooltip(
                              message: 'Jump to card',
                              child: bottomAction(
                                onTap: () {
                                  if (currentSetWords.isNotEmpty) {
                                    setState(() {
                                      showSlider = !showSlider;
                                      sliderValue = gridMode
                                          ? gridPage.toDouble()
                                          : currentIndex.toDouble();
                                    });
                                  }
                                },
                                child: _GlassIconSurface(
                                  size: 42,
                                  dark: true,
                                  child: SvgPicture.asset(
                                    'assets/icons/Chevrons right.svg',
                                    width: 25,
                                    height: 25,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // --- LAYER 4: SLIDER OVERLAY ---
              if (showSlider && sliderSection is! SizedBox) ...[
                // Tap anywhere (outside bottom bar/slider) to dismiss.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: bottomBarHeight + bottomSafePadding,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => showSlider = false),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  // [MODIFIED] Position above the taller bottom bar
                  bottom: bottomBarHeight + bottomSafePadding + 12,
                  child: IgnorePointer(
                    ignoring: false,
                    child: sliderSection,
                  ),
                ),
              ],

              // --- LAYER 5: MENUS ---
              // Words Menu Panel (and its backdrop)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !showWordsMenu,
                  child: AnimatedOpacity(
                    opacity: showWordsMenu ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: GestureDetector(
                      onTap: () => setState(() => showWordsMenu = false),
                      child:
                          Container(color: Colors.black.withValues(alpha: 0.1)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: overlayPanelTop,
                right: 20,
                child: IgnorePointer(
                  ignoring: !showWordsMenu,
                  child: AnimatedOpacity(
                    opacity: showWordsMenu ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSlide(
                      offset:
                          showWordsMenu ? Offset.zero : const Offset(0, -0.05),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      child: GestureDetector(
                        onVerticalDragEnd: (details) {
                          final v = details.primaryVelocity ?? 0.0;
                          if (v < -500) {
                            setState(() => showWordsMenu = false);
                          }
                        },
                        child: _WordsMenuPanel(
                          groupedLists: groupedLists,
                          activeLevel: panelActiveLevel,
                          currentLevel: selectedLevel,
                          currentSublist: selectedSublist,
                          levelLabel: _t('level'),
                          listLabel: _t('list'),
                          onChangeLevel: (lvl) =>
                              setState(() => panelActiveLevel = lvl),
                          onSelect: (level, sublist) {
                            setState(() {
                              selectedLevel = level;
                              selectedSublist = sublist;
                              filterCurrentSet();
                              showWordsMenu = false;
                            });
                            _saveCurrentPosition();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Settings Menu (and its backdrop)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !showSettingsMenu,
                  child: AnimatedOpacity(
                    opacity: showSettingsMenu ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: GestureDetector(
                      onTap: () => setState(() => showSettingsMenu = false),
                      child: Container(
                        color: Colors.transparent,
                      ), // Catches taps outside the menu
                    ),
                  ),
                ),
              ),
              // The settingsMenu variable is already a Positioned widget
              settingsMenu,
            ],
          ),
        ),
      ),
    );
  }

  int _levelOrderIndex(String level) {
    final order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'SALES', 'CUSTOM'];
    final idx = order.indexOf(level.toUpperCase());
    return idx == -1 ? 1000 : idx;
  }

  // --- ADD THESE METHODS ---

  Future<void> _removeWordFromCustomList(WordEntry word) async {
    if (selectedLevel != 'custom') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Can only remove words from custom lists.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Remove the word from the in-memory lists
    setState(() {
      _customEntries.removeWhere((entry) =>
          entry.sublist == selectedSublist &&
          entry.wordMain.trim().toLowerCase() ==
              word.wordMain.trim().toLowerCase());

      allWords.removeWhere((entry) =>
          entry.level == 'custom' &&
          entry.sublist == selectedSublist &&
          entry.wordMain.trim().toLowerCase() ==
              word.wordMain.trim().toLowerCase());
      _updateCustomWordsSet();
      _invalidateGroupedLists();

      filterCurrentSet();
    });

    // Save the updated custom lists in the background
    _saveCustomListEntries(_customEntries);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t('removed_from_custom').replaceAll('{word}', word.wordMain),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _removeWordFromAnyCustomList(WordEntry word) async {
    final cleanWord = word.wordMain.trim().toLowerCase();
    setState(() {
      _customEntries.removeWhere((entry) =>
          entry.wordMain.trim().toLowerCase() == cleanWord);
      allWords.removeWhere((entry) =>
          entry.level == 'custom' &&
          entry.wordMain.trim().toLowerCase() == cleanWord);
      _updateCustomWordsSet();
      _invalidateGroupedLists();
      if (selectedLevel == 'custom') {
        filterCurrentSet();
      }
    });

    await _saveCustomListEntries(_customEntries);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t('removed_from_custom').replaceAll('{word}', word.wordMain),
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(milliseconds: 600),
      ),
    );
  }

  Future<void> _toggleCustomSetWord(WordEntry word) async {
    if (_isWordInCustomList(word)) {
      await _removeWordFromAnyCustomList(word);
    } else {
      await _addWordToCustomSet(word);
    }
  }

  Future<void> _addWordToCustomSet(WordEntry word) async {
    if (targetCustomSet.isEmpty) {
      if (allCustomListNames.isNotEmpty) {
        targetCustomSet = allCustomListNames.first;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('targetCustomSet', targetCustomSet);
      } else {
        if (!mounted) return;
        _showCustomListDialog(setAsTarget: true, wordToAddOnCreate: word);
        return;
      }
    }

    // Check if the word already exists in the target custom list (using cache)
    if (_customEntries.any((entry) =>
        entry.sublist == targetCustomSet &&
        entry.wordMain.trim().toLowerCase() ==
            word.wordMain.trim().toLowerCase())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('already_in_list').replaceAll('{word}', word.wordMain),
          ),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(milliseconds: 500),
        ),
      );
      return;
    }

    final newEntry = WordEntry(
      'custom',
      targetCustomSet,
      word.wordMain,
      word.trans1,
      word.example1,
      word.example2,
      word.example3,
      word.example4,
      word.wordSyn,
      word.trans2,
    );

    // Update in-memory cache and allWords list
    _customEntries.add(newEntry);
    _updateCustomWordsSet();

    // Save to persistent storage in background
    _saveCustomListEntries(_customEntries);

    setState(() {
      allWords.add(newEntry);
      _invalidateGroupedLists();
      // If the user is currently viewing the list they just saved to, refresh it.
      if (selectedLevel == 'custom' && selectedSublist == targetCustomSet) {
        filterCurrentSet();
      }
    });

    if (!mounted) return;
    final savedMsg = _t('saved_to_custom').replaceAll('{word}', word.wordMain);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(savedMsg),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _saveCustomListEntries(List<WordEntry> allCustomEntries) async {
    final List<Map<String, String>> jsonList = allCustomEntries
        .map((entry) => {
              'level': entry.level,
              'sublist': entry.sublist,
              'wordMain': entry.wordMain,
              'trans1': entry.trans1,
              'wordSyn': entry.wordSyn,
              'trans2': entry.trans2,
              'example1': entry.example1,
              'example2': entry.example2,
            })
        .toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_lists', jsonEncode(jsonList));
  }

  Widget _settingsLanguageRow({
    required String studyCode,
    required String nativeCode,
    required ValueChanged<String> onStudyChanged,
    required ValueChanged<String> onNativeChanged,
    required bool darkTheme,
  }) {
    final options = LanguageCatalog.available;

    AppLanguage byCode(String code) => options.firstWhere(
          (language) => language.code == code,
          orElse: () => options.first,
        );

    final titleStyle = TextStyle(
      color: darkTheme ? Colors.white70 : Colors.black54,
      fontSize: 14,
      fontWeight: FontWeight.w800,
    );

    final studyBg = const Color(0xFFB3E5FC);
    final nativeBg = const Color(0xFFB2FFB2);
    final borderColor = darkTheme
        ? Colors.white24
        : const Color(0xFF1A237E).withValues(alpha: 0.25);
    final textColor = Colors.black;

    Future<void> showPicker({
      required String title,
      required bool isStudy,
      required String currentCode,
      required String disabledCode,
      required ValueChanged<String> onPick,
    }) async {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: darkTheme ? const Color(0xFF1E2A3A) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          final maxHeight = MediaQuery.of(ctx).size.height * 0.75;
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: (darkTheme ? Colors.white : Colors.black)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: darkTheme ? Colors.white : const Color(0xFF1A237E),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: maxHeight,
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.9,
                    ),
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final o = options[index];
                      final bool selected = o.code == currentCode;
                      final bool disabled = o.code == disabledCode;
                      final Color activeColor = isStudy
                          ? const Color(0xFFB3E5FC)
                          : const Color(0xFFB2FFB2);
                      final Color baseColor =
                          darkTheme ? const Color(0xFF263240) : Colors.white;
                      final Color borderColor = darkTheme
                          ? Colors.white24
                          : const Color(0xFF1A237E).withValues(alpha: 0.12);
                      return GestureDetector(
                        onTap: disabled
                            ? null
                            : () {
                                _playTapClick();
                                Navigator.of(ctx).pop();
                                onPick(o.code);
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? activeColor : baseColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              Text(o.flag,
                                  style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      o.label,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.black
                                            : (darkTheme
                                                ? Colors.white
                                                : Colors.black87),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      o.nativeLabel,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.black54
                                            : (darkTheme
                                                ? Colors.white60
                                                : Colors.black54),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.check,
                                  size: 18,
                                  color: selected ? Colors.black : Colors.white,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      );
    }

    Widget pickerColumn({
      required String title,
      required bool isStudy,
      required String code,
      required String disabledCode,
      required ValueChanged<String> onPick,
    }) {
      final o = byCode(code);
      final bg = isStudy ? studyBg : nativeBg;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: titleStyle),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                _playTapClick();
                showPicker(
                  title: title,
                  isStudy: isStudy,
                  currentCode: code,
                  disabledCode: disabledCode,
                  onPick: onPick,
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(o.flag, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              o.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: darkTheme ? Colors.white70 : Colors.black54,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pickerColumn(
          title: _t('study'),
          isStudy: true,
          code: studyCode,
          disabledCode: nativeCode,
          onPick: onStudyChanged,
        ),
        const SizedBox(width: 12),
        pickerColumn(
          title: _t('native'),
          isStudy: false,
          code: nativeCode,
          disabledCode: studyCode,
          onPick: onNativeChanged,
        ),
      ],
    );
  }

  Widget _settingsRow({
    required Widget icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool darkTheme,
    bool isButton = false, // <-- Add this
    Color? labelColor,
    Color? chevronColor,
  }) {
    return InkWell(
      // <-- Wrap with InkWell
      onTap: () => onChanged(!value),
      child: Padding(
        // <-- Add Padding
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor ??
                      (darkTheme ? Colors.white : const Color(0xFF1E1E1E)),
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  fontSize: 21, // -25% from 28
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // --- CHANGE THIS ---
            if (isButton)
              Icon(Icons.chevron_right,
                  color: chevronColor ??
                      (darkTheme ? Colors.white70 : Colors.black54))
            else
              GestureDetector(
                onTap: () => onChanged(!value),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: value ? const Color(0xFF1A237E) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF1A237E),
                      width: 2,
                    ),
                  ),
                  child: value
                      ? const Center(
                          child:
                              Icon(Icons.check, color: Colors.white, size: 22),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const String _privacyPolicyUrl =
      'https://volary.mrcs-global.com/privacy.html';
  static const String _termsUrl = 'https://volary.mrcs-global.com/terms.html';

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('could_not_open')}: $url')),
      );
    }
  }

  // --- ADD THIS NEW WIDGET METHOD ---
  Widget _buildSaveToSection(bool darkTheme, StateSetter setMenuState) {
    final customLists = getGroupedLists()['custom'] ?? [];
    String currentTargetDisplayName = targetCustomSet.isNotEmpty
        ? targetCustomSet.replaceFirst('list_custom_', '').replaceAll('_', ' ')
        : _t('none');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The main "save to custom list" row
        InkWell(
          onTap: () {
            // --- USE THE NEW STATESETTER ---
            setMenuState(() {
              showSaveToSubMenu = !showSaveToSubMenu;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                // --- RESTORE SVG ICON ---
                SvgPicture.asset(
                  'assets/icons/savetolist.svg',
                  width: 32,
                  height: 32,
                  colorFilter: ColorFilter.mode(
                    darkTheme ? Colors.white : Colors.black,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('save_to_custom_list'),
                        style: TextStyle(
                          color: darkTheme
                              ? Colors.white
                              : const Color(0xFF1E1E1E),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          fontSize: 21, // -25% from 28
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        currentTargetDisplayName,
                        style: TextStyle(
                          color: darkTheme ? Colors.white70 : Colors.black54,
                          fontSize: 20, // Increased from 14
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  showSaveToSubMenu ? Icons.expand_less : Icons.expand_more,
                  color: darkTheme ? Colors.white70 : Colors.black54,
                ),
              ],
            ),
          ),
        ),
        // The expandable submenu
        if (showSaveToSubMenu)
          Container(
            padding: const EdgeInsets.only(left: 50, top: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...customLists.map((listName) {
                  final displayName = listName
                      .replaceFirst('list_custom_', '')
                      .replaceAll('_', ' ');
                  final isSelected = listName == targetCustomSet;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      displayName,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 22, // Added 22
                        color: isSelected
                            ? (darkTheme
                                ? Colors.lightBlueAccent
                                : Colors.blue.shade800)
                            : (darkTheme ? Colors.white : Colors.black),
                      ),
                    ),
                    onTap: () {
                      _setTargetCustomSet(listName);
                      // --- USE THE NEW STATESETTER ---
                      setMenuState(() {
                        showSaveToSubMenu = false;
                      });
                    },
                  );
                }),
                const Divider(),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add, color: Colors.green),
                  title: Text(
                    _t('create'),
                    style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 22), // Added 22
                  ),
                  onTap: () {
                    // --- USE THE NEW STATESETTER ---
                    setMenuState(() {
                      showSaveToSubMenu = false;
                    });
                    _showCustomListDialog(setAsTarget: true);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showCustomListDialog(
      {bool setAsTarget = false, WordEntry? wordToAddOnCreate}) {
    final TextEditingController listNameController = TextEditingController();
    final bool isDark = darkTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2A3A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t('create_custom_list'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF102A43),
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: listNameController,
                autofocus: true,
                cursorColor:
                    isDark ? const Color(0xFF2AB7A9) : const Color(0xFF1F6F78),
                style: TextStyle(
                  fontSize: 18,
                  color: isDark ? Colors.white : const Color(0xFF102A43),
                ),
                decoration: InputDecoration(
                  labelText: _t('list_name'),
                  labelStyle: TextStyle(
                    color: isDark
                        ? const Color(0xFF2AB7A9)
                        : const Color(0xFF1F6F78),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  hintText: _t('my_custom_list'),
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                  helperText: _t('custom_list_tip'),
                  helperMaxLines: 3,
                  helperStyle: TextStyle(
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.3,
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF2AB7A9)
                          : const Color(0xFF1F6F78),
                      width: 2,
                    ),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor:
                  isDark ? Colors.white70 : const Color(0xFF64748B),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: Text(_t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDark ? const Color(0xFF2AB7A9) : const Color(0xFF1F6F78),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              final text = listNameController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(context);
                _createCustomList(
                  text,
                  '',
                  setAsTarget: setAsTarget,
                  wordToAddOnCreate: wordToAddOnCreate,
                );
              }
            },
            child: Text(_t('create')),
          ),
        ],
      ),
    );
  }

  Future<void> _createCustomList(String listName, String wordsText,
      {bool setAsTarget = false, WordEntry? wordToAddOnCreate}) async {
    // Format list name
    String formattedListName =
        'list_custom_${listName.replaceAll(' ', '_').toLowerCase()}';

    // Save the list name
    final prefs = await SharedPreferences.getInstance();
    final customListNames = prefs.getStringList('custom_list_names') ?? [];
    if (!customListNames.contains(formattedListName)) {
      customListNames.add(formattedListName);
      await prefs.setStringList('custom_list_names', customListNames);
    }

    // Process the input text to get individual words
    List<String> words = wordsText
        .split(RegExp(r'[,\r\s]+'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      if (!mounted) return;
      setState(() {
        if (!allCustomListNames.contains(formattedListName)) {
          allCustomListNames.add(formattedListName);
          _invalidateGroupedLists();
        }
      });
      if (setAsTarget) {
        await _setTargetCustomSet(formattedListName);
      }
      if (wordToAddOnCreate != null) {
        await _addWordToCustomSet(wordToAddOnCreate);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('create_custom_list')}: $listName'),
            backgroundColor: const Color(0xFF1F6F78),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Show loading indicator with progress
    int processed = 0;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('${_t('processing_words')}: $processed/${words.length}'),
              Text(_t('finding_translations')),
            ],
          ),
        ),
      ),
    );

    try {
      List<WordEntry> newEntries = [];

      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        final translation = await translateWord(
          word: word,
          fromLang: studyLang,
          toLang: nativeLang,
        );
        final example = 'They archived the $word for future use.';

        newEntries.add(WordEntry(
          'custom',
          formattedListName,
          word.trim(),
          translation,
          example,
          '',
        ));

        // Update progress
        processed = i + 1;
      }

      // Update in-memory cache
      _customEntries.addAll(newEntries);
      allWords.addAll(newEntries);
      _invalidateGroupedLists();

      // Save to persistent storage in background
      _saveCustomListEntries(_customEntries);

      if (!mounted) return;
      Navigator.pop(context);

      // Show success message with statistics
      int translatedCount = newEntries
          .where(
              (e) => e.trans1 != _translationNeeded && e.trans1 != e.wordMain)
          .length;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Custom list created: $listName\n$translatedCount/${words.length} words translated'),
          duration: Duration(seconds: 4),
        ),
      );

      // Reload words to include new custom list
      // No longer need to fully reload words, we updated cache
      // await loadWords();

      if (!mounted) return;
      // Refresh UI to show the new list without switching to it.
      setState(() {
        if (!allCustomListNames.contains(formattedListName)) {
          allCustomListNames.add(formattedListName);
          _invalidateGroupedLists();
        }
      });
      if (setAsTarget) {
        _setTargetCustomSet(formattedListName);
      }
    } catch (e) {
      if (mounted) {
        // Close the loading dialog
        Navigator.pop(context);

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('error_creating_list')}: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<WordEntry>> _loadCustomLists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = prefs.getString('custom_lists');
    if (jsonData == null || jsonData.isEmpty) return [];

    try {
      // --- FIX THE TYPO ON THIS LINE ---
      final List<dynamic> jsonList = jsonDecode(jsonData);
      return jsonList
          .map<WordEntry>((json) => WordEntry(
                (json['level'] ?? '').toString(),
                (json['sublist'] ?? '').toString(),
                (json['wordMain'] ?? json['en'] ?? '').toString(),
                (json['trans1'] ?? json['uk'] ?? '').toString(),
                (json['example1'] ?? '').toString(),
                (json['example2'] ?? '').toString(),
                '', '', // example3, 4
                (json['wordSyn'] ?? '').toString(),
                (json['trans2'] ?? '').toString(),
              ))
          .toList();
    } catch (e) {
      debugPrint('Error loading custom lists: $e');
      return [];
    }
  }

  Future<void> _showDeleteCustomListDialog(String listName) async {
    final isDark = darkTheme;
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E2A3A) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            _t('delete_list'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF102A43),
            ),
          ),
          content: Text(
            _t('delete_confirm').replaceAll('{list}', listName),
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF4B5563),
              fontSize: 15,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: <Widget>[
            TextButton(
              child: Text(
                _t('cancel'),
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: Text(_t('delete')),
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteCustomList(listName);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCustomList(String listName) async {
    // 1. Remove from names list in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final customListNames = prefs.getStringList('custom_list_names') ?? [];
    customListNames.remove(listName);
    await prefs.setStringList('custom_list_names', customListNames);
    allCustomListNames = customListNames;

    // 2. Filter the cached words
    _customEntries =
        _customEntries.where((entry) => entry.sublist != listName).toList();
    _updateCustomWordsSet();
    allWords.removeWhere(
        (entry) => entry.level == 'custom' && entry.sublist == listName);
    _invalidateGroupedLists();

    // 3. Save updated words list in background
    _saveCustomListEntries(_customEntries);

    // 4. Update UI: Select another list if the current one was deleted
    if (selectedLevel == 'custom' && selectedSublist == listName) {
      final grouped = getGroupedLists();
      final levels = grouped.keys.toList()
        ..sort((a, b) => _levelOrderIndex(a).compareTo(_levelOrderIndex(b)));
      String nextLevel = levels.isNotEmpty ? levels.first : '';
      String nextSub = '';
      if (nextLevel.isNotEmpty) {
        final subs = List<String>.from(grouped[nextLevel] ?? [])
          ..sort(_compareSublists);
        if (subs.isNotEmpty) nextSub = subs.first;
      }
      setState(() {
        selectedLevel = nextLevel;
        selectedSublist = nextSub;
        filterCurrentSet();
      });
    } else {
      setState(() {
        filterCurrentSet();
      });
    }
  }

  Future<void> loadDictionary() async {
    await _dictionaryReady;
  }

// Enhanced translation function with better fallback
  static const String _translationNeeded = '[ Translation needed ]';

  Future<String> translateWord({
    required String word,
    required String fromLang,
    required String toLang,
  }) async {
    final from = fromLang.trim().toLowerCase();
    final to = toLang.trim().toLowerCase();
    final cleaned = word.trim();

    if (cleaned.isEmpty) return '';
    if (from == to) return cleaned;

    if (from == 'en' && to == 'uk') {
      await _dictionaryReady;
      final local = enUkDictionary[cleaned.toLowerCase()];
      if (local != null && local.isNotEmpty) return local;
    }

    return _translationNeeded;
  }

  Future<String> translateToUkrainian(String englishWord) async {
    return translateWord(word: englishWord, fromLang: 'en', toLang: 'uk');
  }

// Placeholder example generator for custom lists.
  Future<String> getExampleSentence(String word) async {
    return 'They archived the $word for future use.';
  }

// Helpers to sort "listN" numerically
  int? _extractListNumber(String s) {
    final trimmed = s.trim();
    final combined =
        RegExp(r'^[A-Za-z]+\d*\s*L\s*0*(\d+)$', caseSensitive: false)
            .firstMatch(trimmed);
    if (combined != null) return int.tryParse(combined.group(1)!);

    final lOnly =
        RegExp(r'^L\s*0*(\d+)$', caseSensitive: false).firstMatch(trimmed);
    if (lOnly != null) return int.tryParse(lOnly.group(1)!);

    final listN = RegExp(r'^list[_\s]*0*(\d+)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (listN != null) return int.tryParse(listN.group(1)!);

    return null;
  }

  int _compareSublists(String a, String b) {
    final na = _extractListNumber(a);
    final nb = _extractListNumber(b);
    if (na != null && nb != null) return na.compareTo(nb);
    if (na != null) return -1; // numbers first
    if (nb != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  Map<String, List<String>> getGroupedLists() {
    final cached = _groupedListsCache;
    if (cached != null) return cached;

    final Map<String, List<String>> grouped = {};
    for (var w in allWords) {
      grouped.putIfAbsent(w.level, () => []);
      if (!grouped[w.level]!.contains(w.sublist)) {
        grouped[w.level]!.add(w.sublist);
      }
    }

    // --- THIS BLOCK IS UNCHANGED, BUT CONTEXT IS IMPORTANT ---
    // It ensures that even if a custom list has words, it's sorted correctly.
    for (var lists in grouped.values) {
      lists.sort(_compareSublists);
    }

    // --- ADD THIS LOGIC TO MERGE IN EMPTY LISTS ---
    // This ensures that custom lists created without any words still appear in the UI.
    final customListNames =
        allCustomListNames; // Assuming allCustomListNames is loaded elsewhere
    if (customListNames.isNotEmpty) {
      grouped.putIfAbsent('custom', () => []);
      for (final listName in customListNames) {
        if (!grouped['custom']!.contains(listName)) {
          grouped['custom']!.add(listName);
        }
      }
      // Re-sort the custom list to maintain order
      grouped['custom']!.sort(_compareSublists);
    }

    _groupedListsCache = Map.unmodifiable(
      grouped.map(
        (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
      ),
    );
    return _groupedListsCache!;
  }
}

class _WordsMenuButton extends StatelessWidget {
  final Map<String, List<String>> groupedLists;
  final String currentLevel;
  final String currentSublist;
  final String setLabel;
  final String selectListLabel;
  final bool dark;
  final VoidCallback onOpen;
  final void Function(String level, String sublist) onSelect;

  const _WordsMenuButton({
    required this.groupedLists,
    required this.currentLevel,
    required this.currentSublist,
    required this.setLabel,
    required this.selectListLabel,
    required this.dark,
    required this.onOpen,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    String buttonLabel = selectListLabel;
    if (currentLevel.isNotEmpty && currentSublist.isNotEmpty) {
      if (currentLevel == 'custom') {
        buttonLabel = currentSublist
            .replaceFirst('list_custom_', '')
            .replaceAll('_', ' ');
        // Capitalize
        buttonLabel = buttonLabel
            .split(' ')
            .map((s) =>
                s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
            .join(' ');
      } else {
        // e.g. "A1L1"
        final match = RegExp(r'L(\d+)$').firstMatch(currentSublist);
        if (match != null) {
          buttonLabel = '${currentLevel}L${match.group(1)}';
        } else {
          buttonLabel = '$currentLevel $currentSublist';
        }
      }
    }

    return GestureDetector(
      onTap: onOpen,
      child: _LiquidGlassSurface(
        tint: const Color(0xFF1F6F78),
        dark: dark,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    setLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    buttonLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordsMenuPanel extends StatefulWidget {
  final Map<String, List<String>> groupedLists;
  final String activeLevel; // which level's sublists to show
  final String currentLevel; // currently selected level
  final String currentSublist; // currently selected sublist
  final String levelLabel;
  final String listLabel;
  final ValueChanged<String> onChangeLevel;
  final void Function(String level, String sublist) onSelect;

  const _WordsMenuPanel({
    required this.groupedLists,
    required this.activeLevel,
    required this.currentLevel,
    required this.currentSublist,
    required this.levelLabel,
    required this.listLabel,
    required this.onChangeLevel,
    required this.onSelect,
  });

  @override
  State<_WordsMenuPanel> createState() => _WordsMenuPanelState();
}

class _WordsMenuPanelState extends State<_WordsMenuPanel> {
  late String activeLevel;

  @override
  void initState() {
    super.initState();
    activeLevel = widget.activeLevel;
  }

  int _levelOrderIndex(String level) {
    final order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'SALES', 'CUSTOM'];
    final idx = order.indexOf(level.toUpperCase());
    return idx == -1 ? 1000 : idx;
  }

  int? _extractListNumber(String s) {
    final trimmed = s.trim();
    final combined =
        RegExp(r'^[A-Za-z]+\d*\s*L\s*0*(\d+)$', caseSensitive: false)
            .firstMatch(trimmed);
    if (combined != null) return int.tryParse(combined.group(1)!);

    final lOnly =
        RegExp(r'^L\s*0*(\d+)$', caseSensitive: false).firstMatch(trimmed);
    if (lOnly != null) return int.tryParse(lOnly.group(1)!);

    final listN = RegExp(r'^list[_\s]*0*(\d+)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (listN != null) return int.tryParse(listN.group(1)!);

    return null;
  }

  int _compareSublists(String a, String b) {
    final na = _extractListNumber(a);
    final nb = _extractListNumber(b);
    if (na != null && nb != null) return na.compareTo(nb);
    if (na != null) return -1;
    if (nb != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  String _fmtSub(String s) {
    final combinedMatch =
        RegExp(r'^([A-Za-z]+\d*)L(\d+)$', caseSensitive: false)
            .firstMatch(s.trim());
    if (combinedMatch != null) {
      return 'L${combinedMatch.group(2)}';
    }
    final n = _extractListNumber(s);
    if (n != null) return 'L$n';

    // Handle custom lists like 'list_custom_my_favorites' -> 'My Favorites'
    if (s.startsWith('list_custom_')) {
      return s
          .substring(12)
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '')
          .join(' ');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final levels = widget.groupedLists.keys.toList()
      ..sort((a, b) {
        final ia = _levelOrderIndex(a);
        final ib = _levelOrderIndex(b);
        return ia != ib ? ia.compareTo(ib) : a.compareTo(b);
      });

    final sublists = List<String>.from(widget.groupedLists[activeLevel] ?? [])
      ..sort(_compareSublists);

    final itemCount = math.max(levels.length, sublists.length);
    const headerHeight = 56.0;
    const tileHeight = 36.0;
    const minPanelHeight = 200.0;
    const maxPanelHeight = 520.0;
    final panelHeight = (headerHeight + itemCount * tileHeight)
        .clamp(minPanelHeight, maxPanelHeight);

    final double screenWidth = MediaQuery.of(context).size.width;
    final double widthMinusMargin = screenWidth - 32;
    final double panelWidth =
        math.min(420.0, widthMinusMargin > 0 ? widthMinusMargin : screenWidth);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        height: panelHeight,
        decoration: BoxDecoration(
          color: const Color(0xFFF4EFFA),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // Levels column
            Flexible(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 10.0),
                    child: Text(
                      widget.levelLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: levels.length,
                      itemBuilder: (_, i) {
                        final lvl = levels[i];
                        final selected = lvl == activeLevel;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          visualDensity:
                              const VisualDensity(horizontal: 0, vertical: -4),
                          minVerticalPadding: 0,
                          horizontalTitleGap: 8,
                          minLeadingWidth: 14,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 0),
                          leading: selected
                              ? const Icon(Icons.arrow_right,
                                  color: Colors.blue)
                              : null,
                          title: Text(
                            lvl,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w800,
                              color: selected ? Colors.blue : Colors.black87,
                            ),
                          ),
                          onTap: () {
                            setState(() => activeLevel = lvl);
                            widget.onChangeLevel(lvl);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 1,
              child: const VerticalDivider(width: 1),
            ),
            // Sublists column (only of active level)
            Flexible(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 10.0),
                    child: Text(
                      widget.listLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: sublists.length,
                      itemBuilder: (_, i) {
                        final sub = sublists[i];
                        final selected = activeLevel == widget.currentLevel &&
                            sub == widget.currentSublist;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          visualDensity:
                              const VisualDensity(horizontal: 0, vertical: -4),
                          minVerticalPadding: 0,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 0),
                          title: Text(
                            _fmtSub(sub),
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w800,
                              color: selected
                                  ? Colors.blueGrey.shade900
                                  : Colors.black87,
                            ),
                          ),
                          // --- ADD THIS DELETE BUTTON FOR CUSTOM LISTS ---
                          trailing: activeLevel == 'custom'
                              ? IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      color: Colors.red.shade300, size: 20),
                                  onPressed: () {
                                    // Find the state and call the delete method
                                    final screenState =
                                        context.findAncestorStateOfType<
                                            _FlashcardScreenState>();
                                    screenState
                                        ?._showDeleteCustomListDialog(sub);
                                  },
                                )
                              : (selected
                                  ? const Icon(Icons.check,
                                      color: Colors.blueGrey)
                                  : null),
                          onTap: () => widget.onSelect(activeLevel, sub),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- LANGUAGE SELECTION SCREEN ---
