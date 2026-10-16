import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

/// Whether an archive at [path] must be copied into app storage before being
/// registered as a dictionary.
///
/// Android's Storage Access Framework hands back a copy of each picked file
/// under `cacheDir/file_picker/<timestamp>/`: the OS may evict it, and it never
/// contains the sibling `.mdd`, so a dictionary imported from it would lose its
/// audio and eventually its text. Desktop paths are the user's own files, so
/// they are referenced in place — copying a multi-gigabyte `.mdd` would be
/// wasteful and slow.
@visibleForTesting
bool requiresDurableImport({
  required bool isAndroid,
  required String path,
  required String? appDictDir,
}) {
  if (!isAndroid) return false;
  if (appDictDir != null && p.isWithin(appDictDir, path)) return false;
  return true;
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
      // Nothing registered yet: adopt every archive the probe folders hold.
      await autoImportDetectedDictionaries();
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

  /// Folders probed for archives: `DICT_DIR` (one or more folders separated by
  /// `;`, the same variable the backend reads), the working directory, and the
  /// executable's folder with its ancestors — so a portable build finds
  /// archives dropped next to it and a `flutter run` build finds the project's.
  @visibleForTesting
  static List<String> probeDirectories({
    required String cwd,
    required String exeDir,
    String? dictDirEnv,
    int ancestorLevels = 6,
  }) {
    final dirs = <String>[];
    void add(String candidate) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) return;
      final absolute = p.normalize(p.absolute(trimmed));
      if (!dirs.contains(absolute)) dirs.add(absolute);
    }

    for (final dir in (dictDirEnv ?? '').split(';')) {
      add(dir);
    }
    add(cwd);
    var dir = p.normalize(p.absolute(exeDir));
    add(dir);
    for (var level = 0; level < ancestorLevels; level++) {
      final parent = p.dirname(dir);
      if (parent == dir) break; // Filesystem root holds no dictionaries to scan.
      add(parent);
      dir = parent;
    }
    return dirs;
  }

  /// Every `.mdx` archive the probe folders hold. Each folder is scanned one
  /// level deep, which covers both a flat archive folder and the usual
  /// folder-per-dictionary layout.
  Future<List<String>> autoDetectMdxFiles() async {
    final found = <String>[];
    for (final dirPath in probeDirectories(
      cwd: Directory.current.path,
      exeDir: p.dirname(Platform.resolvedExecutable),
      dictDirEnv: Platform.environment['DICT_DIR'],
    )) {
      final root = Directory(dirPath);
      if (!root.existsSync()) continue;
      for (final folder in <Directory>[
        root,
        ..._listSafely(root).whereType<Directory>(),
      ]) {
        for (final entity in _listSafely(folder)) {
          if (entity is! File) continue;
          if (!entity.path.toLowerCase().endsWith('.mdx')) continue;
          final absolute = p.normalize(entity.absolute.path);
          if (!found.contains(absolute)) found.add(absolute);
        }
      }
    }
    found.sort();
    return found;
  }

  static List<FileSystemEntity> _listSafely(Directory dir) {
    try {
      return dir.listSync();
    } on FileSystemException {
      return const []; // Unreadable folder (permissions, removed drive).
    }
  }

  /// Stable id for a detected archive, so re-scanning never registers the same
  /// dictionary twice — its path is its identity.
  @visibleForTesting
  static String autoDictionaryId(String mdxPath) {
    var hash = 0x811c9dc5; // FNV-1a, 32 bit: small, deterministic, dependency-free.
    for (final byte in utf8.encode(p.normalize(p.absolute(mdxPath)).toLowerCase())) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return 'dict_auto_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// Registers and loads every detected archive that is not registered yet.
  Future<List<DictionaryInfo>> autoImportDetectedDictionaries() async {
    final known = {for (final info in await _dao.getAll()) info.mdxPath};
    final registered = <DictionaryInfo>[];

    for (final mdxPath in await autoDetectMdxFiles()) {
      if (known.contains(mdxPath)) continue;
      final info = DictionaryInfo(
        id: autoDictionaryId(mdxPath),
        name: p.basenameWithoutExtension(mdxPath),
        mdxPath: mdxPath,
        mddPath: _sidecar(mdxPath, '.mdd'),
        cssPath: _sidecar(mdxPath, '.css') ?? _firstCssIn(p.dirname(mdxPath)),
        isEnabled: true,
        priority: _loadedDicts.length + registered.length,
        createdAt: DateTime.now(),
      );
      await _dao.insert(info);
      await _loadDictionaryHandle(info);
      registered.add(info);
    }

    return registered;
  }

  /// `<name>.mdd` sitting next to `<name>.mdx` — how MDict pairs the archives.
  static String? _sidecar(String mdxPath, String extension) {
    final candidate = '${p.withoutExtension(mdxPath)}$extension';
    return File(candidate).existsSync() ? candidate : null;
  }

  /// Fallback for archives whose stylesheet is not named after them (SIO ships
  /// `siov32.css` beside `SIO双向双解词典v3.3.mdx`): the folder's first `.css`,
  /// which is what the backend registers too.
  static String? _firstCssIn(String dir) {
    final candidates = _listSafely(Directory(dir))
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.css'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return candidates.isEmpty ? null : candidates.first.absolute.path;
  }

  Future<LoadedDictionary?> _loadDictionaryHandle(DictionaryInfo info) async {
    try {
      if (!File(info.mdxPath).existsSync()) return null;
      final mdx = await MdxReader.open(info.mdxPath);

      // Resolve the audio archive. A dictionary imported without its .mdd keeps
      // mddPath == null, so re-probe the sibling file on every load: dropping
      // <name>.mdd next to <name>.mdx and restarting then picks it up.
      var resolvedInfo = info;
      var mddPath = info.mddPath;
      if (mddPath == null || !File(mddPath).existsSync()) {
        final sibling = p.join(
          p.dirname(info.mdxPath),
          '${p.basenameWithoutExtension(info.mdxPath)}.mdd',
        );
        mddPath = File(sibling).existsSync() ? sibling : null;
        if (mddPath != null) {
          resolvedInfo = info.copyWith(mddPath: mddPath);
          await _dao.update(resolvedInfo);
        }
      }

      MddReader? mdd;
      if (mddPath != null) {
        try {
          mdd = await MddReader.open(mddPath);
        } catch (e) {
          debugPrint('Failed to load MDD for ${info.name}: $e');
        }
      }

      // Update entry count in database
      if (resolvedInfo.entryCount != mdx.numEntries) {
        resolvedInfo = resolvedInfo.copyWith(entryCount: mdx.numEntries);
        await _dao.update(resolvedInfo);
      }

      final loaded = LoadedDictionary(info: resolvedInfo, mdx: mdx, mdd: mdd);
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

    // Auto-detect matching .mdd and .css next to the .mdx (desktop layout).
    final autoMdd = mddPath ?? p.join(dir, '$baseName.mdd');
    final autoCss = cssPath ?? p.join(dir, '$baseName.css');

    // On Android the picker hands back a throwaway copy under
    // cacheDir/file_picker/<timestamp>/, so a sibling .mdd is never there and
    // the path itself can be evicted. Move the archives into app-owned storage
    // first, keeping one basename so the pair still resolves.
    final stored = await _adoptIntoAppStorage(
      mdxPath: mdxPath,
      mddPath: File(autoMdd).existsSync() ? autoMdd : null,
      cssPath: File(autoCss).existsSync() ? autoCss : null,
      baseName: baseName,
    );

    final info = DictionaryInfo(
      id: 'dict_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      mdxPath: stored.mdx,
      mddPath: stored.mdd,
      cssPath: stored.css,
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

  /// Copies picked archives into app-owned storage when the filesystem does not
  /// give us a durable location (Android's SAF path is a cache copy).
  ///
  /// Desktop is returned untouched: archives are referenced in place, which
  /// avoids duplicating a multi-gigabyte `.mdd`.
  Future<({String mdx, String? mdd, String? css})> _adoptIntoAppStorage({
    required String mdxPath,
    required String? mddPath,
    required String? cssPath,
    required String baseName,
  }) async {
    final dictDir = await _appStorageDictDir();
    if (!requiresDurableImport(
      isAndroid: Platform.isAndroid,
      path: mdxPath,
      appDictDir: dictDir,
    )) {
      return (mdx: mdxPath, mdd: mddPath, css: cssPath);
    }

    final dir = Directory(dictDir!);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    Future<String> copyIn(String source, String extension) async {
      final target = p.join(dir.path, '$baseName$extension');
      final src = File(source);
      if (src.absolute.path == File(target).absolute.path) return target;
      await src.copy(target);
      return target;
    }

    return (
      mdx: await copyIn(mdxPath, '.mdx'),
      mdd: mddPath == null ? null : await copyIn(mddPath, '.mdd'),
      css: cssPath == null ? null : await copyIn(cssPath, '.css'),
    );
  }

  /// App-owned dictionary copies live under this folder.
  Future<String?> _appStorageDictDir() async {
    if (!Platform.isAndroid) return null;
    final root = await getApplicationSupportDirectory();
    return p.join(root.path, 'local_dict', 'dicts');
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
    final info = await _dao.getById(id);
    await _dao.delete(id);

    // Remove files this app copied in; never touch archives the user owns.
    final ownedDir = await _appStorageDictDir();
    if (info != null && ownedDir != null) {
      for (final path in [info.mdxPath, info.mddPath, info.cssPath]) {
        if (path == null || !p.isWithin(ownedDir, path)) continue;
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (e) {
          debugPrint('Could not remove $path: $e');
        }
      }
    }

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
