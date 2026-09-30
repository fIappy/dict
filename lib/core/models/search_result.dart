enum SearchMatchType {
  exact,
  prefix,
  substring,
}

class SearchResult {
  final String word;
  final SearchMatchType matchType;
  final String dictionaryId;
  final String dictionaryName;
  final String? phonetic;
  final String? briefDefinition;
  final String? frequencyBadge;

  const SearchResult({
    required this.word,
    required this.matchType,
    required this.dictionaryId,
    required this.dictionaryName,
    this.phonetic,
    this.briefDefinition,
    this.frequencyBadge,
  });
}
