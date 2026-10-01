// ignore_for_file: avoid_print
//
// Engine: Dart (standalone, `dart run`) | Target: tool/ asset generation
// Build: dart run tool/generate_ipa_audio_from_mdd.dart --mdd "<path to .mdd>"
// Deps:  ffmpeg on PATH (or --ffmpeg), and the dictionary's .mdd next to its .mdx
//
// Cuts the 48 IPA demonstration clips out of the dictionary's own human
// recordings, so the chart is spoken by the same voice as the rest of the app
// instead of by a synthesizer.
//
// Reuses lib/core/mdx/mdd_reader_native.dart rather than re-implementing the
// MDict container: there is exactly one parser in this project.
//
// How a clip is chosen from a word recording
// ------------------------------------------
// Dictionary.com ships some entries as several takes of the same word in one
// file ("door" = 3 takes over 2.7 s, "you" = 5 over 4.3 s). A take is the span
// of frames above 10% of peak; when two such spans are each >= 150 ms and are
// separated by >= 350 ms of near-silence, the file is multi-take and only the
// first take is used. A single word like "cats" can contain two energy humps
// (vowel, then the /ts/ frication) with only ~120 ms between them, so it stays
// one take.
//
// Within the chosen take:
//   vowel  the nucleus: the contiguous span >= 25% of the take peak around its
//          loudest frame, plus 10% padding -- this is the actual vowel
//   onset  the first 160 ms -- a plosive/fricative plus its release, "the /p/
//          sound" as it is normally demonstrated
//   coda   the last 160 ms -- for sounds that only occur word-finally (/ŋ/,
//          /ts/, /dz/)
//   word   the whole take
//
// Every clip is then RMS-normalised to -20 dBFS with a -1 dBFS peak ceiling so
// the cells have a consistent level, and encoded to 64 kbps mono mp3.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:local_dict/core/mdx/mdd_reader_native.dart';

const int sampleRate = 22050;
const double targetRmsDb = -20.0;
const double peakCeilingDb = -1.0;
const double silenceFloorDb = -60.0;

enum Mode { vowel, onset, coda, word }

class Spec {
  final String word;
  final Mode mode;
  const Spec(this.word, this.mode);
}

/// key -> carrier word + how to cut it. Words match lib/core/ipa/ipa_data.dart
/// so the card text and the audio agree, except /dz/ where the archive has no
/// recording for "birds" (verified absent; "bed"/"beds" both exist).
const Map<String, Spec> clips = {
  'i_long':      Spec('see', Mode.vowel),
  'i_short':     Spec('sit', Mode.vowel),
  'e':           Spec('bed', Mode.vowel),
  'ae':          Spec('cat', Mode.vowel),
  'er_long':     Spec('bird', Mode.vowel),
  'schwa':       Spec('sofa', Mode.vowel),
  'v_short':     Spec('cup', Mode.vowel),
  'u_long':      Spec('food', Mode.vowel),
  'u_short':     Spec('book', Mode.vowel),
  'o_long':      Spec('door', Mode.vowel),
  'o_short':     Spec('hot', Mode.vowel),
  'a_long':      Spec('car', Mode.vowel),
  'ei':          Spec('name', Mode.vowel),
  'ai':          Spec('time', Mode.vowel),
  'oi':          Spec('boy', Mode.vowel),
  'ou':          Spec('go', Mode.vowel),
  'au':          Spec('house', Mode.vowel),
  'ie_schwa':    Spec('hear', Mode.vowel),
  'e_schwa':     Spec('hair', Mode.vowel),
  'u_schwa':     Spec('poor', Mode.vowel),
  'p':           Spec('pen', Mode.onset),
  'b':           Spec('big', Mode.onset),
  't':           Spec('tea', Mode.onset),
  'd':           Spec('day', Mode.onset),
  'k':           Spec('key', Mode.onset),
  'g':           Spec('go', Mode.onset),
  'f':           Spec('food', Mode.onset),
  'v':           Spec('very', Mode.onset),
  'th_unvoiced': Spec('think', Mode.onset),
  'th_voiced':   Spec('this', Mode.onset),
  's':           Spec('see', Mode.onset),
  'z':           Spec('zoo', Mode.onset),
  'sh':          Spec('she', Mode.onset),
  'zh':          Spec('vision', Mode.coda),
  'h':           Spec('hat', Mode.onset),
  'ch':          Spec('chair', Mode.onset),
  'dzh':         Spec('joy', Mode.onset),
  'm':           Spec('man', Mode.onset),
  'n':           Spec('no', Mode.onset),
  'ng':          Spec('sing', Mode.coda),
  'l':           Spec('light', Mode.onset),
  'r':           Spec('red', Mode.onset),
  'w':           Spec('we', Mode.onset),
  'j':           Spec('yes', Mode.onset),
  'tr':          Spec('tree', Mode.onset),
  'dr':          Spec('dry', Mode.onset),
  'ts':          Spec('cats', Mode.coda),
  'dz':          Spec('beds', Mode.coda),
};

