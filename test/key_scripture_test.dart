import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/key_scripture.dart';

/// The anchor marker must never reach the reader, and must never produce a
/// card on a reply that has no real anchor — a hero card on every reply makes
/// the card mean nothing.
void main() {
  group('parse', () {
    test('reads the marked reference', () {
      expect(
        KeyScripture.parse('Cast it on Him.\n\n[[KEY: 1 Peter 5:7]]'),
        '1 Peter 5:7',
      );
    });

    test('a reply with no anchor gets no card', () {
      expect(KeyScripture.parse('Pray at whatever time you both can.'), isNull);
    });

    test('tolerates loose spacing, casing and quotes', () {
      expect(KeyScripture.parse('x [[ key :  "Psalm 23:1" ]]'), 'Psalm 23:1');
    });

    test('prose written into the marker is refused', () {
      // A reference is short. Anything long is the model narrating, which is
      // not something to set as a citation.
      const rambling = 'the passage about casting your anxiety on him because '
          'he cares for you deeply';
      expect(KeyScripture.parse('x [[KEY: $rambling]]'), isNull);
    });

    test('an empty marker yields nothing', () {
      expect(KeyScripture.parse('x [[KEY: ]]'), isNull);
    });
  });

  group('strip', () {
    test('removes a complete marker', () {
      expect(KeyScripture.strip('Cast it on Him.\n\n[[KEY: 1 Peter 5:7]]'),
          'Cast it on Him.');
    });

    test('removes a dangling marker from a stopped reply', () {
      expect(KeyScripture.strip('Cast it on Him.\n\n[[KEY: 1 Pet'),
          'Cast it on Him.');
    });

    test('leaves an ordinary reply alone', () {
      const reply = 'Read 1 John 2:23 — the [but] clause matters.';
      expect(KeyScripture.strip(reply), reply);
    });

    test('both markers can be stripped together', () {
      // Older replies may still carry the retired follow-up marker.
      const raw = 'Sit with that.\n\n[[KEY: Psalm 23:1]]';
      expect(KeyScripture.strip(raw), 'Sit with that.');
    });
  });
}
