import '../audio/asset_manifest.dart';

/// The recorded vocabulary of the number module.
///
/// Numbers are an open set — nobody can pre-record "1,234,567" — but the words
/// the spoken form is built from are finite, so every *word* ships as a clip and
/// [NumberSpeaker] plays them back to back. That keeps the module fully offline
/// and accent-correct, and it is the same trick the IPA and alphabet modules
/// already use.
///
/// This list is the Dart half of one contract: `tool/generate_number_audio.py`
/// writes exactly these clips, and `test/widget_test.dart` fails when the two
/// drift apart (`NumberAudio` vs `NUMBER_WORDS`), when a clip is missing, or
/// when a reading produces a word that has no clip.
class NumberAudio {
  const NumberAudio._();

  /// Folder inside `assets/` holding `<word>_uk.wav` / `<word>_us.wav`.
  ///
  /// WAV rather than MP3 on purpose: a sentence is spliced out of these clips, so
  /// they are decoded and joined as PCM, and every platform then plays exactly
  /// the same bytes.
  static const String folder = 'audio/numbers';

  /// Every word the speller can emit. Keep in sync with the generator.
  static const Set<String> vocabulary = {
    // ones, teens, tens
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
    'seventeen', 'eighteen', 'nineteen',
    'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
    // scales
    'hundred', 'thousand', 'million', 'billion', 'trillion',
    // ordinals (also the fraction denominators)
    'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth',
    'ninth', 'tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth',
    'fifteenth', 'sixteenth', 'seventeenth', 'eighteenth', 'nineteenth',
    'twentieth', 'thirtieth', 'fortieth', 'fiftieth', 'sixtieth', 'seventieth',
    'eightieth', 'ninetieth', 'hundredth', 'thousandth', 'millionth',
    // plural denominators ("two thirds", "three quarters"); denominators above
    // ten are read "three over twelve" (see NumberSpeller), so they need no
    // plural form here
    'thirds', 'fourths', 'fifths', 'sixths', 'sevenths', 'eighths', 'ninths',
    'tenths',
    // function words and units
    'a', // the article in "one and a half"
    'and', 'point', 'minus', 'plus', 'percent', 'over', 'oh', 'nought', 'double',
    'triple', 'half', 'halves', 'quarter', 'quarters', 'times', 'degrees', 'nil',
    'love', 'nothing',
    // money
    'dollar', 'dollars', 'cent', 'cents', 'pound', 'pounds', 'penny', 'pence',
    'euro', 'euros', 'yuan',
    // clock and calendar
    'oclock', 'to', 'past', 'the', 'of', 'in', 'on', 'morning', 'afternoon',
    'evening', 'night',
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
    // decades and eras: "the nineties", "the two thousands", "500 BC"
    'tens', 'twenties', 'thirties', 'forties', 'fifties', 'sixties', 'seventies',
    // temperature, multiples/frequency and ratios
    'celsius', 'fahrenheit', 'below', 'degree', 'once', 'twice', 'week', 'weeks', 'day',
    'days', 'month', 'months', 'year', 'years', 'every', 'as', 'much', 'by',
    'out', 'ratio',
    'eighties', 'nineties', 'hundreds', 'thousands', 'bc', 'ad',
    'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
    'september', 'october', 'november', 'december',
  };

  /// Asset key for a spoken word: lower case, no apostrophe (`o'clock` → `oclock`).
  static String keyFor(String word) =>
      word.toLowerCase().replaceAll("'", '').replaceAll(RegExp(r'[^a-z]'), '');

  /// `assets/`-relative path handed to the player, e.g. `audio/numbers/one_uk.wav`.
  static String assetPath(String word, String accent) =>
      '$folder/${keyFor(word)}_${accent == 'uk' ? 'uk' : 'us'}.wav';

  /// Splits a spoken sentence into the words to play.
  ///
  /// A comma is *not* a word: [NumberSpeller] writes one at every group boundary
  /// of a phone number, and [NumberSpeaker] turns it into a short pause.
  static List<String> words(String sentence) => sentence
      .split(RegExp(r'[\s\-]+'))
      .map((word) => word.replaceAll(',', '').trim())
      .where((word) => word.isNotEmpty)
      .toList();

  /// Splits a spoken sentence into the chunks between pauses (phone groups).
  static List<String> pauseGroups(String sentence) => sentence
      .split(',')
      .map((chunk) => chunk.trim())
      .where((chunk) => chunk.isNotEmpty)
      .toList();

  /// True when [word] has a recorded clip. Unknown words are skipped silently at
  /// playback time, so this is what the coverage test asserts against.
  static bool hasClip(String word) => vocabulary.contains(keyFor(word));

  /// The clip to play for [word] in [accent], or null when there is none.
  ///
  /// The requested accent wins; the other one is accepted as a fallback because
  /// the generator reuses the other accent's recording for words whose
  /// pronunciation carries no accent difference at all (`sixths`, `sevenths`).
  /// A word with neither clip resolves to null, and the speaker stays silent
  /// rather than saying the number wrong.
  static Future<String?> resolve(String word, String accent) async {
    final key = keyFor(word);
    final primary = '$folder/${key}_${accent == 'uk' ? 'uk' : 'us'}.wav';
    final secondary = '$folder/${key}_${accent == 'uk' ? 'us' : 'uk'}.wav';
    final assets = await audioAssetManifest();
    if (assets.contains('assets/$primary')) return primary;
    if (assets.contains('assets/$secondary')) return secondary;
    return null;
  }
}
