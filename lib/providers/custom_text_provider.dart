import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/custom/custom_text.dart';
import '../core/custom/playback_order.dart';
import '../core/mdx/entry_speech.dart';
import '../core/providers/safe_change_notifier.dart';
import '../core/storage/text_library_store.dart';
import '../core/ui/ui_memory.dart';

Object? _tryDecodeJson(String raw) {
  try {
    return jsonDecode(raw);
  } catch (e) {
    debugPrint('Custom text store unreadable: $e');
    return null;
  }
}

/// Holds the user's 自定义短语 / 自定义短文 and their groups.
///
/// The list is small (notes, not a dictionary), so the whole thing is JSON
/// rather than a dictionary database: one write per change, no schema. It lives
/// in its own files, not in `shared_preferences` — that store rewrites its whole
/// document on every write, and with megabytes of passages in it every unrelated
/// flag (window frame, split position) dragged the library along.
class CustomTextProvider extends ChangeNotifier with SafeChangeNotifier {
  static const String _textsKey = TextLibraryStore.legacyTextsKey;
  static const String _groupsKey = TextLibraryStore.legacyGroupsKey;

  /// The id of the 未分组 bucket, which is a real top-level group like any
  /// other: the list is classified by group first.
  static const String ungroupedId = '__ungrouped__';

  /// The library that ships with the app and the version already merged.
  ///
  /// The library file carries a `version`; bumping it is the way new content
  /// reaches an install that already has older content (see
  /// `tool/publish_custom_library.py`).
  static const String _seedVersionKey = 'custom_library_version';

  /// Fingerprint of the seed the store was last merged with.
  ///
  /// The version number cannot be the only trigger: content fixes (deduplicating
  /// sentences, re-splitting cues) can land without the number moving, and a
  /// rebuilt app then keeps serving the old text. The fingerprint changes
  /// whenever the shipped file does.
  static const String _seedFingerprintKey = 'custom_library_fingerprint';
  static const String _seedAsset = 'assets/seed/custom_home.json';
  static const String _seedMetaAsset = 'assets/seed/custom_home.meta.json';

  final List<CustomText> _texts = [];
  final List<CustomTextGroup> _groups = [];
  String _selectedGroupId = ungroupedId;
  String? _selectedId;
  bool _initialized = false;
  Map<String, int>? _countsCache;
  List<CustomText>? _visibleCache;

  void _invalidateCountsAndVisible() {
    _countsCache = null;
    _visibleCache = null;
  }

  List<CustomText> get allTexts => List.unmodifiable(_texts);
  List<CustomTextGroup> get groups => List.unmodifiable(_groups);

  /// The group whose contents are on screen; [ungroupedId] for 未分组.
  String get selectedGroupId => _selectedGroupId;

  String? get selectedId => _selectedId;

  /// Which top-level bucket an entry belongs to.
  static String groupIdOf(CustomText item) => item.groupId ?? ungroupedId;

  /// How many entries [groupId] holds.
  int countIn(String groupId) {
    final counts = _countsCache ??= _buildCounts();
    return counts[groupId] ?? 0;
  }

  Map<String, int> _buildCounts() {
    final counts = <String, int>{};
    for (final item in _texts) {
      final gid = groupIdOf(item);
      counts[gid] = (counts[gid] ?? 0) + 1;
    }
    return counts;
  }

  String get selectedGroupName {
    for (final group in _groups) {
      if (group.id == _selectedGroupId) return group.name;
    }
    return '未分组';
  }

