// Engine: Dart (pure) | Target: lib/core/audio
//
// Turns the speed multiplier the UI shows (语速 ×0.5 … ×1.5) into what Windows'
// two speech engines are actually asked to do.
//
// What ×1.0 means
// ---------------
// ×1.0 is the **teaching pace**, not the voice's natural rate: it is defined as
// half the natural rate. A native speaker says "one thousand two hundred and
// thirty-four" in 1548 ms; at ×1.0 the drill takes 3100 ms. That anchor exists
// because the voice's natural speed is the wrong neutral for a listening drill —
// you are doing arithmetic in a second language, so native speed is the *fast*
// end of what is useful, and anchoring there left the whole useful band jammed
// against the bottom of the slider.
//
// The slider therefore maps onto the engine like this:
//
//     ×0.5  -> 0.25x natural   (...below the prosody floor: word pauses take over)
//     ×0.66 -> 0.33x natural
//     ×1.0  -> 0.50x natural   <- the anchor, and the prosody floor
//     ×1.25 -> 0.62x natural
//     ×1.5  -> 0.75x natural
//
// Why a table instead of `percent = rate * 100`
// ---------------------------------------------
// Neither engine's rate control is linear, and the code used to pass the
// multiplier straight through as an SSML prosody percentage. Measured on this
// machine (OneCore "Microsoft David", "one thousand two hundred and thirty
// four", natural = 1548 ms), the prosody percentage moves the speed in **eleven
// discrete steps**:
//
//     prosody 1-5%    -> 0.50x     prosody 90-100% -> 1.00x
//     prosody 8-15%   -> 0.57x     prosody 110-120% -> 1.12x
//     prosody 18-30%  -> 0.64x     prosody 130-150% -> 1.24x
//     prosody 35-45%  -> 0.71x     prosody 175%     -> 1.39x
//     prosody 50-60%  -> 0.80x     prosody 200%     -> 1.52x
//     prosody 70-80%  -> 0.90x
//
// So 50-150% — the entire travel of the old linear mapping — spanned four of
// them, i.e. 1.24x slower to 0.81x faster, which is why the drill felt stuck at
// one speed. The table below addresses the plateaus directly. Lookup is nearest
// in *log* space (the steps are multiplicative, ~1.12x apart); ties resolve to
// the slower step, the safer side for a listening drill.
//
// Below the floor: word pauses
// ----------------------------
// prosody cannot go below 0.50x — at 5% it clamps and stops responding. Anything
// slower is therefore done with `SpeechPlan.wordGapMs`, an SSML `<break>` between
// words, which was measured to work (natural 1548 ms -> 2279/2779/3380 ms at
// 150/300/500 ms gaps). Pauses extend the range without touching the voice or
// the pitch, and each word still gets its natural articulation, which is easier
// to follow than stretching the audio further.
//
// The gap is sized from the word count: at the floor the two ends meet (gap 0),
// and asking for half the floor's speed adds about as much silence as there is
// speech. It is a pace approximation, not an exact multiple, because a gap is an
// absolute duration and the multiplier is relative to an utterance whose natural
// length the caller does not know.

import 'dart:math' as math;

/// ×1.0 on the slider means this multiple of the voice's natural rate **on the
/// Windows engines** (see the note on the linear ones below).
const double teachingAnchor = 0.5;

/// Below this engine rate the prosody control stops responding.
double get minimalEngineRate => oneCoreSteps.first.speed;

/// Slider value → engine rate for the **Windows** voices.
///
/// The anchor applies here and nowhere else: it is a calibration of these two
/// voices (David reads the phrase in 1548 ms, ×1.0 puts it at 3100 ms, and the
/// prosody scale's useful band only starts at 50%). The linear engines — Android's
/// `setSpeechRate`, the browser's `utterance.rate`, Piper's `speed` and the
/// player's playback rate — take a plain multiplier of the voice's own natural
/// pace, so they are handed the slider value unchanged. Halving those a second
/// time is what made the phone drill crawl: Piper's natural pace is already
/// deliberate, and ×1.0 at 0.5 sounded like a tape at half speed.
double windowsEngineRateFor(double uiRate) => uiRate * teachingAnchor;

/// One achievable speed and the engine setting that produces it.
class SpeechRateStep {
  /// Playback speed as a multiplier of the engine's natural rate.
  final double speed;

  /// The value handed to that engine's rate control.
  final int setting;

  const SpeechRateStep(this.speed, this.setting);
}

