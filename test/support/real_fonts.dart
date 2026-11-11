import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's real typefaces into the test engine.
///
/// Widget tests otherwise draw every glyph as a square block that is far
/// wider than Spectral or the system sans, so a layout that fits a real
/// phone "overflows" in the test. Size-sensitive tests (the iPhone Duo
/// layouts) load the real fonts so a failure means a real overflow.
///
/// The theme asks for 'Inter', which is not bundled, so on device iOS falls
/// back to its system sans. Roboto stands in for it here: close enough in
/// width to judge fit, and it ships with the Flutter SDK.
Future<void> loadRealFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Spectral', [
    for (final w in ['Light', 'LightItalic', 'Regular', 'Italic', 'SemiBold'])
      'assets/fonts/Spectral-$w.ttf',
  ]);

  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk == null) return;
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  final roboto = [
    for (final w in ['Regular', 'Medium', 'Bold', 'Italic'])
      '$material/Roboto-$w.ttf',
  ].where((p) => File(p).existsSync()).toList();
  await load('Inter', roboto);
  await load('Roboto', roboto);
  final icons = '$material/MaterialIcons-Regular.otf';
  if (File(icons).existsSync()) await load('MaterialIcons', [icons]);
}
