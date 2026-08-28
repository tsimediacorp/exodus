import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/bible_books.dart';
import '../models/bible_ref.dart';
import '../models/saved_verse.dart';
import '../services/bible_paginator.dart';
import '../services/bible_service.dart';
import '../services/progress.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/page_flip.dart';
import '../widgets/progress_view.dart';
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
  final ProgressController _status = ProgressController();

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

  // ---- Paged reading ----

  /// Page mode is the default — the reader is meant to feel like a book.
  /// Scrolling stays available for anyone who prefers it.
  late bool _paged = _storage.loadBiblePagedMode();

  final PageController _pageController = PageController();
  List<BiblePage> _pages = const [];
  int _pageIndex = 0;

  /// Inputs the current pagination was computed for. Re-measuring every verse
  /// on every rebuild would be wasteful, so it only recomputes when the
  /// translation, chapter, viewport or text scale actually changes.
  String? _paginatedFor;

  /// A verse to land on once pages exist — set by a deep link, consumed on
  /// the first pagination pass.
  int? _pendingVerseJump;

  /// Recompute pages if anything they depend on has changed.
  void _repaginate(List<String> verses, Size area, TextScaler scaler) {
    final key = '${_bible.currentTranslation.id}/$_bookIndex/$_chapter/'
        '${area.width.round()}x${area.height.round()}/'
        '${scaler.scale(100).round()}';
    if (key == _paginatedFor) return;

    final pages = BiblePaginator.paginate(
      verses: verses,
      size: area,
      verseTextStyle: _verseTextStyle,
      verseNumberStyle: _verseNumberStyle,
      verseSpacing: _verseSpacing,
      textScaler: scaler,
    );

    // Keep the reader on the verse they were looking at, rather than snapping
    // to page one whenever the viewport changes.
    final anchor = _pendingVerseJump ??
        (_pages.isEmpty || _pageIndex >= _pages.length
            ? null
            : _pages[_pageIndex].firstVerse);
    final target = anchor == null
        ? 0
        : BiblePaginator.pageIndexOf(pages, anchor);

    _pages = pages;
    _pageIndex = target.clamp(0, pages.length - 1);
    _paginatedFor = key;
    _pendingVerseJump = null;

    // Jump after the frame — the controller has no clients until PageView
    // has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      if (_pageController.page?.round() != _pageIndex) {
        _pageController.jumpToPage(_pageIndex);
      }
    });
  }

  void _onPageChanged(int i) {
    // A light tick per page, the way a real page has a sound.
    HapticFeedback.selectionClick();
    setState(() => _pageIndex = i);
  }

  /// Swap between turning pages and continuous scrolling. Persisted, because
  /// this is a taste preference and re-choosing it every session is friction.
  Future<void> _toggleReadingMode() async {
    HapticFeedback.selectionClick();
    // Keep the reader where they were: remember the verse currently on screen
    // so the other mode opens at the same place.
    final anchor = _paged && _pageIndex < _pages.length
        ? _pages[_pageIndex].firstVerse
        : _highlight?.verseStart;
    setState(() {
      _paged = !_paged;
      _paginatedFor = null;
      if (anchor != null) _pendingVerseJump = anchor;
    });
    await _storage.saveBiblePagedMode(_paged);
  }

  static const TextStyle _verseTextStyle = TextStyle(
    color: ExodusTheme.porcelain,
    fontSize: 16,
    height: 1.7,
  );

  static const TextStyle _verseNumberStyle = TextStyle(
    color: ExodusTheme.ironMist,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.7,
  );

  /// Must match the vertical space _verseRow adds around each verse.
  static const double _verseSpacing = 16;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _open();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pageController.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      // Parsing 4.5MB of scripture takes a beat on first open; say what is
      // happening rather than showing a bare spinner.
      _status.begin(_bible.isLoaded
          ? 'Opening…'
          : 'Loading the ${BibleService.translation} — all 66 books…');
      await _bible.load();
      if (!mounted) return;
      _status.done();
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
      _status.done();
      setState(() {
        _loading = false;
        _loadError = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _scrollToHighlight() {
    final start = _highlight?.verseStart;
    if (start == null) return;
    if (_paged) {
      // Pages may not be measured yet (first open); park the target and let
      // the pagination pass land on it.
      if (_pages.isEmpty) {
        _pendingVerseJump = start;
      } else {
        final target = BiblePaginator.pageIndexOf(_pages, start);
        setState(() => _pageIndex = target);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.animateToPage(target,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic);
          }
        });
      }
      return;
    }
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

  /// What each verse actually shows.
  ///
  /// Translations following the critical text carry sixteen verses as empty
  /// strings. Substituting here rather than at the point of rendering keeps
  /// the paginator measuring the same text the reader sees — otherwise page
  /// mode would measure an empty line and lay out a page that overflows.
  List<String> get _displayVerses =>
      [for (final v in _verses) v.trim().isEmpty ? _omittedLabel : v];

  String get _omittedLabel =>
      'Not included in the ${BibleService.translation}.';

  /// Whether verse [number] (1-based) is one the translation omits.
  bool _isOmitted(int number) =>
      number >= 1 &&
      number <= _verses.length &&
      _verses[number - 1].trim().isEmpty;

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
    final verses = _displayVerses;
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
      _pageIndex = 0;
      _paginatedFor = null; // force a re-measure for the new chapter
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_paged && _pageController.hasClients) _pageController.jumpToPage(0);
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

  /// Let the reader change translation. Only offered when more than one is
  /// bundled, so a single-translation build shows no dead control.
  Future<void> _pickTranslation() async {
    final current = _bible.currentTranslation;
    final chosen = await showModalBottomSheet<BibleTranslation>(
      context: context,
      backgroundColor: ExodusTheme.obsidian,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('TRANSLATION',
                  style: TextStyle(
                    color: ExodusTheme.ironMist,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  )),
            ),
            for (final t in BibleService.translations)
              InkWell(
                onTap: () => Navigator.pop(ctx, t),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  color: t.id == current.id
                      ? ExodusTheme.midnight
                      : Colors.transparent,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(t.abbrev,
                            style: TextStyle(
                              color: t.id == current.id
                                  ? ExodusTheme.brass
                                  : ExodusTheme.porcelain,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                style: const TextStyle(
                                    color: ExodusTheme.porcelain,
                                    fontSize: 15)),
                            const SizedBox(height: 3),
                            Text(t.note,
                                style: const TextStyle(
                                    color: ExodusTheme.ironMist,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      if (t.id == current.id)
                        const Icon(Icons.check_rounded,
                            size: 18, color: ExodusTheme.brass),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (chosen == null || chosen.id == current.id || !mounted) return;

    // Switching drops the old text and parses the new one, so the reader goes
    // back through its loading state rather than rendering against no books.
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _status.begin('Loading the ${chosen.abbrev} — all 66 books…');
      await _bible.select(chosen);
      if (!mounted) return;
      _status.done();
      setState(() {
        _loading = false;
        // Page breaks were measured against the old text. Drop them and let
        // the next layout pass re-measure, which is the only place the
        // viewport size is known.
        _pages = const [];
        _pageIndex = 0;
        _paginatedFor = null;
      });
    } catch (e) {
      if (!mounted) return;
      _status.done();
      setState(() {
        _loading = false;
        _loadError = '$e'.replaceFirst('Exception: ', '');
      });
    }
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
          if (BibleService.hasChoice)
            Semantics(
              button: true,
              label: 'Change translation',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _loading ? null : _pickTranslation,
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 44, minWidth: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(BibleService.translation,
                      style: const TextStyle(
                        color: ExodusTheme.brass,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      )),
                ),
              ),
            ),
          IconButton(
            tooltip: _paged ? 'Switch to scrolling' : 'Switch to pages',
            icon: Icon(
                _paged ? Icons.menu_book_rounded : Icons.view_stream_rounded,
                color: ExodusTheme.ironMist),
            onPressed: _loading ? null : _toggleReadingMode,
          ),
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
      return Center(child: ProgressView(controller: _status));
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

    final verses = _displayVerses;
    _verseKeys.clear();

    if (!_paged) {
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

    return Column(
      children: [
        if (_note != null) _noteBanner(_note!),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Pages depend on the viewport and the reader's text scale, so
              // they are measured here and recomputed when either changes —
              // a rotation or an accessibility change must not leave verses
              // stranded off the bottom of a page.
              final scaler = MediaQuery.textScalerOf(context);
              final area = Size(
                constraints.maxWidth - 40, // horizontal padding
                constraints.maxHeight - 56, // vertical padding + footer
              );
              _repaginate(verses, area, scaler);

              return Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    physics: const PageTurnPhysics(),
                    itemCount: _pages.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, i) {
                      final page = _pages[i];
                      return AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, child) {
                          // Fall back to the settled index before the
                          // controller has dimensions (first frame).
                          final position = _pageController.hasClients &&
                                  _pageController.position.hasContentDimensions
                              ? (_pageController.page ?? _pageIndex.toDouble())
                              : _pageIndex.toDouble();
                          return PageFlip(
                              index: i, page: position, child: child!);
                        },
                        child: _pageContent(page, verses),
                      );
                    },
                  ),
                  const SpineShadow(),
                ],
              );
            },
          ),
        ),
        _pageFooter(),
      ],
    );
  }

  /// One page of verses, laid out top-aligned like a printed page.
  Widget _pageContent(BiblePage page, List<String> verses) {
    return Container(
      color: ExodusTheme.obsidian,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var v = page.firstVerse; v <= page.lastVerse; v++)
            if (v - 1 < verses.length) _verseRow(v, verses[v - 1]),
        ],
      ),
    );
  }

  /// Page position plus chapter stepping, so the couple is never stuck at the
  /// end of a chapter with nowhere to go.
  Widget _pageFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: ExodusTheme.obsidian,
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      child: Row(
        children: [
          _footerButton(
            icon: Icons.chevron_left,
            label: 'Previous chapter',
            onTap: (_chapter > 1 || _bookIndex > 0)
                ? () => _changeChapter(-1)
                : null,
          ),
          Expanded(
            child: Text(
              _pages.length <= 1
                  ? '$_bookName $_chapter'
                  : 'Page ${_pageIndex + 1} of ${_pages.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _footerButton(
            icon: Icons.chevron_right,
            label: 'Next chapter',
            onTap: (_chapter < _chapterCount ||
                    _bookIndex < _bible.books.length - 1)
                ? () => _changeChapter(1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _footerButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon,
              size: 22,
              color: onTap == null ? ExodusTheme.steel : ExodusTheme.ironMist),
        ),
      ),
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
                // An omitted verse keeps its number so every other verse
                // still lands where the reader expects, but a bare number with
                // nothing after it reads as a rendering bug — so it is set
                // apart the way a print Bible footnotes it.
                TextSpan(
                  text: text,
                  style: _isOmitted(number)
                      ? const TextStyle(
                          color: ExodusTheme.ironMist,
                          fontSize: 14,
                          height: 1.7,
                          fontStyle: FontStyle.italic,
                        )
                      : const TextStyle(
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
