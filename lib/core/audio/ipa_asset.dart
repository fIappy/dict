import 'asset_manifest.dart';

/// Resolves which bundled IPA clip to play for [audioAssetKey].
///
/// Order: the requested accent, the other accent, then a bare `<key>.mp3`.
/// Cambridge's phonetics page only publishes a recording for the accents a sound
/// actually has (`/ɒ/ /ɜː/ /əʊ/ /ɪə/ /eə/ /ʊə/` are UK-only, `/ɝː/ /ɚ/ /oʊ/ /t̬/`
/// are US-only), and the offline generators in `tool/` write unaccented files.
/// A missing clip resolves to null so the caller stays silent instead of playing
/// a recording of the wrong accent.
///
/// Existence comes from the asset manifest, so native and web agree; the web
/// build has no file system to probe.
Future<String?> resolveIpaAsset(String audioAssetKey, String accent) async {
  final other = accent == 'uk' ? 'us' : 'uk';
  final candidates = [
    'audio/ipa/${audioAssetKey}_$accent.mp3',
    'audio/ipa/${audioAssetKey}_$other.mp3',
    'audio/ipa/$audioAssetKey.mp3',
  ];
  // Manifest keys are pubspec-relative ('assets/audio/ipa/x.mp3'), while
  // audioplayers' AssetSource takes the path inside `assets/`, so probe with the
  // prefix and hand back the path without it.
  final assets = await audioAssetManifest();
  for (final asset in candidates) {
    if (assets.contains('assets/$asset')) return asset;
  }
  return null;
}
