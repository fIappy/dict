import '../ipa/ipa_model.dart';

enum LetterCategory {
  all('全部 (26)'),
  vowel('元音字母 (5)'),
  consonant('辅音字母 (21)');

  final String label;
  const LetterCategory(this.label);
}

class AlphabetLetter {
  final String upper;
  final String lower;
  final String nameIpa;
  final String usNameIpa;
  final String ukNameIpa;
  final bool isVowel;
  final bool isSemiVowel;
  final String rhymeGroup; // e.g. "/eɪ/ 音组", "/iː/ 音组"
  final String phonicsSummary;
  final List<String> phonicsRules;
  final List<IpaExampleWord> examples;
  final String tips;
  final String audioKey; // e.g. "a" -> "a_us.mp3", "a_uk.mp3"

  const AlphabetLetter({
    required this.upper,
    required this.lower,
    required this.nameIpa,
    required this.usNameIpa,
    required this.ukNameIpa,
    this.isVowel = false,
    this.isSemiVowel = false,
    required this.rhymeGroup,
    required this.phonicsSummary,
    this.phonicsRules = const [],
    this.examples = const [],
    required this.tips,
    required this.audioKey,
  });

  String get displayLetter => '$upper $lower';
  String get typeLabel => isVowel ? '元音字母' : (isSemiVowel ? '半元音字母' : '辅音字母');
}
