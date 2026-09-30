import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/frequency/frequency_service.dart';

class FrequencyProvider extends ChangeNotifier {
  final FrequencyService _service = FrequencyService();

  int _startRank = 1;
  int _endRank = 100;
  int _currentPage = 1;
  static const int pageSize = 20;
  bool _isLoading = false;

  int get startRank => _startRank;
  int get endRank => _endRank;
  int get currentPage => _currentPage;
  bool get isLoading => _isLoading;

  int get totalItems => max(0, _endRank - _startRank + 1);
  int get totalPages => max(1, (totalItems + pageSize - 1) ~/ pageSize);

  List<WordFrequencyInfo> get currentPageItems {
    if (totalItems <= 0) return const [];
    final startOffset = (_currentPage - 1) * pageSize;
    final itemStartRank = _startRank + startOffset;
    final itemEndRank = min(_endRank, itemStartRank + pageSize - 1);
    if (itemStartRank > _endRank) return const [];
    return _service.getWordsByRange(itemStartRank, itemEndRank);
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    await _service.init();

    // Restore persisted frequency range from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedStart = prefs.getInt('frequency_range_start') ?? 1;
    final savedEnd = prefs.getInt('frequency_range_end') ?? 100;

    final maxLimit = _service.totalRankedWords > 0 ? _service.totalRankedWords : 20000;
    _startRank = savedStart.clamp(1, maxLimit);
    _endRank = savedEnd.clamp(_startRank, maxLimit);
    _currentPage = 1;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setRange(int start, int end) async {
    final maxLimit = _service.totalRankedWords > 0 ? _service.totalRankedWords : 20000;
    final s = start.clamp(1, maxLimit);
    final e = end.clamp(s, maxLimit);
    _startRank = s;
    _endRank = e;
    _currentPage = 1;
    notifyListeners();

    // Persist to SharedPreferences so it's remembered across restarts
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('frequency_range_start', _startRank);
    await prefs.setInt('frequency_range_end', _endRank);
  }

  void setPage(int page) {
    final p = page.clamp(1, totalPages);
    if (p != _currentPage) {
      _currentPage = p;
      notifyListeners();
    }
  }

  void nextPage() {
    if (_currentPage < totalPages) {
      setPage(_currentPage + 1);
    }
  }

  void previousPage() {
    if (_currentPage > 1) {
      setPage(_currentPage - 1);
    }
  }
}
