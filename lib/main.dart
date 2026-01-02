import 'package:flutter/material.dart';
// import 'home_page.dart'; // <-- import your splash page
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

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
      title: 'English Words Trainer',
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
  bool randomSpeaking = true;
  bool allowBackgroundSpeaking = false;
  bool darkTheme = false;
  String targetCustomSet = ''; // <-- Add this

  // Add this to track loading state
  bool isLoading = true;

  // Add this to your class variables
  Map<String, String> enUkDictionary = {};
  List<String> allCustomListNames = [];
  List<WordEntry> _customEntries = []; // Cache for starred and custom words

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    loadWords();
    _loadDictionary();
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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studyLang = prefs.getString('study_language') ?? 'en';
      nativeLang = prefs.getString('native_language') ?? 'uk';
      targetCustomSet = prefs.getString('targetCustomSet') ?? '';
      allowBackgroundSpeaking =
          prefs.getBool('allowBackgroundSpeaking') ?? false;
    });
  }

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

  Future<void> loadWords() async {
    setState(() {
      isLoading = true;
    });

    // --- FIX: Ensure custom names are loaded ---
    await _loadCustomListNames();

    final prefs = await SharedPreferences.getInstance();
    studyLang = prefs.getString('study_language') ?? 'en';
    nativeLang = prefs.getString('native_language') ?? 'uk';

    final String studyPath = 'assets/sets/$studyLang.csv';
    final String nativePath = 'assets/sets/$nativeLang.csv';

    try {
      final ByteData studyBytes = await rootBundle.load(studyPath);
      final ByteData nativeBytes = await rootBundle.load(nativePath);
      
      final String studyData = utf8.decode(studyBytes.buffer.asUint8List(), allowMalformed: true);
      final String nativeData = utf8.decode(nativeBytes.buffer.asUint8List(), allowMalformed: true);

      // CsvToListConverter without explicit eol will try to auto-detect (\n or \r\n)
      final studyTable = const CsvToListConverter().convert(studyData);
      final nativeTable = const CsvToListConverter().convert(nativeData);

      // We skip header and assume same number of rows and same order
      final int rowsToProcess = math.min(studyTable.length, nativeTable.length);
      
      List<WordEntry> loadedWords = [];
      for (int i = 1; i < rowsToProcess; i++) {
        try {
          final sRow = studyTable[i];
          final nRow = nativeTable[i];

          if (sRow.length < 3 || nRow.length < 3) continue;

          // Format is: Level, List, Word1, Word2
          loadedWords.add(WordEntry(
            sRow[0].toString().trim(), // level
            sRow[1].toString().trim(), // list
            sRow[2].toString().trim(), // wordMain
            nRow[2].toString().trim(), // trans1
            '', '', '', '',            // examples empty for now
            sRow.length > 3 ? sRow[3].toString().trim() : '', // wordSyn
            nRow.length > 3 ? nRow[3].toString().trim() : '', // trans2
          ));
        } catch (rowError) {
          debugPrint('Skipping row $i due to error: $rowError');
        }
      }
      allWords = loadedWords;
    } catch (e) {
      debugPrint('Error loading multilingual CSVs: $e');
      allWords = [];
    }

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
    
    await flutterTts.setLanguage(ttsLang);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak(text);
  }

  Future<void> _speakStudy(String text) async => _speak(text, studyLang);
  Future<void> _speakNative(String text) async => _speak(text, nativeLang);

  Future<void> speakWord(String word) async {
    await _speakStudy(word);
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

  Future<void> playSetWords() async {
    if (isPlaying) return;
    if (currentSetWords.isEmpty) return;
    setState(() {
      isPlaying = true;
    });

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

    if (randomSpeaking) {
      int? lastIdx;
      while (isPlaying) {
        if (currentSetWords.isEmpty) break;
        int idx;
        if (currentSetWords.length == 1) {
          idx = 0;
        } else {
          idx = rng.nextInt(currentSetWords.length);
          int guard = 0;
          while (idx == lastIdx && guard < 6) {
            idx = rng.nextInt(currentSetWords.length);
            guard++;
          }
        }
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
        final studyFirst = rng.nextBool();
        await speakEntry(entry, studyFirst: studyFirst);
        if (!isPlaying) break;
        await Future.delayed(const Duration(milliseconds: 700));
      }
    } else {
      for (int i = startIdx; i < currentSetWords.length; i++) {
        if (!isPlaying) break;
        final entry = currentSetWords[i];

        if (!mounted) break;
        setState(() {
          currentIndex = i;
          if (gridMode) {
            gridPage = i ~/ _cardsPerGridPage;
            gridCardENFace = List.filled(_cardsPerGridPage, showENFace);
          }
        });

        final studyFirst = showENFace;
        await speakEntry(entry, studyFirst: studyFirst);
        if (!isPlaying) break;
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    setState(() {
      isPlaying = false;
    });
  }

  // Optionally, add a stop function
  void stopPlaying({bool updateUi = true}) {
    isPlaying = false;
    if (updateUi && mounted) {
      setState(() {});
    }
    flutterTts.stop();
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
      return Scaffold(
        backgroundColor: darkTheme ? const Color(0xFF1E2A3A) : Colors.white,
        body: const Center(
          child: CircularProgressIndicator(),
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
        onTap: onTap,
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
        int computedColumns = (availableWidth / 150).floor();
        if (computedColumns < 2) {
          computedColumns = 2;
        } else if (computedColumns > 4) {
          computedColumns = 4;
        }
        final int crossAxisCount = computedColumns;
        final double spacing =
            math.max(10.0, math.min(20.0, availableWidth * 0.03));
        final double usableWidth =
            availableWidth - spacing * (crossAxisCount - 1);
        final double cardWidth = usableWidth / crossAxisCount;
        final int startIndex = gridPage * _cardsPerGridPage;
        final int totalRemaining =
            math.max(0, currentSetWords.length - startIndex);
        final int itemsOnPage = totalRemaining > _cardsPerGridPage
            ? _cardsPerGridPage
            : totalRemaining;
        final double viewportHeight = availableHeight;
        final double gridTopPadding = 0.0;
        final double gridBottomPadding = 0.0;
        final int rows = itemsOnPage == 0
            ? 1
            : ((itemsOnPage + crossAxisCount - 1) ~/ crossAxisCount);
        final double availableHeightForCards = math.max(
            160.0, viewportHeight - gridTopPadding - gridBottomPadding);
        final double fittedCardHeight =
            (availableHeightForCards - spacing * (rows - 1)) / rows;
        final double cardHeight = math.max(
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
      top: overlayPanelTop,
      left: 0,
      right: 0,
      child: Visibility(
        visible: showSettingsMenu,
        // --- WRAP THE CONTAINER WITH A STATEFULBUILDER ---
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setMenuState) {
            return Container(
              width: settingsWidth,
              padding: const EdgeInsets.fromLTRB(34, 20, 34, 10),
              decoration: BoxDecoration(
                color: darkTheme ? const Color(0xFF2C3E50) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF1A237E),
                    width: 4,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   _settingsLanguageRow(
                    label: 'Study Language',
                    currentCode: studyLang,
                    onChanged: (code) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('study_language', code);
                      setState(() {
                         studyLang = code;
                      });
                      loadWords(); // reload data
                    },
                    darkTheme: darkTheme,
                  ),
                  const SizedBox(height: 12),
                  _settingsLanguageRow(
                    label: 'Native Language',
                    currentCode: nativeLang,
                    currentStudyCode: studyLang, // to highlight if same
                    onChanged: (code) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('native_language', code);
                      setState(() {
                         nativeLang = code;
                      });
                      loadWords(); // reload data
                    },
                    darkTheme: darkTheme,
                  ),
                  const Divider(),
                  const SizedBox(height: 12),
                  // Play icon left of label, black color
                  _settingsRow(
                    icon: Icon(
                      Icons.play_arrow,
                      size: 32,
                      color: darkTheme ? Colors.white : Colors.black,
                    ),
                    label: 'random speaking',
                    value: randomSpeaking,
                    onChanged: (v) => setState(() => randomSpeaking = v),
                    darkTheme: darkTheme,
                  ),
                  const SizedBox(height: 18),
                  _settingsRow(
                    icon: Icon(
                      Icons.lock_outline,
                      size: 32,
                      color: darkTheme ? Colors.white : Colors.black,
                    ),
                    label: 'background speaking',
                    value: allowBackgroundSpeaking,
                    onChanged: (v) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('allowBackgroundSpeaking', v);
                      if (!mounted) return;
                      setState(() => allowBackgroundSpeaking = v);
                    },
                    darkTheme: darkTheme,
                  ),
                  const SizedBox(height: 18),
                  _settingsRow(
                    icon: SvgPicture.asset(
                      'assets/icons/darkTheme.svg',
                      width: 32,
                      height: 32,
                      colorFilter: ColorFilter.mode(
                        darkTheme ? Colors.white : const Color(0xFF1E1E1E),
                        BlendMode.srcIn,
                      ),
                    ),
                    label: 'dark theme',
                    value: darkTheme,
                    onChanged: (v) => setState(() => darkTheme = v),
                    darkTheme: darkTheme,
                  ),
                  const SizedBox(height: 18),
                  _settingsRow(
                    icon: SvgPicture.asset(
                      'assets/icons/addfile.svg',
                      width: 32,
                      height: 32,
                      colorFilter: ColorFilter.mode(
                        darkTheme ? Colors.white : Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    label: 'add own file',
                    value: false,
                    onChanged: (_) => _showCustomListDialog(),
                    darkTheme: darkTheme,
                    isButton: true,
                  ),
                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 10),
                  // Pass the setMenuState function to the build method
                  _buildSaveToSection(darkTheme, setMenuState),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        ),
      ),
    );

    return Scaffold(
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
                padding: EdgeInsets.fromLTRB(20, topSafePadding + 8, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        gridMode
                            ? 'Cards ${currentSetWords.isEmpty ? 0 : (gridPage * _cardsPerGridPage + 1)} / ${currentSetWords.length}'
                            : 'Cards ${currentSetWords.isEmpty ? 0 : (currentIndex + 1)} / ${currentSetWords.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          letterSpacing: 0.3,
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
                color: Colors.white,
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
                          color: const Color(0xFFF1F3F8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          showENFace ? studyLang.toUpperCase() : nativeLang.toUpperCase(),
                          strutStyle: const StrutStyle(
                            forceStrutHeight: true,
                            height: 1.0,
                          ),
                          style: const TextStyle(
                            color: Color(0xFF1A237E),
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
                            : null,
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
          if (showWordsMenu) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => showWordsMenu = false),
                child: Container(color: Colors.black.withValues(alpha: 0.1)),
              ),
            ),
            Positioned(
              top: overlayPanelTop,
              right: 20,
              child: _WordsMenuPanel(
                groupedLists: getGroupedLists(),
                activeLevel: panelActiveLevel,
                currentLevel: selectedLevel,
                currentSublist: selectedSublist,
                onChangeLevel: (lvl) => setState(() => panelActiveLevel = lvl),
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
          ],

          // Settings Menu (and its backdrop)
          if (showSettingsMenu) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => showSettingsMenu = false),
                child: Container(
                    color: Colors.transparent), // Catches taps outside the menu
              ),
            ),
            // The settingsMenu variable is already a Positioned widget
            settingsMenu,
          ],
        ],
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
        content: Text('Removed "${word.wordMain}" from custom list.'),
        backgroundColor: Colors.red,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _addWordToCustomSet(WordEntry word) async {
    if (targetCustomSet.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No target list selected. Please choose one in Settings > Save to.'),
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
          content: Text('"${word.wordMain}" is already in the target list.'),
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
    required String label,
    required String currentCode,
    String? currentStudyCode,
    required ValueChanged<String> onChanged,
    required bool darkTheme,
  }) {
    final Map<String, String> langNames = {
      'en': 'English',
      'es': 'Spanish',
      'pt': 'Portuguese',
      'uk': 'Ukrainian',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: darkTheme ? Colors.white70 : Colors.black54,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: langNames.entries.map((entry) {
            final isSelected = entry.key == currentCode;
            final isSameAsStudy = entry.key == currentStudyCode;
            return GestureDetector(
              onTap: isSameAsStudy ? null : () => onChanged(entry.key),
              child: Opacity(
                opacity: isSameAsStudy ? 0.3 : 1.0,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF1A237E) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1A237E),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected ? Colors.white : (darkTheme ? Colors.white : Colors.black),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
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
                  color: darkTheme ? Colors.white : const Color(0xFF1E1E1E),
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  fontSize: 28, // Increased from 20
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // --- CHANGE THIS ---
            if (isButton)
              Icon(Icons.chevron_right,
                  color: darkTheme ? Colors.white70 : Colors.black54)
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

  // --- ADD THIS NEW WIDGET METHOD ---
  Widget _buildSaveToSection(bool darkTheme, StateSetter setMenuState) {
    final customLists = getGroupedLists()['custom'] ?? [];
    String currentTargetDisplayName = targetCustomSet.isNotEmpty
        ? targetCustomSet.replaceFirst('list_custom_', '').replaceAll('_', ' ')
        : 'None';

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
                        'save to custom list',
                        style: TextStyle(
                          color: darkTheme
                              ? Colors.white
                              : const Color(0xFF1E1E1E),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          fontSize: 28, // Increased from 20
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
                  title: const Text(
                    'create',
                    style: TextStyle(
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
    final TextEditingController wordsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create Custom List'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: listNameController,
                decoration: InputDecoration(
                  labelText: 'List Name',
                  hintText: 'My Custom List',
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: wordsController,
                decoration: InputDecoration(
                  labelText: 'English Words',
                  hintText: 'Enter words separated by commas or new lines',
                ),
                maxLines: 10,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // --- CHANGE THIS CONDITION ---
              if (listNameController.text.isNotEmpty) {
                _createCustomList(
                  listNameController.text.trim(),
                  wordsController.text.trim(), // This can now be empty
                  setAsTarget: setAsTarget,
                );
                Navigator.pop(context);
              }
            },
            child: Text('Create'),
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
        .split(RegExp(r'[,\n\r\s]+'))
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
              Text('Processing words: $processed/${words.length}'),
              Text('Finding translations...'),
            ],
          ),
        ),
      ),
    );

    try {
      List<WordEntry> newEntries = [];

      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        final translation = await translateToUkrainian(word);
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
          .where((e) => e.trans1 != '[ Переклад потрібен ]' && e.trans1 != e.wordMain)
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
      // Select the new list
      setState(() {
        selectedLevel = 'custom';
        selectedSublist = formattedListName;
        if (setAsTarget) {
          targetCustomSet = formattedListName;
          _setTargetCustomSet(formattedListName);
        }
        filterCurrentSet();
      });
    } catch (e) {
      if (mounted) {
        // Close the loading dialog
        Navigator.pop(context);

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating list: ${e.toString()}'),
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
          title: const Text('Delete List'),
          content: Text(
              'Are you sure you want to delete the list "$listName"?\nThis cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
  Future<String> translateToUkrainian(String englishWord) async {
    final word = englishWord.toLowerCase().trim();

    // First try the local dictionary (from CSV)
    final localTranslation = enUkDictionary[word];
    if (localTranslation != null && localTranslation.isNotEmpty) {
      return localTranslation;
    }

    // Try online translation as fallback
    try {
      final translation = await getOnlineTranslation(word);
      if (translation.isNotEmpty && translation != word) {
        return translation;
      }
    } catch (e) {
      debugPrint('Online translation failed: $e');
    }

    // Final fallback - return placeholder in Ukrainian
    return '[ Переклад потрібен ]';
  }

// Add online translation function
  Future<String> getOnlineTranslation(String word) async {
    try {
      // Using a simple translation API (MyMemory - free tier)
      final url =
          'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(word)}&langpair=en|uk';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translatedText = data['responseData']['translatedText'];

        // Basic validation - avoid returning the same word or obvious errors
        if (translatedText != null &&
            translatedText.toString().trim().isNotEmpty &&
            translatedText.toString().toLowerCase() != word.toLowerCase()) {
          return translatedText.toString().trim();
        }
      }
    } catch (e) {
      debugPrint('Translation API error: $e');
    }

    return ''; // Return empty string if translation fails
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

    return Scaffold(
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
                bottom: -size.height * 0.5 + (1.0 - _liquidAnimation.value) * size.height,
                left: -size.width * 0.2,
                child: Transform.rotate(
                  angle: _liquidAnimation.value * 0.26, // approx 15 degrees
                  child: Container(
                    width: size.width * 1.4,
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
                    fontSize: 120,
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
    );
  }
}

class _WordsMenuButton extends StatelessWidget {
  final Map<String, List<String>> groupedLists;
  final String currentLevel;
  final String currentSublist;
  final VoidCallback onOpen;
  final void Function(String level, String sublist) onSelect;

  const _WordsMenuButton({
    required this.groupedLists,
    required this.currentLevel,
    required this.currentSublist,
    required this.onOpen,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    String buttonLabel = 'Select List';
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
        // e.g. "A1 L1"
        final match = RegExp(r'L(\d+)$').firstMatch(currentSublist);
        if (match != null) {
          buttonLabel = '$currentLevel L${match.group(1)}';
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
                  'Set',
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
  final String activeLevel; // which level’s sublists to show
  final String currentLevel; // currently selected level
  final String currentSublist; // currently selected sublist
  final ValueChanged<String> onChangeLevel;
  final void Function(String level, String sublist) onSelect;

  const _WordsMenuPanel({
    required this.groupedLists,
    required this.activeLevel,
    required this.currentLevel,
    required this.currentSublist,
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
                      'Level',
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
                      'List',
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

  void _selectStudy(String lang) {
    setState(() => studyLang = lang);
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

  @override
  Widget build(BuildContext context) {
    bool pickingNative = studyLang != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                pickingNative ? 'Your native language?' : 'What language to learn?',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                  fontFamily: 'Inter',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // ENGLISH (only if not picking native English while study is English)
              if (!pickingNative || studyLang != 'en')
                _LanguageButton(
                  flag: '🇺🇸',
                  label: 'English',
                  subLabel: pickingNative ? 'Англійська / Inglés' : 'Study English',
                  color: const Color(0xFFE8EAF6),
                  onTap: () => pickingNative ? _selectNative('en') : _selectStudy('en'),
                ),
              if (!pickingNative || studyLang != 'en') const SizedBox(height: 24),

              // UKRAINIAN
              // SPANISH
              if (!pickingNative || studyLang != 'es')
                _LanguageButton(
                  flag: '🇪🇸',
                  label: 'Spanish',
                  subLabel: pickingNative ? 'Español' : 'Study Spanish',
                  color: const Color(0xFFFFF3E0),
                  onTap: () => pickingNative ? _selectNative('es') : _selectStudy('es'),
                ),
              if (!pickingNative || studyLang != 'es') const SizedBox(height: 24),

              // PORTUGUESE
              if (!pickingNative || studyLang != 'pt')
                _LanguageButton(
                  flag: '🇵🇹',
                  label: 'Portuguese',
                  subLabel: pickingNative ? 'Português' : 'Study Portuguese',
                  color: const Color(0xFFE8F5E9),
                  onTap: () => pickingNative ? _selectNative('pt') : _selectStudy('pt'),
                ),
              if (!pickingNative || studyLang != 'pt') const SizedBox(height: 24),

              // UKRAINIAN
              if (!pickingNative || studyLang != 'uk')
                _LanguageButton(
                  flag: '🇺🇦',
                  label: 'Ukrainian',
                  subLabel: pickingNative ? 'Українська' : 'Study Ukrainian',
                  color: const Color(0xFFE3F2FD),
                  onTap: () => pickingNative ? _selectNative('uk') : _selectStudy('uk'),
                ),

              if (pickingNative) ...[
                 const SizedBox(height: 32),
                 TextButton(
                    onPressed: () => setState(() => studyLang = null),
                    child: const Text('← Back to Study Language'),
                 )
              ]
            ],
          ),
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
  final VoidCallback onTap;

  const _LanguageButton({
    required this.flag,
    required this.label,
    required this.subLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        decoration: BoxDecoration(
          color: color,
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
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                Text(
                  subLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF1A237E)),
          ],
        ),
      ),
    );
  }
}
