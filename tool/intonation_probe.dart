import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main() {
  DynamicLibrary.open(
    r'C:\Users\eater\AppData\Local\Temp\sherpa\sherpa-onnx-v1.13.8-win-x64-shared-MD-Release\lib\onnxruntime.dll',
  );
  sherpa.initBindings(
    r'C:\Users\eater\AppData\Local\Temp\sherpa\sherpa-onnx-v1.13.8-win-x64-shared-MD-Release\lib',
  );
  const root = 'tts-models/kokoro';
  final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: '$root/model.onnx',
        voices: '$root/voices.bin',
        tokens: '$root/tokens.txt',
        dataDir: '$root/espeak-ng-data',
      ),
      numThreads: 4,
      debug: false,
    ),
    maxNumSenetences: 1,
  ));
  final samples = <String, String>{
    'statement': 'You are coming to the party.',
    'question': 'Are you coming to the party?',
    'exclaim': 'You are coming to the party!',
  };
  for (final entry in samples.entries) {
    final audio = tts.generateWithConfig(
      text: entry.value,
      config: const sherpa.OfflineTtsGenerationConfig(),
    );
    File('C:/Users/eater/AppData/Local/Temp/inton_${entry.key}.wav')
        .writeAsBytesSync(_wav(audio.samples, audio.sampleRate));
    print('${entry.key}: ${(audio.samples.length / audio.sampleRate).toStringAsFixed(2)} s');
  }
  tts.free();
}

List<int> _wav(Float32List s, int rate) {
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  b.add('RIFF'.codeUnits); u32(36 + s.length * 2);
  b.add('WAVEfmt '.codeUnits); u32(16); u16(1); u16(1);
  u32(rate); u32(rate * 2); u16(2); u16(16);
  b.add('data'.codeUnits); u32(s.length * 2);
  for (final x in s) {
    final v = (x.clamp(-1.0, 1.0) * 32767).round();
    b.addByte(v & 0xFF); b.addByte((v >> 8) & 0xFF);
  }
  return b.takeBytes();
}
