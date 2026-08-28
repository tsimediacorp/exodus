import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/confession.dart';
import '../services/confession_service.dart';
import '../services/progress.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/progress_view.dart';
import '../widgets/scripture_link.dart';

/// The confessional: say the thing, and be prayed for.
///
/// No partner, no wall, no audience. The privacy claim is made precisely on
/// screen rather than as a slogan — see [_privacyNote] — because "100%
/// anonymous" would be a promise the architecture cannot keep: the words do
/// reach the model that writes the prayer.
class ConfessionalScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const ConfessionalScreen({super.key, this.onOpenMenu});

  @override
  State<ConfessionalScreen> createState() => _ConfessionalScreenState();
}

class _ConfessionalScreenState extends State<ConfessionalScreen> {
  final ConfessionService _service = ConfessionService();
  final TextEditingController _input = TextEditingController();
  final ProgressController _status = ProgressController();

  List<Confession> _kept = const [];
  bool _busy = false;

  /// The prayer just returned, held apart from the kept list so it can be read
  /// before deciding whether to keep it at all.
  Confession? _answered;

  @override
  void initState() {
    super.initState();
    _kept = _service.all();
  }

  @override
  void dispose() {
    _input.dispose();
    _status.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _confess() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);

    final result = await _service.pray(text, progress: _status);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = false;
      _answered = result;
      _input.clear();
    });
  }

  /// Keeping is opt-in. The default after reading a prayer is that nothing is
  /// written down at all — for a confessional that is the right default.
  Future<void> _keep() async {
    final answered = _answered;
    if (answered == null) return;
    await _service.keep(answered);
    if (!mounted) return;
    setState(() {
      _kept = _service.all();
      _answered = null;
    });
  }

  void _discard() => setState(() => _answered = null);

  Future<void> _forget(Confession c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Delete this?'),
        content: const Text(
            'The confession and its prayer will be removed from this device '
            'for good.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.forget(c.id);
    if (!mounted) return;
    setState(() => _kept = _service.all());
  }

  Future<void> _forgetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Delete everything?'),
        content: Text(
            'All ${_kept.length} kept confessions and their prayers will be '
            'removed from this device for good.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete all',
                  style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.forgetAll();
    if (!mounted) return;
    setState(() => _kept = _service.all());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONFESSIONAL'),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
          tooltip: 'Menu',
          onPressed: widget.onOpenMenu,
        ),
        actions: [
          if (_kept.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined,
                  color: ExodusTheme.ironMist),
              tooltip: 'Delete everything',
              onPressed: _forgetAll,
            ),
        ],
      ),
      body: SafeArea(
        child: _answered != null
            ? _prayerView(_answered!)
            : _confessView(),
      ),
    );
  }

  // ---------------- Writing ----------------

  Widget _confessView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const Row(
          children: [
            ExodusShield(size: 18, glow: false),
            SizedBox(width: 9),
            Text('NO ONE ELSE SEES THIS',
                style: TextStyle(
                  color: ExodusTheme.brass,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                )),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Say it plainly.',
          style: TextStyle(
            color: ExodusTheme.porcelain,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'You will not be asked questions about it, given a plan, or told '
          'what you should have done. You will be prayed for.',
          style: TextStyle(
            color: ExodusTheme.ironMist,
            fontSize: 14,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _input,
          maxLines: 10,
          minLines: 6,
          enabled: !_busy,
          autofocus: false,
          style: const TextStyle(
              color: ExodusTheme.porcelain, fontSize: 15, height: 1.55),
          decoration: const InputDecoration(
            hintText: 'What do you need to confess?',
          ),
        ),
        const SizedBox(height: 16),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ProgressStrip(controller: _status),
          ),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _confess,
            style: FilledButton.styleFrom(
              backgroundColor: ExodusTheme.covenantBlue,
              disabledBackgroundColor: ExodusTheme.steel,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(_busy ? 'Praying…' : 'Confess it',
                style: const TextStyle(
                    color: ExodusTheme.porcelain,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
        ),
        const SizedBox(height: 20),
        _privacyNote(),
        if (_kept.isNotEmpty) ...[
          const SizedBox(height: 32),
          const Text('KEPT',
              style: TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              )),
          const SizedBox(height: 12),
          for (final c in _kept) _keptTile(c),
        ],
      ],
    );
  }

  /// The exact privacy claim, rather than a comforting one.
  ///
  /// Everything here is true of the implementation: confessions are stored
  /// under their own key, never written to memory (which feeds the check-in
  /// scanner, and therefore Counsel, where a spouse might be looking), and
  /// never sent to the couples backend. The last line is the part a vaguer
  /// promise would hide.
  Widget _privacyNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 14, color: ExodusTheme.ironMist),
              SizedBox(width: 8),
              Text('WHAT PRIVATE MEANS HERE',
                  style: TextStyle(
                    color: ExodusTheme.ironMist,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  )),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Your partner never sees this. It is not shared, not posted, and '
            'never becomes something EXODUS brings up in Counsel. Nothing is '
            'saved unless you choose to keep it.\n\n'
            'To write the prayer, the words are sent to the AI model with no '
            'name or account attached — the same as any other message in the '
            'app.',
            style: TextStyle(
              color: ExodusTheme.ironMist,
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- The prayer ----------------

  Widget _prayerView(Confession c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const Row(
          children: [
            ExodusShield(size: 18, glow: false),
            SizedBox(width: 9),
            Text('PRAYED OVER YOU',
                style: TextStyle(
                  color: ExodusTheme.brass,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                )),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          c.prayer,
          style: const TextStyle(
            color: ExodusTheme.porcelain,
            fontSize: 17,
            height: 1.72,
          ),
        ),
        if (c.scriptureRef.trim().isNotEmpty) ...[
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => openScriptureRef(context, c.scriptureRef),
              child: Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: ExodusTheme.brass.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_rounded,
                        size: 13, color: ExodusTheme.brass),
                    const SizedBox(width: 7),
                    Text(c.scriptureRef,
                        style: const TextStyle(
                          color: ExodusTheme.brass,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (c.isFallback) ...[
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 14, color: ExodusTheme.ironMist),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'EXODUS could not be reached — ${_service.lastError ?? ''} '
                  'This is a prayer from scripture rather than one written for '
                  'what you said.',
                  style: const TextStyle(
                      color: ExodusTheme.ironMist, fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 34),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: _discard,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: ExodusTheme.steel),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Let it go',
                      style: TextStyle(
                          color: ExodusTheme.ironMist,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _keep,
                  style: FilledButton.styleFrom(
                    backgroundColor: ExodusTheme.covenantBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Keep it',
                      style: TextStyle(
                          color: ExodusTheme.porcelain,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Letting it go deletes both the confession and the prayer. Nothing '
          'is written down.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: ExodusTheme.ironMist, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }

  // ---------------- Kept ----------------

  Widget _keptTile(Confession c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: ExodusTheme.midnight,
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            iconColor: ExodusTheme.ironMist,
            collapsedIconColor: ExodusTheme.ironMist,
            title: Text(
              c.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 14, height: 1.4),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_dateLabel(c.createdAt),
                  style: const TextStyle(
                      color: ExodusTheme.ironMist, fontSize: 11)),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(c.text,
                    style: const TextStyle(
                        color: ExodusTheme.ironMist,
                        fontSize: 13,
                        height: 1.55)),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(c.prayer,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 15,
                        height: 1.65)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (c.scriptureRef.trim().isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => openScriptureRef(context, c.scriptureRef),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 10),
                        child: Text(c.scriptureRef,
                            style: const TextStyle(
                              color: ExodusTheme.brass,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _forget(c),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 15, color: ExodusTheme.crimson),
                          SizedBox(width: 6),
                          Text('Delete',
                              style: TextStyle(
                                  color: ExodusTheme.crimson, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dateLabel(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}
