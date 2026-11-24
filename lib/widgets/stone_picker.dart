import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/bible_books.dart';
import '../models/bible_ref.dart';

/// The chapter picker, cut in stone: two arched tablets in the shape of the
/// tablets of the Law. Unfolded, one stands on each page with the hinge
/// between them — the books on the left, the chapters on the right. Folded,
/// a single tablet rises from the foot and turns between its two faces.
///
/// Pops with the [BibleRef] chosen, or null.
class StonePicker extends StatefulWidget {
  final int currentBook;
  final int currentChapter;

  /// Chapters in each book, by canon index.
  final int Function(int book) chapterCount;

  /// The chapter's heading — a plate's title where it has one.
  final String Function(int book, int chapter) titleOf;

  /// Whether the chapter carries an illustrated plate.
  final bool Function(int book, int chapter) illustrated;

  const StonePicker({
    super.key,
    required this.currentBook,
    required this.currentChapter,
    required this.chapterCount,
    required this.titleOf,
    required this.illustrated,
  });

  /// Raise the tablets over the open book.
  static Future<BibleRef?> show(BuildContext context, StonePicker picker) {
    return showGeneralDialog<BibleRef>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close the chapter picker',
      barrierColor: const Color(0x851C140A),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => picker,
      transitionBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<StonePicker> createState() => _StonePickerState();
}

/// The parts of the Bible, as a thumb index divides them: the line under a
/// book's name on the tablet.
String stoneSectionOf(int book) {
  if (book < 5) return 'The Law';
  if (book < 17) return 'The Histories';
  if (book < 22) return 'Poetry and Wisdom';
  if (book < 27) return 'The Major Prophets';
  if (book < 39) return 'The Minor Prophets';
  if (book < 43) return 'The Gospels';
  if (book < 44) return 'The Acts of the Apostles';
  if (book < 57) return 'The Letters of Paul';
  if (book < 65) return 'The General Letters';
  return 'Prophecy';
}

class _StonePickerState extends State<StonePicker> {
  late int _book = widget.currentBook;
  late bool _newTestament = widget.currentBook >= BibleBooks.firstNewTestament;

  /// Folded only: which face of the single tablet is turned outward.
  bool _booksFace = false;

  bool get _browsingCurrent => _book == widget.currentBook;

  /// One scroll position per book's grid, opened on the current chapter.
  final Map<int, ScrollController> _grids = {};

  /// One per testament, opened on the row that holds the current book.
  final Map<bool, ScrollController> _shelves = {};

