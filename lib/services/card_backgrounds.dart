import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Photographic backgrounds for the scripture card, discovered at runtime.
///
/// Deliberately read from the ASSET MANIFEST rather than a hardcoded list:
/// dropping a file into assets/backgrounds/ is all it takes to add one, with
/// no code change and nothing to keep in sync. An empty folder is a valid
/// state — the card falls back to the painted landscape — so the app ships and
/// runs identically whether artwork exists yet or not.
class CardBackgrounds {
  CardBackgrounds._();

  static const String _folder = 'assets/backgrounds/';
  static const _imageTypes = {'.jpg', '.jpeg', '.png', '.webp'};

  static List<String>? _cached;

  /// Everything available, sorted so the choice is stable across launches.
  static List<String> get available => _cached ?? const [];

  static bool get hasAny => available.isNotEmpty;

  /// The images in [paths], sorted.
  ///
  /// Separate from [load] so the rule itself can be tested: the folder also
  /// holds a README explaining the drop-in contract, and shipping that as a
  /// card background would be a silent, ugly failure.
  @visibleForTesting
  static List<String> imagesIn(Iterable<String> paths) => paths
      .where((path) =>
          path.startsWith(_folder) &&
          _imageTypes.any((ext) => path.toLowerCase().endsWith(ext)))
      .toList()
    ..sort();

  /// Read the manifest once. Safe to call repeatedly and safe to skip: until
  /// it completes, [pick] returns null and the painted fallback is used.
  static Future<void> load() async {
    if (_cached != null) return;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _cached = imagesIn(manifest.listAssets());
    } catch (_) {
      // No manifest, or an unreadable bundle. The painted landscape covers it.
      _cached = const [];
    }
  }

  /// Stand in for the manifest, so the selection rule can be exercised without
  /// a built asset bundle. Pass null to return to the unloaded state.
  @visibleForTesting
  static void debugSetAvailable(List<String>? paths) {
    _cached = paths == null ? null : imagesIn(paths);
  }

  /// The background for [seed], or null when there are none.
  ///
  /// Deterministic: the same verse always gets the same image, so a card does
  /// not change scene as the thread rebuilds or the couple scrolls past it
  /// twice. Random() is seeded rather than using the hash directly so that a
  /// short list does not correlate with reference length.
  static String? pick(String seed) {
    final files = available;
    if (files.isEmpty) return null;
    return files[Random(seed.hashCode).nextInt(files.length)];
  }
}
