import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'speech_rate.dart';
import 'voice_choice.dart';

/// The machine's own voices: the modern OneCore ones (Windows' "Mobile"/Natural
/// voices, which Narrator uses) and the old SAPI 5 Desktop ones, probed once.
///
/// Windows exposes them through two completely different APIs — WinRT for
/// OneCore, COM for SAPI — so the probe runs a helper script that asks both. The
/// selection itself lives in `voice_choice.dart` and is unit-tested; this file
/// only talks to the system.
List<SentenceVoice>? _voices;

Future<List<SentenceVoice>> systemVoices() async {
  if (_voices != null) return _voices!;
  if (!Platform.isWindows) return _voices = const [];
  final found = <SentenceVoice>[];
  try {
    final script = await _helperScript();
    final result = await Process.run('powershell', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path, '-Action', 'list',
    ]);
    for (final line in const LineSplitter().convert(result.stdout.toString())) {
      final parts = line.split('|');
      if (parts.length != 3) continue;
      final engine = parts[2].trim() == 'onecore' ? VoiceEngine.oneCore : VoiceEngine.sapi;
      final language = _normaliseLanguage(parts[1].trim());
      if (language.isEmpty) continue;
      found.add(SentenceVoice(name: parts[0].trim(), language: language, engine: engine));
    }
  } catch (e) {
    debugPrint('Voice probe failed: $e');
  }
  return _voices = found;
}

Future<SentenceVoice?> chosenSentenceVoice(String accent) async =>
    chooseSentenceVoice(await systemVoices(), accent);

/// SAPI reports an LCID in hex text ("409" = 0x409); OneCore reports a tag.
String _normaliseLanguage(String raw) {
  if (raw.contains('-')) return raw;
  final lcid = int.tryParse(raw, radix: 16);
  return switch (lcid) {
    0x409 => 'en-US',
    0x809 => 'en-GB',
    0x804 => 'zh-CN',
    0x404 => 'zh-TW',
    null => raw,
    _ => 'lcid-${lcid.toRadixString(16)}',
  };
}

File? _script;

/// One helper for both APIs: `list`, plus `speak` (SAPI) and `wav` (OneCore).
Future<File> _helperScript() async {
  if (_script != null) return _script!;
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, 'local_dict_speech.ps1'));
  // Always rewritten: a stale copy from an older build would keep its bugs.
  await file.writeAsString(r"""
param(
  [string]$Action = 'list', [string]$Voice = '', [string]$Engine = 'sapi',
  [int]$RatePercent = 100, [int]$SapiRate = 0, [int]$WordGapMs = 0,
  [string]$Text = '', [string]$Out = ''
)
# SAPI: `$voice` would BE the -Voice parameter (names are case-insensitive), so
# the COM object needs a name of its own.
function List-Sapi {
  $sapi = New-Object -ComObject SAPI.SpVoice
  foreach ($candidate in $sapi.GetVoices()) {
    "$($candidate.GetDescription())|$([int]$candidate.GetAttribute('Language'))|sapi"
  }
}

function List-OneCore {
  [void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
  foreach ($candidate in [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices) {
    "$($candidate.DisplayName)|$($candidate.Language)|onecore"
  }
}

if ($Action -eq 'list') {
  try { List-OneCore } catch { }
  try { List-Sapi } catch { }
  exit 0
}

if ($Engine -eq 'onecore') {
  [void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
  if ($Voice) {
    foreach ($candidate in [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices) {
      if ($candidate.DisplayName -eq $Voice) { $synth.Voice = $candidate; break }
    }
  }
  # Below the prosody floor the only way further down is silence between words:
  # each word keeps its natural articulation and the gaps do the slowing.
  if ($WordGapMs -gt 0) {
    $break = "<break time=""${WordGapMs}ms""/>"
    $escaped = (($Text -split '\s+') | Where-Object { $_ } | ForEach-Object {
        [System.Security.SecurityElement]::Escape($_)
      }) -join $break
  } else {
    $escaped = [System.Security.SecurityElement]::Escape($Text)
  }
  $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>" +
          "<prosody rate=""$RatePercent%"">$escaped</prosody></speak>"
  # The 1-argument AsTask overload, matched by interface name: these are open
  # generic definitions (their argument is called "TResult"), and the type name
  # itself contains a backtick, which PowerShell would escape inside a string.
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.IsGenericType -and
      $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*' -and
      $_.GetParameters()[0].ParameterType.Name -notlike '*WithProgress*'
    })[0]
  $stream = $asTask.MakeGenericMethod(
      [Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke(
      $null, @($synth.SynthesizeSsmlToStreamAsync($ssml))).GetAwaiter().GetResult()
  # Extension methods are not reachable as instance calls from PowerShell.
  $reader = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
  $writer = [System.IO.File]::Create($Out)
  $reader.CopyTo($writer)
  $writer.Close()
  exit 0
}

$sapi = New-Object -ComObject SAPI.SpVoice
if ($Voice) {
  foreach ($candidate in $sapi.GetVoices()) {
    if ($candidate.GetDescription() -eq $Voice) { $sapi.Voice = $candidate; break }
  }
}
# The caller picks the rate off the same measured table as the OneCore path
# (see speech_rate.dart), so `rate` means one thing across both engines.
$sapi.Rate = $SapiRate
[void]$sapi.Speak($Text)
""", flush: true);
  return _script = file;
}

