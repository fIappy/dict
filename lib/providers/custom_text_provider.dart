import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/custom/custom_text.dart';
import '../core/mdx/entry_speech.dart';

/// Holds the user's 自定义短语 / 自定义短文 and their groups.
///
/// The list is small (notes, not a dictionary), so the whole thing lives in
/// `shared_preferences` as JSON instead of the dictionary database: one write
/// per change, no schema, and it travels with the app's other settings.
class CustomTextProvider extends ChangeNotifier {
  static const String _textsKey = 'custom_texts';
  static const String _groupsKey = 'custom_groups';

  /// The group filter meaning "entries with no group".
  static const String ungroupedFilter = '__ungrouped__';

  final List<CustomText> _texts = [];
  final List<CustomTextGroup> _groups = [];
  CustomTextKind _kind = CustomTextKind.phrase;
  String? _groupFilter;
  String? _selectedId;
  bool _initialized = false;

  List<CustomText> get allTexts => List.unmodifiable(_texts);
  List<CustomTextGroup> get groups => List.unmodifiable(_groups);
  CustomTextKind get kind => _kind;

  /// Null = 全部, [ungroupedFilter] = 未分组, anything else = that group's id.
  String? get groupFilter => _groupFilter;
  String? get selectedId => _selectedId;

  /// The list the current tab and filter show, oldest first.
  List<CustomText> get visibleTexts {
    final filtered = _texts.where((item) {
      if (item.kind != _kind) return false;
      if (_groupFilter == null) return true;
      if (_groupFilter == ungroupedFilter) return item.groupId == null;
      return item.groupId == _groupFilter;
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
  }

  CustomText? get selected {
    for (final item in _texts) {
      if (item.id == _selectedId) return item;
    }
    return null;
  }

  /// Everything the 顺序播放 button reads: the visible entries in list order,
  /// each passage already split into its sentences.
  List<EntryUtterance> get playbackQueue => [
        for (final item in visibleTexts)
          for (final line in item.utterances)
            EntryUtterance(
              text: line,
              isPhrase: item.kind == CustomTextKind.phrase,
            ),
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
    notifyListeners();
  }

  void selectKind(CustomTextKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    _selectedId = null;
    notifyListeners();
  }

  void setGroupFilter(String? filter) {
    _groupFilter = filter;
    _selectedId = null;
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  /// Adds an entry and returns it, so the caller can select it.
  Future<CustomText> add({
    required CustomTextKind kind,
    required String body,
    String title = '',
    String? groupId,
  }) async {
    final item = CustomText(
      id: 'ct_${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
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
    if (_groupFilter == id) _groupFilter = null;
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
