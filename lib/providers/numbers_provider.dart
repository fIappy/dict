import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/kokoro_model_store.dart';
import '../core/audio/kokoro_voice.dart';
import '../core/numbers/number_data.dart';
import '../core/numbers/number_model.dart';
import '../core/numbers/number_speaker.dart';
import '../core/numbers/number_training.dart';
import '../core/numbers/number_speller.dart';

/// State of the number module: which category is being browsed, what the user
/// typed, and the training drill with its speed/interval settings.
///
/// Playback is delegated to [NumberSpeaker] (word-by-word clip playback), while
/// the settings that outlive a session — 语速, 间隔, 训练类型, 位数, 数量 — are
/// persisted, so the drill comes back exactly as it was left.
class NumbersProvider extends ChangeNotifier {
  /// [speaker] is a test seam: it lets the start/stop bookkeeping be exercised
  /// without an audio device. Production code leaves it null — the speaker is
  /// then built on first playback, so a screen that only reads numbers never
  /// touches the audio plugin.
  NumbersProvider({NumberSpeaker? speaker, KokoroVoice? kokoro})
      : _speaker = speaker,
        _kokoro = kokoro ?? KokoroVoice();

  static const String _kRate = 'numbers_rate';
  static const String _kRateAnchored = 'numbers_rate_anchored';
  static const String _kGap = 'numbers_gap_ms';
  static const String _kKind = 'numbers_kind';
  static const String _kDigits = 'numbers_digits';
  static const String _kCount = 'numbers_count';
  static const String _kAccent = 'numbers_accent';
  static const String _kRunMode = 'numbers_run_mode';
  static const String _kLoop = 'numbers_loop';
  static const String _kRunMin = 'numbers_run_min';
  static const String _kRunMax = 'numbers_run_max';
  static const String _kRunGap = 'numbers_run_gap_ms';

  // Built on first playback: constructing it publishes an AudioPlayer, and a
  // module that only reads numbers must not touch the audio plugin at all.
  NumberSpeaker? _speaker;
  NumberSpeaker get _player => _speaker ??= NumberSpeaker(kokoro: _kokoro);

  /// The one engine: Kokoro.
  final KokoroVoice _kokoro;

  /// Bumped by every start and every stop. Only the run that owns the current
  /// value may clear [isPlaying].
  ///
  /// Without it an abandoned run hurts: it un-parks as soon as a newer run
  /// starts, and then clears `_playing` — which greys the stop button out *while
  /// the new run is still speaking*, i.e. exactly when you need to press it.
  int _playRun = 0;

  NumberCategory? _category;
  NumberExample? _selected;
  NumberReading? _lookup;
  String _lookupInput = '';
  NumberCategory? _lookupOverride;

  String _accent = 'uk';

  double _rate = 1.0;
  int _gapMs = 1000;
  // 整数 mode's 多组连读: each row is a run of numbers read back to back.
  bool _runMode = false;
  /// 循环播放: when on, 开始朗读 repeats the whole list until stopped.
  bool _loop = false;
  int _runMin = 3;
  int _runMax = 7;
  int _runGapMs = 80;
  TrainingKind _kind = TrainingKind.integer;
  int _digits = 4;
  int _count = 5;
  List<NumberTrainingItem> _training = const [];
  int _trainingDistinct = 0;
  bool _revealed = false;
  int _playingIndex = -1;
  bool _playing = false;
  bool _paused = false;
  int _resumeFrom = 0;

  NumberCategory? get category => _category;
  NumberExample? get selected => _selected;
  NumberReading? get lookup => _lookup;
  String get lookupInput => _lookupInput;
  NumberCategory? get lookupOverride => _lookupOverride;
  String get accent => _accent;
  /// Whether the Kokoro model is installed and loaded.
  bool get kokoroReady => _kokoroReady;
  bool _kokoroReady = false;

  /// What the UI says about the engine, filled in asynchronously.
  String? get kokoroStatus => _kokoroStatus;
  String? _kokoroStatus;

  /// Whether the engine has been probed since this screen opened.
  bool get kokoroChecked => _kokoroChecked;
  bool _kokoroChecked = false;

  /// Loads the model (once) and reports what the UI should say.
  Future<void> refreshKokoroStatus() async {
    _kokoroReady = await _kokoro.isReady();
    _kokoroStatus = _kokoroReady
        ? await _kokoro.label()
        : await kokoroModelHint();
    _kokoroChecked = true;
    notifyListeners();
  }

  double get rate => _rate;
  int get gapMs => _gapMs;

  /// 多组连读 as configured — integer mode's run batches.
  bool get runMode => _runMode;

  bool get loop => _loop;
  int get runMin => _runMin;
  int get runMax => _runMax;

  /// How tightly the numbers inside one run follow each other.
  int get runGapMs => _runGapMs;

