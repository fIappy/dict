import 'package:flutter/material.dart';
import '../core/database/history_dao.dart';
import '../core/models/history_item.dart';

class HistoryProvider extends ChangeNotifier {
  final HistoryDao _dao = HistoryDao();
  List<HistoryItem> _items = [];
  bool _isLoading = false;

  List<HistoryItem> get items => _items;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    _items = await _dao.getRecentHistory();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addHistory(String word, {String? dictSource, String? phonetic}) async {
    final item = HistoryItem(
      id: 'hist_${DateTime.now().millisecondsSinceEpoch}',
      word: word,
      dictSource: dictSource,
      phonetic: phonetic,
      createdAt: DateTime.now(),
    );
    await _dao.addHistory(item);
    _items = await _dao.getRecentHistory();
    notifyListeners();
  }

  Future<void> deleteItem(String id) async {
    await _dao.deleteHistoryItem(id);
    _items = await _dao.getRecentHistory();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _dao.clearHistory();
    _items = [];
    notifyListeners();
  }
}
