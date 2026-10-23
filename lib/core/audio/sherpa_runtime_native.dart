import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Loads the ONNX Runtime that sits beside the executable, before sherpa-onnx
/// is opened.
///
/// Windows resolves `onnxruntime.dll` from the application directory, then from
/// System32 — and System32 can hold a runtime older than the one sherpa-onnx was
/// built against, which then refuses the model with "requested API version 28 is
/// not available". Loading the shipped copy by path first wins the name.
void preloadOnnxRuntime() {
  if (!Platform.isWindows) return;
  try {
    final beside = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}onnxruntime.dll',
    );
    if (beside.existsSync()) {
      DynamicLibrary.open(beside.path);
    }
  } catch (e) {
    debugPrint('onnxruntime.dll beside the app could not be loaded: $e');
  }
}
