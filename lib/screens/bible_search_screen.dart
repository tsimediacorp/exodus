import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../config/bible_prompt.dart';
import '../models/bible_ref.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/bible_service.dart';
import '../services/progress.dart';
import '../theme/exodus_theme.dart';
import '../widgets/progress_view.dart';

/// What the reader gets back when the couple picks a search result.
class BibleSearchResult {
  final BibleRef ref;

  /// Why EXODUS surfaced this passage — shown as a banner in the reader.
  final String? why;

  const BibleSearchResult(this.ref, this.why);
}

class _Hit {
  final BibleRef ref;
  final String label;
  final String preview;
  final String? why;
  const _Hit(
      {required this.ref,
      required this.label,
      required this.preview,
      this.why});
}

/// Search the Bible two ways: ask EXODUS what speaks to something, or search
/// for exact wording. Both return references that the reader jumps to.
class BibleSearchScreen extends StatefulWidget {
  const BibleSearchScreen({super.key});

  @override
  State<BibleSearchScreen> createState() => _BibleSearchScreenState();
}

class _BibleSearchScreenState extends State<BibleSearchScreen> {
  final BibleService _bible = BibleService.instance;
  final AiService _ai = AiService();
  final TextEditingController _input = TextEditingController();
  final ProgressController _progress = ProgressController();

  bool _aiMode = true;
  bool _busy = false;
  String? _error;
  List<_Hit> _hits = const [];
  bool _searched = false;

  @override
  void dispose() {
    _input.dispose();
    _ai.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final query = _input.text.trim();
    if (query.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _searched = true;
      _hits = const [];
    });
    try {
      _progress.begin(
        _bible.isLoaded
            ? 'Preparing…'
            : 'Loading the ${BibleService.translation}…',
        step: 1,
        totalSteps: _aiMode ? 3 : 2,
      );
      await _bible.load();
      final hits = _aiMode ? await _askExodus(query) : _searchText(query);
      if (!mounted) return;
      _progress.done();
      setState(() {
        _hits = hits;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      _progress.done();
      setState(() {
        _busy = false;
        _error = _friendly(e);
      });
    }
  }

  /// Ask the model for references, then read the actual text out of the
  /// bundled translation. The model never supplies verse text, so it cannot
  /// put words in scripture's mouth — and any reference it invents is dropped
  /// here when it fails to resolve.
  Future<List<_Hit>> _askExodus(String query) async {
    // Stage 2 of 3 — AiService narrates the round-trip and any retries.
    _progress.stage('Asking EXODUS which passages speak to this…',
        step: 2, totalSteps: 3);
    final raw = await _ai.ask(
      userMessage: BiblePrompt.search(query,
          translation: BibleService.translation),
      history: const <ChatMessage>[],
      maxTokens: 1200,
      timeout: const Duration(seconds: 30),
      progress: _progress,
      workingMessage: 'Asking EXODUS which passages speak to this…',
    );
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    late final List<dynamic> parsed;
    try {
      parsed = jsonDecode(raw.substring(start, end + 1)) as List<dynamic>;
    } catch (_) {
      return const [];
    }

    _progress.stage(
        'Looking up ${parsed.length} passage${parsed.length == 1 ? '' : 's'} '
        'in the ${BibleService.translation}…',
        step: 3,
        totalSteps: 3);

    final hits = <_Hit>[];
    for (final item in parsed) {
      if (item is! Map) continue;
      final refText = (item['ref'] ?? '').toString();
      final why = (item['why'] ?? '').toString().trim();
      final parsedRef = _bible.parse(refText);
      if (parsedRef == null) continue;
      final resolved = _bible.resolve(parsedRef);
      if (resolved == null) continue;
      final text = _bible.textFor(resolved);
      if (text.isEmpty) continue;
      hits.add(_Hit(
        ref: resolved,
        label: _bible.label(resolved),
        preview: text,
        why: why.isEmpty ? null : why,
      ));
    }
    return hits;
  }

  List<_Hit> _searchText(String query) {
    _progress.stage('Scanning every verse of the ${BibleService.translation}…',
        step: 2, totalSteps: 2);
    return _bible
        .searchText(query, limit: 80)
        .map((ref) => _Hit(
              ref: ref,
              label: _bible.label(ref),
              preview: _bible.textFor(ref),
            ))
        .toList();
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (e is TimeoutException || s.contains('TimeoutException')) {
      return 'EXODUS took too long to answer.';
    }
    if (e is SocketException || s.contains('SocketException')) {
      return 'No internet connection.';
    }
    if (s.contains('(401)') || s.contains('(403)')) {
      return 'The API key was rejected. Check Settings.';
    }
    if (s.contains('(429)')) return 'Rate limited — try again in a moment.';
    return s.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search the Bible')),
      body: SafeArea(
        child: Column(
          children: [
            _controls(),
            Expanded(child: _results()),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.auto_awesome, size: 15),
                label: Text('Ask EXODUS'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.search, size: 15),
                label: Text('Find words'),
              ),
            ],
            selected: {_aiMode},
            onSelectionChanged: (s) => setState(() {
              _aiMode = s.first;
              _hits = const [];
              _searched = false;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            style: const TextStyle(color: ExodusTheme.porcelain),
            decoration: InputDecoration(
              hintText: _aiMode
                  ? 'What does scripture say about…'
                  : 'Exact words to find',
              prefixIcon: const Icon(Icons.search, color: ExodusTheme.ironMist),
              suffixIcon: IconButton(
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ExodusTheme.brass),
                      )
                    : const Icon(Icons.arrow_forward,
                        color: ExodusTheme.covenantGlow),
                onPressed: _busy ? null : _run,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ExodusTheme.porcelain, fontSize: 14, height: 1.5)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _run,
              style: FilledButton.styleFrom(backgroundColor: ExodusTheme.steel),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_busy) {
      return SingleChildScrollView(child: ProgressView(controller: _progress));
    }
    if (!_searched) return _hint();
    if (_hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _aiMode
              ? 'EXODUS didn\'t find a passage for that. Try asking it '
                  'differently.'
              : 'No verse contains those exact words.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: _hits.length,
      itemBuilder: (_, i) => _hitTile(_hits[i]),
    );
  }

  Widget _hint() {
    final examples = _aiMode
        ? const [
            'How do we forgive each other?',
            'What does the Bible say about money and marriage?',
            'Where does scripture talk about anger?',
            'Verses about waiting on God',
          ]
        : const ['love is patient', 'a threefold cord', 'be still'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          _aiMode
              ? 'Ask in your own words. EXODUS finds the passages that speak '
                  'to it and takes you there.'
              : 'Search for exact wording anywhere in the '
                  '${BibleService.translation}.',
          style: const TextStyle(
              color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 20),
        for (final e in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _input.text = e;
                _run();
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: ExodusTheme.steel),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(e,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain, fontSize: 14)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _hitTile(_Hit hit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ExodusTheme.midnight,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context)
              .pop(BibleSearchResult(hit.ref, hit.why)),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: ExodusTheme.steel),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(hit.label.toUpperCase(),
                          style: const TextStyle(
                              color: ExodusTheme.brass,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700)),
                    ),
                    const Icon(Icons.chevron_right,
                        color: ExodusTheme.ironMist, size: 18),
                  ],
                ),
                const SizedBox(height: 6),
                Text(hit.preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 14,
                        height: 1.5)),
                if (hit.why != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 13, color: ExodusTheme.covenantGlow),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(hit.why!,
                            style: const TextStyle(
                                color: ExodusTheme.ironMist,
                                fontSize: 12,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
