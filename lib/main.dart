import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// import 'home_page.dart'; // <-- import your splash page
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart'
    show
        rootBundle,
        SystemUiOverlayStyle,
        FilteringTextInputFormatter,
        SystemNavigator,
        SystemSound,
        SystemSoundType,
        HapticFeedback;
import 'dart:ui' show ImageFilter;
import 'package:csv/csv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const WordsApp());
}

class WordsApp extends StatefulWidget {
  const WordsApp({super.key});

  @override
  State<WordsApp> createState() => _WordsAppState();
}

class _WordsAppState extends State<WordsApp> {
  bool? hasLanguage;
  bool showENasDefault = true;

  @override
  void initState() {
    super.initState();
    _checkLanguage();
  }

  Future<void> _checkLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final native = prefs.getString('native_language');
    final study = prefs.getString('study_language');
    setState(() {
      hasLanguage = (native != null && study != null);
    });
  }

  void toggleDefaultView() {
    setState(() {
      showENasDefault = !showENasDefault;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show empty container while checking prefs
    if (hasLanguage == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
        debugShowCheckedModeBanner: false,
      );
    }

    return MaterialApp(
      title: 'Volary - Vocabulary Trainer',
      debugShowCheckedModeBanner: false,
      // If language is set -> HomeSplashPage (which goes to Flashcards)
      // If not set -> LanguageSelectionScreen
      home: hasLanguage! ? const HomeSplashPage() : const LanguageSelectionScreen(),
      routes: {
        '/flashcards': (context) => FlashcardScreen(
              showENasDefault: showENasDefault,
              onToggleDefault: toggleDefaultView,
            ),
      },
      // Remove initialRoute as 'home' handles it
    );
  }
}

class WordEntry {
  final String level;
  final String sublist;
  final String wordMain; // The word being learned
  final String wordSyn;  // Synonym or alternative for the word
  final String trans1;   // Primary translation
  final String trans2;   // Secondary translation
  
  // Keep legacy examples for internal data mapping if needed, but we focus on synonyms
  final String example1;
  final String example2;
  final String example3;
  final String example4;

  WordEntry(this.level, this.sublist, this.wordMain, this.trans1, 
      [this.example1 = '', this.example2 = '', this.example3 = '', 
       this.example4 = '', this.wordSyn = '', this.trans2 = '']);
}

