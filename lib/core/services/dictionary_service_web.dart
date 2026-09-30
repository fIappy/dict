import 'package:flutter/foundation.dart';

import '../api/api_config.dart';
import '../api/dict_api_client.dart';
import '../frequency/frequency_service.dart';
import '../mdx/mdx_entry.dart';
import '../models/dictionary_info.dart';
import '../models/search_result.dart';

/// Web implementation of the dictionary service.
///
/// Browsers cannot read local files, so every MDict capability is delegated to
/// the companion backend (`server/dict_server.dart`). Vocabulary features that
/// are asset-backed — IPA chart, alphabet, word frequency — stay fully local.
class DictionaryService {
  static final DictionaryService _instance = DictionaryService._();
  factory DictionaryService() => _instance;
  DictionaryService._();

  final DictApiClient _api = DictApiClient();
  final FrequencyService _frequencyService = FrequencyService();

  bool _isInitialized = false;
  bool _isBackendConnected = false;
  List<DictionaryInfo> _dictionaries = const [];

  /// The backend owns the archive set; the browser cannot import files.
  bool get supportsLocalDictionaries => false;

  bool get isBackendConnected => _isBackendConnected;

  String? get backendBaseUrl => ApiConfig.baseUrl;

  List<DictionaryInfo> get availableDictionaries =>
      List.unmodifiable(_dictionaries);

  bool get hasDictionaries => _dictionaries.any((d) => d.isEnabled);

  /// On web a non-empty path means the backend reported the resource, which
  /// is authoritative — the browser cannot stat files itself.
  bool resourceAvailable(String? path) => path != null && path.isNotEmpty;

  Future<String?> autoDetectWorkspaceMdx() async => null;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await ApiConfig.resolve();
    await _frequencyService.init();
    await refreshDictionaries();
    _isInitialized = true;
  }

  /// Re-reads the archive list from the backend.
  Future<void> refreshDictionaries() async {
    try {
      _dictionaries = await _api.dictionaries();
      _isBackendConnected = true;
    } catch (e) {
      debugPrint('Dictionary backend unreachable at ${ApiConfig.baseUrl}: $e');
      _dictionaries = const [];
      _isBackendConnected = false;
    }
  }

  Future<List<SearchResult>> search(String query, {int limit = 50}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final hits = await _api.search(trimmed, limit: limit);
      _isBackendConnected = true;
      return hits.map(_enrich).toList();
    } catch (e) {
      debugPrint('Search failed against ${ApiConfig.baseUrl}: $e');
      _isBackendConnected = false;
      return const [];
    }
  }

  SearchResult _enrich(ApiSearchHit hit) {
    final freq = _frequencyService.getFrequency(hit.word);
    return SearchResult(
      word: hit.word,
      matchType: _matchType(hit.matchType),
      dictionaryId: hit.dictionaryId,
      dictionaryName: hit.dictionaryName,
      briefDefinition: freq?.briefZh,
      frequencyBadge: freq?.frequencyLabel,
    );
  }

  static SearchMatchType _matchType(String raw) {
    switch (raw) {
      case 'exact':
        return SearchMatchType.exact;
      case 'prefix':
        return SearchMatchType.prefix;
      default:
        return SearchMatchType.substring;
    }
  }

  Future<MdxEntry?> lookup(String word, {String? preferDictId}) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return null;

    try {
      final entry = await _api.lookup(trimmed);
      _isBackendConnected = true;
      return entry;
    } catch (e) {
      debugPrint('Lookup failed against ${ApiConfig.baseUrl}: $e');
      _isBackendConnected = false;
      return null;
    }
  }

  /// Pronunciation bytes read from the server-side `.mdd` archive.
  Future<Uint8List?> getAudioBytes(String soundKey) async {
    try {
      return await _api.audioBytes(soundKey);
    } catch (e) {
      debugPrint('Audio fetch failed for $soundKey: $e');
      return null;
    }
  }

  Future<DictionaryInfo> importDictionary({
    required String mdxPath,
    String? mddPath,
    String? cssPath,
    String? customName,
  }) async {
    throw UnsupportedError(
      '网页版无法导入本地文件。请将 .mdx/.mdd 放入后端词典目录后重启 '
      'server/dict_server.dart。',
    );
  }

  Future<void> reloadDictionaries() => refreshDictionaries();

  Future<void> toggleDictionary(String id, bool isEnabled) async {
    await _api.setDictionaryEnabled(id, isEnabled);
    await refreshDictionaries();
  }

  Future<void> deleteDictionary(String id) async {
    // Archives live on the server; removal is done by editing its directory.
    await refreshDictionaries();
  }

  void dispose() {}
}
