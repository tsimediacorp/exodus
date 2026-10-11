import 'package:flutter/material.dart';

import '../services/custom_instructions.dart';
import '../theme/exodus_theme.dart';
import '../widgets/page_backdrop.dart';

/// Where the couple tells EXODUS, once, how they want to be spoken to.
///
/// Two fields rather than one, because they answer different questions and
/// people fill in a blank box with whichever one they thought of first: who
/// you are talking to, and how to talk to them.
class CustomInstructionsScreen extends StatefulWidget {
  const CustomInstructionsScreen({super.key});

  @override
  State<CustomInstructionsScreen> createState() =>
      _CustomInstructionsScreenState();
}

class _CustomInstructionsScreenState extends State<CustomInstructionsScreen> {
  final _store = CustomInstructions.instance;
  late final _about = TextEditingController(text: _store.about);
  late final _how = TextEditingController(text: _store.how);
  late bool _enabled = _store.enabled;

  bool get _dirty =>
      _about.text.trim() != _store.about ||
      _how.text.trim() != _store.how ||
      _enabled != _store.enabled;

  @override
  void initState() {
    super.initState();
    _about.addListener(_changed);
    _how.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _about.dispose();
    _how.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _store.save(
        about: _about.text, how: _how.text, enabled: _enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Saved. EXODUS will follow these from the next message.'),
      duration: Duration(seconds: 2),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('Custom instructions',
            style: TextStyle(letterSpacing: 0.2, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: _dirty ? _save : null,
            child: Text('Save',
                style: TextStyle(
                  color: _dirty ? ExodusTheme.brass : ExodusTheme.steel,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                )),
          ),
          const SizedBox(width: 6),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: PageBackdrop(
        child: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Text(
                'Tell EXODUS once.',
                style: TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: ExodusTheme.parchment,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'What you write here applies to every answer, in Counsel, '
                'Coaching, your devotional and everything else, without you '
                'having to say it again. Stored on this device only.',
                style: TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 14.5, height: 1.5),
              ),
              const SizedBox(height: 22),
              _toggle(),
              const SizedBox(height: 22),
              _field(
                label: 'WHAT SHOULD EXODUS KNOW ABOUT YOU?',
                controller: _about,
                hint: 'Your names, how long you have been together, your '
                    'children, your church, what season you are in.',
                examples: const [
                  'We are Marcus and Dani, married four years.',
                  'We have a two-year-old and one on the way.',
                  'We read the ESV.',
                ],
              ),
              const SizedBox(height: 24),
              _field(
                label: 'HOW SHOULD EXODUS RESPOND?',
                controller: _how,
                hint: 'Length, tone, what to always do, what to stop doing.',
                examples: const [
                  'Keep answers short unless I ask for more.',
                  'Call me Dani.',
                  'Give me one thing to do, not five.',
                  'Do not end with a prayer unless I ask.',
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight.withValues(alpha: 0.72),
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _enabled ? 'EXODUS is following these' : 'Paused',
              style: const TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: _enabled,
            activeThumbColor: ExodusTheme.obsidian,
            activeTrackColor: ExodusTheme.brass,
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required List<String> examples,
  }) {
    final used = controller.text.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              color: ExodusTheme.brass,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
            )),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          minLines: 4,
          maxLines: 10,
          maxLength: CustomInstructions.maxLength,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: ExodusTheme.brass,
          style: const TextStyle(
            fontFamily: ExodusTheme.serif,
            color: ExodusTheme.parchment,
            fontSize: 16,
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintMaxLines: 3,
            hintStyle: TextStyle(
              fontFamily: ExodusTheme.serif,
              color: ExodusTheme.ironMist.withValues(alpha: 0.75),
              fontSize: 15.5,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
            // Only worth showing as the limit approaches.
            counterText: used > CustomInstructions.maxLength - 200
                ? '$used / ${CustomInstructions.maxLength}'
                : '',
            fillColor: ExodusTheme.midnight.withValues(alpha: 0.72),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: ExodusTheme.brass.withValues(alpha: 0.6), width: 1.2),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Tapping one adds it, so the blank box has somewhere to start.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final example in examples)
              if (!controller.text.contains(example))
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final current = controller.text.trimRight();
                    final next =
                        current.isEmpty ? example : '$current\n$example';
                    controller.value = TextEditingValue(
                      text: next,
                      selection:
                          TextSelection.collapsed(offset: next.length),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: ExodusTheme.slate.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            size: 14, color: ExodusTheme.ironMist),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(example,
                              style: const TextStyle(
                                  color: ExodusTheme.ironMist, fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
