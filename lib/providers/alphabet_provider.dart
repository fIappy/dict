import 'package:flutter/material.dart';
import '../core/alphabet/alphabet_data.dart';
import '../core/alphabet/alphabet_model.dart';

class AlphabetProvider extends ChangeNotifier {
  String _selectedChar = 'A';
  LetterCategory _selectedCategory = LetterCategory.all;

  String get selectedChar => _selectedChar;
  LetterCategory get selectedCategory => _selectedCategory;

  AlphabetLetter get currentLetter => AlphabetData.findByLetter(_selectedChar);

  List<AlphabetLetter> get filteredLetters {
    switch (_selectedCategory) {
      case LetterCategory.all:
        return AlphabetData.allLetters;
      case LetterCategory.vowel:
        return AlphabetData.allLetters.where((l) => l.isVowel || l.isSemiVowel).toList();
      case LetterCategory.consonant:
        return AlphabetData.allLetters.where((l) => !l.isVowel).toList();
    }
  }

  void selectCategory(LetterCategory category) {
    _selectedCategory = category;
    final filtered = filteredLetters;
    if (filtered.isNotEmpty && !filtered.any((l) => l.upper == _selectedChar)) {
      _selectedChar = filtered.first.upper;
    }
    notifyListeners();
  }

  void selectLetter(String char) {
    final upper = char.toUpperCase();
    if (_selectedChar != upper) {
      _selectedChar = upper;
      notifyListeners();
    }
  }
}
