import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:csv/csv.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_book.dart';
import '../models/word_entry.dart';
import '../services/document_text_extractor.dart';
import 'reader_strings.dart';

class ReaderScreen extends StatefulWidget {
  final bool darkTheme;
  final String studyLang;
  final String nativeLang;

  const ReaderScreen({
    super.key,
    required this.darkTheme,
    required this.studyLang,
    required this.nativeLang,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  ReaderStrings get _strings => ReaderStrings(widget.nativeLang);
  String _t(ReaderText key) => _strings.text(key);
  bool _isLoading = true;
  final Map<String, String> _dictionary = {};
  final Map<String, String> _onlineTranslationCache = {};
  List<String> _customListNames = [];
  String _selectedCustomList = '';
  late TabController _tabController;
  final FlutterTts _flutterTts = FlutterTts();

  // Custom text input
  final TextEditingController _customTextController = TextEditingController();
  bool _isReadingCustomText = false;
  String _customTextToRead = '';
  bool _isImportingDocument = false;
  String? _importedDocumentName;

  // Predefined stories
  final List<Map<String, String>> _stories = [
    {
      'title': 'The Lost Key',
      'level': 'A2',
      'content':
          'One sunny morning, Lily found an old, rusty key in her garden. It was lying under a big rose bush. She wondered what it opened. She ran to her grandmother and showed it to her. Her grandmother smiled and told her about an old wooden chest in the attic. Lily was very excited and went upstairs to search for the chest. In a dark corner of the attic, she found it covered in dust. She inserted the key, turned it with a click, and the box opened slowly. Inside, she found old photographs and a beautiful silver pocket watch.',
    },
    {
      'title': 'The Mysterious Traveler',
      'level': 'B2',
      'content':
          'A mysterious traveler arrived in the quiet valley just as the sun set behind the mountains. He wore a long dark coat and carried a wooden suitcase covered in strange symbols. The locals watched him from behind their curtains with curiosity and suspicion. He checked into the only inn at the edge of the town. During the night, strange melodies drifted from his room, played on an instrument no one had ever seen before. The next morning, he disappeared, leaving the suitcase behind. When the innkeeper opened it, he found only a collection of glowing blue stones and a map of the stars.',
    },
    {
      'title': 'The Future of AI',
      'level': 'C1',
      'content':
          'The rapid evolution of artificial intelligence has sparked intense debates across global industries. Critics argue that unchecked development could lead to widespread labor displacement and reinforce systemic biases embedded in training datasets. Conversely, proponents emphasize the transformative potential of machine learning systems in accelerating scientific discoveries, optimizing energy grids, and providing personalized education. As the boundary between human capability and algorithmic automation blurs, establishing robust ethical guidelines and regulatory frameworks becomes imperative to ensure that technological progress aligns with human values.',
    },
  ];

  int _selectedStoryIndex = 0;
  int _selectedChapterIndex = 0;
  Future<ReaderBook>? _selectedBook;
  SharedPreferences? _preferences;
  int? _lastBookId;
  int _initialParagraph = 0;
  int _selectionGeneration = 0;
  GlobalKey<_BookChapterViewState> _chapterViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeScreen();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customTextController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadDictionary();
    await _loadCustomListInfo();
    _preferences = await SharedPreferences.getInstance();
    _lastBookId = _preferences!.getInt('reader_last_book_id');
    _flutterTts.setLanguage(widget.studyLang);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  ({int chapter, int paragraph}) _bookProgress(int bookId) {
    try {
      final raw = _preferences?.getString('reader_book_progress_$bookId');
      if (raw == null) return (chapter: 0, paragraph: 0);
      final data = jsonDecode(raw);
      if (data is Map && data['chapter'] is int && data['paragraph'] is int) {
        return (
          chapter: data['chapter'] as int,
          paragraph: data['paragraph'] as int
        );
      }
    } catch (_) {
      // Ignore obsolete or damaged local progress.
    }
    return (chapter: 0, paragraph: 0);
  }

  void _saveBookProgress(int bookId, int chapter, int paragraph) {
    _preferences?.setString('reader_book_progress_$bookId',
        jsonEncode({'chapter': chapter, 'paragraph': paragraph}));
  }

  Future<void> _selectStory(int index) async {
    _chapterViewKey.currentState?._savePosition();
    final generation = ++_selectionGeneration;
    if (index < _stories.length) {
      setState(() {
        _selectedStoryIndex = index;
        _selectedBook = null;
      });
      return;
    }
    final info = ReaderBookInfo.englishBooks[index - _stories.length];
    final bookFuture = ReaderBook.load(info);
    setState(() {
      _selectedStoryIndex = index;
      _selectedChapterIndex = 0;
      _initialParagraph = 0;
      _selectedBook = bookFuture;
      _chapterViewKey = GlobalKey();
    });
    try {
      final book = await bookFuture;
      if (!mounted || generation != _selectionGeneration) return;
      final progress = _bookProgress(info.id);
      final chapter = progress.chapter.clamp(0, book.chapters.length - 1);
      final paragraph = progress.paragraph
          .clamp(0, book.chapters[chapter].paragraphs.length - 1);
      setState(() {
        _selectedChapterIndex = chapter;
        _initialParagraph = paragraph;
        _lastBookId = info.id;
        _chapterViewKey = GlobalKey();
      });
      _preferences?.setInt('reader_last_book_id', info.id);
      _saveBookProgress(info.id, chapter, paragraph);
    } catch (_) {
      // FutureBuilder displays the localized load error.
    }
  }

  // Load word mappings from study to native language CSV files
  Future<void> _loadDictionary() async {
    try {
      final studyPath = 'assets/data/sets/${widget.studyLang}.csv';
      final nativePath = 'assets/data/sets/${widget.nativeLang}.csv';

      final ByteData studyBytes = await rootBundle.load(studyPath);
      final ByteData nativeBytes = await rootBundle.load(nativePath);

      final String studyData =
          utf8.decode(studyBytes.buffer.asUint8List(), allowMalformed: true);
      final String nativeData =
          utf8.decode(nativeBytes.buffer.asUint8List(), allowMalformed: true);

      List<List<dynamic>> parseCsv(String data) {
        List<List<dynamic>> table = const CsvToListConverter().convert(data);
        if (table.length > 1) return table;
        table = const CsvToListConverter(eol: '\n').convert(data);
        if (table.length > 1) return table;
        final normalized = data.replaceAll('\r', '\n');
        return const CsvToListConverter(eol: '\n').convert(normalized);
      }

      final studyTable = parseCsv(studyData);
      final nativeTable = parseCsv(nativeData);
      final int rows = math.min(studyTable.length, nativeTable.length);

      for (int i = 1; i < rows; i++) {
        final sRow = studyTable[i];
        final nRow = nativeTable[i];
        if (sRow.length < 3 || nRow.length < 3) continue;

        String engWord = sRow[2].toString().toLowerCase().trim();
        String natWord = nRow[2].toString().trim();

        if (engWord.isNotEmpty && natWord.isNotEmpty) {
          _dictionary[engWord] = natWord;
        }

        // Map synonym if available
        if (sRow.length > 3 && nRow.length > 3) {
          String engSyn = sRow[3].toString().toLowerCase().trim();
          String natSyn = nRow[3].toString().trim();
          if (engSyn.isNotEmpty && natSyn.isNotEmpty) {
            _dictionary[engSyn] = natSyn;
          }
        }
      }
      debugPrint(
          'Reader dictionary loaded with ${_dictionary.length} entries.');
    } catch (e) {
      debugPrint('Error loading dictionary in Reader: $e');
    }
  }

  // Load custom list names and the selected target custom list
  Future<void> _loadCustomListInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _customListNames = prefs.getStringList('custom_list_names') ?? [];
      _selectedCustomList = prefs.getString('targetCustomSet') ?? '';

      if (_selectedCustomList.isEmpty && _customListNames.isNotEmpty) {
        _selectedCustomList = _customListNames.first;
      }
    });
  }

  Future<void> _importDocument() async {
    if (_isImportingDocument) return;

    setState(() => _isImportingDocument = true);
    try {
      final imported = await DocumentTextExtractor.pickAndExtract();
      if (!mounted || imported == null) return;

      setState(() {
        _customTextController.text = imported.text;
        _customTextToRead = imported.text;
        _importedDocumentName = imported.name;
        _isReadingCustomText = true;
      });
    } on DocumentTextExtractionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_strings.documentError(error.error)),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(ReaderText.importFailed)),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isImportingDocument = false);
      }
    }
  }

  // Stemming-based word translation lookup
  String? _lookupTranslation(String word) {
    final clean =
        word.toLowerCase().replaceAll(RegExp(r"[^\w\s\'-]"), "").trim();
    if (clean.isEmpty) return null;

    if (_dictionary.containsKey(clean)) {
      return _dictionary[clean];
    }

    // Stemming heuristic for plurals (ends with s / es)
    if (clean.endsWith('s') && clean.length > 2) {
      final stem = clean.substring(0, clean.length - 1);
      if (_dictionary.containsKey(stem)) return _dictionary[stem];
      if (clean.endsWith('es') && clean.length > 3) {
        final stemEs = clean.substring(0, clean.length - 2);
        if (_dictionary.containsKey(stemEs)) return _dictionary[stemEs];
      }
    }

    // Stemming heuristic for past tense (ends with ed / d)
    if (clean.endsWith('ed') && clean.length > 3) {
      final stem = clean.substring(0, clean.length - 2);
      if (_dictionary.containsKey(stem)) return _dictionary[stem];
      final stemD = clean.substring(0, clean.length - 1);
      if (_dictionary.containsKey(stemD)) return _dictionary[stemD];
      // Double consonant rule (e.g. stopped -> stop)
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        final stemDouble = stem.substring(0, stem.length - 1);
        if (_dictionary.containsKey(stemDouble)) return _dictionary[stemDouble];
      }
    }

    // Stemming heuristic for continuous tense (ends with ing)
    if (clean.endsWith('ing') && clean.length > 4) {
      final stemE = '${clean.substring(0, clean.length - 3)}e';
      if (_dictionary.containsKey(stemE)) return _dictionary[stemE];
      final stem = clean.substring(0, clean.length - 3);
      if (_dictionary.containsKey(stem)) return _dictionary[stem];
      // Double consonant rule (e.g. running -> run)
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        final stemDouble = stem.substring(0, stem.length - 1);
        if (_dictionary.containsKey(stemDouble)) return _dictionary[stemDouble];
      }
    }

    // Stemming heuristic for adverbs (ends with ly)
    if (clean.endsWith('ly') && clean.length > 3) {
      final stem = clean.substring(0, clean.length - 2);
      if (_dictionary.containsKey(stem)) return _dictionary[stem];
    }

    return null;
  }

  Future<String?> _translateWordOnline(String word) async {
    final cleaned = word.trim();
    if (cleaned.isEmpty) return null;

    final from = widget.studyLang.trim().toLowerCase();
    final to = widget.nativeLang.trim().toLowerCase();
    if (from.isEmpty || to.isEmpty || from == to) return null;

    final cacheKey = '$from:$to:${cleaned.toLowerCase()}';
    final cached = _onlineTranslationCache[cacheKey];
    if (cached != null) return cached;

    try {
      final uri = Uri.https(
        'translate.googleapis.com',
        '/translate_a/single',
        {
          'client': 'gtx',
          'sl': from,
          'tl': to,
          'dt': 't',
          'q': cleaned,
        },
      );

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
        },
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
        return null;
      }

      final translated = (decoded.first as List)
          .whereType<List>()
          .map((segment) => segment.isNotEmpty ? segment.first.toString() : '')
          .join()
          .trim();

      if (translated.isEmpty ||
          translated.toLowerCase() == cleaned.toLowerCase()) {
        return null;
      }

      _onlineTranslationCache[cacheKey] = translated;
      return translated;
    } catch (e) {
      debugPrint('Reader online translation failed: $e');
      return null;
    }
  }

  // Split paragraph into words and build clickable spans
  List<TextSpan> _buildTextSpans(String text, BuildContext context) {
    final List<TextSpan> spans = [];
    final RegExp regex = RegExp(r"([a-zA-Z\x27\-]+)|([^a-zA-Z\x27\-]+)");
    final matches = regex.allMatches(text);

    final wordStyle = TextStyle(
      color: widget.darkTheme ? Colors.white : const Color(0xFF1E1E1E),
      fontSize: 20,
      fontFamily: 'Inter',
      height: 1.6,
    );

    final punctuationStyle = TextStyle(
      color: widget.darkTheme ? Colors.white60 : Colors.black87,
      fontSize: 20,
      fontFamily: 'Inter',
      height: 1.6,
    );

    for (final match in matches) {
      final String matchText = match.group(0) ?? '';
      final bool isWord = match.group(1) != null;

      if (isWord) {
        spans.add(
          TextSpan(
            text: matchText,
            style: wordStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _showTranslationSheet(matchText),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: matchText,
            style: punctuationStyle,
          ),
        );
      }
    }
    return spans;
  }

  // Handle speaker audio pronunciation of word
  Future<void> _speakWord(String word) async {
    await _flutterTts.speak(word);
  }

  // Display translation bottom sheet modal
  void _showTranslationSheet(String rawWord) {
    final cleanWord = rawWord.replaceAll(RegExp(r"[^\w\s\'-]"), "").trim();
    if (cleanWord.isEmpty) return;

    final String? translation = _lookupTranslation(cleanWord);
    final String initialTranslation = translation ?? '';

    final TextEditingController translationController =
        TextEditingController(text: initialTranslation);
    bool onlineLookupStarted = false;
    bool isOnlineTranslating = false;
    String? onlineTranslationError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (translation == null && !onlineLookupStarted) {
              onlineLookupStarted = true;
              isOnlineTranslating = true;
              _translateWordOnline(cleanWord).then((onlineTranslation) {
                if (!mounted) return;
                setSheetState(() {
                  isOnlineTranslating = false;
                  if (onlineTranslation != null &&
                      onlineTranslation.isNotEmpty) {
                    translationController.text = onlineTranslation;
                    onlineTranslationError = null;
                  } else {
                    onlineTranslationError =
                        _t(ReaderText.translationUnavailable);
                  }
                });
              });
            }

            final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final sheetBgColor = widget.darkTheme
                ? const Color(0xFF1F2B3B)
                : const Color(0xFFFDFBFF);
            final titleStyle = TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: widget.darkTheme ? Colors.white : const Color(0xFF1A237E),
              fontFamily: 'Inter',
            );
            final labelStyle = TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: widget.darkTheme ? Colors.white70 : Colors.black54,
              fontFamily: 'Inter',
            );

            return Container(
              margin: EdgeInsets.only(top: 80, bottom: bottomInset),
              decoration: BoxDecoration(
                color: sheetBgColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color:
                            widget.darkTheme ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          cleanWord,
                          style: titleStyle,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.volume_up, size: 28),
                        color: widget.darkTheme
                            ? Colors.lightBlueAccent
                            : const Color(0xFF1A237E),
                        onPressed: () => _speakWord(cleanWord),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(_t(ReaderText.translation), style: labelStyle),
                  const SizedBox(height: 8),
                  TextField(
                    controller: translationController,
                    cursorColor: widget.darkTheme
                        ? Colors.white
                        : const Color(0xFF1A237E),
                    style: TextStyle(
                      fontSize: 18,
                      color: widget.darkTheme ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: _t(ReaderText.translationHint),
                      hintStyle: TextStyle(
                        color:
                            widget.darkTheme ? Colors.white38 : Colors.black38,
                      ),
                      filled: true,
                      fillColor: widget.darkTheme
                          ? const Color(0xFF2C3E50)
                          : const Color(0xFFF1F3F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  if (isOnlineTranslating ||
                      onlineTranslationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      isOnlineTranslating
                          ? _t(ReaderText.translating)
                          : onlineTranslationError!,
                      style: TextStyle(
                        fontSize: 13,
                        color: isOnlineTranslating
                            ? (widget.darkTheme
                                ? Colors.white54
                                : Colors.black54)
                            : Colors.orange,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(_t(ReaderText.targetList), style: labelStyle),
                  const SizedBox(height: 8),
                  if (_customListNames.isEmpty) ...[
                    Text(
                      _t(ReaderText.noLists),
                      style: TextStyle(
                        color:
                            widget.darkTheme ? Colors.white54 : Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: widget.darkTheme
                            ? const Color(0xFF2C3E50)
                            : const Color(0xFFF1F3F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCustomList.isNotEmpty &&
                                  _customListNames.contains(_selectedCustomList)
                              ? _selectedCustomList
                              : null,
                          dropdownColor: sheetBgColor,
                          hint: Text(
                            _t(ReaderText.selectList),
                            style: TextStyle(
                              color: widget.darkTheme
                                  ? Colors.white38
                                  : Colors.black38,
                            ),
                          ),
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: widget.darkTheme
                                ? Colors.white70
                                : Colors.black54,
                          ),
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 18,
                            color: widget.darkTheme
                                ? Colors.white
                                : Colors.black87,
                          ),
                          items: _customListNames.map((String listName) {
                            final displayName = listName
                                .replaceFirst('list_custom_', '')
                                .replaceAll('_', ' ');
                            return DropdownMenuItem<String>(
                              value: listName,
                              child: Text(displayName),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setSheetState(() {
                                _selectedCustomList = newValue;
                              });
                              setState(() {}); // Sync to parent screen state
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Button to create a new list
                  TextButton.icon(
                    onPressed: () => _showCreateListDialog(setSheetState),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(_t(ReaderText.createList),
                        style: const TextStyle(fontSize: 16)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final trans = translationController.text.trim();
                      if (trans.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_t(ReaderText.enterTranslation)),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      _saveWordToCustomList(cleanWord, trans);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF2E7D32), // Green save button
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _t(ReaderText.saveWord),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Create new custom list dialog
  void _showCreateListDialog(StateSetter setSheetState) {
    final TextEditingController newListNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.darkTheme
            ? const Color(0xFF2C3E50)
            : const Color(0xFFFDFBFF),
        title: Text(
          _t(ReaderText.createListTitle),
          style: TextStyle(
            color: widget.darkTheme ? Colors.white : Colors.black87,
          ),
        ),
        content: TextField(
          controller: newListNameController,
          autofocus: true,
          cursorColor:
              widget.darkTheme ? Colors.white : const Color(0xFF1A237E),
          style: TextStyle(
            color: widget.darkTheme ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: _t(ReaderText.listNameHint),
            hintStyle: TextStyle(
              color: widget.darkTheme ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(_t(ReaderText.cancel),
                style: const TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text(_t(ReaderText.create),
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final name = newListNameController.text.trim();
              final navigator = Navigator.of(context);
              if (name.isNotEmpty) {
                final formatted =
                    'list_custom_${name.replaceAll(' ', '_').toLowerCase()}';
                final prefs = await SharedPreferences.getInstance();
                final list = prefs.getStringList('custom_list_names') ?? [];
                if (!list.contains(formatted)) {
                  list.add(formatted);
                  await prefs.setStringList('custom_list_names', list);
                  await prefs.setString('targetCustomSet', formatted);

                  // Update parent screen state
                  setState(() {
                    _customListNames = list;
                    _selectedCustomList = formatted;
                  });
                  // Update bottom sheet state
                  setSheetState(() {
                    _selectedCustomList = formatted;
                  });
                }
              }
              navigator.pop();
            },
          ),
        ],
      ),
    );
  }

  // Save the custom word using identical architecture from flashcards_screen.dart
  Future<void> _saveWordToCustomList(String word, String translation) async {
    if (_selectedCustomList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(ReaderText.noTargetList)),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 1. Load existing custom entries
    final jsonData = prefs.getString('custom_lists');
    List<WordEntry> customEntries = [];
    if (jsonData != null && jsonData.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonData);
        customEntries = jsonList
            .map<WordEntry>((json) => WordEntry(
                  (json['level'] ?? '').toString(),
                  (json['sublist'] ?? '').toString(),
                  (json['wordMain'] ?? json['en'] ?? '').toString(),
                  (json['trans1'] ?? json['uk'] ?? '').toString(),
                  (json['example1'] ?? '').toString(),
                  (json['example2'] ?? '').toString(),
                  '',
                  '',
                  (json['wordSyn'] ?? '').toString(),
                  (json['trans2'] ?? '').toString(),
                ))
            .toList();
      } catch (e) {
        debugPrint('Error decoding custom list inside Reader: $e');
      }
    }

    // 2. Check for duplicate word in the same custom list
    final hasDuplicate = customEntries.any((entry) =>
        entry.sublist == _selectedCustomList &&
        entry.wordMain.trim().toLowerCase() == word.trim().toLowerCase());

    if (hasDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_t(ReaderText.duplicateWord).replaceAll('{word}', word)),
          backgroundColor: Colors.blueGrey,
        ),
      );
      return;
    }

    // 3. Construct new entry
    final newEntry = WordEntry(
      'custom',
      _selectedCustomList,
      word.trim(),
      translation.trim(),
      'They archived the $word for future use.', // default example
      '',
      '',
      '',
      '',
      '',
    );

    customEntries.add(newEntry);

    // 4. Save back to SharedPreferences
    final List<Map<String, String>> jsonList = customEntries
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

    await prefs.setString('custom_lists', jsonEncode(jsonList));

    // Keep active list as target custom set
    await prefs.setString('targetCustomSet', _selectedCustomList);

    if (!mounted) return;
    final cleanListName = _selectedCustomList
        .replaceFirst('list_custom_', '')
        .replaceAll('_', ' ');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(ReaderText.savedWord)
            .replaceAll('{word}', word)
            .replaceAll('{list}', cleanListName)),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildBookReader(
      Color cardColor, Color primaryColor, TextStyle textStyle) {
    return FutureBuilder<ReaderBook>(
      future: _selectedBook,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
              child: Text(_t(ReaderText.bookLoadFailed), style: textStyle));
        }
        final chapters = snapshot.data!.chapters;
        final chapter = chapters[_selectedChapterIndex];
        final bookId = ReaderBookInfo
            .englishBooks[_selectedStoryIndex - _stories.length].id;
        final storyIndex = _selectedStoryIndex;
        final chapterIndex = _selectedChapterIndex;
        void selectChapter(int index) {
          _chapterViewKey.currentState?._savePosition();
          _saveBookProgress(bookId, index, 0);
          setState(() {
            _selectedChapterIndex = index;
            _initialParagraph = 0;
            _chapterViewKey = GlobalKey();
          });
        }

        return Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: _t(ReaderText.previousChapter),
                  onPressed: _selectedChapterIndex == 0
                      ? null
                      : () => selectChapter(_selectedChapterIndex - 1),
                  icon: const Icon(Icons.chevron_left),
                  color: primaryColor,
                ),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedChapterIndex,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      style: textStyle.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      items: List.generate(
                          chapters.length,
                          (index) => DropdownMenuItem(
                                value: index,
                                child: Text(chapters[index].title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              )),
                      onChanged: (index) {
                        if (index != null) selectChapter(index);
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _t(ReaderText.nextChapter),
                  onPressed: _selectedChapterIndex + 1 >= chapters.length
                      ? null
                      : () => selectChapter(_selectedChapterIndex + 1),
                  icon: const Icon(Icons.chevron_right),
                  color: primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(
                    'book-$_selectedStoryIndex-chapter-$_selectedChapterIndex-start-$_initialParagraph'),
                child: _BookChapterView(
                  key: _chapterViewKey,
                  paragraphs: chapter.paragraphs,
                  initialParagraph: _initialParagraph,
                  darkTheme: widget.darkTheme,
                  buildSpans: (text) => _buildTextSpans(text, context),
                  nextChapterLabel: _t(ReaderText.nextChapter),
                  onNextChapter: chapterIndex + 1 >= chapters.length
                      ? null
                      : () => selectChapter(chapterIndex + 1),
                  onPositionChanged: (paragraph) {
                    if (_selectedStoryIndex == storyIndex &&
                        _selectedChapterIndex == chapterIndex) {
                      _saveBookProgress(bookId, chapterIndex, paragraph);
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.darkTheme ? const Color(0xFF1E2A3A) : const Color(0xFFF5F6FA);
    final cardColor = widget.darkTheme ? const Color(0xFF2C3E50) : Colors.white;
    final primaryColor =
        widget.darkTheme ? Colors.lightBlueAccent : const Color(0xFF1E3A8A);
    final contentTextColor =
        widget.darkTheme ? Colors.white : const Color(0xFF172033);
    final mutedTextColor =
        widget.darkTheme ? Colors.white70 : const Color(0xFF4B5563);
    final hintTextColor =
        widget.darkTheme ? Colors.white60 : const Color(0xFF64748B);
    final textStyle = TextStyle(
      color: contentTextColor,
      fontFamily: 'Inter',
    );

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: Text(
            _t(ReaderText.title),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor:
              widget.darkTheme ? const Color(0xFF1A237E) : primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(_t(ReaderText.title),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor:
            widget.darkTheme ? const Color(0xFF1A237E) : primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: [
            Tab(text: _t(ReaderText.stories)),
            Tab(text: _t(ReaderText.customText)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Predefined Stories View
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Predefined Story Selector Dropdown
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedStoryIndex,
                      dropdownColor: cardColor,
                      isExpanded: true,
                      style: textStyle.copyWith(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      icon: Icon(Icons.arrow_drop_down, color: primaryColor),
                      items: [
                        ...List.generate(_stories.length, (index) {
                          final story = _stories[index];
                          final difficulty = switch (story['level']) {
                            'A2' => ReaderText.easy,
                            'B2' => ReaderText.medium,
                            _ => ReaderText.advanced,
                          };
                          return DropdownMenuItem<int>(
                            value: index,
                            child: Text(
                              '${story['title']} (${_t(difficulty)} - ${story['level']})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                        if (widget.studyLang == 'en')
                          ...ReaderBookInfo.englishBooks.asMap().entries.map(
                                (entry) => DropdownMenuItem<int>(
                                  value: _stories.length + entry.key,
                                  child: Text(
                                    '${entry.value.title} — ${entry.value.author}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                      ],
                      onChanged: (int? newValue) {
                        if (newValue != null) _selectStory(newValue);
                      },
                    ),
                  ),
                ),
                if (widget.studyLang == 'en' &&
                    _lastBookId != null &&
                    ReaderBookInfo.englishBooks
                        .any((b) => b.id == _lastBookId) &&
                    (_selectedStoryIndex < _stories.length ||
                        ReaderBookInfo
                                .englishBooks[
                                    _selectedStoryIndex - _stories.length]
                                .id !=
                            _lastBookId))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _selectStory(_stories.length +
                            ReaderBookInfo.englishBooks
                                .indexWhere((b) => b.id == _lastBookId)),
                        icon: const Icon(Icons.bookmark_outline),
                        label: Text(_t(ReaderText.continueReading)),
                      ),
                    ),
                  ),
                // Story text reader area
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _selectedBook != null
                        ? _buildBookReader(cardColor, primaryColor, textStyle)
                        : SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t(ReaderText.tip),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: mutedTextColor,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                RichText(
                                  text: TextSpan(
                                    children: _buildTextSpans(
                                        _stories[_selectedStoryIndex]
                                            ['content']!,
                                        context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),

            // Custom Text View
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isReadingCustomText
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isReadingCustomText = false;
                            });
                          },
                          icon: const Icon(Icons.edit, color: Colors.white),
                          label: Text(_t(ReaderText.editText),
                              style: const TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: RichText(
                                text: TextSpan(
                                  children: _buildTextSpans(
                                      _customTextToRead, context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(ReaderText.customTextPrompt),
                          style: textStyle.copyWith(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed:
                                _isImportingDocument ? null : _importDocument,
                            icon: _isImportingDocument
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryColor,
                                    ),
                                  )
                                : const Icon(Icons.upload_file_outlined),
                            label: Text(
                              _isImportingDocument
                                  ? _t(ReaderText.importing)
                                  : _t(ReaderText.importFile),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        if (_importedDocumentName != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _importedDocumentName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedTextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Expanded(
                          child: TextField(
                            controller: _customTextController,
                            maxLines: null,
                            expands: true,
                            cursorColor: primaryColor,
                            style: TextStyle(
                              color: contentTextColor,
                              fontSize: 18,
                            ),
                            decoration: InputDecoration(
                              hintText: _t(ReaderText.textHint),
                              hintStyle: TextStyle(
                                color: hintTextColor,
                              ),
                              filled: true,
                              fillColor: cardColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: widget.darkTheme
                                      ? Colors.white12
                                      : Colors.black12,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide:
                                    BorderSide(color: primaryColor, width: 2),
                              ),
                              contentPadding: const EdgeInsets.all(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            final text = _customTextController.text.trim();
                            if (text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_t(ReaderText.emptyText)),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _customTextToRead = text;
                              _isReadingCustomText = true;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF15803D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            _t(ReaderText.readText),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
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

class _BookChapterView extends StatefulWidget {
  const _BookChapterView({
    super.key,
    required this.paragraphs,
    required this.initialParagraph,
    required this.darkTheme,
    required this.buildSpans,
    required this.nextChapterLabel,
    required this.onNextChapter,
    required this.onPositionChanged,
  });

  final List<String> paragraphs;
  final int initialParagraph;
  final bool darkTheme;
  final List<TextSpan> Function(String) buildSpans;
  final String nextChapterLabel;
  final VoidCallback? onNextChapter;
  final ValueChanged<int> onPositionChanged;

  @override
  State<_BookChapterView> createState() => _BookChapterViewState();
}

class _BookChapterViewState extends State<_BookChapterView>
    with WidgetsBindingObserver {
  final _viewportKey = GlobalKey();
  final _centerKey = const ValueKey('chapter-center');
  late final List<GlobalKey> _paragraphKeys;
  Timer? _saveTimer;
  late int _visibleParagraph;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibleParagraph = widget.initialParagraph;
    _paragraphKeys =
        List.generate(widget.paragraphs.length, (_) => GlobalKey());
  }

  void _capturePosition() {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.attached || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    double? bestTop;
    for (var index = 0; index < _paragraphKeys.length; index++) {
      final box = _paragraphKeys[index].currentContext?.findRenderObject()
          as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final itemTop = box.localToGlobal(Offset.zero).dy;
      final itemBottom = itemTop + box.size.height;
      if (itemBottom <= top || itemTop >= bottom) continue;
      if (bestTop == null || itemTop < bestTop) {
        bestTop = itemTop;
        _visibleParagraph = index;
      }
    }
  }

  void _savePosition() {
    _saveTimer?.cancel();
    _capturePosition();
    widget.onPositionChanged(_visibleParagraph);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePosition();
    }
  }

  @override
  void dispose() {
    _savePosition();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _paragraph(int index) => Padding(
        key: _paragraphKeys[index],
        padding: const EdgeInsets.only(bottom: 16),
        child: _BookParagraph(
          text: widget.paragraphs[index],
          darkTheme: widget.darkTheme,
          buildSpans: widget.buildSpans,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final anchor = widget.initialParagraph;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification is ScrollUpdateNotification) {
          _saveTimer?.cancel();
          _saveTimer = Timer(const Duration(milliseconds: 400), _savePosition);
        } else if (notification.depth == 0 &&
            notification is ScrollEndNotification) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _savePosition();
          });
        }
        return false;
      },
      child: CustomScrollView(
        key: _viewportKey,
        center: _centerKey,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverList.builder(
            itemCount: anchor,
            itemBuilder: (context, index) => _paragraph(anchor - 1 - index),
          ),
          SliverList.builder(
            key: _centerKey,
            itemCount: widget.paragraphs.length - anchor + 1,
            itemBuilder: (context, index) {
              final paragraph = anchor + index;
              if (paragraph < widget.paragraphs.length) {
                return _paragraph(paragraph);
              }
              return Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onNextChapter,
                  icon: const Icon(Icons.chevron_right),
                  label: Text(widget.nextChapterLabel),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BookParagraph extends StatefulWidget {
  const _BookParagraph({
    required this.text,
    required this.darkTheme,
    required this.buildSpans,
  });

  final String text;
  final bool darkTheme;
  final List<TextSpan> Function(String) buildSpans;

  @override
  State<_BookParagraph> createState() => _BookParagraphState();
}

class _BookParagraphState extends State<_BookParagraph> {
  late List<TextSpan> _spans;

  @override
  void initState() {
    super.initState();
    _spans = widget.buildSpans(widget.text);
  }

  @override
  void didUpdateWidget(covariant _BookParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.darkTheme != widget.darkTheme) {
      _disposeSpans();
      _spans = widget.buildSpans(widget.text);
    }
  }

  void _disposeSpans() {
    for (final span in _spans) {
      span.recognizer?.dispose();
    }
  }

  @override
  void dispose() {
    _disposeSpans();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RichText(text: TextSpan(children: _spans));
}