class Clip {
  final Int16List pcm;
  final int takeStartMs;
  final int takeEndMs;
  final int startMs;
  final int endMs;
  final int takes;
  Clip(this.pcm, this.takes, this.takeStartMs, this.takeEndMs, this.startMs, this.endMs);
  int get durationMs => endMs - startMs;
}

List<double> envelope(Int16List pcm, int hopMs) {
  final hop = sampleRate * hopMs ~/ 1000;
  final out = <double>[];
  for (var i = 0; i + hop <= pcm.length; i += hop) {
    var sum = 0.0;
    for (var j = 0; j < hop; j++) {
      final v = pcm[i + j] / 32768.0;
      sum += v * v;
    }
    out.add(math.sqrt(sum / hop));
  }
  return out;
}

/// Runs of consecutive frames above [frac] of the envelope peak.
List<List<int>> spans(List<double> env, double frac) {
  final peak = env.reduce(math.max);
  final thr = peak * frac;
  final runs = <List<int>>[];
  int? start;
  for (var i = 0; i < env.length; i++) {
    if (env[i] > thr) {
      start ??= i;
    } else if (start != null) {
      runs.add([start, i]);
      start = null;
    }
  }
  if (start != null) runs.add([start, env.length]);
  return runs;
}

Clip segment(Int16List pcm, Mode mode, {int hopMs = 10}) {
  final env = envelope(pcm, hopMs);
  final runs = spans(env, 0.10);
  if (runs.isEmpty) throw const FormatException('no active region');

  // multi-take: >= 2 runs of >= 150 ms separated by >= 350 ms
  final minRun = 150 ~/ hopMs;
  final minGap = 350 ~/ hopMs;
  final takes = <List<int>>[];
  for (final r in runs) {
    if (takes.isEmpty) {
      takes.add(r);
      continue;
    }
    final prev = takes.last;
    if (r[0] - prev[1] >= minGap && (prev[1] - prev[0]) >= minRun && (r[1] - r[0]) >= minRun) {
      takes.add(r);
    } else {
      prev[1] = r[1]; // merge: one word with an internal dip
    }
  }
  final take = takes.first;
  final takeStart = take[0] * hopMs, takeEnd = take[1] * hopMs;

  int start, end;
  switch (mode) {
    case Mode.word:
      start = takeStart;
      end = takeEnd;
    case Mode.onset:
      start = takeStart;
      end = math.min(takeEnd, takeStart + 160);
    case Mode.coda:
      end = takeEnd;
      start = math.max(takeStart, takeEnd - 160);
    case Mode.vowel:
      // loudest frame inside the take, then the contiguous span around it that
      // stays above 25% of the take peak
      var peakIdx = take[0];
      for (var i = take[0]; i < take[1]; i++) {
        if (env[i] > env[peakIdx]) peakIdx = i;
      }
      final thr = env[peakIdx] * 0.25;
      var a = peakIdx, b = peakIdx;
      while (a > take[0] && env[a - 1] > thr) {
        a--;
      }
      while (b + 1 < take[1] && env[b + 1] > thr) {
        b++;
      }
      final pad = ((take[1] - take[0]) * 0.10).round();
      a = math.max(take[0], a - pad);
      b = math.min(take[1], b + pad);
      start = a * hopMs;
      end = b * hopMs;
  }
  return Clip(pcm, takes.length, takeStart, takeEnd, start, end);
}

Uint8List normalise(Int16List pcm, int startMs, int endMs) {
  final a = startMs * sampleRate ~/ 1000;
  final b = math.min(pcm.length, endMs * sampleRate ~/ 1000);
  final n = b - a;
  var sum = 0.0;
  var peak = 0.0;
  for (var i = a; i < b; i++) {
    final v = pcm[i] / 32768.0;
    sum += v * v;
    if (v.abs() > peak) peak = v.abs();
  }
  final rms = math.sqrt(sum / n);
  var gain = math.pow(10, targetRmsDb / 20) / rms;
  final ceiling = math.pow(10, peakCeilingDb / 20) / peak;
  if (gain > ceiling) gain = ceiling;

  final out = Int16List(n);
  final fade = math.min(sampleRate * 5 ~/ 1000, n ~/ 4);
  for (var i = 0; i < n; i++) {
    var v = (pcm[a + i] / 32768.0) * gain;
    if (i < fade) v *= i / fade;
    if (i >= n - fade) v *= (n - i) / fade;
    out[i] = (v.clamp(-1.0, 1.0) * 32767).round();
  }
  return out.buffer.asUint8List();
}