/// OneCore renders rate as an SSML `<prosody rate="N%">` percentage.
const List<SpeechRateStep> oneCoreSteps = <SpeechRateStep>[
  SpeechRateStep(0.50, 3),
  SpeechRateStep(0.57, 11),
  SpeechRateStep(0.64, 24),
  SpeechRateStep(0.71, 40),
  SpeechRateStep(0.80, 55),
  SpeechRateStep(0.90, 75),
  SpeechRateStep(1.00, 95),
  SpeechRateStep(1.12, 115),
  SpeechRateStep(1.24, 140),
  SpeechRateStep(1.39, 175),
  SpeechRateStep(1.52, 200),
];

/// SAPI takes `SpVoice.Rate`, an integer -10…10 (0 = neutral). Measured over the
/// same phrase with "Microsoft David Desktop" (natural = 3099 ms).
const List<SpeechRateStep> sapiSteps = <SpeechRateStep>[
  SpeechRateStep(0.33, -10),
  SpeechRateStep(0.42, -8),
  SpeechRateStep(0.52, -6),
  SpeechRateStep(0.65, -4),
  SpeechRateStep(0.82, -2),
  SpeechRateStep(1.00, 0),
  SpeechRateStep(1.28, 2),
  SpeechRateStep(1.61, 4),
  SpeechRateStep(2.00, 6),
  SpeechRateStep(2.49, 8),
  SpeechRateStep(3.05, 10),
];

/// Mean spoken length of one word at natural rate: 1548 ms over the 7 words of
/// the calibration phrase. Only used to size pauses below the prosody floor.
const int _msPerSpokenWord = 221;

/// Longest pause inserted between words, so a mis-set preference cannot turn the
/// drill into a sequence of isolated words.
const int _maxWordGapMs = 1200;

/// Slowest engine rate the slider can ask for (×0.5 → 0.25x natural). A stored
/// or corrupt value below it is treated as this rather than dividing by zero.
const double _slowestEngineRate = 0.25;

/// Fastest the mapping needs to consider; past it every table clamps anyway.
const double _fastestEngineRate = 4.0;

/// The setting in [steps] that plays closest to [engineRate].
///
/// A non-positive rate would make the ratio undefined; the UI cannot produce
/// one, but a stored preference could.
int nearestSpeechRate(List<SpeechRateStep> steps, double engineRate) {
  final wanted = engineRate <= 0 ? steps.first.speed : engineRate;
  var best = steps.first;
  var bestDistance = double.infinity;
  for (final step in steps) {
    final distance = math.log(step.speed / wanted).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = step;
    }
  }
  return best.setting;
}

/// What one utterance has to be given to the engine.
class SpeechPlan {
  /// SSML `<prosody rate>` percentage.
  final int prosodyPercent;

  /// Silence inserted between words, 0 when the prosody control is enough.
  final int wordGapMs;

  const SpeechPlan({required this.prosodyPercent, required this.wordGapMs});

  @override
  String toString() => 'SpeechPlan(prosody: $prosodyPercent%, gap: ${wordGapMs}ms)';
}

/// The plan for an utterance of [wordCount] words at [engineRate].
///
/// Takes the output of [windowsEngineRateFor], not a slider value: the conversion
/// happens once, at the module that owns the slider.
SpeechPlan speechPlanFor(double engineRate, {required int wordCount}) {
  final clamped = engineRate.clamp(_slowestEngineRate, _fastestEngineRate);
  if (clamped >= minimalEngineRate || wordCount < 2) {
    // A single word has no gap to put a pause in; it keeps the floor and stops
    // there rather than inventing trailing silence.
    return SpeechPlan(
      prosodyPercent: nearestSpeechRate(oneCoreSteps, clamped),
      wordGapMs: 0,
    );
  }
  // Below the floor the slowest articulation is already in use, so the extra
  // time has to come from silence: the shortfall in duration ratio, spread over
  // the gaps and converted with the per-word speaking time.
  final floorRatio = 1 / minimalEngineRate;
  final shortfall = 1 / clamped - floorRatio;
  final gaps = wordCount - 1;
  final gapMs = (shortfall * _msPerSpokenWord * wordCount / gaps).round();
  return SpeechPlan(
    prosodyPercent: oneCoreSteps.first.setting,
    wordGapMs: gapMs.clamp(0, _maxWordGapMs),
  );
}

/// `SpVoice.Rate` for [engineRate] (SAPI 5 desktop voices, the fallback engine).
///
/// SAPI has no pause support here, so its floor is hard: below it the slider
/// keeps going but the speech does not. Its scale is wider than OneCore's,
/// reaching 0.33x natural, which covers all but the last fifth of the slider.
int sapiRate(double engineRate) => nearestSpeechRate(sapiSteps, engineRate);