  @override
  void dispose() {
    for (final c in [..._grids.values, ..._shelves.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pickBook(int book) => setState(() {
        _book = book;
        _booksFace = false;
      });

  void _pickChapter(int chapter) =>
      Navigator.of(context).pop(BibleRef(bookIndex: _book, chapter: chapter));

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (context, c) {
      final open = c.maxWidth > c.maxHeight && c.maxWidth >= 700;
      return Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          // Tapping the dimmed page around the stone closes it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          if (open) _open(c, pad) else _folded(c, pad),
        ]),
      );
    });
  }

  // ── Unfolded: two tablets across the hinge ───────────────────────────

  Widget _open(BoxConstraints c, EdgeInsets pad) {
    const gap = 34.0;
    final width = math.min(380.0, (c.maxWidth - gap) / 2 - 24);
    return Positioned(
      left: 0,
      right: 0,
      top: 22 + pad.top,
      bottom: 18 + pad.bottom,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: width,
            child: StoneTablet(
              seed: 4,
              padding: const EdgeInsets.fromLTRB(26, 34, 26, 18),
              child: _booksTablet(columns: 2),
            ),
          ),
          const SizedBox(width: gap),
          SizedBox(
            width: width,
            child: StoneTablet(
              seed: 9,
              padding: const EdgeInsets.fromLTRB(26, 34, 26, 18),
              child: _chaptersTablet(columns: 6, cell: 38),
            ),
          ),
        ],
      ),
    );
  }

  // ── Folded: one tablet rising from the foot ──────────────────────────

  Widget _folded(BoxConstraints c, EdgeInsets pad) {
    final right = 10 + pad.right;
    final width = c.maxWidth - 10 - pad.left - right;
    return Positioned(
      left: 10 + pad.left,
      right: right,
      top: pad.top + math.max(60, c.maxHeight * 0.14),
      bottom: 0,
      child: StoneTablet(
        seed: 5,
        footless: true,
        archHeight: math.min(80, width * 0.2),
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
        child: Column(children: [
          _foldedHeader(),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _faceButton('CHAPTERS', !_booksFace,
                    () => setState(() => _booksFace = false)),
                Text('·', style: StoneType.carved(14)),
                _faceButton('BOOKS', _booksFace,
                    () => setState(() => _booksFace = true)),
              ],
            ),
          ),
          const StoneRule(),
          Expanded(
            child: _booksFace
                ? Column(children: [
                    _testamentSwitch(),
                    Expanded(child: _bookList(columns: 2, bottom: pad.bottom)),
                  ])
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _chapterGrid(
                        columns: 5, cell: 44, bottom: pad.bottom + 24),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _foldedHeader() {
    final name = BibleBooks.names[_book];
    return Column(children: [
      Text(
        _booksFace || !_browsingCurrent
            ? stoneSectionOf(_book).toUpperCase()
            : '${_chapterWord.toUpperCase()} ${widget.currentChapter}',
        textAlign: TextAlign.center,
        style: StoneType.kicker(),
      ),
      const SizedBox(height: 8),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(name.toUpperCase(),
            style: StoneType.gilt(30, weight: 700, spacing: 3.6)),
      ),
      const SizedBox(height: 2),
      Text(
        _browsingCurrent && !_booksFace
            ? widget.titleOf(_book, widget.currentChapter)
            : _countWords,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: StoneType.italic(15),
      ),
    ]);
  }

  Widget _faceButton(String label, bool on, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: on,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(label,
                  style: on
                      ? StoneType.gilt(11, spacing: 3.3)
                      : StoneType.carved(11, spacing: 3.3)),
            ),
          ),
        ),
      ),
    );
  }

  // ── The books tablet ─────────────────────────────────────────────────

  Widget _booksTablet({required int columns}) {
    return Column(children: [
      Text('THE BOOKS', style: StoneType.kicker()),
      const SizedBox(height: 8),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(BibleBooks.names[_book].toUpperCase(),
            style: StoneType.carved(26, weight: 700, spacing: 3.1)),
      ),
      const SizedBox(height: 2),
      Text(stoneSectionOf(_book), style: StoneType.italic(15)),
      _testamentSwitch(),
      const StoneRule(),
      const SizedBox(height: 8),
      Expanded(child: _bookList(columns: columns)),
    ]);
  }

  Widget _testamentSwitch() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _faceButton('OLD', !_newTestament,
              () => setState(() => _newTestament = false)),
          Text('·', style: StoneType.carved(14)),
          _faceButton(
              'NEW', _newTestament, () => setState(() => _newTestament = true)),
        ],
      ),
    );
  }

  Widget _bookList({required int columns, double bottom = 0}) {
    final first = _newTestament ? BibleBooks.firstNewTestament : 0;
    final end =
        _newTestament ? BibleBooks.names.length : BibleBooks.firstNewTestament;
    final books = [for (var i = first; i < end; i++) i];
    final rows = (books.length / columns).ceil();
    final at = books.indexOf(widget.currentBook);
    final row = at < 0 ? 0 : at ~/ columns;
    return _Fade(
      child: ListView.builder(
        key: ValueKey('stone-books-$_newTestament'),
        controller: _shelves.putIfAbsent(
            _newTestament,
            () => ScrollController(
                initialScrollOffset: math.max(0.0, (row - 3) * 42.0))),
        padding: EdgeInsets.only(top: 6, bottom: 24 + bottom),
        itemCount: rows,
        itemBuilder: (_, r) => Row(children: [
          for (var k = 0; k < columns; k++)
            Expanded(
              child: r * columns + k < books.length
                  ? _bookCell(books[r * columns + k])
                  : const SizedBox(),
            ),
        ]),
      ),
    );
  }

  Widget _bookCell(int i) {
    final on = i == _book;
    final current = i == widget.currentBook;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pickBook(i),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: on ? StoneRecess.decoration(radius: 4) : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              BibleBooks.names[i].toUpperCase(),
              style: on || current
                  ? StoneType.gilt(12.5, spacing: 1.1)
                  : StoneType.carved(12.5, spacing: 1.1),
            ),
          ),
        ),
      ),
    );
  }

  // ── The chapters tablet ──────────────────────────────────────────────

  String get _chapterWord =>
      BibleBooks.names[_book] == 'Psalms' ? 'Psalm' : 'Chapter';

  String get _countWords {
    final n = widget.chapterCount(_book);
    final word = BibleBooks.names[_book] == 'Psalms' ? 'psalm' : 'chapter';
    return n == 1 ? 'One $word' : '$n ${word}s';
  }

  Widget _chaptersTablet({required int columns, required double cell}) {
    final current = _browsingCurrent;
    return Column(children: [
      Text(
        current
            ? _chapterWord.toUpperCase()
            : BibleBooks.names[_book].toUpperCase(),
        style: StoneType.kicker(),
      ),
      const SizedBox(height: 8),
      Text(
        current ? '${widget.currentChapter}' : '${widget.chapterCount(_book)}',
        style: StoneType.gilt(44, weight: 700, height: 1),
      ),
      const SizedBox(height: 4),
      Text(
        current
            ? widget.titleOf(_book, widget.currentChapter)
            : (widget.chapterCount(_book) == 1
                ? 'One ${_chapterWord.toLowerCase()}'
                : '${_chapterWord}s'),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: StoneType.italic(15),
      ),
      const SizedBox(height: 12),
      const StoneRule(),
      const SizedBox(height: 14),
      Expanded(child: _chapterGrid(columns: columns, cell: cell)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const _Diamond(size: 7),
        const SizedBox(width: 6),
        Flexible(
          child: Text('marks a chapter with a plate',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StoneType.italic(13)),
        ),
      ]),
    ]);
  }

  Widget _chapterGrid(
      {required int columns, required double cell, double bottom = 0}) {
    final count = widget.chapterCount(_book);
    const gap = 7.0;
    final current = _browsingCurrent ? widget.currentChapter : 0;
    return LayoutBuilder(builder: (context, c) {
      // Open on the row that holds the current chapter.
      final row = current == 0 ? 0 : (current - 1) ~/ columns;
      final offset = math.max(0.0, row * (cell + gap) - c.maxHeight * 0.4);
      return _Fade(
        child: GridView.builder(
          key: ValueKey('stone-chapters-$_book'),
          controller: _grids.putIfAbsent(
              _book, () => ScrollController(initialScrollOffset: offset)),
          padding: EdgeInsets.only(top: 2, bottom: bottom + 6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: cell,
          ),
          itemCount: count,
          itemBuilder: (_, i) => _chapterCell(i + 1, current),
        ),
      );
    });
  }

  Widget _chapterCell(int n, int current) {
    final on = n == current;
    final plate = widget.illustrated(_book, n);
    return Semantics(
      button: true,
      selected: on,
      label: '$_chapterWord $n${plate ? ', illustrated' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pickChapter(n),
        child: DecoratedBox(
          decoration: on
              ? StoneRecess.gilded(radius: 5)
              : StoneRecess.decoration(radius: 5),
          child: Stack(children: [
            Center(
              child: Text(
                '$n',
                style: on
                    ? StoneType.inGold(15)
                    : StoneType.carved(n > 99 ? 13 : 15),
              ),
            ),
            if (plate)
              Positioned(
                top: 5,
                right: 5,
                child: _Diamond(size: 6, onGold: on),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Fades a scrolling list out under the stone's edge, top and foot, so rows
/// seem to pass beneath the carving rather than being cut off.
class _Fade extends StatelessWidget {
  final Widget child;
  const _Fade({required this.child});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0x00000000)
        ],
        stops: [0, 0.03, 0.94, 1],
      ).createShader(r),
      child: child,
    );
  }
}

/// The small lozenge that marks an illustrated chapter, inlaid in gilt.
class _Diamond extends StatelessWidget {
  final double size;
  final bool onGold;
  const _Diamond({required this.size, this.onGold = false});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onGold ? StoneType.goldInk : StoneType.gilt0,
          boxShadow: const [
            BoxShadow(color: Color(0xB3FFFCF2), offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

// ── Materials ──────────────────────────────────────────────────────────

/// Inscriptional lettering: Cinzel cut into the stone, lit from above — a
/// highlight on the lower lip of each stroke and a shadow on the upper.
class StoneType {
  static const ink = Color(0xFF6A5E4C);
  static const gilt0 = Color(0xFF9C7536);
  static const goldInk = Color(0xFF3E2A0E);

  static const _carvedShadows = [
    Shadow(color: Color(0xBFFFFCF2), offset: Offset(0, 1)),
    Shadow(color: Color(0x733C2E1C), offset: Offset(0, -1)),
  ];
  static const _giltShadows = [
    Shadow(color: Color(0xCCFFF0C8), offset: Offset(0, 1)),
    Shadow(color: Color(0x8C50340E), offset: Offset(0, -1)),
  ];

  static TextStyle _cinzel(double size, double weight, double spacing,
          Color color, List<Shadow> shadows, double? height) =>
      TextStyle(
        fontFamily: 'Cinzel',
        fontSize: size,
        fontVariations: [FontVariation('wght', weight)],
        fontWeight: weight >= 650 ? FontWeight.w700 : FontWeight.w600,
        letterSpacing: spacing,
        height: height,
        color: color,
        shadows: shadows,
      );

  static TextStyle carved(double size,
          {double weight = 600, double spacing = 0, double? height}) =>
      _cinzel(size, weight, spacing, ink, _carvedShadows, height);

  static TextStyle gilt(double size,
          {double weight = 600, double spacing = 0, double? height}) =>
      _cinzel(size, weight, spacing, gilt0, _giltShadows, height);

  /// A numeral cut into a gilded cell: dark in the gold.
  static TextStyle inGold(double size) => _cinzel(size, 700, 0, goldInk,
      const [Shadow(color: Color(0x99FFECBE), offset: Offset(0, 1))], null);

  static TextStyle kicker() => carved(10, spacing: 4.2);

  static TextStyle italic(double size) => TextStyle(
        fontFamily: 'Cormorant',
        fontStyle: FontStyle.italic,
        fontSize: size,
        fontVariations: const [FontVariation('wght', 500)],
        height: 1.2,
        color: ink,
        shadows: _carvedShadows,
      );
}

/// A cell sunk into the stone: darker where the lip shades it at the top,
/// catching light along its lower edge.
class StoneRecess {
  // The lip is painted into the gradient — a dark band under the top edge,
  // a lit one along the foot — since a rounded border must be one colour.
  static BoxDecoration decoration({double radius = 5}) => BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x7A4A3A24),
            Color(0x476E5E46),
            Color(0x146E5E46),
            Color(0x1FFFFAEE),
            Color(0x99FFFCF2),
          ],
          stops: [0, 0.1, 0.4, 0.92, 1],
        ),
      );

  static BoxDecoration gilded({double radius = 5}) => BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF7E5B22),
            Color(0xFFA9823E),
            Color(0xFFC9A55E),
            Color(0xFFB18A45),
            Color(0xFFFFE6B0),
          ],
          stops: [0, 0.1, 0.5, 0.92, 1],
        ),
      );
}

