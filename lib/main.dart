import 'package:flutter/material.dart';
// import 'home_page.dart'; // <-- import your splash page
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
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
  bool showENasDefault = true;

  void toggleDefaultView() {
    setState(() {
      showENasDefault = !showENasDefault;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Words Trainer',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeSplashPage(),
        '/flashcards': (context) => FlashcardScreen(
              showENasDefault: showENasDefault,
              onToggleDefault: toggleDefaultView,
            ),
      },
    );
  }
}

class WordEntry {
  final String level;
  final String sublist;
  final String en;
  final String uk;
  final String example1;
  final String example2;

  WordEntry(this.level, this.sublist, this.en, this.uk, this.example1, [this.example2 = '']);
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

class _FlashcardScreenState extends State<FlashcardScreen> {
  bool showENFace = true;
  bool gridMode = false;
  int gridPage = 0;
  List<bool> gridCardENFace = List.filled(10, true);
  List<WordEntry> allWords = [];
  List<WordEntry> currentSetWords = [];
  int currentIndex = 0;
  String selectedLevel = '';
  String selectedSublist = '';

  // Inline words menu state
  bool showWordsMenu = false;
  String panelActiveLevel = '';

  final FlutterTts flutterTts = FlutterTts();
  bool isPlaying = false; // Add this to your _FlashcardScreenState
  bool showSlider = false; // <-- Add this
  double sliderValue = 0;  // <-- Add this
  bool showSettingsMenu = false;
  bool showSaveToSubMenu = false; // <-- ADD THIS
  bool randomSpeaking = true;
  bool darkTheme = false;
  String targetCustomSet = ''; // <-- Add this

  // Add this to track loading state
  bool isLoading = true;

  // Add this to your class variables
  Map<String, String> enUkDictionary = {};
  List<String> allCustomListNames = []; // <-- ADD THIS

  @override
  void initState() {
    super.initState();
    _loadSettings();
    loadWords();
    loadDictionary();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      targetCustomSet = prefs.getString('targetCustomSet') ?? '';
      // you can also load randomSpeaking and darkTheme here if you want them to persist
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
    
    // --- ADD THIS CALL ---
    await _loadCustomListNames();

    // Load predefined lists from CSV
    final rawData = await rootBundle.loadString('assets/sets/all_lists.csv');
    final csvTable = const CsvToListConverter().convert(rawData, eol: '\n');

    allWords = csvTable.skip(1).map((row) {
      return WordEntry(
        row[0].toString().trim(), // level
        row[1].toString().trim(), // sublist
        row[2].toString(),        // en
        row.length > 3 ? row[3].toString() : '', // uk
        row.length > 4 ? row[4].toString() : '', // example1
        '', // example2 (not in CSV; keep empty)
      );
    }).toList();
    
    // Load custom lists from SharedPreferences
    List<WordEntry> customEntries = await _loadCustomLists();
    
    // Merge predefined and custom lists
    allWords.addAll(customEntries);
    
    // Pick default by CEFR order, then numeric sublist
    final grouped = getGroupedLists();
    final levels = grouped.keys.toList()
      ..sort((a, b) => _levelOrderIndex(a).compareTo(_levelOrderIndex(b)));
    String initLevel = levels.isNotEmpty ? levels.first : '';
    String initSub = '';
    if (initLevel.isNotEmpty) {
      final subs = List<String>.from(grouped[initLevel] ?? [])..sort(_compareSublists);
      if (subs.isNotEmpty) initSub = subs.first;
    }

    setState(() {
      selectedLevel = initLevel;
      selectedSublist = initSub;
      filterCurrentSet();
      isLoading = false;
    });
    
    print('Loaded ${allWords.length} words');
    print('Levels: $levels');
    print('Current: $selectedLevel / $selectedSublist');
    print('Words in current list: ${currentSetWords.length}');
  }

