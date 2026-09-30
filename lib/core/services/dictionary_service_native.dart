import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../database/dictionaries_dao.dart';
import '../frequency/frequency_service.dart';
import '../mdx/mdd_reader.dart';
import '../mdx/mdx_entry.dart';
import '../mdx/mdx_reader.dart';
import '../models/dictionary_info.dart';
import '../models/search_result.dart';

class LoadedDictionary {
  final DictionaryInfo info;
  final MdxReader mdx;
  final MddReader? mdd;

  LoadedDictionary({
    required this.info,
    required this.mdx,
    this.mdd,
  });

  void close() {
    mdx.close();
    mdd?.close();
  }
}

class DictionaryService {
  static final DictionaryService _instance = DictionaryService._();
  factory DictionaryService() => _instance;
  DictionaryService._();

  final DictionariesDao _dao = DictionariesDao();
  final FrequencyService _frequencyService = FrequencyService();

  final List<LoadedDictionary> _loadedDicts = [];
  bool _isInitialized = false;

  List<LoadedDictionary> get loadedDictionaries => List.unmodifiable(_loadedDicts);
  bool get hasDictionaries => _loadedDicts.isNotEmpty;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _frequencyService.init();

    // 1. Load registered enabled dictionaries from database
    final registered = await _dao.getEnabled();

    if (registered.isEmpty) {
      // Auto-detect local Dictionary.com 20260913_hahaya in project workspace if present
      await _autoDetectDefaultDictionary();
    } else {
      for (final info in registered) {
        await _loadDictionaryHandle(info);
      }
    }

