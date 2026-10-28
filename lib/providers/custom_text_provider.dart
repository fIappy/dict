import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/custom/custom_text.dart';
import '../core/custom/playback_order.dart';
import '../core/mdx/entry_speech.dart';
import '../core/ui/ui_memory.dart';

/// Holds the user's 自定义短语 / 自定义短文 and their groups.
///
/// The list is small (notes, not a dictionary), so the whole thing lives in
/// `shared_preferences` as JSON instead of the dictionary database: one write
/// per change, no schema, and it travels with the app's other settings.
class CustomTextProvider extends ChangeNotifier {
  static const String _textsKey = 'custom_texts';
  static const String _groupsKey = 'custom_groups';

  /// The id of the 未分组 bucket, which is a real top-level group like any
  /// other: the list is classified by group first.
  static const String ungroupedId = '__ungrouped__';

  /// The library that ships with the app and the version already merged.
  ///
  /// The library file carries a `version`; bumping it is the way new content
  /// reaches an install that already has older content (see
  /// `tool/publish_custom_library.py`).
  static const String _seedVersionKey = 'custom_library_version';
  static const String _seedAsset = 'assets/seed/custom_home.json';

  final List<CustomText> _texts = [];
  final List<CustomTextGroup> _groups = [];
  String _selectedGroupId = ungroupedId;
  String? _selectedId;
  bool _initialized = false;

  List<CustomText> get allTexts => List.unmodifiable(_texts);
  List<CustomTextGroup> get groups => List.unmodifiable(_groups);

  /// The group whose contents are on screen; [ungroupedId] for 未分组.
  String get selectedGroupId => _selectedGroupId;

  String? get selectedId => _selectedId;

  /// Which top-level bucket an entry belongs to.
  static String groupIdOf(CustomText item) => item.groupId ?? ungroupedId;

  /// How many entries [groupId] holds.
  int countIn(String groupId) =>
      _texts.where((item) => groupIdOf(item) == groupId).length;

  String get selectedGroupName {
    for (final group in _groups) {
      if (group.id == _selectedGroupId) return group.name;
    }
    return '未分组';
  }

  /// The entries of the selected group, oldest first.
  List<CustomText> get visibleTexts {
    final filtered = _texts
        .where((item) => groupIdOf(item) == _selectedGroupId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
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
    _groups
      ..clear()
      ..addAll(_decodeList(prefs.getString(_groupsKey), CustomTextGroup.fromJson));
    _texts
      ..clear()
      ..addAll(_decodeList(prefs.getString(_textsKey), CustomText.fromJson));
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
    final merged = prefs.getInt(_seedVersionKey) ?? 0;
    try {
      final raw = await rootBundle.loadString(_seedAsset);
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final version = (data['version'] as num?)?.toInt() ?? 0;
      if (version <= merged) return;

      final added = _mergeLibrary(data);
      await prefs.setInt(_seedVersionKey, version);
      if (added == 0) return;
      _selectFirstWithContent();
      notifyListeners();
      await _persistGroups();
      await _persistTexts();
    } catch (e) {
      debugPrint('custom library import failed: $e');
    }
  }

  /// Adds the groups and entries of [data] whose ids are not here yet; returns
  /// how many were added. Existing ids are left alone.
  ///
  /// A group is matched by id first and then by **name**: the store on this
  /// machine was built before the seed existed, so its 家庭场景 has a different
  /// id — matching on id alone grew a second, empty 家庭场景 beside the real one.
  /// Entries inherit that mapping, so imported passages land in the group the
  /// reader already has.
  int _mergeLibrary(Map<dynamic, dynamic> data) {
    var added = 0;
    final groupIds = <String, String>{};
    final groups = data['groups'];
    if (groups is List) {
      for (final entry in groups) {
        if (entry is! Map) continue;
        final group = CustomTextGroup.fromJson(entry.cast<String, Object?>());
        if (group.id.isEmpty) continue;
        final existing = _groups.where(
          (local) => local.id == group.id || local.name == group.name,
        );
        if (existing.isNotEmpty) {
          groupIds[group.id] = existing.first.id;
          continue;
        }
        _groups.add(group);
        groupIds[group.id] = group.id;
        added++;
      }
    }
    final texts = data['texts'];
    if (texts is List) {
      for (final entry in texts) {
        if (entry is! Map) continue;
        final item = CustomText.fromJson(entry.cast<String, Object?>());
        if (item.id.isEmpty) continue;
        if (_texts.any((existing) => existing.id == item.id)) continue;
        final target = item.groupId == null ? null : groupIds[item.groupId];
        _texts.add(
          target == null || target == item.groupId
              ? item
              : item.copyWith(groupId: target),
        );
        added++;
      }
    }
    return added;
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
    UiMemory.writeString(UiMemory.customGroup, groupId);
    UiMemory.writeString(UiMemory.customText, '');
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
    UiMemory.writeString(UiMemory.customText, id ?? '');
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
    notifyListeners();
    await _persistTexts();
    return item;
  }

  Future<void> update(CustomText item) async {
    final index = _texts.indexWhere((existing) => existing.id == item.id);
    if (index == -1) return;
    _texts[index] = item;
    notifyListeners();
    await _persistTexts();
  }

  Future<void> remove(String id) async {
    _texts.removeWhere((item) => item.id == id);
    if (_selectedId == id) {
      _selectedId = null;
      UiMemory.writeString(UiMemory.customText, '');
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
    notifyListeners();
    await _persistGroups();
    return group;
  }

  Future<void> renameGroup(String id, String name) async {
    final index = _groups.indexWhere((group) => group.id == id);
    final trimmed = name.trim();
    if (index == -1 || trimmed.isEmpty) return;
    _groups[index] = CustomTextGroup(id: id, name: trimmed);
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
    if (_selectedGroupId == id) {
      _selectedGroupId = ungroupedId;
      UiMemory.writeString(UiMemory.customGroup, ungroupedId);
    }
    notifyListeners();
    await _persistGroups();
    if (changed) await _persistTexts();
  }

  Future<void> _persistTexts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _textsKey,
      jsonEncode([for (final item in _texts) item.toJson()]),
    );
  }

  Future<void> _persistGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _groupsKey,
      jsonEncode([for (final group in _groups) group.toJson()]),
    );
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, Object?>) decode,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final entry in decoded)
          if (entry is Map) decode(entry.cast<String, Object?>()),
      ];
    } catch (e) {
      debugPrint('Custom text store unreadable: $e');
      return [];
    }
  }
}
