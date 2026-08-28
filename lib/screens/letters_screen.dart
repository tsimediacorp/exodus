import 'package:flutter/material.dart';
import '../models/marriage_letter.dart';
import '../services/letter_service.dart';
import '../services/progress.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/progress_view.dart';

/// The weekly letters EXODUS writes the couple, newest first, plus a card for
/// the week just gone that shows what would feed it before spending a request.
class LettersScreen extends StatefulWidget {
  const LettersScreen({super.key});

  @override
  State<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends State<LettersScreen> {
  final StorageService _storage = StorageService.instance;
  final LetterService _service = LetterService();
  final ProgressController _status = ProgressController();

  List<MarriageLetter> _letters = const [];
  bool _busy = false;
  String? _error;

  /// Monday of the week that just finished — the one a letter is written for.
  DateTime get _lastWeek => MarriageLetter.startOfWeek(
      DateTime.now().subtract(const Duration(days: 7)));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    _status.dispose();
    super.dispose();
  }

  void _load() => setState(() => _letters = _storage.loadLetters());

  Future<void> _write(DateTime weekStart) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final letter = await _service.generate(weekStart, progress: _status);
    if (!mounted) return;
    _status.done();
    setState(() {
      _busy = false;
      _error = letter == null ? _service.lastError : null;
    });
    _load();
    if (letter != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _LetterDetailScreen(letter: letter)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = _storage.letterForWeek(_lastWeek);
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly letter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text(
              'Each week EXODUS writes the two of you a letter, drawn from what '
              'you actually did — the devotionals you read, what you worked on, '
              'and what you have been carrying.',
              style: TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            if (_busy) ...[
              ProgressStrip(controller: _status),
              const SizedBox(height: 12),
            ],
            if (existing == null) _composeCard(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorCard(),
            ],
            if (_letters.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('LETTERS',
                  style: TextStyle(
                      color: ExodusTheme.ironMist,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              for (final l in _letters) _letterTile(l),
            ] else if (existing == null && !_busy) ...[
              const SizedBox(height: 32),
              _empty(),
            ],
          ],
        ),
      ),
    );
  }

  /// The week just gone, with the basis shown up front so the couple can see
  /// the letter is built from their real week rather than generic filler.
  Widget _composeCard() {
    final basis = _service.gather(_lastWeek);
    final label = MarriageLetter(weekStart: _lastWeek, body: '', basis: '')
        .rangeLabel;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ExodusShield(size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Week of $label',
                    style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(basis.summary,
              style: const TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 13, height: 1.4)),
          if (basis.isEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'There is not much to draw on yet — the letter will be short and '
              'honest about that.',
              style: TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : () => _write(_lastWeek),
              style: FilledButton.styleFrom(
                backgroundColor: ExodusTheme.covenantBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ExodusTheme.porcelain),
                    )
                  : const Text('Write this week\'s letter',
                      style: TextStyle(
                          color: ExodusTheme.porcelain,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.crimson.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined,
              color: ExodusTheme.crimson, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_error!,
                style: const TextStyle(
                    color: ExodusTheme.porcelain, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'No letters yet. Write the first one above.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ExodusTheme.ironMist, fontSize: 14),
        ),
      ),
    );
  }

  Widget _letterTile(MarriageLetter l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ExodusTheme.midnight,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _LetterDetailScreen(letter: l)),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: ExodusTheme.steel),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.mail_outline_rounded,
                    color: ExodusTheme.brass, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.rangeLabel,
                          style: const TextStyle(
                              color: ExodusTheme.porcelain, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(l.basis,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: ExodusTheme.ironMist, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: ExodusTheme.ironMist, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LetterDetailScreen extends StatelessWidget {
  final MarriageLetter letter;
  const _LetterDetailScreen({required this.letter});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(letter.rangeLabel)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExodusShield(size: 40),
              const SizedBox(height: 20),
              SelectableText(
                letter.body,
                style: const TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 16,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                letter.basis,
                style: const TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