Uint8List wav(Int16List pcm) {
  final data = pcm.buffer.asUint8List();
  final out = BytesBuilder();
  void u32(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u16(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF]);
  out.add('RIFF'.codeUnits); u32(36 + data.length); out.add('WAVE'.codeUnits);
  out.add('fmt '.codeUnits); u32(16); u16(1); u16(1); u32(sampleRate);
  u32(sampleRate * 2); u16(2); u16(16);
  out.add('data'.codeUnits); u32(data.length); out.add(data);
  return out.toBytes();
}

Int16List decode(Ffmpeg ff, Uint8List mp3, Directory tmp, String tag) {
  final src = File('${tmp.path}/$tag.mp3')..writeAsBytesSync(mp3);
  final raw = ff.run(['-v', 'error', '-i', src.path, '-f', 's16le', '-ac', '1',
                      '-ar', '$sampleRate', '-']);
  final bytes = Uint8List.fromList(raw);
  return Int16List.view(bytes.buffer, 0, bytes.length ~/ 2);
}

class Ffmpeg {
  final String path;
  Ffmpeg(this.path);
  List<int> run(List<String> args) {
    final r = Process.runSync(path, args, stdoutEncoding: null);
    if (r.exitCode != 0) {
      throw ProcessException(path, args, '${r.stderr}', r.exitCode);
    }
    return r.stdout as List<int>;
  }
}

Future<void> main(List<String> argv) async {
  final args = <String, String>{};
  var checkOnly = false;
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--check') {
      checkOnly = true;
    } else if (argv[i].startsWith('--')) {
      args[argv[i].substring(2)] = argv[++i];
    }
  }
  final mddPath = args['mdd'] ??
      'Dictionary.com 20260913_hahaya/Dictionary.com 20260913.mdd';
  final outDir = Directory(args['out'] ?? 'assets/audio/ipa');
  final ff = Ffmpeg(args['ffmpeg'] ?? 'ffmpeg');

  if (!File(mddPath).existsSync()) {
    stderr.writeln('error: no .mdd at "$mddPath" (pass --mdd <path>)');
    exitCode = 2;
    return;
  }
  final mddPathResolved = mddPath;
  final reader = await MddReader.open(mddPathResolved);
  final tmp = Directory.systemTemp.createTempSync('ipa-clips');
  if (!checkOnly) outDir.createSync(recursive: true);

  print('source: $mddPathResolved');
  print('');
  print('${'key'.padRight(13)}${'word'.padRight(8)}${'mode'.padRight(7)}'
        '${'takes'.padRight(7)}${'take ms'.padRight(13)}${'clip ms'.padRight(9)}bytes');

  final problems = <String>[];
  final rows = <List<String>>[];
  for (final key in clips.keys.toList()..sort()) {
    final spec = clips[key]!;
    final mp3 = reader.getResource('${spec.word}.mp3');
    if (mp3 == null) {
      problems.add('$key: "${spec.word}" has no recording in the archive');
      continue;
    }
    final pcm = decode(ff, mp3, tmp, key);
    final Clip c = segment(pcm, spec.mode);
    final bytes = normalise(pcm, c.startMs, c.endMs);

    // level check on the produced clip
    final samples = Int16List.view(bytes.buffer, 0, bytes.length ~/ 2);
    var sum = 0.0;
    for (final s in samples) {
      final v = s / 32768.0;
      sum += v * v;
    }
    final rmsDb = 20 * (math.log(math.sqrt(sum / samples.length)) / math.ln10);
    if (rmsDb < silenceFloorDb) {
      problems.add('$key: clip is silent (${rmsDb.toStringAsFixed(1)} dB)');
    }
    if (c.durationMs < 80) {
      problems.add('$key: clip is only ${c.durationMs} ms');
    }

    if (!checkOnly) {
      final w = File('${tmp.path}/$key.wav')..writeAsBytesSync(wav(samples));
      ff.run(['-y', '-v', 'error', '-i', w.path, '-ac', '1', '-ar', '$sampleRate',
              '-b:a', '64k', '${outDir.path}/$key.mp3']);
    }
    final size = checkOnly ? '-' : File('${outDir.path}/$key.mp3').lengthSync().toString();
    rows.add([key, spec.word, spec.mode.name, '${c.takes}',
              '${c.takeStartMs}-${c.takeEndMs}', '${c.durationMs}', size]);
  }

  for (final r in rows) {
    print('${r[0].padRight(13)}${r[1].padRight(8)}${r[2].padRight(7)}'
          '${r[3].padRight(7)}${r[4].padRight(13)}${r[5].padRight(9)}${r[6]}');
  }
  print('');
  print(checkOnly
      ? '${rows.length}/${clips.length} clips would be written to ${outDir.path} (--check)'
      : '${rows.length}/${clips.length} clips written to ${outDir.path}');
  if (problems.isEmpty) {
    print('no problems');
  } else {
    print('PROBLEMS:');
    for (final p in problems) {
      print('  - $p');
    }
    exitCode = 1;
  }
  tmp.deleteSync(recursive: true);
}
