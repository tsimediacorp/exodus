import 'package:flutter/foundation.dart';
import 'storage_service.dart';

/// Standing instructions the couple wrote themselves.
///
/// Memory is what EXODUS picked up; this is what they told it outright, and
/// the two were being treated the same. A line like "keep it short" or "call
/// her Dani" sat in a list of sixty facts under a heading that said to let it
/// inform the answer naturally, and it lost to the house style every time.
/// These are stated as instructions, placed last in the system prompt, and
/// restated beside the newest message — see [AiService] — because an
/// instruction thirty turns up a long thread is one a model stops following.
///
/// On the device only. They are not part of the beta snapshot the admin panel
/// receives and nothing remote can write them: an instruction about how
/// someone wants to be spoken to has to be theirs, or it is not one.
class CustomInstructions extends ChangeNotifier {
  CustomInstructions._();
  static final CustomInstructions instance = CustomInstructions._();

  /// Enough room to say something real, bounded so two paragraphs of
  /// preference cannot crowd out the conversation in a small context window.
  static const int maxLength = 1500;

  String _about = '';
  String _how = '';
  bool _enabled = true;

  /// What EXODUS should know about them.
  String get about => _about;

  /// How they want EXODUS to answer.
  String get how => _how;

  bool get enabled => _enabled;
  bool get isEmpty => _about.isEmpty && _how.isEmpty;

  /// Whether anything will actually reach the model.
  bool get isActive => _enabled && !isEmpty;

  void load() {
    final storage = StorageService.instance;
    _about = storage.instructionsAbout;
    _how = storage.instructionsHow;
    _enabled = storage.instructionsEnabled;
    notifyListeners();
  }

  Future<void> save({
    required String about,
    required String how,
    required bool enabled,
  }) async {
    _about = _clip(about);
    _how = _clip(how);
    _enabled = enabled;
    await StorageService.instance
        .saveInstructions(about: _about, how: _how, enabled: _enabled);
    notifyListeners();
  }

  static String _clip(String s) {
    final t = s.trim();
    return t.length <= maxLength ? t : t.substring(0, maxLength);
  }

  /// The block that closes the system prompt. Empty when there is nothing to
  /// say, so callers can append unconditionally.
  ///
  /// With [shaped] the caller is generating something with a fixed form — a
  /// devotional, a study exercise, a JSON batch — and an instruction such as
  /// "answer in two sentences" must not be allowed to break it.
  String promptBlock({bool shaped = false}) {
    if (!isActive) return '';
    final b = StringBuffer('''

# ============================================================
# STANDING INSTRUCTIONS FROM THIS COUPLE
# They wrote these themselves. They apply to every reply, from the first to
# the last, without being repeated.
# ============================================================
''');
    if (_about.isNotEmpty) {
      b.writeln('What they want you to know about them:\n$_about\n');
    }
    if (_how.isNotEmpty) {
      b.writeln('How they want you to respond:\n$_how\n');
    }
    b.write('''
Follow these exactly. Where they conflict with your default voice, tone,
length or format above, theirs win: if they ask for short, be short; if they
ask for gentle, be gentle; if they ask to be called something, use it. Do not
mention that you were instructed, and do not drift back to your defaults as
the conversation goes on.

They change how you speak, not what scripture says, and they never set aside
the boundaries on abuse, self-harm or danger.
''');
    if (shaped) {
      b.write('''
This request asks for a specific format. Keep that format exactly; apply the
instructions above to everything the format leaves open.
''');
    }
    return b.toString();
  }

  /// A short restatement, sent beside the newest message in Counsel.
  ///
  /// Only the response preferences: who they are does not fade with distance
  /// the way "stop ending with a prayer" does.
  String reminder() {
    if (!isActive || _how.isEmpty) return '';
    return 'Before you answer: this couple\'s standing instructions for how '
        'you respond still apply to this reply.\n$_how';
  }
}