  /// The entries of the selected group, oldest first.
  List<CustomText> get visibleTexts {
    return _visibleCache ??= List.unmodifiable(
      _texts.where((item) => groupIdOf(item) == _selectedGroupId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
  }

  CustomText? get selected {
    for (final item in _texts) {
      if (item.id == _selectedId) return item;
    }
    return null;
  }

  /// Everything the 顺序播放 / 随机播放 button reads: the open group's entries,
  /// each already split into its sentences.
  ///
  /// [order] only reorders the articles - the sentences of one article always
  /// stay in reading order, so a shuffled run never mixes two passages.
  List<EntryUtterance> queueFor(PlaybackOrder order, {Random? random}) =>
      queueFrom(0, order, random: random);

  /// Builds the playback queue starting at [startIndex] in the open group.
  ///
  /// In sequential mode, this walks from [startIndex] through the remaining
  /// entries to the end of the group. In shuffle mode, [startIndex] plays
  /// first, followed by the rest of the entries in random order.
  List<EntryUtterance> queueFrom(
    int startIndex,
    PlaybackOrder order, {
    Random? random,
  }) {
    final items = [...visibleTexts];
    if (startIndex < 0 || startIndex >= items.length) return const [];

    List<CustomText> ordered;
    if (order == PlaybackOrder.shuffle) {
      final rest = [
        for (var i = 0; i < items.length; i++)
          if (i != startIndex) items[i],
      ]..shuffle(random ?? Random());
      ordered = [items[startIndex], ...rest];
    } else {
      ordered = items.sublist(startIndex);
    }

    final result = <EntryUtterance>[];
    for (final item in ordered) {
      final sentences = item.utterances;
      for (var sIdx = 0; sIdx < sentences.length; sIdx++) {
        result.add(EntryUtterance(
          text: sentences[sIdx],
          isPhrase: false,
          itemId: item.id,
          sentenceIndex: sIdx,
        ));
      }
    }
    return result;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    // A library left in preferences by an older build moves to disk here; after
    // that the two keys are gone and preferences stay small.
    await TextLibraryStore.migrate(prefs);
    final groupsRaw =
        await TextLibraryStore.readGroups() ?? prefs.getString(_groupsKey);
    final textsRaw =
        await TextLibraryStore.readTexts() ?? prefs.getString(_textsKey);
    final decodedGroups = await _decodeRawJsonAsync(groupsRaw);
    final decodedTexts = await _decodeRawJsonAsync(textsRaw);
    _groups
      ..clear()
      ..addAll(_decodeListFromObject(decodedGroups, CustomTextGroup.fromJson));
    _texts
      ..clear()
      ..addAll(_decodeListFromObject(decodedTexts, CustomText.fromJson));
    _invalidateCountsAndVisible();
    // Reopen the group that was on screen, unless it was deleted meanwhile.
    final remembered = prefs.getString(UiMemory.customGroup);
    if (remembered != null &&
        (remembered == ungroupedId || _groups.any((g) => g.id == remembered))) {
      _selectedGroupId = remembered;
    }
    // …and the entry that was open inside it.
    final openText = prefs.getString(UiMemory.customText);
    if (openText != null && openText.isNotEmpty) {
      for (final item in _texts) {
        if (item.id == openText && groupIdOf(item) == _selectedGroupId) {
          _selectedId = openText;
          break;
        }
      }
    }
    // The library merges into groups; landing on an empty 未分组 made it look
    // like nothing had been imported.
    if (_dropEmptyDuplicateGroups() > 0) await _persistGroups();
    _selectFirstWithContent();
    notifyListeners();
  }

  /// Merges the library that ships with the app.
  ///
  /// Runs whenever the library's `version` is newer than the version already
  /// merged: groups and entries that are not here yet are added, and an id that
  /// exists locally keeps the local text (that is the reader's edit). Deleting a
  /// built-in entry therefore only sticks until the next library version.
  Future<void> ensureSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      String? metaFingerprint;
      try {
        final metaRaw = await rootBundle.loadString(_seedMetaAsset);
        final meta = jsonDecode(metaRaw);
        if (meta is Map) {
          metaFingerprint = meta['fingerprint']?.toString();
        }
      } catch (_) {
        // Fallback for builds/tests that do not ship custom_home.meta.json.
      }
      final storedFingerprint = prefs.getString(_seedFingerprintKey);
      if (metaFingerprint != null &&
          metaFingerprint.isNotEmpty &&
          storedFingerprint == metaFingerprint) {
        return;
      }

      final raw = await rootBundle.loadString(_seedAsset);
      final fingerprint = _fingerprintOf(raw);
      if (storedFingerprint == fingerprint) return;

      final data = await _decodeRawJsonAsync(raw);
      if (data is! Map) return;

      final merged = _mergeLibrary(data);
      if (merged.added > 0 || merged.updated > 0) {
        _invalidateCountsAndVisible();
      }
      await prefs.setString(_seedFingerprintKey, fingerprint);
      await prefs.setInt(
        _seedVersionKey,
        (data['version'] as num?)?.toInt() ?? 0,
      );
      if (merged.added == 0 && merged.updated == 0) return;
      _selectFirstWithContent();
      notifyListeners();
      await _persistGroups();
      await _persistTexts();
    } catch (e) {
      debugPrint('custom library import failed: $e');
    }
  }

