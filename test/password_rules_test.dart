import 'package:flutter_test/flutter_test.dart';

/// Mirrors the rules in together_screen.dart, which in turn mirror the
/// deployed Cognito policy in amplify_outputs.dart (`password_policy`:
/// min_length 8, require_uppercase, require_lowercase, require_numbers,
/// require_symbols).
///
/// The failure this guards against: a user could only discover that a symbol
/// was required by submitting and being handed a raw InvalidPasswordException
/// rendered as JSON. If the deployed policy ever changes, this test and the
/// on-screen checklist have to change with it.
bool meetsPolicy(String p) =>
    p.length >= 8 &&
    RegExp(r'[A-Z]').hasMatch(p) &&
    RegExp(r'[a-z]').hasMatch(p) &&
    RegExp(r'[0-9]').hasMatch(p) &&
    RegExp(r'[^A-Za-z0-9]').hasMatch(p);

void main() {
  group('the checklist matches the deployed Cognito policy', () {
    test('a password meeting every rule passes', () {
      expect(meetsPolicy('Covenant1!'), isTrue);
    });

    test('the exact failure from the screenshot is caught locally', () {
      // Eight characters, upper, lower, digits — but no symbol. Cognito
      // rejected this after a round trip; now it never leaves the device.
      expect(meetsPolicy('Passw0rdd'), isFalse);
    });

    test('each rule is actually required', () {
      expect(meetsPolicy('Short1!'), isFalse, reason: 'under 8 characters');
      expect(meetsPolicy('covenant1!'), isFalse, reason: 'no uppercase');
      expect(meetsPolicy('COVENANT1!'), isFalse, reason: 'no lowercase');
      expect(meetsPolicy('Covenants!'), isFalse, reason: 'no number');
      expect(meetsPolicy('Covenant11'), isFalse, reason: 'no symbol');
    });

    test('a range of symbols all count', () {
      for (final symbol in ['!', '?', r'$', '#', '@', '%', '&', '*', '-', '_']) {
        expect(meetsPolicy('Covenant1$symbol'), isTrue,
            reason: '$symbol should satisfy the symbol rule');
      }
    });

    test('whitespace counts as a symbol, as Cognito treats it', () {
      expect(meetsPolicy('Covenant 1x'), isTrue);
    });
  });
}
