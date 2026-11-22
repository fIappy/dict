import 'package:flutter/material.dart';
import '../core/lexicon/coca_lexicon_service.dart';
import '../core/mdx/mdx_entry.dart';
import '../core/models/dictionary_info.dart';
import '../core/models/lexeme_entry.dart';
import '../core/models/search_result.dart';
import '../core/providers/safe_change_notifier.dart';
import '../core/ui/ui_memory.dart';

class DictionaryProvider extends ChangeNotifier with SafeChangeNotifier {
  DictionaryProvider({CocaLexiconService? lexicon})
      : _lexicon = lexicon ?? CocaLexiconService();

  final CocaLexiconService _lexicon;

  bool _isLoading = true;
  String? _initError;
  String _searchQuery = '';
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;

  String? _currentWord;
  LexemeEntry? _currentLexeme;
  MdxEntry? _currentEntry;
  String? _currentDictionaryName;
  bool _isLoadingEntry = false;

  bool get isLoading => _isLoading;
  String? get initError => _initError;
  String get searchQuery => _searchQuery;
  List<SearchResult> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get currentWord => _currentWord;
  LexemeEntry? get currentLexeme => _currentLexeme;
  MdxEntry? get currentEntry => _currentEntry;
  String? get currentDictionaryName =>
      _currentDictionaryName ?? (_lexicon.isReady ? _lexicon.libraryName : null);
  bool get isLoadingEntry => _isLoadingEntry;
  List<DictionaryInfo> get allDictionaries => const [];
  bool get hasDictionaries => _lexicon.isReady;
  int get totalEntries => _lexicon.entryCount;

  /// [restoreWord] is false in a child window (背词): that window looks words
  /// up on demand and must not reopen — or overwrite — the main window's word.
  Future<void> initialize({bool restoreWord = true}) async {
    _isLoading = true;
    _initError = null;
    notifyListeners();

    try {
      await _lexicon.initialize();
      _initError = _lexicon.initError;

      // Reopen the word the reader was on; 'hello' only on first launch or when
      // the remembered word has no entry in the learning corpus.
      if (restoreWord && _lexicon.isReady && _currentWord == null) {
        final remembered = (await UiMemory.readString(UiMemory.word))?.trim();
        final first =
            remembered == null || remembered.isEmpty ? 'hello' : remembered;
        await lookupWord(first, addToHistory: false);
        if (_currentLexeme == null && first != 'hello') {
          await lookupWord('hello', addToHistory: false);
        }
      }
    } catch (e) {
      _initError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Incremented per request so a slow response cannot overwrite a newer one.
  int _searchSeq = 0;
  int _lookupSeq = 0;

  Future<void> onSearchQueryChanged(String query) async {
    _searchQuery = query;
    final seq = ++_searchSeq;

    if (query.trim().isEmpty) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    final results = await _lexicon.search(query, limit: 60);

    // A newer keystroke already superseded this request.
    if (seq != _searchSeq) return;

    _searchResults = results;
    _isSearching = false;
    notifyListeners();
  }

  /// [remember] is false in a child window: a lookup there is a glance, not the
  /// word the reader left the dictionary on.
  Future<void> lookupWord(
    String word, {
    bool addToHistory = true,
    bool remember = true,
    String? preferDictId,
  }) async {
    if (word.trim().isEmpty) return;
    _currentWord = word.trim();
    final lookupSeq = ++_lookupSeq;
    _isLoadingEntry = true;
    notifyListeners();

    if (remember) await _rememberWord();
    try {
      final lexeme = await _lexicon.lookup(_currentWord!);
      if (lookupSeq != _lookupSeq) return;
      _currentLexeme = lexeme;
      _currentEntry = null;
      _currentDictionaryName = lexeme == null ? null : _lexicon.libraryName;
    } catch (e) {
      debugPrint('Error looking up word $word: $e');
      if (lookupSeq == _lookupSeq) {
        _currentLexeme = null;
        _currentEntry = null;
        _currentDictionaryName = null;
      }
    } finally {
      if (lookupSeq == _lookupSeq) {
        _isLoadingEntry = false;
        notifyListeners();
      }
    }
  }

  /// Remembers the word on screen so the next launch opens the same entry.
  Future<void> _rememberWord() async {
    final word = _currentWord;
    if (word == null || word.isEmpty) return;
    await UiMemory.writeString(UiMemory.word, word);
  }

  // Legacy dictionary-management hooks retained cleanly for `DictionaryManagerScreen`.
  Future<DictionaryInfo> importDictionary({
    required String mdxPath,
    String? mddPath,
    String? cssPath,
    String? customName,
  }) =>
      Future.error(UnsupportedError('当前版本已内置 COCA 5.4万 AI 学习库，不再使用外部 MDX 查词'));

  Future<List<DictionaryInfo>> autoImportDetected() async => const [];

  Future<void> toggleDictionary(String id, bool isEnabled) async {}

  Future<void> deleteDictionary(String id) async {}

  Future<void> refreshDictionaries() => initialize(restoreWord: false);
}