  /// FNV-1a (32-bit) over the seed text: cheap, stable across platforms (the
  /// web has no 64-bit integers), and only ever compared with itself.
  static String _fingerprintOf(String raw) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < raw.length; i++) {
      hash = ((hash ^ raw.codeUnitAt(i)) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Merges the shipped library into the store.
  ///
  /// The shipped library is this app's own content, so it wins where the two
  /// overlap: a passage it carries replaces a stale local copy of the same id
  /// (body, title, group) and a group's shipped name is put back. Everything
  /// the library does not know — passages and groups written on this machine —
  /// is left exactly as it is, which is what lets a new build arrive on someone
  /// else's install without touching what they wrote.
  ///
  /// A group is matched by id first and then by **name**: a store built before
  /// the seed existed carries its 家庭场景 under a different id, and matching on
  /// id alone grew a second, empty 家庭场景 beside the real one. Entries inherit
  /// that mapping, so imported passages land in the group the reader has.
  ({int added, int updated}) _mergeLibrary(Map<dynamic, dynamic> data) {
    var added = 0;
    var updated = 0;
    final groupIds = <String, String>{};
    final groups = data['groups'];
    if (groups is List) {
      for (final entry in groups) {
        if (entry is! Map) continue;
        final group = CustomTextGroup.fromJson(entry.cast<String, Object?>());
        if (group.id.isEmpty) continue;
        final byId = _groups.where((local) => local.id == group.id);
        if (byId.isNotEmpty) {
          // Same group, possibly renamed in a newer build: the built-in name
          // wins, the passages keep pointing at it.
          final local = byId.first;
          if (local.name != group.name) {
            _groups[_groups.indexOf(local)] =
                CustomTextGroup(id: local.id, name: group.name);
            updated++;
          }
          groupIds[group.id] = local.id;
          continue;
        }
        // A store built before the seed existed: its 家庭场景 carries another
        // id, and matching on id alone grew a second, empty 家庭场景 beside it.
        final byName = _groups.where((local) => local.name == group.name);
        if (byName.isNotEmpty) {
          groupIds[group.id] = byName.first.id;
          continue;
        }
        _groups.add(group);
        groupIds[group.id] = group.id;
        added++;
      }
    }
    final texts = data['texts'];
    if (texts is List) {
      final textIndexById = <String, int>{
        for (var i = 0; i < _texts.length; i++) _texts[i].id: i,
      };
      for (final entry in texts) {
        if (entry is! Map) continue;
        final item = CustomText.fromJson(entry.cast<String, Object?>());
        if (item.id.isEmpty) continue;
        final target = item.groupId == null ? null : groupIds[item.groupId];
        final seeded = target == null || target == item.groupId
            ? item
            : item.copyWith(groupId: target);

        final index = textIndexById[item.id];
        if (index == null) {
          textIndexById[seeded.id] = _texts.length;
          _texts.add(seeded);
          added++;
          continue;
        }
        final local = _texts[index];
        if (local.body == seeded.body && local.title == seeded.title) continue;
        // A shipped passage: the library owns its text, so a rebuilt app shows
        // the fix. The reader's placement (group, creation time) is kept.
        _texts[index] = local.copyWith(
          body: seeded.body,
          title: seeded.title,
          groupId: seeded.groupId,
          clearGroup: seeded.groupId == null,
        );
        updated++;
      }
    }
    if (added > 0 || updated > 0) {
      _invalidateCountsAndVisible();
    }
    return (added: added, updated: updated);
  }

  /// Drops an empty group whose name another group already uses.
  ///
  /// Only reachable through the id-mismatch above, but the stray group is
  /// visible in the sidebar, so it is cleaned up on the next launch instead of
  /// asking the reader to delete it by hand.
  int _dropEmptyDuplicateGroups() {
    final before = _groups.length;
    final byName = <String, int>{};
    for (final group in _groups) {
      byName[group.name] = (byName[group.name] ?? 0) + 1;
    }
    _groups.removeWhere((group) {
      if (byName[group.name] == 1) return false;
      if (countIn(group.id) > 0) return false;
      return true;
    });
    return before - _groups.length;
  }

  /// Opens a group that actually holds something.
  ///
  /// The remembered group can be empty (its entries were deleted, or the group
  /// was renamed away), and an empty pane reads as a lost library. The first
  /// group with content wins, and 未分组 stays the choice when nothing else has
  /// any.
  void _selectFirstWithContent() {
    if (countIn(_selectedGroupId) > 0) return;
    for (final group in _groups) {
      if (countIn(group.id) > 0) {
        _selectedGroupId = group.id;
        return;
      }
    }
  }

  void selectGroup(String groupId) {
    if (_selectedGroupId == groupId) return;
    _selectedGroupId = groupId;
    _selectedId = null;
    _visibleCache = null;
    unawaited(UiMemory.writeString(UiMemory.customGroup, groupId));
    unawaited(UiMemory.writeString(UiMemory.customText, ''));
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
    unawaited(UiMemory.writeString(UiMemory.customText, id ?? ''));
    notifyListeners();
  }

  /// Adds an entry and returns it, so the caller can select it.
  Future<CustomText> add({
    required String body,
    String title = '',
    String? groupId,
  }) async {
    final item = CustomText(
      id: 'ct_${DateTime.now().microsecondsSinceEpoch}',
      body: body,
      title: title,
      groupId: groupId,
      createdAt: DateTime.now(),
    );
    _texts.add(item);
    _invalidateCountsAndVisible();
    notifyListeners();
    await _persistTexts();
    return item;
  }

  Future<void> update(CustomText item) async {
    final index = _texts.indexWhere((existing) => existing.id == item.id);
    if (index == -1) return;
    _texts[index] = item;
    _invalidateCountsAndVisible();
    notifyListeners();
    await _persistTexts();
  }

  Future<void> remove(String id) async {
    _texts.removeWhere((item) => item.id == id);
    _invalidateCountsAndVisible();
    if (_selectedId == id) {
      _selectedId = null;
      unawaited(UiMemory.writeString(UiMemory.customText, ''));
    }
    notifyListeners();
    await _persistTexts();
  }

  /// Adds a group and returns it (null when the name is blank).
  Future<CustomTextGroup?> addGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final group = CustomTextGroup(
      id: 'cg_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
    );
    _groups.add(group);
    _invalidateCountsAndVisible();
    notifyListeners();
    await _persistGroups();
    return group;
  }

  Future<void> renameGroup(String id, String name) async {
    final index = _groups.indexWhere((group) => group.id == id);
    final trimmed = name.trim();
    if (index == -1 || trimmed.isEmpty) return;
    _groups[index] = CustomTextGroup(id: id, name: trimmed);
    _invalidateCountsAndVisible();
    notifyListeners();
    await _persistGroups();
  }

  /// Removes a group; its entries stay, ungrouped.
  Future<void> removeGroup(String id) async {
    _groups.removeWhere((group) => group.id == id);
    var changed = false;
    for (var i = 0; i < _texts.length; i++) {
      if (_texts[i].groupId == id) {
        _texts[i] = _texts[i].copyWith(clearGroup: true);
        changed = true;
      }
    }
    _invalidateCountsAndVisible();
    if (_selectedGroupId == id) {
      _selectedGroupId = ungroupedId;
      unawaited(UiMemory.writeString(UiMemory.customGroup, ungroupedId));
    }
    notifyListeners();
    await _persistGroups();
    if (changed) await _persistTexts();
  }

  Future<void> _persistTexts() async {
    final raw = jsonEncode([for (final item in _texts) item.toJson()]);
    if (await TextLibraryStore.writeTexts(raw)) return;
    // No writable support directory (tests, an exotic platform): preferences
    // still hold it, as they always did.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textsKey, raw);
  }

  Future<void> _persistGroups() async {
    final raw = jsonEncode([for (final group in _groups) group.toJson()]);
    if (await TextLibraryStore.writeGroups(raw)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, raw);
  }

  static Future<Object?> _decodeRawJsonAsync(String? raw) async {
    if (raw == null || raw.isEmpty) return null;
    if (!kIsWeb && raw.length > 100000) {
      return compute(_tryDecodeJson, raw);
    }
    return _tryDecodeJson(raw);
  }

  static List<T> _decodeListFromObject<T>(
    Object? decoded,
    T Function(Map<String, Object?>) decode,
  ) {
    if (decoded is! List) return [];
    return [
      for (final entry in decoded)
        if (entry is Map) decode(entry.cast<String, Object?>()),
    ];
  }
}