    _isInitialized = true;
  }

  /// Whether a resource path reported by the registry is usable in this build.
  bool resourceAvailable(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  /// Native targets can read local MDict archives from disk.
  bool get supportsLocalDictionaries => true;

  /// Native builds read archives directly; there is no remote hop to report.
  bool get isBackendConnected => true;

  /// Native builds have no remote backend address.
  String? get backendBaseUrl => null;

  /// Probes well-known locations for the bundled Dictionary.com sample archive.
  Future<String?> autoDetectWorkspaceMdx() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(Directory.current.path, 'Dictionary.com 20260913_hahaya', 'Dictionary.com 20260913.mdx'),
      p.join(exeDir, 'Dictionary.com 20260913_hahaya', 'Dictionary.com 20260913.mdx'),
      p.join(exeDir, '..', '..', '..', '..', '..', 'Dictionary.com 20260913_hahaya', 'Dictionary.com 20260913.mdx'),
      'D:/proj/flutter/dict/Dictionary.com 20260913_hahaya/Dictionary.com 20260913.mdx',
      'Dictionary.com 20260913_hahaya/Dictionary.com 20260913.mdx',
      'Dictionary.com 20260913.mdx',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        return File(c).absolute.path;
      }
    }
    return null;
  }

  Future<void> _autoDetectDefaultDictionary() async {
    final foundMdx = await autoDetectWorkspaceMdx();
    if (foundMdx == null) return;

    final dir = p.dirname(foundMdx);
    final mddCandidate = p.join(dir, 'Dictionary.com 20260913.mdd');
    final cssCandidate = p.join(dir, 'dcom-mdx-style.css');

    final info = DictionaryInfo(
      id: 'dict_com_20260913',
      name: 'Dictionary.com (20260913)',
      mdxPath: foundMdx,
      mddPath: File(mddCandidate).existsSync() ? mddCandidate : null,
      cssPath: File(cssCandidate).existsSync() ? cssCandidate : null,
      isEnabled: true,
      priority: 0,
      createdAt: DateTime.now(),
    );

    await _dao.insert(info);
    await _loadDictionaryHandle(info);
  }

  Future<LoadedDictionary?> _loadDictionaryHandle(DictionaryInfo info) async {
    try {
      if (!File(info.mdxPath).existsSync()) return null;
      final mdx = await MdxReader.open(info.mdxPath);

      MddReader? mdd;
      if (info.mddPath != null && File(info.mddPath!).existsSync()) {
        try {
          mdd = await MddReader.open(info.mddPath!);
        } catch (e) {
          debugPrint('Failed to load MDD for ${info.name}: $e');
        }
      }

      // Update entry count in database
      if (info.entryCount != mdx.numEntries) {
        final updated = info.copyWith(entryCount: mdx.numEntries);
        await _dao.update(updated);
      }

      final loaded = LoadedDictionary(info: info, mdx: mdx, mdd: mdd);
      _loadedDicts.add(loaded);
      return loaded;
    } catch (e) {
      debugPrint('Error loading dictionary ${info.name}: $e');
      return null;
    }
  }

  /// Import a new dictionary from local path
  Future<DictionaryInfo> importDictionary({
    required String mdxPath,
    String? mddPath,
    String? cssPath,
    String? customName,
  }) async {
    final mdxFile = File(mdxPath);
    if (!mdxFile.existsSync()) {
      throw FileSystemException('MDX file not found', mdxPath);
    }

    final baseName = p.basenameWithoutExtension(mdxPath);
    final name = customName ?? baseName;
    final dir = p.dirname(mdxPath);

    // Auto-detect matching .mdd and .css if not provided
    final autoMdd = mddPath ?? p.join(dir, '$baseName.mdd');
    final autoCss = cssPath ?? p.join(dir, '$baseName.css');

    final info = DictionaryInfo(
      id: 'dict_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      mdxPath: mdxPath,
      mddPath: File(autoMdd).existsSync() ? autoMdd : null,
      cssPath: File(autoCss).existsSync() ? autoCss : null,
      isEnabled: true,
      priority: _loadedDicts.length,
      createdAt: DateTime.now(),
    );

    await _dao.insert(info);
    final loaded = await _loadDictionaryHandle(info);
    if (loaded == null) {
      await _dao.delete(info.id);
      throw Exception('Failed to load imported dictionary');
    }

    return info;
  }

  Future<void> reloadDictionaries() async {
    for (final d in _loadedDicts) {
      d.close();
    }
    _loadedDicts.clear();
    final enabled = await _dao.getEnabled();
    for (final info in enabled) {
      await _loadDictionaryHandle(info);
    }
  }

  Future<void> toggleDictionary(String id, bool isEnabled) async {
    await _dao.toggleEnabled(id, isEnabled);
    await reloadDictionaries();
  }

  Future<void> deleteDictionary(String id) async {
    await _dao.delete(id);
    await reloadDictionaries();
  }

  /// Multi-dictionary search with ranked matching (exact -> prefix -> substring)
  Future<List<SearchResult>> search(String query, {int limit = 50}) async {
    if (query.trim().isEmpty || _loadedDicts.isEmpty) return const [];
    final q = query.trim().toLowerCase();
    final results = <SearchResult>[];
    final seenWords = <String>{};

    // 1. Exact matches across loaded dictionaries
    for (final dict in _loadedDicts) {
      if (dict.mdx.getEntry(q) != null) {
        if (!seenWords.contains(q)) {
          final freq = _frequencyService.getFrequency(q);
          results.add(SearchResult(
            word: q,
            matchType: SearchMatchType.exact,
            dictionaryId: dict.info.id,
            dictionaryName: dict.info.name,
            briefDefinition: freq?.briefZh,
            frequencyBadge: freq?.frequencyLabel,
          ));
          seenWords.add(q);
        }
      }
    }

    // 2. Prefix matches across dictionaries
    for (final dict in _loadedDicts) {
      final matches = dict.mdx.search(q, limit: limit, prefixOnly: true);
      for (final word in matches) {
        final lower = word.toLowerCase();
        if (!seenWords.contains(lower)) {
          final freq = _frequencyService.getFrequency(lower);
          results.add(SearchResult(
            word: word,
            matchType: SearchMatchType.prefix,
            dictionaryId: dict.info.id,
            dictionaryName: dict.info.name,
            briefDefinition: freq?.briefZh,
            frequencyBadge: freq?.frequencyLabel,
          ));
          seenWords.add(lower);
          if (results.length >= limit) return results;
        }
      }
    }

    // 3. Substring (partial) matches across dictionaries if limit not reached
    if (results.length < limit) {
      for (final dict in _loadedDicts) {
        final matches = dict.mdx.search(q, limit: limit, prefixOnly: false);
        for (final word in matches) {
          final lower = word.toLowerCase();
          if (!seenWords.contains(lower)) {
            final freq = _frequencyService.getFrequency(lower);
            results.add(SearchResult(
              word: word,
              matchType: SearchMatchType.substring,
              dictionaryId: dict.info.id,
              dictionaryName: dict.info.name,
              briefDefinition: freq?.briefZh,
              frequencyBadge: freq?.frequencyLabel,
            ));
            seenWords.add(lower);
            if (results.length >= limit) return results;
          }
        }
      }
    }

    return results;
  }

  /// Lookup a word entry across loaded dictionaries
  Future<MdxEntry?> lookup(String word, {String? preferDictId}) async {
    if (_loadedDicts.isEmpty) return null;

    // 1. Try preferred dictionary first if specified
    if (preferDictId != null) {
      final preferred = _loadedDicts.firstWhere(
        (d) => d.info.id == preferDictId,
        orElse: () => _loadedDicts.first,
      );
      final rawHtml = preferred.mdx.getEntry(word);
      if (rawHtml != null) {
        return MdxEntry.parse(word, rawHtml);
      }
    }

    // 2. Try each loaded dictionary in priority order
    for (final dict in _loadedDicts) {
      final rawHtml = dict.mdx.getEntry(word);
      if (rawHtml != null) {
        return MdxEntry.parse(word, rawHtml);
      }
    }

    return null;
  }

  /// Retrieve pronunciation audio data (MP3/WAV) from associated MDD
  Future<Uint8List?> getAudioBytes(String soundKey) async {
    if (_loadedDicts.isEmpty) return null;
    for (final dict in _loadedDicts) {
      if (dict.mdd != null) {
        final bytes = dict.mdd!.getResource(soundKey);
        if (bytes != null) return bytes;
      }
    }
    return null;
  }

  void dispose() {
    for (final d in _loadedDicts) {
      d.close();
    }
    _loadedDicts.clear();
  }
}