/// A rule incised across the stone.
class StoneRule extends StatelessWidget {
  const StoneRule({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 1.5,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [
            Color(0x003C2E1C),
            Color(0x5A3C2E1C),
            Color(0x003C2E1C),
          ]),
        ),
      ),
      Container(
        height: 1,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [
            Color(0x00FFFCF2),
            Color(0x99FFFCF2),
            Color(0x00FFFCF2),
          ]),
        ),
      ),
    ]);
  }
}

/// A tablet of pale limestone with an arched head, as the tablets of the Law
/// are drawn. [footless] runs it off the foot of the screen.
class StoneTablet extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final int seed;
  final bool footless;
  final double? archHeight;

  const StoneTablet({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.seed = 1,
    this.footless = false,
    this.archHeight,
  });

  @override
  Widget build(BuildContext context) {
    final shape = _ArchBorder(arch: archHeight, footless: footless);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: const [
          BoxShadow(
              color: Color(0x73140E06), blurRadius: 40, offset: Offset(0, 18)),
          BoxShadow(
              color: Color(0x4D140E06), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: _LimestonePainter(seed: seed, shape: shape),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
  }
}

class _ArchBorder extends ShapeBorder {
  final double? arch;
  final bool footless;
  const _ArchBorder({this.arch, this.footless = false});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  double _archOf(Rect r) => arch ?? math.min(92, r.width * 0.24);

  @override
  Path getOuterPath(Rect r, {TextDirection? textDirection}) {
    final a = _archOf(r);
    final foot = footless ? 0.0 : 16.0;
    final half = r.width / 2;
    return Path()
      ..moveTo(r.left, r.top + a)
      ..arcToPoint(Offset(r.left + half, r.top),
          radius: Radius.elliptical(half, a))
      ..arcToPoint(Offset(r.right, r.top + a),
          radius: Radius.elliptical(half, a))
      ..lineTo(r.right, r.bottom - foot)
      ..quadraticBezierTo(r.right, r.bottom, r.right - foot, r.bottom)
      ..lineTo(r.left + foot, r.bottom)
      ..quadraticBezierTo(r.left, r.bottom, r.left, r.bottom - foot)
      ..close();
  }

  @override
  Path getInnerPath(Rect r, {TextDirection? textDirection}) =>
      getOuterPath(r, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

/// Pale Jerusalem limestone: a lit face falling to warm shade, a fine grain
/// of pits and flecks, a few faint veins, and a chamfered edge that catches
/// the light along the arch.
class _LimestonePainter extends CustomPainter {
  final int seed;
  final ShapeBorder shape;
  _LimestonePainter({required this.seed, required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.6, -1),
          end: Alignment(0.6, 1),
          colors: [Color(0xFFDCD3C2), Color(0xFFCFC5B2), Color(0xFFC2B7A2)],
          stops: [0, 0.45, 1],
        ).createShader(r),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.3, size.height * 0.12),
          size.longestSide * 0.6,
          [const Color(0x8CFFFAEE), const Color(0x00FFFAEE)],
        ),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.8, size.height),
          size.longestSide * 0.55,
          [const Color(0x385A4A34), const Color(0x005A4A34)],
        ),
    );

    final rnd = math.Random(seed);
    // Veins: long, faint, wandering.
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0x1C5A4A34);
    for (var v = 0; v < 4; v++) {
      var p =
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final path = Path()..moveTo(p.dx, p.dy);
      var angle = rnd.nextDouble() * math.pi * 2;
      for (var s = 0; s < 18; s++) {
        angle += (rnd.nextDouble() - 0.5) * 0.9;
        p += Offset(math.cos(angle), math.sin(angle)) * 18;
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, vein);
    }

    // Grain: pits in shade, flecks in light.
    final area = size.width * size.height;
    final count = (area / 90).clamp(400, 6000).toInt();
    final dark = <Offset>[];
    final pale = <Offset>[];
    final pits = <Offset>[];
    for (var i = 0; i < count; i++) {
      final o =
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final k = rnd.nextDouble();
      if (k < 0.5) {
        dark.add(o);
      } else if (k < 0.92) {
        pale.add(o);
      } else {
        pits.add(o);
      }
    }
    canvas.drawPoints(
        ui.PointMode.points,
        dark,
        Paint()
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x2E59492F));
    canvas.drawPoints(
        ui.PointMode.points,
        pale,
        Paint()
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x40FFFCF2));
    // A pit: a dark speck with light on its lower lip.
    final pitDark = Paint()..color = const Color(0x4D4A3A24);
    final pitLight = Paint()..color = const Color(0x59FFFCF2);
    for (final o in pits) {
      final rad = 0.6 + rnd.nextDouble() * 1.1;
      canvas.drawCircle(o + Offset(0, rad * 0.6), rad, pitLight);
      canvas.drawCircle(o, rad, pitDark);
    }

    // The chamfer: light along the top edge, shade inside the foot.
    final edge = shape.getOuterPath(r);
    canvas.drawPath(
      edge.shift(const Offset(0, 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x99FFFDF5),
    );
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x5978684F),
    );
  }

  @override
  bool shouldRepaint(_LimestonePainter old) => old.seed != seed;
}
