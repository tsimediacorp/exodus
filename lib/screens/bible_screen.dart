import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/bible_books.dart';
import '../layout/exodus_layout.dart';
import '../models/bible_ref.dart';
import '../models/saved_verse.dart';
import '../services/bible_marks.dart';
import '../services/bible_art.dart';
import '../services/bible_service.dart';
import '../services/bible_typesetter.dart';
import '../services/progress.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/bible_cover.dart';
import '../widgets/bible_pages.dart';
import '../widgets/bible_paper.dart';
import '../widgets/book_spread.dart';
import '../widgets/ink_layer.dart';
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

  // ---- Study: highlights, notes, ink ----

  final BibleMarks _marks = BibleMarks.instance;

  /// The pen, the eraser, or neither. While either is out, the page is for
  /// drawing: swipes draw instead of turning, taps do not select.
  InkTool _tool = InkTool.off;
  int _inkColor = 0;
  int _markerColor = 0;

  /// Bumped whenever ink or notes change, so the page pictures the curl is
  /// textured with are retaken.
  int _marksRev = 0;

  // ---- The closed book ----

  /// Folded, the Duo's front screen shows the Bible closed: its cover.
  /// Unfolding opens it; folding it again closes it.
  bool _showCover = false;
  bool? _folded;
  late String _coverName = _storage.loadBibleCoverName();

  // ---- Reading aloud ----

  bool _narrating = false;
  int? _narratedVerse;

  /// Reading mode: every control hidden, nothing on the glass but the page.
  bool _immersive = false;

  void _onMarksChanged() {
    if (mounted) setState(() => _marksRev++);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final folded = ExodusLayout.sideColumnWidth(context) > 0;
    if (_folded == null) {
      // Arriving at a passage someone sent you goes straight to it.
      _showCover = folded && widget.initialRef == null;
    } else if (folded != _folded) {
      _showCover = folded;
    }
    _folded = folded;
  }

  // ---- Paged reading ----

  /// Page mode is the default — the reader is meant to feel like a book.
  /// Scrolling stays available for anyone who prefers it.
  late bool _paged = _storage.loadBiblePagedMode();

  final BibleArt _art = BibleArt.instance;

  /// The chapter set in type, and the pages it falls on.
  TypesetChapter? _set;
  List<_Leaf> _leaves = const [];
  _Heading? _heading;
  int _pageIndex = 0;

  /// Pages a view: 2 unfolded (facing pages), 1 folded.
  int _per = 1;

  /// Inputs the current typesetting was made for. Setting a chapter is not
  /// free, so it is only redone when the translation, chapter, page size,
  /// pages a view or text scale actually change.
  String? _setFor;

  /// Bumped when a chapter's art has decoded, so the pictures the turning
  /// leaf is textured with are retaken with the plates on them.
  int _artRev = 0;

  /// A verse to land on once pages exist — set by a deep link, consumed on
  /// the first typesetting pass.
  int? _pendingVerseJump;

  static const _ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen'
  ];
  static const _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety'
  ];

  /// "Fourteen", "One Hundred and Nineteen": chapters as a book names them.
  static String numberWords(int n) {
    if (n >= 100) {
      final rest = n % 100;
      return 'One Hundred${rest == 0 ? '' : ' and ${numberWords(rest)}'}';
    }
    if (n < 20) return _ones[n];
    final one = n % 10;
    return '${_tens[n ~/ 10]}${one == 0 ? '' : '-${_ones[one]}'}';
  }

  /// The heading over the chapter's first page.
  _Heading _headingFor(
      List<BiblePlate> plates, int per, double width, double content) {
    final plate = plates.isEmpty ? null : plates.first;
    final psalm = _bookName == 'Psalms';
    final chapterName =
        '${psalm ? 'Psalm' : 'Chapter'} ${numberWords(_chapter)}';
    final kicker = plate == null ? _bookName : '$_bookName · $chapterName';
    final title = plate?.title ?? chapterName;
    // Folded, the plate is let into the head of the page; unfolded it has a
    // page of its own facing this one, and an ornament heads the text.
    final headpiece = per == 1 ? plate?.asset : null;
    final headpieceHeight =
        headpiece == null ? 0.0 : math.min(content * 0.34, width * 0.74);
    final vignette =
        headpiece == null ? _art.vignetteFor(_bookIndex, _chapter) : null;
    final titleSize = per == 2 ? 36.0 : 32.0;
    return _Heading(
      kicker: kicker,
      title: title,
      vignette: vignette,
      headpiece: headpiece,
      headpieceHeight: headpieceHeight,
      titleSize: titleSize,
      height: ChapterHeading.measure(
        width: width,
        title: title,
        kicker: kicker,
        hasVignette: vignette != null,
        headpieceHeight: headpieceHeight,
        titleSize: titleSize,
      ),
    );
  }

  /// Set the chapter in type for pages of [page] size, and lay out the
  /// leaves of the book: the opening, the plates where they fall, the text,
  /// and a tailpiece.
  void _typeset(List<String> verses, Size page, int per, TextScaler scaler) {
    final key = '${_bible.currentTranslation.id}/$_bookIndex/$_chapter/'
        '${page.width.round()}x${page.height.round()}/$per/'
        '${scaler.scale(100).round()}/${_art.isLoaded}';
    if (key == _setFor) return;

    // Keep the reader on the verse they were looking at, rather than snapping
    // to page one whenever the viewport changes.
    final anchor =
        _pendingVerseJump ?? (_set == null ? null : _firstVisibleVerse);

    final side = per == 2 ? PageSide.left : PageSide.single;
    final m = PageMargins.of(side);
    final width = page.width - m.horizontal;
    final content = page.height - m.vertical;
    final plates = _art.platesFor(_bookIndex, _chapter);
    final heading = _headingFor(plates, per, width, content);
    final set = TypesetChapter.layout(
      verses: verses,
      width: width,
      type: bibleTypeFor(width, scaler),
      openingHeight: content - heading.height,
      pageHeight: content,
      omittedLabel: _omittedLabel,
    );

    // Plates after the first stand after the page their verse is on.
    final later = [
      for (final p in plates.skip(1)) (set.sliceOfVerse(p.verse), p)
    ];
    final leaves = <_Leaf>[const _ProseLeaf(0)];
    if (per == 2 && plates.isNotEmpty) leaves.add(_PlateLeaf(plates.first));
    for (var s = 0; s < set.slices.length; s++) {
      if (s > 0) leaves.add(_ProseLeaf(s));
      for (final (at, p) in later) {
        if (at == s) leaves.add(_PlateLeaf(p));
      }
    }
    if (per == 1 || leaves.length.isOdd) leaves.add(const _EndLeaf());

    final old = _set;
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    _set = set;
    _heading = heading;
    _leaves = leaves;
    _per = per;
    _setFor = key;
    _pendingVerseJump = null;
    _pageIndex = anchor == null
        ? _pageIndex.clamp(0, leaves.length - 1)
        : _leafOfVerse(anchor);

    final art = [
      for (final p in plates) p.asset,
      if (heading.vignette != null) heading.vignette!,
      if (_art.vignetteFor(_bookIndex, _chapter + 1) case final v?) v,
    ];
    // Pages are measured during layout, after the chrome has been built, so
    // it needs one more pass to show the new count; and the art is decoded
    // now, so the plates are on the paper before the leaf is lifted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      precacheChapterArt(context, art).then((_) {
        if (mounted) setState(() => _artRev++);
      });
    });
  }

  /// The leaf on which verse [v] begins.
  int _leafOfVerse(int v) {
    final set = _set;
    if (set == null || _leaves.isEmpty) return 0;
    final slice = set.sliceOfVerse(v);
    final i = _leaves.indexWhere((l) => l is _ProseLeaf && l.slice == slice);
    return i < 0 ? 0 : i;
  }

  /// Swap between turning pages and continuous scrolling. Persisted, because
  /// this is a taste preference and re-choosing it every session is friction.
  Future<void> _toggleReadingMode() async {
    HapticFeedback.selectionClick();
    // Keep the reader where they were: remember the verse currently on screen
    // so the other mode opens at the same place.
    final anchor =
        _paged && _set != null ? _firstVisibleVerse : _highlight?.verseStart;
    setState(() {
      _paged = !_paged;
      _setFor = null;
      if (anchor != null) _pendingVerseJump = anchor;
    });
    await _storage.saveBiblePagedMode(_paged);
  }

  /// Set like a printed Bible: a book face in near-black on cream, verse
  /// numbers in red.
  static const TextStyle _verseTextStyle = TextStyle(
    fontFamily: ExodusTheme.serif,
    color: BiblePalette.ink,
    fontSize: 17,
    height: 1.55,
  );

  static const TextStyle _verseNumberStyle = TextStyle(
    fontFamily: ExodusTheme.serif,
    color: BiblePalette.rubric,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.55,
    fontFeatures: [FontFeature.oldstyleFigures()],
  );

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _marks.addListener(_onMarksChanged);
    _open();
  }

  @override
  void dispose() {
    _marks.removeListener(_onMarksChanged);
    if (_narrating) TtsService.instance.stop();
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _scroll.dispose();
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
      // The art is a nicety; a reader without it still reads.
      await Future.wait([
        _bible.load(),
        _art.load().catchError((Object e) {
          debugPrint('Bible art unavailable: $e');
        }),
      ]);
      if (!mounted) return;
      _status.done();
      final target =
          widget.initialRef == null ? null : _bible.resolve(widget.initialRef!);
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
      if (_set == null) {
        _pendingVerseJump = start;
      } else {
        setState(() => _pageIndex = _leafOfVerse(start));
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

  List<String> get _verses => _bible.books.isEmpty
      ? const []
      : _bible.books[_bookIndex].verses(_chapter);

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
      _setFor = null; // set the new chapter in type
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _changeChapter(int delta) {
    if (_narrating) _stopListening();
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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

  // ---------------- Study ----------------

  ChapterMarks get _chapterMarks => _marks.chapter(_bookIndex, _chapter);

  /// Write or edit the note on [verse].
  Future<void> _editNote(int verse) async {
    final existing = _chapterMarks.notes[verse] ?? '';
    final controller = TextEditingController(text: existing);
    final ref =
        BibleRef(bookIndex: _bookIndex, chapter: _chapter, verseStart: verse);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ExodusTheme.midnight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 20, 22, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded,
                      color: ExodusTheme.brass, size: 20),
                  const SizedBox(width: 8),
                  Text(_bible.label(ref),
                      style: const TextStyle(
                        color: ExodusTheme.brass,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      )),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _displayVerses.length >= verse ? _displayVerses[verse - 1] : '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: ExodusTheme.ironMist,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                style: const TextStyle(
                    fontFamily: ExodusTheme.serif,
                    color: ExodusTheme.parchment,
                    fontSize: 16,
                    height: 1.5),
                decoration: const InputDecoration(
                  hintText: 'What is this verse saying to you?',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (existing.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: const Text('Delete note',
                          style: TextStyle(color: ExodusTheme.crimson)),
                    ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: ExodusTheme.brass,
                        foregroundColor: ExodusTheme.obsidian),
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _marks.setNote(_bookIndex, _chapter, verse, result);
    if (mounted) setState(() => _selected.clear());
  }

  /// Every note in the Bible, grouped by where it is; tapping one goes there.
  Future<void> _showNotes() async {
    final notes = _marks.allNotes();
    final target =
        await showModalBottomSheet<({int book, int chapter, int verse})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ExodusTheme.midnight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => notes.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No notes yet. Select a verse and tap Note to write '
                    'one in the margin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ExodusTheme.ironMist, height: 1.5),
                  ),
                ),
              )
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                itemCount: notes.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text('Your notes',
                          style: TextStyle(
                            fontFamily: ExodusTheme.serif,
                            color: ExodusTheme.parchment,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          )),
                    );
                  }
                  final n = notes[i - 1];
                  final label = _bible.label(BibleRef(
                      bookIndex: n.book,
                      chapter: n.chapter,
                      verseStart: n.verse));
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx,
                        (book: n.book, chapter: n.chapter, verse: n.verse)),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ExodusTheme.obsidian.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: ExodusTheme.steel),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                color: ExodusTheme.brass,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              )),
                          const SizedBox(height: 6),
                          Text(n.text,
                              style: const TextStyle(
                                fontFamily: ExodusTheme.serif,
                                color: ExodusTheme.porcelain,
                                fontSize: 15,
                                height: 1.5,
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
    if (target == null || !mounted) return;
    _goTo(target.book, target.chapter);
    setState(() {
      _highlight = BibleRef(
          bookIndex: target.book,
          chapter: target.chapter,
          verseStart: target.verse);
      _pendingVerseJump = target.verse;
    });
    _scrollToHighlight();
  }

  // ---------------- Reading aloud ----------------

  /// The first verse on the page (or spread) in front of the reader.
  int get _firstVisibleVerse {
    final set = _set;
    if (_paged && set != null && _leaves.isNotEmpty) {
      final start = _per == 2 ? (_pageIndex ~/ 2) * 2 : _pageIndex;
      for (var i = start; i < _leaves.length; i++) {
        final leaf = _leaves[i];
        if (leaf is _ProseLeaf) return set.firstVerseOn(leaf.slice);
      }
      return set.verseCount;
    }
    return _highlight?.verseStart ?? 1;
  }

  /// Read the chapter aloud from the page in front of the reader, or just
  /// [only], verse by verse. The verse being read is lit on the page, and
  /// the page turns when the reading runs onto the next one.
  Future<void> _listen({List<int>? only}) async {
    if (_narrating) {
      _stopListening();
      return;
    }
    HapticFeedback.selectionClick();
    final verses = _displayVerses;
    final queue =
        only ?? [for (var v = _firstVisibleVerse; v <= verses.length; v++) v];
    if (queue.isEmpty) return;
    setState(() {
      _narrating = true;
      _selected.clear();
      _tool = InkTool.off;
    });
    final tts = TtsService.instance;
    if (only == null && queue.first == 1) {
      final ok =
          await tts.speakAndWait('bible', '$_bookName, chapter $_chapter.');
      if (!ok || !_narrating) return _finishListening();
    }
    for (final v in queue) {
      if (!mounted || !_narrating) break;
      if (v < 1 || v > verses.length || _isOmitted(v)) continue;
      setState(() => _narratedVerse = v);
      _bringIntoView(v);
      final ok = await tts.speakAndWait('bible', verses[v - 1]);
      if (!ok) break;
    }
    _finishListening();
  }

  void _stopListening() {
    TtsService.instance.stop();
    _finishListening();
  }

  void _finishListening() {
    if (!mounted) return;
    setState(() {
      _narrating = false;
      _narratedVerse = null;
    });
  }

  /// Turn to (or scroll to) verse [v].
  void _bringIntoView(int v) {
    if (_paged) {
      if (_set == null) return;
      final target = _leafOfVerse(v);
      final now = _per == 2 ? _pageIndex ~/ 2 : _pageIndex;
      final next = _per == 2 ? target ~/ 2 : target;
      if (now != next) setState(() => _pageIndex = target);
      return;
    }
    final ctx = _verseKeys[v]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut);
  }

  // ---------------- The cover ----------------

  Future<void> _editCoverName() async {
    final controller = TextEditingController(text: _coverName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Name on the cover'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Christian & Ana',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Stamp it',
                style: TextStyle(color: ExodusTheme.brass)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    setState(() => _coverName = name.trim());
    await _storage.saveBibleCoverName(name);
  }

  void _setTool(InkTool tool) {
    HapticFeedback.selectionClick();
    setState(() {
      _tool = tool;
      _selected.clear();
    });
  }

  Future<void> _undoInk() async {
    final ink = _chapterMarks.ink;
    if (ink.isEmpty) return;
    HapticFeedback.selectionClick();
    await _marks.removeStroke(_bookIndex, _chapter, ink.last.id);
  }

  Future<void> _toggleImmersive() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _immersive = !_immersive;
      _selected.clear();
    });
    await SystemChrome.setEnabledSystemUIMode(
        _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
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
                                    color: ExodusTheme.ironMist, fontSize: 11)),
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
        _pageIndex = 0;
        _setFor = null;
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
    // Always the same shape of tree, cover or not: swapping the reader in
    // and out of a Stack would rebuild it from scratch, losing the page.
    return Stack(
      children: [
        Positioned.fill(child: _reader(context)),
        if (_showCover)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: BibleCover(
                ownerName: _coverName,
                onEditName: _editCoverName,
                onOpened: () => setState(() => _showCover = false),
              ),
            ),
          ),
      ],
    );
  }

  /// Everything else: reading mode, notes, the cover, scroll or turn.
  Widget _moreMenu(Color color) => PopupMenuButton<String>(
        tooltip: 'More',
        enabled: !_loading,
        icon: Icon(Icons.more_vert_rounded, color: color),
        color: ExodusTheme.midnight,
        onSelected: (v) {
          switch (v) {
            case 'read':
              _toggleImmersive();
            case 'notes':
              _showNotes();
            case 'mode':
              _toggleReadingMode();
            case 'close':
              if (_narrating) _stopListening();
              setState(() => _showCover = true);
            case 'name':
              _editCoverName();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'read',
            child: ListTile(
              leading: Icon(Icons.chrome_reader_mode_outlined),
              title: Text('Reading mode'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'notes',
            child: ListTile(
              leading: Icon(Icons.sticky_note_2_outlined),
              title: Text('Your notes'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'close',
            child: ListTile(
              leading: Icon(Icons.book_rounded),
              title: Text('Close the book'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'name',
            child: ListTile(
              leading: Icon(Icons.draw_rounded),
              title: Text('Name on the cover'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'mode',
            child: ListTile(
              leading: Icon(
                  _paged ? Icons.view_stream_rounded : Icons.menu_book_rounded),
              title: Text(_paged ? 'Scroll instead' : 'Turn pages'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      );

  Widget _reader(BuildContext context) {
    final drawing = _tool != InkTool.off;
    // Turning pages, the book is the whole screen: paper to the edges, its
    // controls drawn on the head of the page. Scrolling keeps the bar.
    final book = _paged && !_loading && _loadError == null;
    return Scaffold(
      backgroundColor: book ? BiblePalette.paper : const Color(0xFF0B0E17),
      // Reading mode takes the bar away entirely; the page runs to the top.
      appBar: _immersive || _paged
          ? null
          : AppBar(
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
                  tooltip: _narrating ? 'Stop reading aloud' : 'Read aloud',
                  icon: Icon(
                      _narrating
                          ? Icons.stop_circle_outlined
                          : Icons.headphones_rounded,
                      color: _narrating
                          ? ExodusTheme.brass
                          : ExodusTheme.ironMist),
                  onPressed: _loading ? null : () => _listen(),
                ),
                IconButton(
                  tooltip: drawing ? 'Put the pen down' : 'Highlight and draw',
                  icon: Icon(
                      drawing
                          ? Icons.edit_off_rounded
                          : Icons.border_color_outlined,
                      color:
                          drawing ? ExodusTheme.brass : ExodusTheme.ironMist),
                  onPressed: _loading
                      ? null
                      : () => _setTool(drawing ? InkTool.off : InkTool.marker),
                ),
                IconButton(
                  tooltip: 'Ask EXODUS to find a passage',
                  icon: const Icon(Icons.auto_awesome,
                      color: ExodusTheme.covenantGlow),
                  onPressed: _loading ? null : _search,
                ),
                _moreMenu(ExodusTheme.ironMist),
              ],
            ),
      // Scrolling, the selection bar takes its place under the text. Turning
      // pages it floats over the foot of the page instead: giving it room
      // would shorten every page and reflow the chapter under the reader's
      // finger the moment they touched a verse.
      bottomNavigationBar:
          _selected.isEmpty || drawing || book ? null : _selectionBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(top: !_immersive, child: _body()),
          ),
          if (_paged && !_immersive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(bottom: false, child: _inkChrome()),
            ),
          if (book && !_immersive)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(top: false, child: _bookFooter()),
            ),
          if (book && _selected.isNotEmpty && !drawing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _selectionBar(),
            ),
          // The pen's tools float over the page rather than pushing it up,
          // so the page does not reflow under the pen as the bar appears.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, 0.4), end: Offset.zero)
                            .animate(a),
                    child: child,
                  ),
                ),
                child: Padding(
                  key: ValueKey(drawing
                      ? 'pen'
                      : _narrating
                          ? 'listen'
                          : 'none'),
                  // Clear of the chapter footer when there is one.
                  padding:
                      EdgeInsets.only(bottom: _paged && !_immersive ? 44 : 0),
                  child: drawing
                      ? _penBar()
                      : _narrating
                          ? _player()
                          : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          // Bottom centre: the one place empty in both layouts, between the
          // folios and, unfolded, at the foot of the spine.
          if (_immersive)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Semantics(
                      button: true,
                      label: 'Leave reading mode',
                      child: Material(
                        color: ExodusTheme.midnight.withValues(alpha: 0.55),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _toggleImmersive,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.fullscreen_exit_rounded,
                                size: 18, color: ExodusTheme.ironMist),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Highlighter or pen, their colours, eraser, undo, done.
  Widget _penBar() {
    final marker = _tool == InkTool.marker;
    final colors = marker ? MarkColors.markers : MarkColors.ink;
    final chosen = marker ? _markerColor : _inkColor;
    Widget toolButton(InkTool tool, IconData icon, String label) {
      final on = _tool == tool;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _setTool(tool),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? ExodusTheme.brass.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
            child: Icon(icon,
                size: 20, color: on ? ExodusTheme.brass : ExodusTheme.ironMist),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: ExodusTheme.brass.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FittedBox(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              toolButton(
                  InkTool.marker, Icons.border_color_rounded, 'Highlighter'),
              toolButton(InkTool.pen, Icons.edit_rounded, 'Pen'),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: ExodusTheme.steel,
              ),
              if (_tool != InkTool.eraser)
                for (var i = 0; i < colors.length; i++)
                  Semantics(
                    button: true,
                    selected: chosen == i,
                    label: '${marker ? 'Highlighter' : 'Pen'} colour ${i + 1}',
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (marker) {
                            _markerColor = i;
                          } else {
                            _inkColor = i;
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: marker ? 30 : 24,
                        height: marker ? 18 : 24,
                        decoration: BoxDecoration(
                          // A marker's chisel tip; a pen's round nib.
                          shape: marker ? BoxShape.rectangle : BoxShape.circle,
                          borderRadius:
                              marker ? BorderRadius.circular(4) : null,
                          color: colors[i],
                          border: Border.all(
                            color: chosen == i
                                ? ExodusTheme.porcelain
                                : Colors.transparent,
                            width: 2.2,
                          ),
                        ),
                      ),
                    ),
                  ),
              toolButton(
                  InkTool.eraser, Icons.cleaning_services_outlined, 'Eraser'),
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo_rounded,
                    size: 20, color: ExodusTheme.ironMist),
                onPressed: _chapterMarks.ink.isEmpty ? null : _undoInk,
              ),
              TextButton(
                onPressed: () => _setTool(InkTool.off),
                child: const Text('Done',
                    style: TextStyle(
                        color: ExodusTheme.brass, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// While reading aloud: where it has got to, and a way to stop.
  Widget _player() {
    final v = _narratedVerse;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: ExodusTheme.brass.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq_rounded,
                size: 18, color: ExodusTheme.brass),
            const SizedBox(width: 10),
            Text(
              v == null ? 'Reading aloud' : '$_bookName $_chapter:$v',
              style: const TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Stop reading',
              icon: const Icon(Icons.stop_rounded, color: ExodusTheme.brass),
              onPressed: _stopListening,
            ),
          ],
        ),
      ),
    );
  }

  /// Ink over [child], which lays out verses [first]..[last].
  Widget _inked(int first, int last, Widget child) => InkLayer(
        book: _bookIndex,
        chapter: _chapter,
        verses: [for (var v = first; v <= last; v++) v],
        verseKeys: _verseKeys,
        tool: _tool,
        inkColor: _inkColor,
        markerColor: _markerColor,
        child: child,
      );

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
            child: PaperPage(
              side: PageSide.single,
              child: SingleChildScrollView(
                controller: _scroll,
                // With the pen out, a vertical drag is a line, not a scroll.
                physics: _tool == InkTool.off
                    ? null
                    : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _inked(
                      1,
                      verses.length,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < verses.length; i++)
                            _verseRow(i + 1, verses[i]),
                        ],
                      ),
                    ),
                    _chapterNav(),
                  ],
                ),
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
              // the chapter is set here and reset when either changes — a
              // rotation or an accessibility change must not leave words
              // stranded off the foot of a page.
              final scaler =
                  MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.8);

              // An open book unfolded, two facing pages with the spine on the
              // fold; folded, one page with the spine at its left edge.
              final per = ExodusLayout.isExpanded(context) ? 2 : 1;
              final page =
                  Size(constraints.maxWidth / per, constraints.maxHeight);
              _typeset(verses, page, per, scaler);
              final decor = _decor();
              return BookSpread(
                pagesPerView: per,
                pageCount: _leaves.length,
                spread: per == 2 ? _pageIndex ~/ 2 : _pageIndex,
                interactive: _tool == InkTool.off,
                reduceMotion: ExodusLayout.reduceMotion(context),
                paperColor: BiblePalette.paper,
                revision: Object.hash(
                  _setFor,
                  _marksRev,
                  Object.hashAll(_selected),
                  _highlight?.verseStart,
                  _narratedVerse,
                  _artRev,
                ),
                onSpreadChanged: (s) => setState(() => _pageIndex =
                    (per == 2 ? s * 2 : s).clamp(0, _leaves.length - 1)),
                pageBuilder: (context, i) => _leafPage(i, per, decor),
                blankBuilder: (context) => PaperPage(
                  side: per == 1 ? PageSide.single : PageSide.right,
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// How each verse looks on the page and what touching it does.
  ProseDecor _decor() {
    final marks = _chapterMarks;
    return ProseDecor(
      selected: _selected,
      narrated: _narratedVerse,
      highlightStart: _highlight?.verseStart,
      highlightEnd: _highlight?.verseEnd,
      legacy: {
        for (final e in marks.highlights.entries)
          e.key: MarkColors.markers[e.value % MarkColors.markers.length],
      },
      notes: marks.notes,
      onVerseTap: _toggleVerse,
      onNoteTap: _editNote,
      ink: (verses, rectOf, child) => InkLayer(
        book: _bookIndex,
        chapter: _chapter,
        verses: verses,
        verseRect: rectOf,
        tool: _tool,
        inkColor: _inkColor,
        markerColor: _markerColor,
        child: child,
      ),
    );
  }

  /// Leaf [i] of the chapter.
  Widget _leafPage(int i, int per, ProseDecor decor) {
    final side = per == 1
        ? PageSide.single
        : i.isEven
            ? PageSide.left
            : PageSide.right;
    if (i >= _leaves.length) {
      return PaperPage(side: side, child: const SizedBox.expand());
    }
    final verses = _displayVerses;
    switch (_leaves[i]) {
      case _PlateLeaf(:final plate):
        final v = plate.verse;
        return PlatePage(
          plate: plate,
          side: side,
          caption: PlatePage.captionFor(
              v >= 1 && v <= verses.length ? verses[v - 1] : ''),
          reference: '$_bookName $_chapter:$v',
        );
      case _EndLeaf():
        final hasNext =
            _chapter < _chapterCount || _bookIndex < _bible.books.length - 1;
        final nextBook = _chapter < _chapterCount ? _bookIndex : _bookIndex + 1;
        final nextChapter = _chapter < _chapterCount ? _chapter + 1 : 1;
        return ChapterEndPage(
          side: side,
          label: 'Here ends $_bookName $_chapter',
          vignette: _art.vignetteFor(_bookIndex, _chapter + 1),
          nextLabel: hasNext
              ? 'Turn to ${_bible.bookName(nextBook)} $nextChapter'
              : null,
          onNext: hasNext ? () => _changeChapter(1) : null,
        );
      case _ProseLeaf(:final slice):
        return _prosePage(slice, side, i, decor);
    }
  }

  /// A page of the chapter's text; the first carries its heading.
  Widget _prosePage(int slice, PageSide side, int index, ProseDecor decor) {
    final m = PageMargins.of(side);
    final set = _set!;
    final heading = slice == 0 ? _heading : null;
    return PaperPage(
      side: side,
      child: Stack(
        children: [
          Positioned(
            left: m.left,
            right: m.right,
            top: m.top,
            bottom: m.bottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (heading != null)
                  // Measured unscaled, so drawn unscaled: the heading is
                  // display type, and a scaled title would no longer fit the
                  // space measured for it.
                  MediaQuery.withNoTextScaling(
                    child: ChapterHeading(
                      kicker: heading.kicker,
                      title: heading.title,
                      vignette: heading.vignette,
                      headpiece: heading.headpiece,
                      headpieceHeight: heading.headpieceHeight,
                      titleSize: heading.titleSize,
                    ),
                  ),
                ProseView(
                  chapter: set,
                  slice: slice,
                  decor: decor,
                  notesOnLeft: side == PageSide.left,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: side == PageSide.left ? m.left : null,
            right: side == PageSide.left ? null : m.right,
            child: Folio(index + 1),
          ),
        ],
      ),
    );
  }

  /// The reader's controls, drawn in ink on the head of the page rather than
  /// in a bar over it.
  Widget _inkChrome() {
    final drawing = _tool != InkTool.off;
    final ink = _loading ? ExodusTheme.ironMist : BiblePalette.faint;
    final nav = Navigator.of(context);
    Widget icon(IconData i, String label, VoidCallback? onTap,
            {Color? color}) =>
        IconButton(
          tooltip: label,
          iconSize: 20,
          color: color ?? ink,
          disabledColor: ink.withValues(alpha: 0.35),
          onPressed: _loading ? null : onTap,
          icon: Icon(i),
        );
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (nav.canPop())
              icon(Icons.arrow_back_ios_new_rounded, 'Back', nav.maybePop),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Change book and chapter',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _loading ? null : _pickBook,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // The book's name gives way before the chapter
                            // number does.
                            Flexible(
                              child: Text(
                                _loading ? 'BIBLE' : _bookName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ChapterHeading.kickerStyle.copyWith(
                                    color: ink,
                                    fontSize: 11,
                                    letterSpacing: 1.6),
                              ),
                            ),
                            if (!_loading)
                              Text(' $_chapter',
                                  style: ChapterHeading.kickerStyle.copyWith(
                                      color: ink,
                                      fontSize: 11,
                                      letterSpacing: 1.6)),
                            Icon(Icons.arrow_drop_down, size: 18, color: ink),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(BibleService.translation,
                        style: TextStyle(
                          fontFamily: 'Spectral',
                          color: ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        )),
                  ),
                ),
              ),
            icon(
              _narrating
                  ? Icons.stop_circle_outlined
                  : Icons.headphones_outlined,
              _narrating ? 'Stop reading aloud' : 'Read aloud',
              () => _listen(),
              color: _narrating ? BiblePalette.rubric : null,
            ),
            icon(
              drawing ? Icons.edit_off_outlined : Icons.border_color_outlined,
              drawing ? 'Put the pen down' : 'Highlight and draw',
              () => _setTool(drawing ? InkTool.off : InkTool.marker),
              color: drawing ? BiblePalette.rubric : null,
            ),
            icon(Icons.auto_awesome_outlined, 'Ask EXODUS to find a passage',
                _search),
            _moreMenu(ink),
          ],
        ),
      ),
    );
  }

  /// Where the reader is in the chapter, and the way to the next one, at the
  /// foot of the book.
  Widget _bookFooter() {
    final total = _leaves.length;
    final String where;
    if (total <= 1) {
      where = '';
    } else if (_per == 2) {
      final first = (_pageIndex ~/ 2) * 2 + 1;
      final last = math.min(first + 1, total);
      where = '  ·  ${first == last ? first : '$first\u2013$last'} of $total';
    } else {
      where = '  ·  ${_pageIndex + 1} of $total';
    }
    const ink = BiblePalette.faint;
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous chapter',
            iconSize: 20,
            color: ink,
            disabledColor: ink.withValues(alpha: 0.3),
            onPressed: (_chapter > 1 || _bookIndex > 0)
                ? () => _changeChapter(-1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('$_bookName $_chapter$where',
              style: const TextStyle(
                fontFamily: 'Spectral',
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: ink,
                fontFeatures: [FontFeature.oldstyleFigures()],
              )),
          IconButton(
            tooltip: 'Next chapter',
            iconSize: 20,
            color: ink,
            disabledColor: ink.withValues(alpha: 0.3),
            onPressed: (_chapter < _chapterCount ||
                    _bookIndex < _bible.books.length - 1)
                ? () => _changeChapter(1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
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
        border:
            Border.all(color: ExodusTheme.covenantGlow.withValues(alpha: 0.4)),
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
    final reading = _narratedVerse == number;
    final marks = _chapterMarks;
    // Highlights made before the highlighter existed: kept, shown as a
    // soft wash of marker, with nothing over the words.
    final legacy = marks.highlights[number] == null
        ? null
        : MarkColors
            .markers[marks.highlights[number]! % MarkColors.markers.length];
    final note = marks.notes[number];
    final key = _verseKeys.putIfAbsent(number, () => GlobalKey());
    return Semantics(
      key: key,
      button: true,
      selected: selected,
      label: 'Verse $number',
      child: InkWell(
        onTap: () => _toggleVerse(number),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1F3A6E).withValues(alpha: 0.12)
                : reading
                    ? BiblePalette.gilt.withValues(alpha: 0.26)
                    : highlighted
                        ? BiblePalette.gilt.withValues(alpha: 0.18)
                        : legacy != null
                            ? legacy.withValues(alpha: 0.30)
                            : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(text: '$number ', style: _verseNumberStyle),
                    // An omitted verse keeps its number so every other verse
                    // still lands where the reader expects, but a bare number
                    // with nothing after it reads as a rendering bug, so it is
                    // set apart the way a print Bible footnotes it.
                    TextSpan(
                      text: text,
                      style: _isOmitted(number)
                          ? _verseTextStyle.copyWith(
                              color: BiblePalette.faint,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            )
                          : _verseTextStyle,
                    ),
                  ],
                ),
              ),
              // A note in the margin: a small red mark at the verse's end
              // corner that opens it. Overlaid rather than inline, so it
              // never changes how the verse wraps.
              if (note != null)
                Positioned(
                  top: -10,
                  right: -12,
                  child: Semantics(
                    button: true,
                    label: 'Note on verse $number',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _editNote(number),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: BiblePalette.paper,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color:
                                    BiblePalette.rubric.withValues(alpha: 0.7)),
                          ),
                          child: const Icon(Icons.edit_note_rounded,
                              size: 12, color: BiblePalette.rubric),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
            onPressed: (_chapter < _chapterCount ||
                    _bookIndex < _bible.books.length - 1)
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
            const SizedBox(height: 4),
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
                    icon: Icons.headphones_rounded,
                    label: 'Read aloud',
                    onTap: () => _listen(only: (_selected.toList()..sort()))),
                _barAction(
                    icon: Icons.help_outline_rounded,
                    label: 'Ask a question',
                    onTap: _askAbout),
                _barAction(
                    icon: Icons.edit_note_rounded,
                    label: 'Note',
                    onTap: () => _editNote((_selected.toList()..sort()).first)),
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
    final chapters =
        widget.bible.books.isEmpty ? 0 : widget.bible.books[i].chapterCount;
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

/// A leaf of the open chapter.
sealed class _Leaf {
  const _Leaf();
}

/// A page of the chapter's text: band [slice] of the typeset chapter.
class _ProseLeaf extends _Leaf {
  final int slice;
  const _ProseLeaf(this.slice);
}

/// A full page of art.
class _PlateLeaf extends _Leaf {
  final BiblePlate plate;
  const _PlateLeaf(this.plate);
}

/// The tailpiece after the chapter's last page.
class _EndLeaf extends _Leaf {
  const _EndLeaf();
}

/// The heading over a chapter's first page, as measured.
class _Heading {
  final String kicker;
  final String title;
  final String? vignette;
  final String? headpiece;
  final double headpieceHeight;
  final double titleSize;
  final double height;

  const _Heading({
    required this.kicker,
    required this.title,
    required this.vignette,
    required this.headpiece,
    required this.headpieceHeight,
    required this.titleSize,
    required this.height,
  });
}