SystemUiOverlayStyle _overlayStyleForTop({required bool darkTop}) {
  return SystemUiOverlayStyle(
    statusBarIconBrightness: darkTop ? Brightness.light : Brightness.dark,
    statusBarBrightness: darkTop ? Brightness.dark : Brightness.light,
  );
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
  bool showENFace = true;
  bool gridMode = false;
  int gridPage = 0;
  List<bool> gridCardENFace = List.filled(_cardsPerGridPage, true);
  List<WordEntry> allWords = [];
  List<WordEntry> currentSetWords = [];
  int currentIndex = 0;
  String selectedLevel = '';
  String selectedSublist = '';
  String studyLang = 'en';  // Language being learned
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

  // Add this to track loading state
  bool isLoading = true;

  // Add this to your class variables
  Map<String, String> enUkDictionary = {};
  List<String> allCustomListNames = [];
  List<WordEntry> _customEntries = []; // Cache for starred and custom words
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    loadWords();
    _loadDictionary();
    _setupAudioSession();
    // Best-effort: some platforms may not support awaiting completion.
    flutterTts.awaitSpeakCompletion(true).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When disabled: stop any running TTS as soon as the app is backgrounded
    // (screen off/locked or app minimized).
    if (!allowBackgroundSpeaking &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      stopPlaying();
    }
  }

  @override
  void dispose() {
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
      'repeat_list': 'Repeat list',
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
      'removed_from_custom':
          'Se elimino "{word}" de la lista personalizada.',
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
      'removed_from_custom':
          'Removido "{word}" da lista personalizada.',
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
      'removed_from_custom':
          '"{word}" wurde aus der eigenen Liste entfernt.',
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
      'removed_from_custom':
          'Rimosso "{word}" dalla lista personalizzata.',
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
      'removed_from_custom':
          '"{word}" ozel listeden kaldirildi.',
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

  static const Map<String, String> _languageLabel = {
    'en': 'English',
    'es': 'Spanish',
    'pt': 'Portuguese',
    'uk': 'Ukrainian',
    'de': 'German',
    'fr': 'French',
    'it': 'Italian',
    'tr': 'Turkish',
  };

  // --- ADD THIS NEW METHOD ---
  Future<void> _loadCustomListNames() async {
    final prefs = await SharedPreferences.getInstance();
    allCustomListNames = prefs.getStringList('custom_list_names') ?? [];
  }

  Future<void> _setTargetCustomSet(String listName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('targetCustomSet', listName);
    setState(() {
      targetCustomSet = listName;
    });
  }

  void _cancelSleepTimer() {
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
      if (!mounted) return;
      stopPlaying();
      setState(() {
        _cancelSleepTimer();
      });
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        SystemNavigator.pop();
      }
    });
  }

  Future<void> loadWords() async {
    setState(() {
      isLoading = true;
    });

    // --- FIX: Ensure custom names are loaded ---
    await _loadCustomListNames();

    final prefs = await SharedPreferences.getInstance();
    const allowedLangs = {
      'en',
      'es',
      'pt',
      'uk',
      'de',
      'fr',
      'it',
      'tr',
    };
    String prefStudy = prefs.getString('study_language') ?? 'en';
    String prefNative = prefs.getString('native_language') ?? 'uk';
    if (!allowedLangs.contains(prefStudy)) prefStudy = 'en';
    if (!allowedLangs.contains(prefNative)) prefNative = 'uk';

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
        final String studyPath = 'assets/sets/$sLang.csv';
        final String nativePath = 'assets/sets/$nLang.csv';
        final ByteData studyBytes = await rootBundle.load(studyPath);
        final ByteData nativeBytes = await rootBundle.load(nativePath);

        final String studyData =
            utf8.decode(studyBytes.buffer.asUint8List(), allowMalformed: true);
        final String nativeData =
            utf8.decode(nativeBytes.buffer.asUint8List(), allowMalformed: true);

        final studyTable = parseCsv(studyData);
        final nativeTable = parseCsv(nativeData);
        final int rowsToProcess = math.min(studyTable.length, nativeTable.length);

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
            if (wordMain.isEmpty || trans1.isEmpty) continue;

            loadedWords.add(WordEntry(
              level,
              sublist,
              wordMain,
              trans1,
              '', '', '', '',
              sRow.length > 3 ? sRow[3].toString().trim() : '',
              nRow.length > 3 ? nRow[3].toString().trim() : '',
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

    // Merge predefined and custom lists
    allWords.addAll(_customEntries);

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

    setState(() {
      selectedLevel = initLevel;
      selectedSublist = initSub;
      filterCurrentSet();
      isLoading = false;
    });

    debugPrint('Loaded ${allWords.length} words');
    debugPrint('Levels: $levels');
    debugPrint('Current: $selectedLevel / $selectedSublist');
    debugPrint('Words in current list: ${currentSetWords.length}');
  }

  void filterCurrentSet() {
    currentSetWords = allWords
        .where((w) =>
            w.level.trim().toLowerCase() ==
                selectedLevel.trim().toLowerCase() &&
            w.sublist.trim().toLowerCase() ==
                selectedSublist.trim().toLowerCase())
        .toList();
    currentIndex = 0;
    gridPage = 0;
    gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
    setState(() {});
    debugPrint(
        'Filtering for "$selectedLevel / $selectedSublist", found ${currentSetWords.length} words');
  }

  void changeSet(String newSet) {
    setState(() {
      selectedSublist = newSet;
      filterCurrentSet();
    });
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

  void nextGridPage() {
    setState(() {
      final int maxPage =
          (currentSetWords.length / _cardsPerGridPage).ceil() - 1;
      if (maxPage <= 0) {
        gridPage = 0;
      } else if (gridPage >= maxPage) {
        gridPage = 0;
      } else {
        gridPage++;
      }
      gridCardENFace =
          List.filled(_cardsPerGridPage, showENFace); // <-- use current default
    });
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
      final subs = List<String>.from(grouped[lvl] ?? [])..sort(_compareSublists);
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

    Future<void> speakEntry(WordEntry entry,
        {required bool studyFirst}) async {
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
        if (lastIdx != null && len > 1 && order.isNotEmpty && order.first == lastIdx) {
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
        if (!isPlaying) break;
        await Future.delayed(const Duration(milliseconds: 700));
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
        if (!isPlaying) break;
        await Future.delayed(const Duration(seconds: 1));
        i++;
      }
    }

    setState(() {
      isPlaying = false;
    });
    if (!_pausedByInterruption) {
      unawaited(_deactivateAudioSession());
    }
  }

  // Optionally, add a stop function
  void stopPlaying({bool updateUi = true, bool dueToInterruption = false}) {
    isPlaying = false;
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
      // Load from the main CSV file instead of a separate dictionary
      final rawData =
          await rootBundle.loadString('assets/sets/combined_words.csv');
      final csvTable = const CsvToListConverter().convert(rawData, eol: '\n');

      // Create a map for fast lookups from the existing CSV data
      for (var row in csvTable.skip(1)) {
        if (row.length >= 4) {
          String englishWord = row[2].toString().toLowerCase().trim();
          String ukrainianWord = row[3].toString().trim();
          if (englishWord.isNotEmpty && ukrainianWord.isNotEmpty) {
            enUkDictionary[englishWord] = ukrainianWord;
          }
        }
      }
      debugPrint(
          'Dictionary loaded with ${enUkDictionary.length} entries from main CSV');
    } catch (e) {
      debugPrint('Error loading dictionary from CSV: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator if still loading
    if (isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlayStyleForTop(darkTop: darkTheme),
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

    // Smaller cards for 10-word grid
    // Larger cards for single view
    final desiredCardWidth = math.max(safeWidth * 0.65, 170.0);
    final cardWidth = math.min(desiredCardWidth, safeWidth);
    final cardHeight = math.max(140.0, cardWidth * 0.52); // Increased height (+30%)
    final double singleCardSectionHeight = cardHeight + 48.0;
    final bool isWideGrid = safeWidth >= 420.0;
    final double bottomSafePadding = mediaQuery.viewPadding.bottom;
    const double bottomBarHeight = 72.0;
    final double gridCardMinHeight = isWideGrid ? 118.0 : 92.0;
    final double sliderHorizontalPadding = math.max(16.0, screenWidth * 0.06);
    final double settingsWidth = math.min(safeWidth, 420.0);
    // Raise the slider overlay (~30% up from the bottom, but never below the bar)
    final enWord =
        currentSetWords.isNotEmpty ? currentSetWords[currentIndex].wordMain : '';
    final ukWord =
        currentSetWords.isNotEmpty ? currentSetWords[currentIndex].trans1 : '';
    final example1 = currentSetWords.isNotEmpty
        ? currentSetWords[currentIndex].example1
        : '';
    final example2 = currentSetWords.isNotEmpty
        ? currentSetWords[currentIndex].example2
        : '';

    final entry = currentSetWords.isNotEmpty ? currentSetWords[currentIndex] : null;

    Widget centeredWordBlock({
      required String main,
      required TextStyle mainStyle,
      String? secondary,
      TextStyle? secondaryStyle,
      List<String>? examples,
      TextStyle? exampleStyle,
    }) {
      final cleanedSecondary = (secondary ?? '').trim();
      final cleanedExamples = (examples ?? []).where((e) => e.trim().isNotEmpty).toList();

      return Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.center,
            child: Text(main, style: mainStyle, textAlign: TextAlign.center),
          ),
          if (cleanedSecondary.isNotEmpty)
            Align(
              alignment: const Alignment(0, 0.55),
              child: Text(
                cleanedSecondary,
                style: secondaryStyle,
                textAlign: TextAlign.center,
              ),
            ),
          if (cleanedExamples.isNotEmpty)
            Align(
              alignment: const Alignment(0, 0.88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ex in cleanedExamples)
                    Text(ex, style: exampleStyle, textAlign: TextAlign.center),
                ],
              ),
            ),
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
                  setState(() {
                    if (currentSetWords.isNotEmpty) {
                      currentIndex =
                          (currentIndex + 1) % currentSetWords.length;
                    }
                    showENFace = widget.showENasDefault;
                  });
                } else if (details.primaryVelocity! > 0) {
                  setState(() {
                    if (currentSetWords.isNotEmpty) {
                      currentIndex =
                          (currentIndex - 1 + currentSetWords.length) %
                              currentSetWords.length;
                    }
                    showENFace = widget.showENasDefault;
                  });
                }
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Container(
                key: ValueKey(
                    '$currentIndex-$showENFace'), // <-- add currentIndex to key for animation
                width: cardWidth,
                height: cardHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: showENFace
                      ? const Color(0xFFB3E5FC)
                      : const Color(0xFFB2FFB2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 12,
                      left: 12,
                      child: GestureDetector(
                        onTap: () {
                          _playTapClick();
                          if (currentSetWords.isNotEmpty) {
                            // Check if we're in a custom list
                            if (selectedLevel == 'custom') {
                              _removeWordFromCustomList(
                                  currentSetWords[currentIndex]);
                            } else {
                              _addWordToCustomSet(
                                  currentSetWords[currentIndex]);
                            }
                          }
                        },
                        child: Container(
                          width: 35,
                          height: 38,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFE3F2FD).withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              selectedLevel == 'custom'
                                  ? Icons.delete_outline
                                  : Icons.star_border,
                              color: selectedLevel == 'custom'
                                  ? Colors.blueGrey.shade400
                                  : Colors.blueGrey.shade600,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40.0),
                        child: centeredWordBlock(
                          main: showENFace ? enWord : ukWord,
                          mainStyle: TextStyle(
                            color: showENFace ? Colors.black : const Color(0xFFB71C1C),
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: showENFace ? 34 : 27,
                            height: 1.1,
                          ),
                          secondary: showENFace
                              ? (entry != null && entry.wordSyn.isNotEmpty ? '(${entry.wordSyn})' : '')
                              : (entry != null && entry.trans2.isNotEmpty ? entry.trans2 : ''),
                          secondaryStyle: showENFace
                              ? TextStyle(
                                  color: Colors.blueGrey.shade600,
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                )
                              : const TextStyle(
                                  color: Color(0xFFB71C1C),
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
                        child: Container(
                          width: 35,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/Speaker.svg',
                              width: 20,
                              height: 20,
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
          const SizedBox(height: 18),
          // Always reserve space for examples, but only show for EN card
          SizedBox(
            height: 38,
            child: showENFace && (example1.isNotEmpty || example2.isNotEmpty)
                ? Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (example1.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8.0, horizontal: 12.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            example1,
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                              fontSize: 17, // +~20%
                            ),
                          ),
                        ),
                      if (example2.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8.0, horizontal: 12.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            example2,
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                              fontSize: 17, // +~20%
                            ),
                          ),
                        ),
                    ],
                  )
                : null,
          ),
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
        child: Container(
          constraints: BoxConstraints(minHeight: gridCardMinHeight),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isEN ? const Color(0xFFB3E5FC) : const Color(0xFFB2FFB2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTap: () {
                    _playTapClick();
                    // Check if we're in a custom list
                    if (selectedLevel == 'custom') {
                      _removeWordFromCustomList(entry);
                    } else {
                      _addWordToCustomSet(entry);
                    }
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD).withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        selectedLevel == 'custom'
                            ? Icons.delete_outline
                            : Icons.star_border,
                        color: selectedLevel == 'custom'
                            ? Colors.blueGrey.shade400
                            : Colors.blueGrey.shade600,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: centeredWordBlock(
                    main: isEN ? entry.wordMain : entry.trans1,
                    mainStyle: TextStyle(
                      color: isEN ? Colors.black : const Color(0xFFB71C1C),
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 22, // +~20%
                    ),
                    secondary: isEN
                        ? (entry.wordSyn.isNotEmpty ? '(${entry.wordSyn})' : '')
                        : (entry.trans2.isNotEmpty ? entry.trans2 : ''),
                    secondaryStyle: isEN
                        ? TextStyle(
                            color: Colors.blueGrey.shade700,
                            fontFamily: 'Inter',
                            fontStyle: FontStyle.italic,
                            fontSize: 14,
                          )
                        : const TextStyle(
                            color: Color(0xFFB71C1C),
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                    examples: isEN ? [entry.example1, entry.example2] : const [],
                    exampleStyle: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: 14, // +~20%
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    _playTapClick();
                    speakWord(entry.wordMain);
                  },
                  child: SvgPicture.asset(
                    'assets/icons/Speaker.svg',
                    width: 18,
                    height: 18,
                  ),
                ),
              ),
            ],
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
        final double maxWidth = constraints.maxWidth;
        final double horizontalPadding =
            math.max(12.0, math.min(32.0, maxWidth * 0.04));
        final double availableWidth =
            math.max(140.0, maxWidth - horizontalPadding * 2);
        final double spacing =
            math.max(10.0, math.min(20.0, availableWidth * 0.03));
        final int startIndex = gridPage * _cardsPerGridPage;
        final int totalRemaining =
            math.max(0, currentSetWords.length - startIndex);
        final int itemsOnPage = totalRemaining > _cardsPerGridPage
            ? _cardsPerGridPage
            : totalRemaining;
        final double viewportHeight = availableHeight;
        final double gridTopPadding = 0.0;
        final double gridBottomPadding = 0.0;
        final bool isLandscape = maxWidth >= viewportHeight;
        final bool isTabletLayout =
            math.min(maxWidth, viewportHeight) >= 600.0;
        final bool forceTabletGrid =
            isTabletLayout && itemsOnPage == _cardsPerGridPage;
        int computedColumns = (availableWidth / 150).floor();
        if (computedColumns < 2) {
          computedColumns = 2;
        } else if (computedColumns > 4) {
          computedColumns = 4;
        }
        final int crossAxisCount =
            forceTabletGrid ? (isLandscape ? 5 : 2) : computedColumns;
        final double usableWidth =
            availableWidth - spacing * (crossAxisCount - 1);
        final double cardWidth = usableWidth / crossAxisCount;
        final int rows = itemsOnPage == 0
            ? 1
            : forceTabletGrid
                ? (isLandscape ? 2 : 5)
                : ((itemsOnPage + crossAxisCount - 1) ~/ crossAxisCount);
        final double availableHeightForCards = math.max(
            160.0, viewportHeight - gridTopPadding - gridBottomPadding);
        final double fittedCardHeight =
            (availableHeightForCards - spacing * (rows - 1)) / rows;
        final double cardHeight = forceTabletGrid
            ? math.max(gridCardMinHeight, fittedCardHeight)
            : math.max(
                gridCardMinHeight, math.min(cardWidth * 0.78, fittedCardHeight));
        final double aspectRatio = cardWidth / cardHeight;
        final double gridContentHeight =
            rows * cardHeight + math.max(0, rows - 1) * spacing;
        final double extraVerticalPadding = math.max(
          0.0,
          (viewportHeight - gridContentHeight - gridTopPadding - gridBottomPadding) /
              2,
        );

        return GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null) {
              setState(() {
                if (details.primaryVelocity! < 0) {
                  nextGridPage();
                } else if (details.primaryVelocity! > 0) {
                  prevGridPage();
                }
                gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
              });
            }
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: GridView.builder(
              padding: EdgeInsets.only(
                bottom: gridBottomPadding + extraVerticalPadding,
                top: gridTopPadding + extraVerticalPadding,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itemsOnPage,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
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
            // --- WRAP THE CONTAINER WITH A STATEFULBUILDER ---
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setMenuState) {
            void togglePanel(String panel) {
              setState(() {
                activeSettingsPanel = activeSettingsPanel == panel ? '' : panel;
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
              required bool enabled,
              required VoidCallback onTap,
            }) {
              final Color base = darkTheme ? const Color(0xFF263240) : Colors.white;
              final Color active = const Color(0xFFD6ECFF);
              final Color border = darkTheme
                  ? Colors.white24
                  : const Color(0xFF1A237E).withValues(alpha: 0.18);
              final Color labelColor =
                  enabled ? Colors.black : (darkTheme ? Colors.white : Colors.black87);
              final Color subColor =
                  enabled ? Colors.black54 : (darkTheme ? Colors.white60 : Colors.black54);
              return GestureDetector(
                onTap: () {
                  _playTapClick();
                  onTap();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                              style: TextStyle(
                                color: labelColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            if (subLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  subLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: subColor,
                                    fontSize: 13,
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
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: darkTheme ? const Color(0xFF1F2B3B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: panelBorderColor(
                        sleepTimerEnd != null || activeSettingsPanel == 'sleep',
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('sleep_timer'),
                        style: TextStyle(
                          color: darkTheme ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sleepTimerEnd == null
                                  ? _t('off')
                                  : _remainingSleepMinutesLabel(),
                              style: TextStyle(
                                color: darkTheme ? Colors.white : Colors.black,
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
                                color:
                                    darkTheme ? Colors.white : Colors.black87,
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
                                contentPadding: const EdgeInsets.symmetric(
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_t('enter_minutes')),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _startSleepTimer(Duration(minutes: minutes));
                              });
                              setMenuState(() {});
                            },
                            icon: Icon(
                              Icons.play_arrow,
                              color: darkTheme ? Colors.white : Colors.black,
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
                              color: darkTheme ? Colors.white : Colors.black,
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
                                color: darkTheme ? Colors.white70 : Colors.black87,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: sleepTimerLoop,
                            onChanged: (value) async {
                              _playTapClick();
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('sleepTimerLoop', value);
                              if (!mounted) return;
                              setState(() => sleepTimerLoop = value);
                              setMenuState(() {});
                            },
                            activeThumbColor:
                                darkTheme ? Colors.white : Colors.black,
                            activeTrackColor: const Color(0xFFB3E5FC),
                            inactiveThumbColor:
                                darkTheme ? Colors.white70 : Colors.black54,
                            inactiveTrackColor: darkTheme
                                ? Colors.white24
                                : const Color(0xFF1A237E).withValues(alpha: 0.18),
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
                    color: darkTheme ? const Color(0xFF1F2B3B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: panelBorderColor(
                        targetCustomSet.isNotEmpty || activeSettingsPanel == 'save',
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
                    color: darkTheme ? const Color(0xFF1F2B3B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: panelBorderColor(activeSettingsPanel == 'legal'),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('legal'),
                        style: TextStyle(
                          color: darkTheme ? Colors.white70 : Colors.black54,
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
                          color: darkTheme ? Colors.white60 : Colors.black38,
                        ),
                        label: _t('privacy_policy'),
                        value: false,
                        onChanged: (_) => _openLegalUrl(_privacyPolicyUrl),
                        darkTheme: darkTheme,
                        isButton: true,
                        labelColor: darkTheme ? Colors.white60 : Colors.black38,
                        chevronColor: darkTheme ? Colors.white60 : Colors.black38,
                      ),
                      const SizedBox(height: 10),
                      _settingsRow(
                        icon: Icon(
                          Icons.description_outlined,
                          size: 32,
                          color: darkTheme ? Colors.white60 : Colors.black38,
                        ),
                        label: _t('terms_of_use'),
                        value: false,
                        onChanged: (_) => _openLegalUrl(_termsUrl),
                        darkTheme: darkTheme,
                        isButton: true,
                        labelColor: darkTheme ? Colors.white60 : Colors.black38,
                        chevronColor: darkTheme ? Colors.white60 : Colors.black38,
                      ),
                    ],
                  ),
                );
              }

              return const SizedBox.shrink();
            }

            return GestureDetector(
              onVerticalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0.0;
                if (v < -500) {
                  setState(() => showSettingsMenu = false);
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: settingsWidth,
                    padding: const EdgeInsets.fromLTRB(34, 18, 34, 18),
                    decoration: BoxDecoration(
                      color: darkTheme ? const Color(0xFF2C3E50) : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: const Color(0xFF1A237E),
                          width: 8,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        _settingsLanguageRow(
                    studyCode: studyLang,
                    nativeCode: nativeLang,
                    onStudyChanged: (code) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('study_language', code);
                      setState(() => studyLang = code);
                      loadWords();
                    },
                    onNativeChanged: (code) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('native_language', code);
                      setState(() => nativeLang = code);
                      loadWords();
                    },
                    darkTheme: darkTheme,
                  ),
                  const Divider(),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final double tileAspect =
                          constraints.maxWidth > 520 ? 3.0 : 2.6;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: tileAspect,
                        children: [
                          settingsTile(
                            icon: Icon(
                              Icons.play_arrow,
                              size: 26,
                              color: tileIconColor(randomSpeaking),
                            ),
                            label: _t('random_speaking'),
                            enabled: randomSpeaking,
                            onTap: () {
                              setState(() => randomSpeaking = !randomSpeaking);
                              setMenuState(() {});
                            },
                          ),
                          settingsTile(
                            icon: Icon(
                              Icons.bedtime_outlined,
                              size: 26,
                              color: tileIconColor(sleepTimerEnd != null ||
                                  activeSettingsPanel == 'sleep'),
                            ),
                            label: _t('sleep_timer'),
                            subLabel: sleepTimerEnd == null
                                ? _t('off')
                                : _remainingSleepMinutesLabel(),
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
                              setState(() => darkTheme = !darkTheme);
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
                                ? '${_t('native')}: ${_languageLabel[nativeLang] ?? nativeLang}'
                                : _languageLabel['en'] ?? 'English',
                            enabled: uiUseNative,
                            onTap: () async {
                              final prefs = await SharedPreferences.getInstance();
                              final v = !uiUseNative;
                              await prefs.setBool('uiUseNative', v);
                              if (!mounted) return;
                              setState(() => uiUseNative = v);
                              setMenuState(() {});
                            },
                          ),
                          settingsTile(
                            icon: Icon(
                              Icons.edit_note,
                              size: 26,
                              color: tileIconColor(targetCustomSet.isNotEmpty ||
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
                              color: tileIconColor(activeSettingsPanel == 'legal'),
                            ),
                            label: _t('legal'),
                            subLabel: '${_t('privacy_policy')} & ${_t('terms_of_use')}',
                            enabled: activeSettingsPanel == 'legal',
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
                  Positioned(
                    top: -12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 150,
                        height: 20,
                        decoration: BoxDecoration(
                          color:
                              darkTheme ? const Color(0xFF2C3E50) : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 150,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A237E),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
              },
            ),
          ),
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyleForTop(darkTop: true),
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
                        constraints: BoxConstraints(minHeight: contentMinHeight),
                        child: Center(
                          child: buildGridView(availableHeight: contentMinHeight),
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: contentPadding,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: contentMinHeight),
                      child: Center(
                        child: GestureDetector(
                          onHorizontalDragEnd: (details) {
                            if (details.primaryVelocity != null) {
                              if (details.primaryVelocity! < 0) {
                                setState(() {
                                  if (currentSetWords.isNotEmpty) {
                                    currentIndex = (currentIndex + 1) %
                                        currentSetWords.length;
                                  }
                                  showENFace = widget.showENasDefault;
                                });
                              } else if (details.primaryVelocity! > 0) {
                                setState(() {
                                  if (currentSetWords.isNotEmpty) {
                                    currentIndex = (currentIndex -
                                            1 +
                                            currentSetWords.length) %
                                        currentSetWords.length;
                                  }
                                  showENFace = widget.showENasDefault;
                                });
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
              child: Container(
                width: double.infinity,
                height: appBarTotalHeight,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A237E),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, topSafePadding + 18, 20, 16),
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
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            letterSpacing: 0.3,
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
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _remainingSleepMinutesLabel(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 18,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            showSettingsMenu = !showSettingsMenu;
                          });
                        },
                        child: Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/settings.svg',
                              width: 26,
                              height: 26,
                              colorFilter: const ColorFilter.mode(
                                  Colors.white, BlendMode.srcIn),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _WordsMenuButton(
                        groupedLists: getGroupedLists(),
                        currentLevel: selectedLevel,
                        currentSublist: selectedSublist,
                        setLabel: _t('set'),
                        selectListLabel: _t('select_list'),
                        onOpen: () {
                          setState(() {
                            panelActiveLevel = selectedLevel.isNotEmpty
                                ? selectedLevel
                                : (getGroupedLists().keys.isNotEmpty
                                    ? getGroupedLists().keys.first
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
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // --- LAYER 3: BOTTOM BAR (PINNED) ---
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                width: double.infinity,
                // [MODIFIED] Height includes safe area
                height: bottomBarHeight + bottomSafePadding,
                // [MODIFIED] Padding for safe area
                padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: bottomSafePadding > 0 ? bottomSafePadding : 0),
                decoration: BoxDecoration(
                  color: darkTheme ? const Color(0xFF1A237E) : Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: bottomAction(
                        onTap: () {
                          setState(() {
                            gridMode = !gridMode;
                          });
                        },
                        child: SvgPicture.asset(
                          'assets/icons/Grid.svg',
                          width: 32,
                          height: 32,
                          colorFilter: darkTheme
                              ? const ColorFilter.mode(
                                  Colors.white, BlendMode.srcIn)
                              : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: bottomAction(
                        onTap: () {
                          widget.onToggleDefault();
                          setState(() {
                            showENFace = !showENFace;
                            gridCardENFace =
                                List.filled(_cardsPerGridPage, showENFace);
                          });
                        },
                        child: Container(
                          width: 48,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: darkTheme
                                ? const Color(0xFF263240)
                                : const Color(0xFFF1F3F8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            showENFace ? studyLang.toUpperCase() : nativeLang.toUpperCase(),
                            strutStyle: const StrutStyle(
                              forceStrutHeight: true,
                              height: 1.0,
                            ),
                            style: TextStyle(
                              color: darkTheme
                                  ? Colors.white
                                  : const Color(0xFF1A237E),
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: bottomAction(
                        onTap: () {
                          if (!isPlaying) {
                            playSetWords();
                          } else {
                            stopPlaying();
                          }
                        },
                        child: SvgPicture.asset(
                          'assets/icons/Play circle.svg',
                          width: 32,
                          height: 32,
                          colorFilter: isPlaying
                              ? const ColorFilter.mode(
                                  Colors.green, BlendMode.srcIn)
                              : (darkTheme
                                  ? const ColorFilter.mode(
                                      Colors.white, BlendMode.srcIn)
                                  : null),
                        ),
                      ),
                    ),
                    Expanded(
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
                        child: SvgPicture.asset(
                          'assets/icons/Chevrons right.svg',
                          width: 32,
                          height: 32,
                          colorFilter: darkTheme
                              ? const ColorFilter.mode(
                                  Colors.white, BlendMode.srcIn)
                              : null,
                        ),
                      ),
                    ),
                  ],
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
                  child: Container(color: Colors.black.withValues(alpha: 0.1)),
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
                  offset: showWordsMenu ? Offset.zero : const Offset(0, -0.05),
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
                      groupedLists: getGroupedLists(),
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
    final order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'custom'];
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
          entry.wordMain.trim().toLowerCase() == word.wordMain.trim().toLowerCase());
      
      allWords.removeWhere((entry) =>
          entry.level == 'custom' &&
          entry.sublist == selectedSublist &&
          entry.wordMain.trim().toLowerCase() == word.wordMain.trim().toLowerCase());
          
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

  Future<void> _addWordToCustomSet(WordEntry word) async {
    if (targetCustomSet.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('no_target_list')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if the word already exists in the target custom list (using cache)
    if (_customEntries.any((entry) =>
        entry.sublist == targetCustomSet &&
        entry.wordMain.trim().toLowerCase() == word.wordMain.trim().toLowerCase())) {
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
    
    // Save to persistent storage in background
    _saveCustomListEntries(_customEntries);

    setState(() {
      allWords.add(newEntry);
      // If the user is currently viewing the list they just saved to, refresh it.
      if (selectedLevel == 'custom' && selectedSublist == targetCustomSet) {
        filterCurrentSet();
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "${word.wordMain}" to target list.'),
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
    const options = <Map<String, String>>[
      {'code': 'en', 'label': 'English', 'native': 'English', 'flag': '\u{1F1FA}\u{1F1F8}'},
      {'code': 'de', 'label': 'German', 'native': 'Deutsch', 'flag': '\u{1F1E9}\u{1F1EA}'},
      {'code': 'es', 'label': 'Spanish', 'native': 'Espa\u00F1ol', 'flag': '\u{1F1EA}\u{1F1F8}'},
      {'code': 'fr', 'label': 'French', 'native': 'Fran\u00E7ais', 'flag': '\u{1F1EB}\u{1F1F7}'},
      {'code': 'it', 'label': 'Italian', 'native': 'Italiano', 'flag': '\u{1F1EE}\u{1F1F9}'},
      {'code': 'pt', 'label': 'Portuguese', 'native': 'Portugu\u00EAs', 'flag': '\u{1F1F5}\u{1F1F9}'},
      {'code': 'tr', 'label': 'Turkish', 'native': 'T\u00FCrk\u00E7e', 'flag': '\u{1F1F9}\u{1F1F7}'},
      {'code': 'uk', 'label': 'Ukrainian', 'native': '\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430', 'flag': '\u{1F1FA}\u{1F1E6}'},
    ];

    Map<String, String> byCode(String code) =>
        options.firstWhere((o) => o['code'] == code, orElse: () => options.first);

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
                    color: (darkTheme ? Colors.white : Colors.black).withValues(alpha: 0.15),
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
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.9,
                    ),
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final o = options[index];
                      final bool selected = o['code'] == currentCode;
                      final bool disabled = o['code'] == disabledCode;
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
                                onPick(o['code']!);
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
                              Text(o['flag']!, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      o['label']!,
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
                                      o['native']!,
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(o['flag']!, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            o['label']!,
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


  static const String _privacyPolicyUrl = 'https://volary.mrcs-global.com/privacy.html';
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

  void _showCustomListDialog({bool setAsTarget = false}) {
    final TextEditingController listNameController = TextEditingController();
    const accentBlue = Color(0xFF1A237E);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFDFBFF),
        title: Text(
          _t('create_custom_list'),
          style: const TextStyle(fontSize: 22),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: listNameController,
                autofocus: true,
                style: const TextStyle(fontSize: 22),
                decoration: InputDecoration(
                  labelText: _t('list_name'),
                  hintText: _t('my_custom_list'),
                  helperText: _t('custom_list_tip'),
                  helperMaxLines: 3,
                  helperStyle: TextStyle(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontSize: 17,
                  ),
                  labelStyle: const TextStyle(
                    color: accentBlue,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: accentBlue,
              textStyle: const TextStyle(fontSize: 22),
            ),
            child: Text(_t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontSize: 22),
            ),
            onPressed: () {
              // --- CHANGE THIS CONDITION ---
              if (listNameController.text.isNotEmpty) {
                _createCustomList(
                  listNameController.text.trim(),
                  '',
                  setAsTarget: setAsTarget,
                );
                Navigator.pop(context);
              }
            },
            child: Text(_t('create')),
          ),
        ],
      ),
    );
  }

  Future<void> _createCustomList(String listName, String wordsText,
      {bool setAsTarget = false}) async {
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

      // Save to persistent storage in background
      _saveCustomListEntries(_customEntries);

      if (!mounted) return;
      Navigator.pop(context);

      // Show success message with statistics
      int translatedCount = newEntries
          .where((e) => e.trans1 != _translationNeeded && e.trans1 != e.wordMain)
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
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_t('delete_list')),
          content: Text(
              _t('delete_confirm').replaceAll('{list}', listName)),
          actions: <Widget>[
            TextButton(
              child: Text(_t('cancel')),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(_t('delete'), style: const TextStyle(color: Colors.red)),
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
    _customEntries = _customEntries.where((entry) => entry.sublist != listName).toList();
    allWords.removeWhere((entry) => entry.level == 'custom' && entry.sublist == listName);

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
    try {
      // Load from the main CSV file instead of a separate dictionary
      final rawData =
          await rootBundle.loadString('assets/sets/combined_words.csv');
      final csvTable = const CsvToListConverter().convert(rawData, eol: '\n');

      // Create a map for fast lookups from the existing CSV data
      for (var row in csvTable.skip(1)) {
        if (row.length >= 4) {
          String englishWord = row[2].toString().toLowerCase().trim();
          String ukrainianWord = row[3].toString().trim();
          if (englishWord.isNotEmpty && ukrainianWord.isNotEmpty) {
            enUkDictionary[englishWord] = ukrainianWord;
          }
        }
      }
      debugPrint(
          'Dictionary loaded with ${enUkDictionary.length} entries from main CSV');
    } catch (e) {
      debugPrint('Error loading dictionary from CSV: $e');
    }
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

    return grouped;
  }
}

class HomeSplashPage extends StatefulWidget {
  const HomeSplashPage({super.key});

  @override
  State<HomeSplashPage> createState() => _HomeSplashPageState();
}

class _HomeSplashPageState extends State<HomeSplashPage>
    with TickerProviderStateMixin {
  late AnimationController _liquidController;
  late AnimationController _logoController;
  late Animation<double> _liquidAnimation;
  late Animation<double> _logoAnimation;

  @override
  void initState() {
    super.initState();

    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _liquidAnimation = CurvedAnimation(
      parent: _liquidController,
      curve: const Cubic(0.45, 0.05, 0.55, 0.95),
    );

    _logoAnimation = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );

    // Start liquid immediately
    _liquidController.forward();

    // Start logo after 400ms
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _logoController.forward();
    });

    // Navigate to home after 1.5 seconds (to allow fade out transition)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/flashcards');
      }
    });
  }

  @override
  void dispose() {
    _liquidController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyleForTop(darkTop: false),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Liquid Layer Background
            AnimatedBuilder(
              animation: _liquidAnimation,
              builder: (context, child) {
                // Sliding up from bottom (-100% to -30%)
                return Positioned(
                  bottom: -size.height * 0.55 +
                      (1.0 - _liquidAnimation.value) * size.height,
                  left: -size.width * 0.35,
                  child: Transform.rotate(
                    angle: _liquidAnimation.value * 0.26, // approx 15 degrees
                    child: Container(
                      width: size.width * 1.25,
                      height: size.height * 2.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00004D),
                        borderRadius: BorderRadius.circular(size.width * 0.6),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Logo Reveal
            Center(
              child: ScaleTransition(
                scale: _logoAnimation,
                child: FadeTransition(
                  opacity: _logoAnimation,
                  child: const Text(
                    'vo',
                    style: TextStyle(
                      fontSize: 150,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                      fontFamily: 'Inter', // Defaulting to Inter as Caveat might not be loaded
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          offset: Offset(0, 4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordsMenuButton extends StatelessWidget {
  final Map<String, List<String>> groupedLists;
  final String currentLevel;
  final String currentSublist;
  final String setLabel;
  final String selectListLabel;
  final VoidCallback onOpen;
  final void Function(String level, String sublist) onSelect;

  const _WordsMenuButton({
    required this.groupedLists,
    required this.currentLevel,
    required this.currentSublist,
    required this.setLabel,
    required this.selectListLabel,
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

    final accentColor = const Color(0xFF1A237E);

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
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
                    color: Colors.blueGrey.shade500,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  buttonLabel,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Icon(Icons.keyboard_arrow_down, color: accentColor),
          ],
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
    final order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'custom'];
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
class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String? studyLang;
  String? nativeLang;
  bool isTransitioning = false;
  String? pressedLang;
  bool pressedIsNative = false;
  bool tapSounds = true;

  @override
  void initState() {
    super.initState();
    tapSounds = true;
  }

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

  void _selectStudy(String lang) {
    setState(() {
      isTransitioning = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        studyLang = lang;
        isTransitioning = false;
      });
    });
  }

  void _selectNative(String lang) async {
    setState(() => nativeLang = lang);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('study_language', studyLang!);
    await prefs.setString('native_language', lang);
    
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeSplashPage()),
    );
  }

  Future<void> _flashAndSelect(String lang, {required bool native}) async {
    _playTapClick();
    setState(() {
      pressedLang = lang;
      pressedIsNative = native;
    });
    await Future.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    setState(() {
      pressedLang = null;
    });
    if (native) {
      _selectNative(lang);
    } else {
      _selectStudy(lang);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool pickingNative = studyLang != null && !isTransitioning;
    final Color baseStudy = const Color(0xFFEAF2FF);
    final Color baseNative = const Color(0xFFEAF8EE);
    final Color pressedStudy = const Color(0xFFB3E5FC);
    final Color pressedNative = const Color(0xFFB2FFB2);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyleForTop(darkTop: false),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final blur = Tween<double>(begin: 6.0, end: 0.0).animate(animation);
          final fade = Tween<double>(begin: 0.4, end: 1.0).animate(animation);
          return FadeTransition(
            opacity: fade,
            child: AnimatedBuilder(
              animation: blur,
              builder: (context, _) => ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blur.value,
                  sigmaY: blur.value,
                ),
                child: child,
              ),
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(pickingNative),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    _TitlePill(
                      text: pickingNative
                          ? 'Your native language?'
                          : 'What language to learn?',
                      backgroundColor: pickingNative
                          ? const Color(0xFFB2FFB2) // active green
                          : const Color(0xFFB3E5FC), // active blue
                    ),
                    const SizedBox(height: 48),

                    // ENGLISH (only if not picking native English while study is English)
                    if (!pickingNative || studyLang != 'en')
                      _LanguageButton(
                        flag: '\u{1F1FA}\u{1F1F8}',
                        label: 'English',
                        subLabel: pickingNative ? 'English' : 'Study English',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'en' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'en',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'en')
                      const SizedBox(height: 12),

                    // GERMAN
                    if (!pickingNative || studyLang != 'de')
                      _LanguageButton(
                        flag: '\u{1F1E9}\u{1F1EA}',
                        label: 'German',
                        subLabel: pickingNative ? 'Deutsch' : 'Study German',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'de' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'de',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'de')
                      const SizedBox(height: 12),

                    // FRENCH
                    if (!pickingNative || studyLang != 'fr')
                      _LanguageButton(
                        flag: '\u{1F1EB}\u{1F1F7}',
                        label: 'French',
                        subLabel: pickingNative ? 'Fran\u00E7ais' : 'Study French',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'fr' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'fr',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'fr')
                      const SizedBox(height: 12),

                    // ITALIAN
                    if (!pickingNative || studyLang != 'it')
                      _LanguageButton(
                        flag: '\u{1F1EE}\u{1F1F9}',
                        label: 'Italian',
                        subLabel: pickingNative ? 'Italiano' : 'Study Italian',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'it' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'it',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'it')
                      const SizedBox(height: 12),

                    // SPANISH
                    if (!pickingNative || studyLang != 'es')
                      _LanguageButton(
                        flag: '\u{1F1EA}\u{1F1F8}',
                        label: 'Spanish',
                        subLabel: pickingNative ? 'Espa\u00F1ol' : 'Study Spanish',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'es' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'es',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'es')
                      const SizedBox(height: 12),

                    // PORTUGUESE
                    if (!pickingNative || studyLang != 'pt')
                      _LanguageButton(
                        flag: '\u{1F1F5}\u{1F1F9}',
                        label: 'Portuguese',
                        subLabel: pickingNative ? 'Portugu\u00EAs' : 'Study Portuguese',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'pt' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'pt',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'pt')
                      const SizedBox(height: 12),

                    // TURKISH
                    if (!pickingNative || studyLang != 'tr')
                      _LanguageButton(
                        flag: '\u{1F1F9}\u{1F1F7}',
                        label: 'Turkish',
                        subLabel: pickingNative ? 'T\u00FCrk\u00E7e' : 'Study Turkish',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'tr' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'tr',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'tr')
                      const SizedBox(height: 12),

                    // UKRAINIAN
                    if (!pickingNative || studyLang != 'uk')
                      _LanguageButton(
                        flag: '\u{1F1FA}\u{1F1E6}',
                        label: 'Ukrainian',
                        subLabel: pickingNative
                            ? '\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430'
                            : 'Study Ukrainian',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'uk' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'uk',
                          native: pickingNative,
                        ),
                      ),

                    if (pickingNative) ...[
                      const SizedBox(height: 32),
                      TextButton(
                        onPressed: () {
                          _playTapClick();
                          setState(() => studyLang = null);
                        },
                        child: const Text('Back to Study Language'),
                      )
                    ]
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _TitlePill extends StatelessWidget {
  final String text;
  final Color backgroundColor;

  const _TitlePill({
    required this.text,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
            fontFamily: 'Inter',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final String flag;
  final String label;
  final String subLabel;
  final Color color;
  final Color? pressedColor;
  final bool isPressed;
  final VoidCallback onTap;

  const _LanguageButton({
    required this.flag,
    required this.label,
    required this.subLabel,
    required this.color,
    this.pressedColor,
    this.isPressed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isPressed && pressedColor != null ? pressedColor : color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(
              flag,
              style: const TextStyle(fontSize: 42),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                Text(
                  subLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF1A237E), size: 18),
          ],
        ),
      ),
    );
  }
}