Process? _speaking;

/// Speaks [text] as one utterance through SAPI.
Future<bool> speakWithSapi(String text, SentenceVoice voice, {double rate = 1.0}) async {
  try {
    final script = await _helperScript();
    _speaking = await Process.start('powershell', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path,
      '-Action', 'speak', '-Engine', 'sapi', '-Voice', voice.name,
      '-SapiRate', '${sapiRate(rate)}', '-Text', text,
    ]);
    final exitCode = await _speaking!.exitCode;
    _speaking = null;
    if (exitCode != 0) debugPrint('SAPI speech exited with $exitCode');
    return exitCode == 0;
  } catch (e) {
    debugPrint('SAPI speech failed: $e');
    return false;
  } finally {
    _speaking = null;
  }
}

/// Renders [text] to a wav file with a OneCore voice, returning its path.
///
/// OneCore has no "speak now" call in this bridging setup, so the audio is
/// written to a file and played by the app; that also lets the UI keep its own
/// playback control (rate is baked in as an SSML prosody percentage).
Future<String?> synthesizeWithVoice(
  String text,
  SentenceVoice voice, {
  double rate = 1.0,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    var hash = 17;
    for (final unit in text.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final plan = speechPlanFor(rate, wordCount: RegExp(r'\S+').allMatches(text).length);
    final out = File(p.join(
      dir.path,
      'sentence_${hash.toRadixString(16)}_${plan.prosodyPercent}_${plan.wordGapMs}.wav',
    ));
    if (out.existsSync() && out.lengthSync() > 4000) return out.path;

    final script = await _helperScript();
    final result = await Process.run('powershell', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path,
      '-Action', 'wav', '-Engine', 'onecore', '-Voice', voice.name,
      '-RatePercent', '${plan.prosodyPercent}',
      '-WordGapMs', '${plan.wordGapMs}',
      '-Text', text, '-Out', out.path,
    ]);
    if (result.exitCode != 0) {
      debugPrint('OneCore synthesis exited with ${result.exitCode}: ${result.stderr}');
      return null;
    }
    if (!out.existsSync() || out.lengthSync() < 4000) {
      debugPrint('OneCore synthesis produced no audio');
      return null;
    }
    return out.path;
  } catch (e) {
    debugPrint('OneCore synthesis failed: $e');
    return null;
  }
}

/// Stops a SAPI utterance in flight (OneCore renders to a file first).
void cancelSystemVoice() {
  _speaking?.kill();
  _speaking = null;
}