  /// Whether the current batch is made of runs: the option only applies to
  /// integer mode, so switching the kind away from it silently drops back to one
  /// number per row (and the setting is still there when you switch back).
  bool get runBatch => _runMode && _kind == TrainingKind.integer;
  TrainingKind get kind => _kind;
  int get digits => _digits;
  int get count => _count;
  List<NumberTrainingItem> get training => _training;
  bool get revealed => _revealed;
  int get playingIndex => _playingIndex;
  bool get isPlaying => _playing;
  bool get isPaused => _paused;

  List<NumberExample> get visibleExamples => _category == null
      ? NumberData.allExamples
      : NumberData.getByCategory(_category!);

  /// The reading shown in the detail pane: the selected card, or the last lookup.
  NumberReading? get currentReading => _lookup ?? (_selected == null ? null : NumberData.readingOf(_selected!));

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _rate = await _loadRate(prefs);
    _gapMs = (prefs.getInt(_kGap) ?? 1000)
        .clamp(NumbersLimits.minGapMs, NumbersLimits.maxGapMs);
    _digits = prefs.getInt(_kDigits) ?? 4;
    _count = (prefs.getInt(_kCount) ?? 5).clamp(1, NumbersLimits.maxTrainingCount);
    _runMode = prefs.getBool(_kRunMode) ?? false;
    _loop = prefs.getBool(_kLoop) ?? false;
    _runMin = (prefs.getInt(_kRunMin) ?? 3)
        .clamp(NumbersLimits.minRunLength, NumbersLimits.maxRunLength);
    _runMax = (prefs.getInt(_kRunMax) ?? 7)
        .clamp(_runMin, NumbersLimits.maxRunLength);
    _runGapMs = (prefs.getInt(_kRunGap) ?? 80)
        .clamp(NumbersLimits.minRunGapMs, NumbersLimits.maxRunGapMs);
    _accent = prefs.getString(_kAccent) ?? 'uk';
    _kind = TrainingKind.values.firstWhere(
      (k) => k.name == prefs.getString(_kKind),
      orElse: () => TrainingKind.integer,
    );
    notifyListeners();
  }

  /// The slider's ×1.0 used to mean the voice's natural rate; it now means the
  /// teaching pace, which is half of it. A value stored before that change is
  /// doubled so the learner keeps the pace they picked. Anything landing past the
  /// top of the new range is clamped — the old ×1.0 and above no longer exist.
  static Future<double> _loadRate(SharedPreferences prefs) async {
    final stored = prefs.getDouble(_kRate);
    if (stored == null) return 1.0;
    final alreadyAnchored = prefs.getBool(_kRateAnchored) ?? false;
    final migrated = (alreadyAnchored ? stored : stored * 2)
        .clamp(NumbersLimits.minRate, NumbersLimits.maxRate);
    if (!alreadyAnchored) await prefs.setBool(_kRateAnchored, true);
    if (migrated != stored) await prefs.setDouble(_kRate, migrated);
    return migrated;
  }

  void selectCategory(NumberCategory? category) {
    _category = category;
    final visible = visibleExamples;
    if (visible.isNotEmpty && (_selected == null || !visible.contains(_selected))) {
      _selected = visible.first;
    }
    notifyListeners();
  }

  void selectExample(NumberExample example) {
    _selected = example;
    _lookup = null;
    notifyListeners();
  }

  /// Parses [input]; an empty field clears the result. Returns true when a
  /// reading was produced, so the UI can flag unreadable input.
  bool parseInput(String input, {NumberCategory? override}) {
    _lookupInput = input;
    _lookupOverride = override;
    _lookup = NumberSpeller.read(input, as: override);
    notifyListeners();
    return _lookup != null && _lookup!.ukText.isNotEmpty;
  }

  // ------------------------------------------------------------------ audio

  Future<void> playReading(NumberReading reading, {String? accent}) async {
    final chosen = accent ?? _accent;
    final run = ++_playRun;
    _playing = true;
    _paused = false;
    _playingIndex = -1;
    notifyListeners();
    await _player.speak(
      reading.textFor(chosen),
      accent: chosen,
      rate: _rate,
    );
    if (run != _playRun) return;
    _playing = false;
    _playingIndex = -1;
    notifyListeners();
  }

  /// Speaks one row of the batch: a run is read in full, its numbers [runGapMs]
  /// apart.
  Future<void> playTrainingItem(NumberTrainingItem item) async {
    final run = ++_playRun;
    _playing = true;
    _paused = false;
    _playingIndex = -1;
    notifyListeners();
    await _player.speakRuns(
      <List<String>>[item.textsFor(_accent)],
      accent: _accent,
      rate: _rate,
      innerGap: Duration(milliseconds: _runGapMs),
    );
    if (run != _playRun) return;
    _playing = false;
    notifyListeners();
  }

  /// Speaks the whole training list, pausing [gapMs] between the rows (and
  /// [runGapMs] between the numbers inside a run).
  Future<void> playTraining({int startAt = 0}) async {
    if (_training.isEmpty) return;
    final from = startAt.clamp(0, _training.length - 1);
    final run = ++_playRun;
    _playing = true;
    _paused = false;
    notifyListeners();
    final rows = [
      for (var i = from; i < _training.length; i++) _training[i].textsFor(_accent),
    ];
    final gap = Duration(milliseconds: _gapMs);
    do {
      await _player.speakRuns(
        rows,
        accent: _accent,
        rate: _rate,
        innerGap: Duration(milliseconds: _runGapMs),
        gap: gap,
        onIndex: (index) {
          _playingIndex = from + index;
          notifyListeners();
        },
      );
      // A stop (or a newer run) wins over the loop; the speaker has already
      // dropped its rows, so there is nothing left to wait for.
      if (run != _playRun) return;
      // `_loop` is read per pass, so flipping the switch takes effect as soon as
      // the pass in flight ends rather than at the next start.
      if (!_loop) break;
      // Same spacing as between the items, so the last number does not run into
      // the first of the next pass.
      await Future.delayed(gap);
    } while (run == _playRun);
    if (run != _playRun) return;
    _playing = false;
    _playingIndex = -1;
    notifyListeners();
  }

  void stopPlayback() {
    _playRun++; // invalidate whatever is still in flight, so it cannot re-arm
    _speaker?.cancel();
    _playing = false;
    _paused = false;
    _playingIndex = -1;
    notifyListeners();
  }

  /// 暂停: silence now and remember the row. A drill cannot be paused inside a
  /// number — the speaker writes one buffer per run — so the row it was reading
  /// is the place to come back to.
  void pausePlayback() {
    if (!_playing || _paused) return;
    _paused = true;
    _resumeFrom = _playingIndex < 0 ? 0 : _playingIndex;
    _playRun++;
    _speaker?.cancel();
    _playing = false;
    notifyListeners();
  }

  /// 继续: start again at the interrupted row.
  Future<void> resumePlayback() async {
    if (!_paused) return;
    await playTraining(startAt: _resumeFrom);
  }

  // --------------------------------------------------------------- training

  /// How many of [training] hold different numbers — the rest are repeats, which
  /// only happen when the kind has fewer options than the batch asked for.
  int get trainingDistinctCount => _trainingDistinct;

  Future<void> setRunMode(bool value) async {
    _runMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRunMode, value);
  }

  /// Turning the loop on mid-pass takes effect at the end of that pass; turning
  /// it off stops the drill after the pass that is running now.
  Future<void> setLoop(bool value) async {
    _loop = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoop, value);
  }

  /// The length range a run of numbers is drawn from; [max] never drops below
  /// [min].
  Future<void> setRunRange(int min, int max) async {
    _runMin = min.clamp(NumbersLimits.minRunLength, NumbersLimits.maxRunLength);
    _runMax = max.clamp(_runMin, NumbersLimits.maxRunLength);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRunMin, _runMin);
    await prefs.setInt(_kRunMax, _runMax);
  }

  Future<void> setRunGapMs(int gapMs) async {
    _runGapMs = gapMs.clamp(NumbersLimits.minRunGapMs, NumbersLimits.maxRunGapMs);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRunGap, _runGapMs);
  }

  void generateTraining() {
    _training = runBatch
        ? NumberTraining.generateRuns(
            digits: _digits,
            count: _count,
            minLength: _runMin,
            maxLength: _runMax,
          )
        : NumberTraining.generate(
            kind: _kind,
            digits: _digits,
            count: _count,
          );
    _trainingDistinct = _training.map((item) => item.input).toSet().length;
    _revealed = false;
    _playingIndex = -1;
    notifyListeners();
  }

  void toggleReveal() {
    _revealed = !_revealed;
    notifyListeners();
  }

  // --------------------------------------------------------------- settings

  Future<void> setAccent(String accent) async {
    _accent = accent;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, accent);
  }

  Future<void> setRate(double rate) async {
    _rate = rate;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kRate, rate);
    // Without this the re-anchoring migration would treat a value saved by this
    // very version as a pre-anchoring one and double it on the next launch.
    await prefs.setBool(_kRateAnchored, true);
  }

  Future<void> setGapMs(int gapMs) async {
    _gapMs = gapMs.clamp(NumbersLimits.minGapMs, NumbersLimits.maxGapMs);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGap, _gapMs);
  }

  Future<void> setKind(TrainingKind kind) async {
    _kind = kind;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKind, kind.name);
  }

  Future<void> setDigits(int digits) async {
    _digits = digits;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDigits, digits);
  }

  Future<void> setCount(int count) async {
    _count = count.clamp(1, NumbersLimits.maxTrainingCount);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCount, count);
  }

  @override
  void dispose() {
    _speaker?.cancel();
    _kokoro.dispose();
    super.dispose();
  }
}
