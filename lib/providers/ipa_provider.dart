import 'package:flutter/material.dart';
import '../core/ipa/ipa_data.dart';
import '../core/ipa/ipa_model.dart';

class IpaProvider extends ChangeNotifier {
  IpaCategory? _selectedCategory;
  IpaAccent? _selectedAccent;
  String _selectedSymbol = '/iː/';
  String _preferredPlaybackAccent = 'uk'; // 'uk' or 'us'
  bool _includeVariants = false;

  IpaCategory? get selectedCategory => _selectedCategory;
  IpaAccent? get selectedAccent => _selectedAccent;
  String get selectedSymbol => _selectedSymbol;
  String get preferredPlaybackAccent => _preferredPlaybackAccent;
  bool get includeVariants => _includeVariants;

  IpaPhoneme get currentPhoneme => IpaData.findBySymbol(_selectedSymbol);

  List<IpaPhoneme> get filteredPhonemes {
    List<IpaPhoneme> list;
    if (_selectedAccent == null) {
      list = _includeVariants ? IpaData.allWithCambridgeVariants : IpaData.allPhonemes;
    } else {
      list = IpaData.getByAccent(_selectedAccent!);
    }

    if (_selectedCategory != null) {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }
    return list;
  }

  void selectCategory(IpaCategory? category) {
    _selectedCategory = category;
    final filtered = filteredPhonemes;
    if (filtered.isNotEmpty && !filtered.any((p) => p.symbol == _selectedSymbol)) {
      _selectedSymbol = filtered.first.symbol;
    }
    notifyListeners();
  }

  void selectAccent(IpaAccent? accent) {
    _selectedAccent = accent;
    if (accent == IpaAccent.usOnly) {
      _preferredPlaybackAccent = 'us';
    } else if (accent == IpaAccent.ukOnly) {
      _preferredPlaybackAccent = 'uk';
    }
    final filtered = filteredPhonemes;
    if (filtered.isNotEmpty && !filtered.any((p) => p.symbol == _selectedSymbol)) {
      _selectedSymbol = filtered.first.symbol;
    }
    notifyListeners();
  }

  void setPreferredPlaybackAccent(String accent) {
    if (_preferredPlaybackAccent != accent) {
      _preferredPlaybackAccent = accent;
      notifyListeners();
    }
  }

  void toggleIncludeVariants(bool value) {
    _includeVariants = value;
    notifyListeners();
  }

  void selectPhoneme(String symbol) {
    if (_selectedSymbol != symbol) {
      _selectedSymbol = symbol;
      notifyListeners();
    }
  }
}
