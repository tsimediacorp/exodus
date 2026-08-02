import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/bible_books.dart';
import '../models/bible_ref.dart';
import '../models/saved_verse.dart';
import '../services/bible_service.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/verse_card.dart';
import 'bible_explain_sheet.dart';
import 'bible_search_screen.dart';

/// The in-app Bible reader.
///
/// Opens either at a passage ([initialRef], used when something elsewhere in
/// the app deep-links a reference) or at the book picker. A deep-linked
/// passage is scrolled to and highlighted so the couple lands on the verse
/// rather than the top of a chapter.
class BibleScreen extends StatefulWidget {
  final BibleRef? initialRef;

  /// Shown under the reference when arriving from AI search, explaining why
  /// this passage was surfaced.
  final String? note;

  const BibleScreen({super.key, this.initialRef, this.note});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final BibleService _bible = BibleService.instance;
  final StorageService _storage = StorageService.instance;
  final ScrollController _scroll = ScrollController();

  /// One key per verse in the current chapter, so a deep-linked verse can be
  /// scrolled into view. Chapters top out at 176 verses (Psalm 119), so the
  /// whole chapter is laid out at once and every key is live.
  final Map<int, GlobalKey> _verseKeys = {};

  bool _loading = true;
  String? _loadError;

  int _bookIndex = 0;
  int _chapter = 1;

  /// Verses currently highlighted from a deep link. Cleared once the couple
  /// starts selecting their own.
  BibleRef? _highlight;
  String? _note;

