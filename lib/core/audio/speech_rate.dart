// Engine: Dart (pure) | Target: lib/core/audio
//
// Maps the speed multiplier the UI shows (语速 ×0.5 … ×1.5) onto what Windows'
// two speech engines can actually produce.
//
// Why a table instead of `percent = rate * 100`
// ---------------------------------------------
// Neither engine's rate control is linear, and the old code passed the
// multiplier straight through as an SSML prosody percentage. Measured on this
// machine (OneCore "Microsoft David", "one thousand two hundred and thirty
// four", neutral = 1548 ms), the prosody percentage moves the speed in **eleven
// discrete steps**, and 50–150% — the entire travel of the old mapping — spans
// only four of them:
//
//     prosody 1-5%    -> 0.50x     prosody 90-100% -> 1.00x
//     prosody 8-15%   -> 0.57x     prosody 110-120% -> 1.12x
//     prosody 18-30%  -> 0.64x     prosody 130-150% -> 1.24x
//     prosody 35-45%  -> 0.71x     prosody 175%     -> 1.39x
//     prosody 50-60%  -> 0.80x     prosody 200%     -> 1.52x
//     prosody 70-80%  -> 0.90x
//
// So the slider's ×0.5 end did nothing: the slowest result was 1.24x slower and
// the fastest 0.81x quicker, which is why the drill felt like it was stuck at
// one speed. The steps do cover 0.50x–1.52x — the slider's nominal range
// exactly — they just have to be addressed by plateau rather than linearly.
//
// SAPI (the fallback engine) is far more generous: `SpVoice.Rate` -10…10 gives
// 3.0x slower … 3.1x faster, measured the same way (neutral = 3099 ms). Both
// tables are recorded so `rate` means the same thing whichever engine ran.
//
// The lookup takes the nearest step in *log* space, because the steps are
// multiplicative (~1.12x apart); ties resolve to the slower step, the safer side
// for a listening drill.

import 'dart:math' as math;

/// One achievable speed and the engine setting that produces it.
class SpeechRateStep {
  /// Playback speed as a multiplier of the engine's neutral setting.
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

/// SAPI takes `SpVoice.Rate`, an integer -10…10 (0 = neutral).
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

/// The setting in [steps] that plays closest to [rate].
///
/// A non-positive multiplier would make the ratio undefined; the UI cannot
/// produce one, but a stored preference could.
int nearestSpeechRate(List<SpeechRateStep> steps, double rate) {
  final wanted = rate <= 0 ? steps.first.speed : rate;
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

/// SSML prosody percentage for [rate] (OneCore / modern Windows voices).
int oneCoreProsodyPercent(double rate) => nearestSpeechRate(oneCoreSteps, rate);

/// `SpVoice.Rate` for [rate] (SAPI 5 desktop voices).
int sapiRate(double rate) => nearestSpeechRate(sapiSteps, rate);