  void filterCurrentSet() {
    currentSetWords = allWords.where((w) =>
      w.level.trim().toLowerCase() == selectedLevel.trim().toLowerCase() &&
      w.sublist.trim().toLowerCase() == selectedSublist.trim().toLowerCase()
    ).toList();
    currentIndex = 0;
    gridPage = 0;
    gridCardENFace = List.filled(10, showENFace);
    setState(() {});
    print('Filtering for "$selectedLevel / $selectedSublist", found ${currentSetWords.length} words');
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

  Future<void> speakWord(String word) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak(word);
  }

  void nextGridPage() {
    setState(() {
      int maxPage = (currentSetWords.length / 10).ceil() - 1;
      if (gridPage < maxPage) {
        gridPage++;
      }
      gridCardENFace = List.filled(10, showENFace); // <-- use current default
    });
  }

  void prevGridPage() {
    setState(() {
      if (gridPage > 0) {
        gridPage--;
      }
      gridCardENFace = List.filled(10, showENFace); // <-- use current default
    });
  }

  Future<void> playSetWords() async {
    if (isPlaying) return;
    setState(() {
      isPlaying = true;
    });

    // Determine start index for single or grid mode
    int startIdx = gridMode ? gridPage * 10 : currentIndex;

    for (int i = startIdx; i < currentSetWords.length; i++) {
      if (!isPlaying) break;
      final entry = currentSetWords[i];

      if (showENFace) {
        // EN default: EN -> 1s pause -> UK -> 2s pause
        await flutterTts.setLanguage("en-US");
        await flutterTts.setSpeechRate(0.5);
        await flutterTts.speak(entry.en);
        await Future.delayed(const Duration(seconds: 1));

        await flutterTts.setLanguage("uk-UA");
        await flutterTts.setSpeechRate(0.5);
        if (entry.uk.isNotEmpty) {
          await flutterTts.speak(entry.uk);
        }
        await Future.delayed(const Duration(seconds: 2));
      } else {
        // UK default: UK -> 3s pause -> EN
        await flutterTts.setLanguage("uk-UA");
        await flutterTts.setSpeechRate(0.5);
        if (entry.uk.isNotEmpty) {
          await flutterTts.speak(entry.uk);
        }
        await Future.delayed(const Duration(seconds: 3));

        await flutterTts.setLanguage("en-US");
        await flutterTts.setSpeechRate(0.5);
        await flutterTts.speak(entry.en);
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    setState(() {
      isPlaying = false;
    });
  }

  // Optionally, add a stop function
  void stopPlaying() {
    setState(() {
      isPlaying = false;
    });
    flutterTts.stop();
  }

  // Helper for grid page count
  int get totalGridPages => (currentSetWords.length / 10).ceil();

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator if still loading
    if (isLoading) {
      return Scaffold(
        backgroundColor: darkTheme ? const Color(0xFF397386) : Colors.white,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    final enWord = currentSetWords.isNotEmpty ? currentSetWords[currentIndex].en : '';
    final ukWord = currentSetWords.isNotEmpty ? currentSetWords[currentIndex].uk : '';
    final example1 = currentSetWords.isNotEmpty ? currentSetWords[currentIndex].example1 : '';
    final example2 = currentSetWords.isNotEmpty ? currentSetWords[currentIndex].example2 : '';

    Widget singleCardView = SizedBox(
      width: 300,
      height: 240,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
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
                      currentIndex = (currentIndex + 1) % currentSetWords.length;
                    }
                    showENFace = widget.showENasDefault;
                  });
                } else if (details.primaryVelocity! > 0) {
                  setState(() {
                    if (currentSetWords.isNotEmpty) {
                      currentIndex = (currentIndex - 1 + currentSetWords.length) % currentSetWords.length;
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
                key: ValueKey('$currentIndex-$showENFace'), // <-- add currentIndex to key for animation
                width: 300,
                height: 180,
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
                              _removeWordFromCustomList(currentSetWords[currentIndex]);
                            } else {
                              _addWordToCustomSet(currentSetWords[currentIndex]);
                            }
                          }
                        },
                        child: Container(
                          width: 35,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD).withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              selectedLevel == 'custom' ? Icons.delete_outline : Icons.star_border,
                              color: selectedLevel == 'custom' ? Colors.red.shade600 : Colors.blueGrey.shade600,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        showENFace ? enWord : ukWord,
                        style: TextStyle(
                          color: showENFace
                              ? Colors.black
                              : const Color(0xFFB71C1C),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: showENFace ? 36 : 28,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: () {
                          speakWord(enWord);
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
                              fontSize: 14,
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
                              fontSize: 14,
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
          width: 140,
          height: 100,
          margin: const EdgeInsets.all(8),
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
                      color: const Color(0xFFE3F2FD).withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        selectedLevel == 'custom' ? Icons.delete_outline : Icons.star_border,
                        color: selectedLevel == 'custom' ? Colors.red.shade600 : Colors.blueGrey.shade600,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isEN ? entry.en : entry.uk,
                      style: TextStyle(
                        color: isEN ? Colors.black : const Color(0xFFB71C1C),
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isEN && (entry.example1.isNotEmpty || entry.example2.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Column(
                          children: [
                            if (entry.example1.isNotEmpty)
                              Text(
                                entry.example1,
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            if (entry.example2.isNotEmpty)
                              Text(
                                entry.example2,
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    speakWord(entry.en);
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

    Widget gridView = GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          setState(() {
            if (details.primaryVelocity! < 0) {
              nextGridPage();
            } else if (details.primaryVelocity! > 0) {
              prevGridPage();
            }
            // Reset all cards on the new page to the current default language
            gridCardENFace = List.filled(10, showENFace);
          });
        }
      },
      child: SizedBox(
        width: 320,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(
            (currentSetWords.length - gridPage * 10 >= 10 ? 10 : currentSetWords.length - gridPage * 10),
            (i) => gridCard(currentSetWords[gridPage * 10 + i], i),
          ),
        ),
      ),
    );

    // --- SLIDER OVERLAY ---
    Widget sliderOverlay;
    if (showSlider && currentSetWords.isNotEmpty) {
      if (gridMode) {
        // Grid mode: slider for pages
        sliderOverlay = Positioned(
          left: 32,
          right: 32,
          bottom: 110,
          child: Material(
            color: Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Center(
                    child: Text(
                      '${(sliderValue * 10 + 1).toInt()}',
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
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                    ),
                    child: Slider(
                      min: 0,
                      max: (totalGridPages - 1).toDouble(),
                      value: sliderValue.clamp(0, (totalGridPages - 1).toDouble()),
                      divisions: totalGridPages > 1 ? totalGridPages - 1 : 1,
                      onChanged: (v) {
                        setState(() {
                          sliderValue = v;
                          gridPage = v.round();
                          gridCardENFace = List.filled(10, showENFace);
                        });
                      },
                      onChangeEnd: (v) {
                        setState(() {
                          gridPage = v.round();
                          showSlider = false;
                          gridCardENFace = List.filled(10, showENFace);
                        });
                      },
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
        );
      } else {
        // Single card mode: slider for words
        sliderOverlay = Positioned(
          left: 32,
          right: 32,
          bottom: 110,
          child: Material(
            color: Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Center(
                    child: Text(
                      '${(sliderValue + 1).toInt()}',
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
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                    ),
                    child: Slider(
                      min: 0,
                      max: (currentSetWords.length - 1).toDouble(),
                      value: sliderValue.clamp(0, (currentSetWords.length - 1).toDouble()),
                      divisions: currentSetWords.length > 1 ? currentSetWords.length - 1 : 1,
                      onChanged: (v) {
                        setState(() {
                          sliderValue = v;
                          currentIndex = v.round();
                        });
                      },
                      onChangeEnd: (v) {
                        setState(() {
                          currentIndex = v.round();
                          showSlider = false;
                        });
                      },
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
        );
      }
    } else {
      sliderOverlay = const SizedBox.shrink();
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
      top: 80,
      left: 0,
      right: 0,
      child: Visibility(
        visible: showSettingsMenu,
        // --- WRAP THE CONTAINER WITH A STATEFULBUILDER ---
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setMenuState) {
            return Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(34, 20, 34, 10),
              decoration: BoxDecoration(
                color: darkTheme ? const Color(0xFF397386) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
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
                  // Play icon left of label, black color
                  _settingsRow(
                    icon: Icon(Icons.play_arrow, size: 32, color: Colors.black),
                    label: 'random speaking',
                    value: randomSpeaking,
                    onChanged: (v) => setState(() => randomSpeaking = v),
                    darkTheme: darkTheme,
                  ),
                  const SizedBox(height: 18),
                  _settingsRow(
                    icon: SvgPicture.asset('assets/icons/DarkTheme.svg', width: 32, height: 32),
                    label: 'dark theme',
                    value: darkTheme,
                    onChanged: (v) => setState(() => darkTheme = v),
                    darkTheme: darkTheme,
                  ),
                  const SizedBox(height: 18),
                  _settingsRow(
                    // --- RESTORE SVG ICON ---
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
      backgroundColor: darkTheme ? const Color(0xFF397386) : Colors.white,
      body: Stack(
        clipBehavior: Clip.none, // This is correct, keep it.
        children: [
          // AppBar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              width: 360,
              height: 80,
              decoration: BoxDecoration(
                color: darkTheme ? const Color(0xFF1A237E) : const Color(0xFF1A237E),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      gridMode
                          ? 'Cards ${currentSetWords.isEmpty ? 0 : (gridPage * 10 + 1)} / ${currentSetWords.length}'
                          : 'Cards ${currentSetWords.isEmpty ? 0 : (currentIndex + 1)} / ${currentSetWords.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                        fontSize: 16,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          showSettingsMenu = !showSettingsMenu;
                        });
                      },
                      child: SvgPicture.asset(
                        'assets/icons/settings.svg',
                        width: 28,
                        height: 28,
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                      ),
                    ),
                    _WordsMenuButton(
                      groupedLists: getGroupedLists(),
                      currentLevel: selectedLevel,
                      currentSublist: selectedSublist,
                      onOpen: () {
                        setState(() {
                          // open panel with the current level active
                          panelActiveLevel = selectedLevel.isNotEmpty
                              ? selectedLevel
                              : (getGroupedLists().keys.isNotEmpty
                                  ? getGroupedLists().keys.first
                                  : '');
                          showWordsMenu = !showWordsMenu;
                          showSettingsMenu = false; // close settings if open
                        });
                      },
                      onSelect: (level, sublist) {
                        setState(() {
                          selectedLevel = level;
                          selectedSublist = sublist;
                          filterCurrentSet();
                         showWordsMenu = false; // close after choose
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Main content: single card or grid
          IgnorePointer(
            ignoring: showSettingsMenu || showWordsMenu, // Also ignore pointer when words menu is open
            child: Center(
              child: gridMode
                  ? gridView
                  : GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity != null) {
                          if (details.primaryVelocity! < 0) {
                            setState(() {
                              if (currentSetWords.isNotEmpty) {
                                currentIndex = (currentIndex + 1) % currentSetWords.length;
                              }
                              showENFace = widget.showENasDefault;
                            });
                          } else if (details.primaryVelocity! > 0) {
                            setState(() {
                              if (currentSetWords.isNotEmpty) {
                                currentIndex = (currentIndex - 1 + currentSetWords.length) % currentSetWords.length;
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
          // Slider overlay (for both modes)
          sliderOverlay,
          // Bottom bar
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 360,
              height: 85,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        gridMode = !gridMode;
                      });
                    },
                    child: SvgPicture.asset(
                      'assets/icons/Grid.svg',
                      width: 22.5,
                      height: 22.5,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      widget.onToggleDefault();
                      setState(() {
                        showENFace = !showENFace;
                        gridCardENFace = List.filled(10, showENFace);
                      });
                    },
                    child: Text(
                      showENFace ? 'EN' : 'UK',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1D),
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (!isPlaying) {
                        playSetWords();
                      } else {
                        stopPlaying();
                      }
                    },
                    child: SvgPicture.asset(
                      'assets/icons/Play circle.svg',
                      width: 25,
                      height: 25,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (currentSetWords.isNotEmpty) {
                        setState(() {
                          showSlider = true;
                          // Set sliderValue to current page or index
                          sliderValue = gridMode ? gridPage.toDouble() : currentIndex.toDouble();
                        });
                      }
                    },
                    child: SvgPicture.asset(
                      'assets/icons/Chevrons right.svg',
                      width: 24,
                      height: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // --- START: RESTRUCTURED MENU OVERLAYS ---

          // Words Menu Panel (and its backdrop)
          if (showWordsMenu) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => showWordsMenu = false),
                child: Container(color: Colors.black.withOpacity(0.1)),
              ),
            ),
            Positioned(
              top: 80 + 6,
              right: 16,
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
                child: Container(color: Colors.transparent), // Catches taps outside the menu
              ),
            ),
            // The settingsMenu variable is already a Positioned widget
            settingsMenu,
          ],
          
          // --- END: RESTRUCTURED MENU OVERLAYS ---
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

    // Remove the word from the in-memory list
    setState(() {
      allWords.removeWhere((entry) =>
          entry.sublist == selectedSublist &&
          entry.en.trim().toLowerCase() == word.en.trim().toLowerCase());
      filterCurrentSet();
    });

    // Save the updated custom lists
    final updatedCustomLists = allWords.where((entry) => entry.level == 'custom').toList();
    await _saveCustomListEntries(updatedCustomLists);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${word.en}" from custom list.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _addWordToCustomSet(WordEntry word) async {
    if (targetCustomSet.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No target list selected. Please choose one in Settings > Save to.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if the word already exists in the target custom list
    bool alreadyExists = allWords.any((entry) =>
        entry.sublist == targetCustomSet &&
        entry.en.trim().toLowerCase() == word.en.trim().toLowerCase());

    if (alreadyExists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${word.en}" is already in the target list.'),
          backgroundColor: Colors.blueGrey,
        ),
      );
      return;
    }

    final newEntry = WordEntry(
      'custom',
      targetCustomSet,
      word.en,
      word.uk,
      word.example1,
      word.example2,
    );

    // Save the new entry to persistent storage
    final existingCustomLists = await _loadCustomLists();
    await _saveCustomListEntries([...existingCustomLists, newEntry]);

    // --- START: MODIFICATION ---
    // Instead of reloading everything, just add the new word to the in-memory list
    // and update the state. This preserves the user's current view.
    setState(() {
      allWords.add(newEntry);
      // If the user is currently viewing the list they just saved to, refresh it.
      if (selectedLevel == 'custom' && selectedSublist == targetCustomSet) {
        filterCurrentSet();
      }
    });
    // --- END: MODIFICATION ---

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "${word.en}" to target list.'),
        backgroundColor: Colors.green,
      ),
    );

    // --- REMOVE THIS LINE ---
    // await loadWords(); // This was causing the reset.
  }

  Future<void> _saveCustomListEntries(List<WordEntry> allCustomEntries) async {
    final List<Map<String, String>> jsonList = allCustomEntries.map((entry) => {
      'level': entry.level,
      'sublist': entry.sublist,
      'en': entry.en,
      'uk': entry.uk,
      'example1': entry.example1,
      'example2': entry.example2,
    }).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_lists', jsonEncode(jsonList));
  }

  Widget _settingsRow({
    required Widget icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool darkTheme,
    bool isButton = false, // <-- Add this
  }) {
    return InkWell( // <-- Wrap with InkWell
      onTap: () => onChanged(!value),
      child: Padding( // <-- Add Padding
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
                  fontSize: 20,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // --- CHANGE THIS ---
            if (isButton)
              Icon(Icons.chevron_right, color: darkTheme ? Colors.white70 : Colors.black54)
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
                          child: Icon(Icons.check, color: Colors.white, size: 22),
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
                          color: darkTheme ? Colors.white : const Color(0xFF1E1E1E),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          fontSize: 20,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        currentTargetDisplayName,
                        style: TextStyle(
                          color: darkTheme ? Colors.white70 : Colors.black54,
                          fontSize: 14,
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
                  final displayName = listName.replaceFirst('list_custom_', '').replaceAll('_', ' ');
                  final isSelected = listName == targetCustomSet;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      displayName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? (darkTheme ? Colors.lightBlueAccent : Colors.blue.shade800)
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
                }).toList(),
                const Divider(),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add, color: Colors.green),
                  title: const Text(
                    'create',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
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

  void _showSaveToDialog() {
    final customLists = getGroupedLists()['custom'] ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Target List'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: customLists.length + 1, // Add 1 for the "Create New" option
            itemBuilder: (context, index) {
              // If it's the last item, show the "Create New" button
              if (index == customLists.length) {
                return ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.green),
                  title: const Text('Create New List...'),
                  onTap: () {
                    Navigator.pop(context); // Close the current dialog
                    _showCustomListDialog(setAsTarget: true); // Open create dialog and flag it to set as target
                  },
                );
              }

              // Otherwise, show an existing custom list
              final listName = customLists[index];
              final displayName = listName.replaceFirst('list_custom_', '').replaceAll('_', ' ');
              final isSelected = listName == targetCustomSet;
              return ListTile(
                title: Text(displayName),
                trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                onTap: () {
                  _setTargetCustomSet(listName);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
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

  Future<void> _createCustomList(String listName, String wordsText, {bool setAsTarget = false}) async {
  // Format list name
  String formattedListName = 'list_custom_${listName.replaceAll(' ', '_').toLowerCase()}';
  
  // --- ADD THIS BLOCK TO SAVE THE LIST NAME ---
  final prefs = await SharedPreferences.getInstance();
  final customListNames = prefs.getStringList('custom_list_names') ?? [];
  if (!customListNames.contains(formattedListName)) {
    customListNames.add(formattedListName);
    await prefs.setStringList('custom_list_names', customListNames);
  }
  // --- END OF BLOCK ---

  // Process the input text to get individual words
  List<String> words = wordsText
      .split(RegExp(r'[,\n\r\s]+')) // Split by comma, newline, or space
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();
  
  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Processing words...'),
        ],
      ),
    ),
  );
  
  try {
    List<WordEntry> newEntries = await _processWordsWithAPI(formattedListName, words);
    
    // Save the custom list
    final existingLists = await _loadCustomLists();
    await _saveCustomListEntries([...existingLists, ...newEntries]);
    
    // Close the loading dialog
    Navigator.pop(context);
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Custom list created: ${listName}')),
    );
    
    // Reload words to include new custom list
    await loadWords();
    
    // Select the new list
    setState(() {
      selectedLevel = 'custom';
      selectedSublist = formattedListName;
      if (setAsTarget) {
        targetCustomSet = formattedListName;
        _setTargetCustomSet(formattedListName); // Persist it
      }
      filterCurrentSet();
    });
    
  } catch (e) {
    // Close the loading dialog
    Navigator.pop(context);
    
    // Show error message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error creating list: ${e.toString()}')),
    );
  }
}

Future<List<WordEntry>> _processWordsWithAPI(String listName, List<String> words) async {
  final entries = <WordEntry>[];
  for (final word in words) {
    final translation = await translateToUkrainian(word);
    final example = await getExampleSentence(word);
    entries.add(WordEntry(
      'custom',
      listName,
      word.trim(),
      translation,
      example,   // example1
      '',        // example2
    ));
  }
  return entries;
}

Future<void> _saveCustomList(List<WordEntry> entries) async {
  final customLists = [...await _loadCustomLists(), ...entries];
  await _saveCustomListEntries(customLists);
}

Future<List<WordEntry>> _loadCustomLists() async {
  final prefs = await SharedPreferences.getInstance();
  final jsonData = prefs.getString('custom_lists');
  if (jsonData == null || jsonData.isEmpty) return [];

  try {
    // --- FIX THE TYPO ON THIS LINE ---
    final List<dynamic> jsonList = jsonDecode(jsonData);
    return jsonList.map<WordEntry>((json) => WordEntry(
      (json['level'] ?? '').toString(),
      (json['sublist'] ?? '').toString(),
      (json['en'] ?? '').toString(),
      (json['uk'] ?? '').toString(),
      (json['example1'] ?? '').toString(),
      (json['example2'] ?? '').toString(),
    )).toList();
  } catch (e) {
    print('Error loading custom lists: $e');
    return [];
  }
}

void _showDeleteCustomListDialog(String listName) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete Custom List'),
      content: Text('Are you sure you want to delete "$listName"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            _deleteCustomList(listName);
            Navigator.pop(context);
          },
          child: Text('Delete'),
        ),
      ],
    ),
  );
}

Future<void> _deleteCustomList(String listName) async {
  // Get existing custom lists
  List<WordEntry> customLists = await _loadCustomLists();
  
  // Filter out the list to delete
  customLists = customLists.where((entry) => entry.sublist != listName).toList();
  
  // --- ADD THIS BLOCK TO REMOVE THE LIST NAME ---
  final prefs = await SharedPreferences.getInstance();
  final customListNames = prefs.getStringList('custom_list_names') ?? [];
  customListNames.remove(listName);
  await prefs.setStringList('custom_list_names', customListNames);
  // --- END OF BLOCK ---

  // Convert to JSON and save
  await _saveCustomListEntries(customLists);
  
  // Reload all words
  await loadWords();
}

Future<void> loadDictionary() async {
  try {
    // --- FIX THE PATH HERE ---
    final rawDict = await rootBundle.loadString('assets/en_uk_dictionary.csv');
    List<List<dynamic>> dictTable = const CsvToListConverter().convert(rawDict, eol: '\n');
    
    // Create a map for fast lookups
    for (var row in dictTable.skip(1)) {
      if (row.length >= 2) {
        enUkDictionary[row[0].toString().toLowerCase()] = row[1].toString();
      }
    }
    print('Dictionary loaded with ${enUkDictionary.length} entries');
  } catch (e) {
    print('Dictionary file not found, using online translation only');
  }
}

// Then update the translation function
String translateFromDictionary(String word) {
  return enUkDictionary[word.toLowerCase()] ?? '[ Переклад відсутній ]';
}

// ADD: helpers inside the state + close the state class

// Try local dictionary first; fallback keeps UI working.
// Swap this for a real API later if needed.
Future<String> translateToUkrainian(String englishWord) async {
  final local = translateFromDictionary(englishWord);
  if (local != '[ Переклад відсутній ]') return local;
  return englishWord;
}

// Placeholder example generator for custom lists.
Future<String> getExampleSentence(String word) async {
  return 'They archived the $word for future use.';
}

// Helpers to sort "listN" numerically
int? _extractListNumber(String s) {
  final m = RegExp(r'^list[_\s]*0*([0-9]+)$', caseSensitive: false).firstMatch(s.trim());
  return m == null ? null : int.tryParse(m.group(1)!);
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
  final customListNames = allCustomListNames; // Assuming allCustomListNames is loaded elsewhere
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

// CLOSE the _FlashcardScreenState so the next classes are top‑level
}

class _WordsMenuButton extends StatefulWidget {
  final Map<String, List<String>> groupedLists;
  final String currentLevel;
  final String currentSublist;
  final void Function(String level, String sublist) onSelect;
  final VoidCallback onOpen;

  const _WordsMenuButton({
    Key? key,
    required this.groupedLists,
    required this.currentLevel,
    required this.currentSublist,
    required this.onSelect,
    required this.onOpen,
  }) : super(key: key);

  @override
  State<_WordsMenuButton> createState() => _WordsMenuButtonState();
}

class _WordsMenuButtonState extends State<_WordsMenuButton> {
  String? openLevel;

  int _levelOrderIndex(String level) {
    final order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'custom'];
    final idx = order.indexOf(level.toUpperCase());
    return idx == -1 ? 1000 : idx;
  }

  int? _extractListNumber(String s) {
    final m = RegExp(r'^list[_\s]*0*([0-9]+)$', caseSensitive: false).firstMatch(s.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
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
    final n = _extractListNumber(s);
    if (n != null) return 'L$n';

    // Handle custom lists like 'list_custom_my_favorites' -> 'My Favorites'
    if (s.startsWith('list_custom_')) {
      return s
          .substring(12)
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
          .join(' ');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final String labelLevel;
    if (widget.currentLevel == 'custom') {
      labelLevel = ''; // Don't show "custom" for custom lists
    } else {
      labelLevel = widget.currentLevel.isNotEmpty ? widget.currentLevel.toUpperCase() : 'All';
    }

    final labelSublist = _fmtSub(widget.currentSublist);

    return InkWell(
      onTap: widget.onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF3949AB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$labelLevel $labelSublist',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _MenuChoice {
  final String level;
  final String sublist;
  const _MenuChoice(this.level, this.sublist);
}

// Minimal splash so '/' route compiles and redirects
class HomeSplashPage extends StatelessWidget {
  const HomeSplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    Future.microtask(() {
      Navigator.of(context).pushReplacementNamed('/flashcards');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _WordsMenuPanel extends StatefulWidget {
  final Map<String, List<String>> groupedLists;
  final String activeLevel;        // which level’s sublists to show
  final String currentLevel;       // currently selected level
  final String currentSublist;     // currently selected sublist
  final ValueChanged<String> onChangeLevel;
  final void Function(String level, String sublist) onSelect;

  const _WordsMenuPanel({
    Key? key,
    required this.groupedLists,
    required this.activeLevel,
    required this.currentLevel,
    required this.currentSublist,
    required this.onChangeLevel,
    required this.onSelect,
  }) : super(key: key);

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
    final m = RegExp(r'^list[_\s]*0*([0-9]+)$', caseSensitive: false).firstMatch(s.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
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
    final n = _extractListNumber(s);
    if (n != null) return 'L$n';

    // Handle custom lists like 'list_custom_my_favorites' -> 'My Favorites'
    if (s.startsWith('list_custom_')) {
      return s
          .substring(12)
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
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

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 420,
        height: 420,
        decoration: BoxDecoration(
          color: const Color(0xFFF4EFFA),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // Levels column
            SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
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
                      itemCount: levels.length,
                      itemBuilder: (_, i) {
                        final lvl = levels[i];
                        final selected = lvl == activeLevel;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          leading: selected ? const Icon(Icons.arrow_right, color: Colors.blue) : null,
                          title: Text(
                            lvl,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
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
            const VerticalDivider(width: 1),
            // Sublists column (only of active level)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
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
                        final selected = activeLevel == widget.currentLevel && sub == widget.currentSublist;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          title: Text(
                            _fmtSub(sub),
                            style: TextStyle(
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? Colors.blueGrey.shade900 : Colors.black87,
                            ),
                          ),
                          // --- ADD THIS DELETE BUTTON FOR CUSTOM LISTS ---
                          trailing: activeLevel == 'custom'
                              ? IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                                  onPressed: () {
                                    // Find the state and call the delete method
                                    final screenState = context.findAncestorStateOfType<_FlashcardScreenState>();
                                    screenState?._showDeleteCustomListDialog(sub);
                                  },
                                )
                              : (selected ? const Icon(Icons.check, color: Colors.blueGrey) : null),
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