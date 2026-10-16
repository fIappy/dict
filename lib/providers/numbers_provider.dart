import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/piper_model_store.dart' as piper_store;
import '../core/audio/piper_voice.dart';
import '../core/numbers/number_data.dart';
import '../core/numbers/number_model.dart';
import '../core/audio/sentence_voice.dart';
import '../core/numbers/number_speaker.dart';
import '../core/numbers/sentence_engine.dart';
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
  NumbersProvider({NumberSpeaker? speaker}) : _speaker = speaker;

  static const String _kRate = 'numbers_rate';
  static const String _kRateAnchored = 'numbers_rate_anchored';
  static const String _kGap = 'numbers_gap_ms';
  static const String _kKind = 'numbers_kind';
  static const String _kDigits = 'numbers_digits';
  static const String _kCount = 'numbers_count';
  static const String _kAccent = 'numbers_accent';
  static const String _kSpeechMode = 'numbers_speech_mode';
  static const String _kSentenceEngine = 'numbers_sentence_engine';
  static const String _kRunMode = 'numbers_run_mode';
  static const String _kRunMin = 'numbers_run_min';
  static const String _kRunMax = 'numbers_run_max';
  static const String _kRunGap = 'numbers_run_gap_ms';

  // Built on first playback: constructing it publishes an AudioPlayer, and a
  // module that only reads numbers must not touch the audio plugin at all.
  NumberSpeaker? _speaker;
  NumberSpeaker get _player =>
      _speaker ??= NumberSpeaker(engine: _sentenceEngine, piper: _piper);

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
  SpeechMode _speechMode = SpeechMode.sentence;
  double _rate = 1.0;
  int _gapMs = 1000;
  // 整数 mode's 多组连读: each row is a run of numbers read back to back.
  bool _runMode = false;
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

  NumberCategory? get category => _category;
  NumberExample? get selected => _selected;
  NumberReading? get lookup => _lookup;
  String get lookupInput => _lookupInput;
  NumberCategory? get lookupOverride => _lookupOverride;
  String get accent => _accent;
  SpeechMode get speechMode => _speechMode;

  /// Which voice the sentence engine will use, or null when this platform has
  /// none (then the module speaks the recorded words one by one).
  String? _sentenceVoice;
  bool _sentenceVoiceChecked = false;
  String? get sentenceVoice => _sentenceVoice;
  bool get hasSentenceVoice => _sentenceVoice != null;
  bool get sentenceVoiceChecked => _sentenceVoiceChecked;

  SentenceEngine _sentenceEngine = SentenceEngine.system;

  /// The Piper model, shared by the speaker and the status line.
  final PiperVoice _piper = PiperVoice();

  /// What the UI says about the selected engine, refreshed asynchronously
  /// because the Piper model has to be read from disk (or fetched) first.
  String? _piperStatus;

  /// Whether Piper's model for the current accent is loaded and usable.
  bool get piperModelReady => _piperReady;
  bool _piperReady = false;

  /// Whether this platform can copy models out of a folder the user picks.
  bool get canImportPiperModels => piper_store.canImportPiperModels;

  /// Which engine reads a whole number sentence. Whatever is picked, an engine
  /// that cannot speak that sentence falls back to the recorded words.
  SentenceEngine get sentenceEngine => _sentenceEngine;

  /// What the UI says about the engine that will read a whole sentence: the
  /// system voice names itself (and warns when it has none for the accent), the
  /// other engines can always speak.
  String get sentenceEngineStatus => switch (_sentenceEngine) {
        // With no English voice here the sentence is still read in one go, by
        // the next engine that can — the same order [NumberSpeaker] walks.
        SentenceEngine.system => _sentenceVoice ??
            (_piperReady
                ? '本机没有英语语音：改用 Piper 神经语音整句朗读'
                : '本机没有英语语音：改用自带录音整句朗读（无接缝）'),
        SentenceEngine.spliced =>
          '内置录音在内存里拼成一句：无接缝、完全离线，三端同一份音频',
        SentenceEngine.piper => _piperStatus ?? '正在检测 Piper 模型…',
      };

  /// Probes the selected engine: loads the Piper model (once) or asks the system
  /// for its voices. Called when the engine or the accent changes, and once when
  /// the training section first paints — the flag is what keeps that from
  /// becoming a rebuild loop.
  Future<void> refreshSentenceEngineStatus() async {
    switch (_sentenceEngine) {
      case SentenceEngine.system:
        await refreshSentenceVoice();
        if (_sentenceVoice == null) {
          // Say what will read the numbers instead. Only the model's presence is
          // asked for here — loading it is the engine's business.
          _piperReady = await piper_store.findPiperModel(_accent) != null;
          notifyListeners();
        }
      case SentenceEngine.spliced:
        _sentenceEngineChecked = true;
        notifyListeners();
      case SentenceEngine.piper:
        _piperReady = await _piper.isReady(_accent);
        _piperStatus = await _piper.label(_accent) ?? await piper_store.piperModelHint();
        _sentenceEngineChecked = true;
        notifyListeners();
    }
  }

  bool _sentenceEngineChecked = false;

  /// Whether the selected engine has been probed since it was chosen.
  bool get sentenceEngineChecked => _sentenceEngineChecked;
  double get rate => _rate;
  int get gapMs => _gapMs;

  /// 多组连读 as configured — integer mode's run batches.
  bool get runMode => _runMode;
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
    _runMin = (prefs.getInt(_kRunMin) ?? 3)
        .clamp(NumbersLimits.minRunLength, NumbersLimits.maxRunLength);
    _runMax = (prefs.getInt(_kRunMax) ?? 7)
        .clamp(_runMin, NumbersLimits.maxRunLength);
    _runGapMs = (prefs.getInt(_kRunGap) ?? 80)
        .clamp(NumbersLimits.minRunGapMs, NumbersLimits.maxRunGapMs);
    _accent = prefs.getString(_kAccent) ?? 'uk';
    _speechMode = SpeechMode.values.firstWhere(
      (mode) => mode.name == prefs.getString(_kSpeechMode),
      orElse: () => SpeechMode.sentence,
    );
    // A preference saved when 录音拼接 was still offered names an engine that is
    // no longer selectable: it stays in the fallback chain, but not as the choice.
    final savedEngine = SentenceEngine.values.firstWhere(
      (engine) => engine.name == prefs.getString(_kSentenceEngine),
      orElse: () => SentenceEngine.system,
    );
    _sentenceEngine = savedEngine.selectable ? savedEngine : SentenceEngine.system;
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
    _playingIndex = -1;
    notifyListeners();
    await _player.speak(
      reading.textFor(chosen),
      accent: chosen,
      rate: _rate,
      mode: _speechMode,
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
    _playingIndex = -1;
    notifyListeners();
    await _player.speakRuns(
      <List<String>>[item.textsFor(_accent)],
      accent: _accent,
      rate: _rate,
      innerGap: Duration(milliseconds: _runGapMs),
      mode: _speechMode,
    );
    if (run != _playRun) return;
    _playing = false;
    notifyListeners();
  }

  /// Speaks the whole training list, pausing [gapMs] between the rows (and
  /// [runGapMs] between the numbers inside a run).
  Future<void> playTraining() async {
    if (_training.isEmpty) return;
    final run = ++_playRun;
    _playing = true;
    notifyListeners();
    await _player.speakRuns(
      _training.map((item) => item.textsFor(_accent)).toList(),
      accent: _accent,
      rate: _rate,
      innerGap: Duration(milliseconds: _runGapMs),
      gap: Duration(milliseconds: _gapMs),
      mode: _speechMode,
      onIndex: (index) {
        _playingIndex = index;
        notifyListeners();
      },
    );
    if (run != _playRun) return;
    _playing = false;
    _playingIndex = -1;
    notifyListeners();
  }

  void stopPlayback() {
    _playRun++; // invalidate whatever is still in flight, so it cannot re-arm
    _speaker?.cancel();
    _playing = false;
    _playingIndex = -1;
    notifyListeners();
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

  /// Looks up the voice once, for the UI to show what 整句朗读 will sound like.
  ///
  /// Uses the standalone probe (not the audio manager): it must not publish an
  /// AudioPlayer just to ask which voice exists.
  Future<void> refreshSentenceVoice() async {
    final voice = await chosenSentenceVoice(_accent);
    _sentenceVoice = voice == null ? null : sentenceVoiceDescription(voice, _accent);
    _sentenceVoiceChecked = true;
    notifyListeners();
  }

  Future<void> setSpeechMode(SpeechMode mode) async {
    _speechMode = mode;
    notifyListeners();
    if (!_sentenceVoiceChecked) await refreshSentenceVoice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSpeechMode, mode.name);
  }

  /// Picks the engine that reads a whole sentence. Each engine reports its own
  /// availability first (the system voice is a property of the machine, the Piper
  /// model has to be loaded), so the status line is right before the next drill.
  Future<void> setSentenceEngine(SentenceEngine engine) async {
    _sentenceEngine = engine;
    _speaker?.engine = engine;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSentenceEngine, engine.name);
    await refreshSentenceEngineStatus();
  }

  /// Asks the user for the voice — an archive on Android, a folder elsewhere —
  /// and copies it into app storage; returns the message to show.
  Future<String> importPiperModels() async {
    final List<String> installed;

    if (piper_store.piperImportUsesArchive) {
      // Android: one readable archive, because a picked folder is only a SAF tree
      // that cannot be opened as a path. The picker hands back a copy of the file
      // in the app's cache, which is readable.
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择 Piper 模型压缩包（piper.zip）',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      final path = picked?.path;
      if (path == null) return '已取消';
      installed = await piper_store.installPiperArchive(
        await piper_store.readPickedFile(path),
      );
    } else {
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: '选择包含 Piper 模型的文件夹',
      );
      if (picked == null) return '已取消';
      installed = await piper_store.importPiperModelsFrom(picked);
    }

    _sentenceEngineChecked = false;
    await refreshSentenceEngineStatus();
    if (installed.isEmpty) {
      return '没找到模型：压缩包/文件夹里应有 us/ 或 uk/，'
          '里面有 model.onnx、tokens.txt 与 espeak-ng-data/';
    }
    return '已安装${installed.map((a) => a == 'uk' ? '英音' : '美音').join('、')}模型';
  }

  Future<void> setAccent(String accent) async {
    _accent = accent;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, accent);
    _sentenceVoiceChecked = false;
    // The accent picks a voice (system) and a model (Piper), so the selected
    // engine re-reports either way.
    await refreshSentenceEngineStatus();
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
    _piper.dispose();
    super.dispose();
  }
}
