import 'package:flutter/services.dart';

Set<String>? _assets;

/// The asset keys compiled into the running bundle.
///
/// Clips are addressed by path (`AudioManager.play…(AssetSource)`) rather than
/// probed on disk, so native and web agree on what exists: the web build has no
/// file system to stat, and a missing asset only fails when playback starts.
Future<Set<String>> audioAssetManifest() async =>
    _assets ??= (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets().toSet();
