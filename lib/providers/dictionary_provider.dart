import 'package:flutter/material.dart';
import '../core/database/dictionaries_dao.dart';
import '../core/mdx/mdx_entry.dart';
import '../core/models/dictionary_info.dart';
import '../core/models/search_result.dart';
import '../core/services/dictionary_service.dart';
import '../core/ui/ui_memory.dart';

class DictionaryProvider extends ChangeNotifier {
  final DictionaryService _service = DictionaryService();
  final DictionariesDao _dao = DictionariesDao();

  bool _isLoading = true;
  String? _initError;
  String _searchQuery = '';
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;

  String? _currentWord;
  MdxEntry? _currentEntry;
  bool _isLoadingEntry = false;
  List<DictionaryInfo> _allDictionaries = [];

  bool get isLoading => _isLoading;
  String? get initError => _initError;
  String get searchQuery => _searchQuery;
  List<SearchResult> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get currentWord => _currentWord;
  MdxEntry? get currentEntry => _currentEntry;
  bool get isLoadingEntry => _isLoadingEntry;
  List<DictionaryInfo> get allDictionaries => _allDictionaries;
  bool get hasDictionaries => _service.hasDictionaries;

  /// [restoreWord] is false in a child window (背词): that window looks words
  /// up on demand and must not reopen — or overwrite — the main window's word.
  Future<void> initialize({bool restoreWord = true}) async {
    _isLoading = true;
    _initError = null;
    notifyListeners();

    try {
      await _service.initialize();
      _allDictionaries = await _dao.getAll();
      
      // Reopen the word the reader was on; 'hello' only when there is nothing
      // remembered (first run) or the remembered word is gone with its
      // dictionary.
      if (restoreWord && _service.hasDictionaries && _currentWord == null) {
        final remembered = (await UiMemory.readString(UiMemory.word))?.trim();
        final first = remembered == null || remembered.isEmpty ? 'hello' : remembered;
        await lookupWord(first, addToHistory: false);
        if (_currentEntry == null && first != 'hello') {
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

    final results = await _service.search(query, limit: 60);

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
      final entry = await _service.lookup(_currentWord!, preferDictId: preferDictId);
      if (lookupSeq != _lookupSeq) return;
      _currentEntry = entry;
    } catch (e) {
      debugPrint('Error looking up word $word: $e');
      if (lookupSeq == _lookupSeq) _currentEntry = null;
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

  /// Imports a dictionary and returns it, so the caller can report whether a
  /// pronunciation archive (.mdd) was paired with it.
  Future<DictionaryInfo> importDictionary({
    required String mdxPath,
    String? mddPath,
    String? cssPath,
    String? customName,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final info = await _service.importDictionary(
        mdxPath: mdxPath,
        mddPath: mddPath,
        cssPath: cssPath,
        customName: customName,
      );
      _allDictionaries = await _dao.getAll();
      if (_currentWord != null) {
        await lookupWord(_currentWord!, addToHistory: false);
      }
      return info;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Registers every archive the service's probe folders hold and returns the
  /// ones that were new. The service has already loaded them, so the registry
  /// only needs re-reading — no reload round trip.
  Future<List<DictionaryInfo>> autoImportDetected() async {
    _isLoading = true;
    notifyListeners();
    try {
      final registered = await _service.autoImportDetectedDictionaries();
      _allDictionaries = await _dao.getAll();
      if (registered.isNotEmpty && _currentWord != null) {
        await lookupWord(_currentWord!, addToHistory: false);
      }
      return registered;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleDictionary(String id, bool isEnabled) async {
    await _service.toggleDictionary(id, isEnabled);
    _allDictionaries = await _dao.getAll();
    notifyListeners();
  }

  Future<void> deleteDictionary(String id) async {
    await _service.deleteDictionary(id);
    _allDictionaries = await _dao.getAll();
    notifyListeners();
  }

  Future<void> refreshDictionaries() async {
    await _service.reloadDictionaries();
    _allDictionaries = await _dao.getAll();
    notifyListeners();
  }
}
