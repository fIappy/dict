import 'package:flutter/material.dart';
import '../core/ipa/ipa_data.dart';
import '../core/ipa/ipa_model.dart';

class IpaProvider extends ChangeNotifier {
  IpaCategory? _selectedCategory;
  String _selectedSymbol = '/iː/';

  IpaCategory? get selectedCategory => _selectedCategory;
  String get selectedSymbol => _selectedSymbol;

  IpaPhoneme get currentPhoneme => IpaData.findBySymbol(_selectedSymbol);

  List<IpaPhoneme> get filteredPhonemes {
    if (_selectedCategory == null) {
      return IpaData.allPhonemes;
    }
    return IpaData.getByCategory(_selectedCategory!);
  }

  void selectCategory(IpaCategory? category) {
    _selectedCategory = category;
    // If the currently selected phoneme is not in the filtered category, auto-select first
    final filtered = filteredPhonemes;
    if (filtered.isNotEmpty && !filtered.any((p) => p.symbol == _selectedSymbol)) {
      _selectedSymbol = filtered.first.symbol;
    }
    notifyListeners();
  }

  void selectPhoneme(String symbol) {
    if (_selectedSymbol != symbol) {
      _selectedSymbol = symbol;
      notifyListeners();
    }
  }
}
