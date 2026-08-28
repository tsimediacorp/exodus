import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/together_service.dart';
import '../theme/exodus_theme.dart';

/// The couple's prayer wall: what they're asking God for, and what he has
/// already answered. Private prayers stay with their author — the backend
/// enforces that through the same `members` audience rule messages use.
class PrayerWallScreen extends StatefulWidget {
  final String coupleId;
  final String userId;
  final List<String> members;

  const PrayerWallScreen({
    super.key,
    required this.coupleId,
    required this.userId,
    required this.members,
  });

  @override
  State<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends State<PrayerWallScreen> {
  final TogetherService _svc = TogetherService();

  List<Prayer> _prayers = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prayers = await _svc.listPrayers(widget.coupleId);
      if (!mounted) return;
      setState(() {
        _prayers = prayers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A failed load must not render as an empty wall — that reads as "your
      // prayers are gone".
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  String _clean(Object e) {
    final s = '$e'.replaceFirst('Exception: ', '');
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    if (s.contains('TimeoutException')) return 'The connection timed out.';
    // The wall needs a backend model that may not be deployed yet.
    if (s.contains('listPrayers') || s.contains('ValidationException')) {
      return 'The prayer wall isn\'t available on the server yet. '
          'Deploy the backend and try again.';
    }
    return s;
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<_NewPrayer>(
      context: context,
      backgroundColor: ExodusTheme.obsidian,
      isScrollControlled: true,
      builder: (_) => const _AddPrayerSheet(),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _svc.addPrayer(
        coupleId: widget.coupleId,
        authorId: widget.userId,
        text: result.text,
        shared: result.shared,
        members: widget.members,
      );
      await _refresh();
    } catch (e) {
      if (mounted) _snack('Could not add: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answer(Prayer p) async {
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => _AnsweredDialog(prayer: p),
    );
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _svc.markPrayerAnswered(id: p.id, answered: true, note: note);
      HapticFeedback.mediumImpact();
      await _refresh();
    } catch (e) {
      if (mounted) _snack('Could not update: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Prayer p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Remove this prayer?'),
        content: const Text('It will be removed from the wall for good.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _svc.deletePrayer(p.id);
      await _refresh();
    } catch (e) {
      if (mounted) _snack('Could not remove: ${_clean(e)}');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ExodusTheme.steel));

  @override
  Widget build(BuildContext context) {
    final open = _prayers.where((p) => !p.answered).toList();
    final answered = _prayers.where((p) => p.answered).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Prayer wall')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        backgroundColor: ExodusTheme.covenantBlue,
        icon: const Icon(Icons.add, color: ExodusTheme.porcelain),
        label: const Text('Add prayer',
            style: TextStyle(color: ExodusTheme.porcelain)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: ExodusTheme.brass))
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                  children: [
                    if (_error != null) _errorCard(),
                    if (_error == null && _prayers.isEmpty) _empty(),
                    if (open.isNotEmpty) ...[
                      _label('ASKING'),
                      for (final p in open) _tile(p),
                    ],
                    if (answered.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _label('ANSWERED · ${answered.length}'),
                      for (final p in answered) _tile(p),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
      );

  Widget _errorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.crimson.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!,
              style: const TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _refresh,
            style: TextButton.styleFrom(
              foregroundColor: ExodusTheme.covenantGlow,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Column(
        children: [
          Icon(Icons.volunteer_activism_outlined,
              size: 44, color: ExodusTheme.steel),
          SizedBox(height: 16),
          Text('Nothing on the wall yet',
              style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            'Add what the two of you are asking God for. Keep them here, and '
            'mark them answered when he moves.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _tile(Prayer p) {
    final mine = p.authorId == widget.userId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight,
          border: Border.all(
              color: p.answered ? ExodusTheme.brass : ExodusTheme.steel),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  p.isShared ? Icons.people_outline : Icons.lock_outline,
                  size: 14,
                  color: ExodusTheme.ironMist,
                ),
                const SizedBox(width: 6),
                Text(
                  p.isShared ? (mine ? 'Shared by you' : 'Shared') : 'Private',
                  style: const TextStyle(
                      color: ExodusTheme.ironMist, fontSize: 11),
                ),
                const Spacer(),
                if (p.answered)
                  const Icon(Icons.verified_rounded,
                      color: ExodusTheme.brass, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(p.text,
                style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 15,
                  height: 1.5,
                  decoration: p.answered ? TextDecoration.none : null,
                )),
            if (p.answered && p.answeredNote.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ExodusTheme.brass.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('“${p.answeredNote}”',
                    style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 13,
                        height: 1.45,
                        fontStyle: FontStyle.italic)),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (!p.answered)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _answer(p),
                    style: TextButton.styleFrom(
                      foregroundColor: ExodusTheme.brass,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 17),
                    label: const Text('Answered'),
                  ),
                const Spacer(),
                if (mine)
                  Semantics(
                    button: true,
                    label: 'Remove prayer',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _busy ? null : () => _delete(p),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.delete_outline_rounded,
                            size: 18, color: ExodusTheme.ironMist),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewPrayer {
  final String text;
  final bool shared;
  const _NewPrayer(this.text, this.shared);
}

class _AddPrayerSheet extends StatefulWidget {
  const _AddPrayerSheet();

  @override
  State<_AddPrayerSheet> createState() => _AddPrayerSheetState();
}

class _AddPrayerSheetState extends State<_AddPrayerSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _shared = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lift above the keyboard rather than sitting under it.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What are you asking God for?',
                  style: TextStyle(
                      color: ExodusTheme.porcelain,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                style: const TextStyle(color: ExodusTheme.porcelain),
                decoration: const InputDecoration(
                    hintText: 'Lord, we\'re asking you for…'),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.people_outline, size: 16),
                    label: Text('Share with them'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.lock_outline, size: 16),
                    label: Text('Just me'),
                  ),
                ],
                selected: {_shared},
                onSelectionChanged: (s) => setState(() => _shared = s.first),
              ),
              const SizedBox(height: 18),
              // Rebuilds per keystroke so the button is genuinely disabled
              // while empty rather than looking tappable and doing nothing.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (_, value, __) => SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: value.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(
                            context, _NewPrayer(value.text.trim(), _shared)),
                    style: FilledButton.styleFrom(
                      backgroundColor: ExodusTheme.covenantBlue,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Add to the wall',
                        style: TextStyle(
                            color: ExodusTheme.porcelain,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnsweredDialog extends StatefulWidget {
  final Prayer prayer;
  const _AnsweredDialog({required this.prayer});

  @override
  State<_AnsweredDialog> createState() => _AnsweredDialogState();
}

class _AnsweredDialogState extends State<_AnsweredDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ExodusTheme.midnight,
      title: const Text('How did God answer?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“${widget.prayer.text}”',
              style: const TextStyle(
                  color: ExodusTheme.ironMist,
                  fontSize: 13,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: ExodusTheme.porcelain),
            decoration: const InputDecoration(
                hintText: 'Optional — write it down while it\'s fresh'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          style: FilledButton.styleFrom(
              backgroundColor: ExodusTheme.covenantBlue),
          child: const Text('Mark answered'),
        ),
      ],
    );
  }
}