  /// 1-based verse numbers the couple has tapped to select.
  final Set<int> _selected = <int>{};

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _open();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await _bible.load();
      if (!mounted) return;
      final target = widget.initialRef == null
          ? null
          : _bible.resolve(widget.initialRef!);
      setState(() {
        _loading = false;
        if (target != null) {
          _bookIndex = target.bookIndex;
          _chapter = target.chapter;
          _highlight = target.hasVerses ? target : null;
        }
      });
      if (_highlight != null) _scrollToHighlight();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _scrollToHighlight() {
    final start = _highlight?.verseStart;
    if (start == null) return;
    // After the frame, so the verse's key has a render object to scroll to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _verseKeys[start]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3, // a little above centre, so context above is visible
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
      );
    });
  }

  List<String> get _verses =>
      _bible.books.isEmpty ? const [] : _bible.books[_bookIndex].verses(_chapter);

  int get _chapterCount =>
      _bible.books.isEmpty ? 0 : _bible.books[_bookIndex].chapterCount;

  String get _bookName => _bible.bookName(_bookIndex);

  /// The couple's selection as a reference, or null when nothing is selected.
  BibleRef? get _selectionRef {
    if (_selected.isEmpty) return null;
    final sorted = _selected.toList()..sort();
    return BibleRef(
      bookIndex: _bookIndex,
      chapter: _chapter,
      verseStart: sorted.first,
      verseEnd: sorted.last == sorted.first ? null : sorted.last,
    );
  }

  String get _selectionText {
    final sorted = _selected.toList()..sort();
    final verses = _verses;
    return sorted
        .where((v) => v >= 1 && v <= verses.length)
        .map((v) => verses[v - 1])
        .join(' ');
  }

  void _goTo(int bookIndex, int chapter) {
    setState(() {
      _bookIndex = bookIndex;
      _chapter = chapter;
      _highlight = null;
      _note = null;
      _selected.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _changeChapter(int delta) {
    final next = _chapter + delta;
    if (next >= 1 && next <= _chapterCount) {
      _goTo(_bookIndex, next);
    } else if (next < 1 && _bookIndex > 0) {
      final prevBook = _bookIndex - 1;
      _goTo(prevBook, _bible.books[prevBook].chapterCount);
    } else if (next > _chapterCount && _bookIndex < _bible.books.length - 1) {
      _goTo(_bookIndex + 1, 1);
    }
  }

  void _toggleVerse(int verse) {
    HapticFeedback.selectionClick();
    setState(() {
      // A deep-link highlight is guidance, not a selection — the first tap
      // clears it so the two never fight over the same verses.
      _highlight = null;
      _note = null;
      if (!_selected.remove(verse)) _selected.add(verse);
    });
  }

  Future<void> _pickBook() async {
    final picked = await showModalBottomSheet<BibleRef>(
      context: context,
      backgroundColor: ExodusTheme.obsidian,
      isScrollControlled: true,
      builder: (_) => _BookPicker(
        bible: _bible,
        currentBook: _bookIndex,
        currentChapter: _chapter,
      ),
    );
    if (picked != null) _goTo(picked.bookIndex, picked.chapter);
  }

  Future<void> _search() async {
    final result = await Navigator.of(context).push<BibleSearchResult>(
      MaterialPageRoute(builder: (_) => const BibleSearchScreen()),
    );
    if (result == null || !mounted) return;
    final resolved = _bible.resolve(result.ref);
    if (resolved == null) return;
    setState(() {
      _bookIndex = resolved.bookIndex;
      _chapter = resolved.chapter;
      _highlight = resolved.hasVerses ? resolved : null;
      _note = result.why;
      _selected.clear();
    });
    _scrollToHighlight();
  }

  void _explain({String? question}) {
    final ref = _selectionRef;
    if (ref == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ExodusTheme.obsidian,
      isScrollControlled: true,
      builder: (_) => BibleExplainSheet(
        reference: _bible.label(ref),
        text: _selectionText,
        question: question,
      ),
    );
  }

  Future<void> _askAbout() async {
    final controller = TextEditingController();
    final question = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Ask about this passage'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: ExodusTheme.porcelain),
          decoration: const InputDecoration(
              hintText: 'What do you want to understand?'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(
                backgroundColor: ExodusTheme.covenantBlue),
            child: const Text('Ask'),
          ),
        ],
      ),
    );
    final text = question;
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    _explain(question: text);
  }

  Future<void> _keepSelection() async {
    final ref = _selectionRef;
    if (ref == null) return;
    await _storage.saveVerse(SavedVerse(
      reference: _bible.label(ref),
      text: _selectionText,
      source: '${BibleService.translation} · read in the Bible',
    ));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Kept ${_bible.label(ref)}'),
      duration: const Duration(seconds: 2),
    ));
    setState(() => _selected.clear());
  }

  void _shareSelection() {
    final ref = _selectionRef;
    if (ref == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          VerseCardSheet(reference: _bible.label(ref), text: _selectionText),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _loading
            ? const Text('Bible')
            : Semantics(
                button: true,
                label: 'Change book and chapter',
                child: InkWell(
                  onTap: _pickBook,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text('$_bookName $_chapter',
                            overflow: TextOverflow.ellipsis),
                      ),
                      const Icon(Icons.arrow_drop_down,
                          color: ExodusTheme.ironMist),
                    ],
                  ),
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Ask EXODUS to find a passage',
            icon: const Icon(Icons.auto_awesome, color: ExodusTheme.covenantGlow),
            onPressed: _loading ? null : _search,
          ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty ? null : _selectionBar(),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: ExodusTheme.brass),
            SizedBox(height: 16),
            Text('Opening the Bible…',
                style: TextStyle(color: ExodusTheme.ironMist, fontSize: 13)),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not open the Bible.\n$_loadError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: ExodusTheme.ironMist, fontSize: 14, height: 1.5)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _open();
                },
                style:
                    FilledButton.styleFrom(backgroundColor: ExodusTheme.steel),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final verses = _verses;
    _verseKeys.clear();
    return Column(
      children: [
        if (_note != null) _noteBanner(_note!),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < verses.length; i++)
                  _verseRow(i + 1, verses[i]),
                _chapterNav(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _noteBanner(String note) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ExodusTheme.covenantBlue.withValues(alpha: 0.15),
        border: Border.all(color: ExodusTheme.covenantGlow.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome,
              size: 16, color: ExodusTheme.covenantGlow),
          const SizedBox(width: 10),
          Expanded(
            child: Text(note,
                style: const TextStyle(
                    color: ExodusTheme.porcelain, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _verseRow(int number, String text) {
    final selected = _selected.contains(number);
    final highlighted = _highlight?.covers(number) ?? false;
    final key = _verseKeys.putIfAbsent(number, () => GlobalKey());
    return Semantics(
      key: key,
      button: true,
      selected: selected,
      label: 'Verse $number',
      child: InkWell(
        onTap: () => _toggleVerse(number),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? ExodusTheme.covenantBlue.withValues(alpha: 0.28)
                : highlighted
                    ? ExodusTheme.brass.withValues(alpha: 0.16)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: highlighted && !selected
                ? Border.all(color: ExodusTheme.brass.withValues(alpha: 0.5))
                : null,
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$number ',
                  style: TextStyle(
                    color: selected || highlighted
                        ? ExodusTheme.brass
                        : ExodusTheme.ironMist,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.7,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: const TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 16,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chapterNav() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: (_chapter > 1 || _bookIndex > 0)
                ? () => _changeChapter(-1)
                : null,
            style: TextButton.styleFrom(
                foregroundColor: ExodusTheme.ironMist,
                minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.chevron_left, size: 20),
            label: const Text('Previous'),
          ),
          TextButton.icon(
            onPressed:
                (_chapter < _chapterCount || _bookIndex < _bible.books.length - 1)
                    ? () => _changeChapter(1)
                    : null,
            style: TextButton.styleFrom(
                foregroundColor: ExodusTheme.ironMist,
                minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.chevron_right, size: 20),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }

  /// Appears once verses are selected — the whole point of tap-to-select.
  Widget _selectionBar() {
    final ref = _selectionRef!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: ExodusTheme.obsidian,
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_bible.label(ref),
                      style: const TextStyle(
                          color: ExodusTheme.brass,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                Semantics(
                  button: true,
                  label: 'Clear selection',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => setState(() => _selected.clear()),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.close,
                          size: 18, color: ExodusTheme.ironMist),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _explain(),
                    style: FilledButton.styleFrom(
                      backgroundColor: ExodusTheme.covenantBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.auto_awesome,
                        size: 16, color: ExodusTheme.porcelain),
                    label: const Text('Explain',
                        style: TextStyle(color: ExodusTheme.porcelain)),
                  ),
                ),
                const SizedBox(width: 8),
                _barAction(
                    icon: Icons.help_outline_rounded,
                    label: 'Ask a question',
                    onTap: _askAbout),
                _barAction(
                    icon: Icons.bookmark_border_rounded,
                    label: 'Keep verse',
                    onTap: _keepSelection),
                _barAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: _shareSelection),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _barAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 44,
          child: Icon(icon, size: 19, color: ExodusTheme.ironMist),
        ),
      ),
    );
  }
}

/// Book then chapter picker.
class _BookPicker extends StatefulWidget {
  final BibleService bible;
  final int currentBook;
  final int currentChapter;

  const _BookPicker({
    required this.bible,
    required this.currentBook,
    required this.currentChapter,
  });

  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  int? _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.currentBook;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ExodusTheme.steel,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: BibleBooks.names.length,
              itemBuilder: (_, i) => _bookTile(i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookTile(int i) {
    final isExpanded = _expanded == i;
    final chapters = widget.bible.books.isEmpty
        ? 0
        : widget.bible.books[i].chapterCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (i == 0 || i == BibleBooks.firstNewTestament)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              i == 0 ? 'OLD TESTAMENT' : 'NEW TESTAMENT',
              style: const TextStyle(
                  color: ExodusTheme.ironMist,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700),
            ),
          ),
        InkWell(
          onTap: () => setState(() => _expanded = isExpanded ? null : i),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(BibleBooks.names[i],
                      style: TextStyle(
                          color: i == widget.currentBook
                              ? ExodusTheme.brass
                              : ExodusTheme.porcelain,
                          fontSize: 15,
                          fontWeight: i == widget.currentBook
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: ExodusTheme.ironMist),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var c = 1; c <= chapters; c++)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(
                        context, BibleRef(bookIndex: i, chapter: c)),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: (i == widget.currentBook &&
                                    c == widget.currentChapter)
                                ? ExodusTheme.brass
                                : ExodusTheme.steel),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$c',
                          style: const TextStyle(
                              color: ExodusTheme.porcelain, fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
