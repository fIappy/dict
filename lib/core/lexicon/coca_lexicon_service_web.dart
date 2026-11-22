import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../models/lexeme_entry.dart';
import '../models/search_result.dart';

/// Web client for the 53,925-word COCA AI learning corpus served by `dict_server`.
class CocaLexiconService {
  static final CocaLexiconService _instance = CocaLexiconService._();
  factory CocaLexiconService() => _instance;

  CocaLexiconService._();

  factory CocaLexiconService.forPath(String _) => CocaLexiconService._();

  final http.Client _client = http.Client();
  Future<void>? _initializing;
  bool _isReady = false;
  int _entryCount = 0;
  String? _initError;

  bool get isReady => _isReady;
  int get entryCount => _entryCount;
  String? get databasePath => null;
  String? get initError => _initError;
  String get libraryName => 'COCA 5.4万 AI 学习库';

  Future<void> initialize() {
    if (_isReady) return Future<void>.value();
    return _initializing ??= _doInitialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _doInitialize() async {
    await ApiConfig.resolve();
    try {
      final res = await _client
          .get(ApiConfig.endpoint('/api/lexicon/info'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          _isReady = decoded['ready'] == true;
          _entryCount = (decoded['entryCount'] as num?)?.toInt() ?? 0;
          _initError = _isReady ? null : '后端未加载 coca_learn.db';
          return;
        }
      }
      _initError = '学习库接口返回 HTTP ${res.statusCode}';
    } catch (e) {
      _initError = e.toString();
    }
  }

  Future<LexemeEntry?> lookup(String word) async {
    await ApiConfig.resolve();
    try {
      final uri = ApiConfig.endpoint('/api/lexicon/lookup', {'word': word});
      final res = await _client.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['found'] != true) {
        return null;
      }
      final raw = decoded['entry'];
      if (raw is! Map) return null;
      return LexemeEntry.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Future<List<SearchResult>> search(String query, {int limit = 60}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    await ApiConfig.resolve();
    try {
      final uri = ApiConfig.endpoint('/api/lexicon/search', {
        'q': trimmed,
        'limit': '$limit',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return const [];
      final list = decoded['results'];
      if (list is! List) return const [];
      return list.whereType<Map>().map((raw) {
        final matchName = raw['matchType'] as String? ?? 'substring';
        final matchType = SearchMatchType.values.firstWhere(
          (t) => t.name == matchName,
          orElse: () => SearchMatchType.substring,
        );
        return SearchResult(
          word: raw['word'] as String? ?? '',
          matchType: matchType,
          dictionaryId: raw['dictionaryId'] as String? ?? 'coca_learn',
          dictionaryName:
              raw['dictionaryName'] as String? ?? 'COCA 5.4万 AI 学习库',
          briefDefinition: raw['briefDefinition'] as String?,
          frequencyBadge: raw['frequencyBadge'] as String?,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> close() async {
    _isReady = false;
    _entryCount = 0;
  }
}
