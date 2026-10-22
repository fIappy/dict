import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/custom/custom_text.dart';
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

  /// One-time import of the library that ships with the app.
  static const String _seedKey = 'custom_seed_v1';
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

  /// Everything the 顺序播放 button reads: the open group's entries in list
  /// order, each already split into its sentences.
  List<EntryUtterance> get playbackQueue => [
        for (final item in visibleTexts)
          for (final line in item.utterances)
            EntryUtterance(text: line, isPhrase: false),
      ];

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
    notifyListeners();
  }

  /// Imports the built-in 家庭场景 library the first time the app runs.
  ///
  /// Never on top of a library the reader already built: an existing entry wins.
  /// The flag is set either way, so a later version of the seed cannot overwrite
  /// hand-written passages.
  Future<void> ensureSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seedKey) ?? false) return;
    await prefs.setBool(_seedKey, true);
    if (_texts.isNotEmpty || _groups.isNotEmpty) return;
    try {
      final raw = await rootBundle.loadString(_seedAsset);
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final groups = data['groups'];
      if (groups is List) {
        for (final entry in groups) {
          if (entry is! Map) continue;
          final group = CustomTextGroup.fromJson(entry.cast<String, Object?>());
          if (group.id.isNotEmpty && !_groups.any((g) => g.id == group.id)) {
            _groups.add(group);
          }
        }
      }
      final texts = data['texts'];
      if (texts is List) {
        for (final entry in texts) {
          if (entry is! Map) continue;
          final item = CustomText.fromJson(entry.cast<String, Object?>());
          if (item.id.isNotEmpty && !_texts.any((t) => t.id == item.id)) {
            _texts.add(item);
          }
        }
      }
      _selectedGroupId = _groups.isEmpty ? ungroupedId : _groups.first.id;
      notifyListeners();
      await _persistGroups();
      await _persistTexts();
    } catch (e) {
      debugPrint('custom seed import failed: $e');
    }
  }

  void selectGroup(String groupId) {
    if (_selectedGroupId == groupId) return;
    _selectedGroupId = groupId;
    _selectedId = null;
    UiMemory.writeString(UiMemory.customGroup, groupId);
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
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
    if (_selectedId == id) _selectedId = null;
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
