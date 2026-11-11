import 'dart:async';

import 'package:flutter/material.dart';
import '../layout/exodus_layout.dart';

import '../models/conversation.dart';
import '../services/bible_service.dart';
import '../services/analytics.dart';
import '../services/daily_verse.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/arrival.dart';
import '../widgets/community_strip.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/page_backdrop.dart';
import '../widgets/scripture_background.dart';
import '../widgets/scripture_link.dart';

/// The landing screen: a greeting, the day's verse, and the conversations
/// already under way.
///
/// This replaces opening straight into a chat thread. Arriving on an empty
/// composer asks the couple to think of something; arriving here hands them a
/// verse and their own unfinished conversations.
class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;

  /// Open an existing conversation in Counsel.
  final ValueChanged<String> onOpenConversation;

  /// Start a fresh conversation in Counsel.
  final VoidCallback onNewConversation;

  /// Show the whole conversation list (the drawer's chats section).
  final VoidCallback onSeeAll;

  const HomeScreen({
    super.key,
    this.onOpenMenu,
    required this.onOpenConversation,
    required this.onNewConversation,
    required this.onSeeAll,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _bibleReady = BibleService.instance.isLoaded;

  @override
  void initState() {
    super.initState();
    // The verse needs the translation parsed. It is ~4MB off the UI isolate,
    // so the card shows its reference immediately and fills in the text.
    if (!_bibleReady) {
      // Best-effort: a Bible that fails to parse leaves the card showing its
      // reference, which is still useful, rather than taking the screen down.
      unawaited(BibleService.instance.load().then((_) {
        if (mounted) setState(() => _bibleReady = true);
      }, onError: (_) {}));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Refresh after returning from a conversation, so times and previews are
  /// current. Called by the shell.
  void refresh() {
    if (mounted) setState(() {});
  }

  List<Conversation> get _conversations {
    final all = StorageService.instance.loadConversations()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_query.isEmpty) return all;
    final needle = _query.toLowerCase();
    return all
        .where((c) =>
            c.title.toLowerCase().contains(needle) ||
            c.messages.any((m) => m.content.toLowerCase().contains(needle)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = _conversations;
    final expanded = ExodusLayout.isExpanded(context);

    final welcome = <Widget>[
      _header(),
      const SizedBox(height: 22),
      Text('Peace be with you.',
          style: TextStyle(
            fontFamily: ExodusTheme.serif,
            color: ExodusTheme.parchment,
            fontSize: expanded ? 38 : 32,
            fontWeight: FontWeight.w600,
            height: 1.15,
            letterSpacing: -0.4,
          )),
      const SizedBox(height: 8),
      const Text('Real conversations. A higher perspective.',
          style: TextStyle(
            color: ExodusTheme.ironMist,
            fontSize: 15,
            letterSpacing: 0.2,
          )),
      const SizedBox(height: 22),
      // Above the verse on purpose: on a hard morning, knowing someone
      // else is in it lands before scripture does.
      const CommunityStrip(),
      const SizedBox(height: 20),
      _verseCard(),
    ];

    final threads = <Widget>[
      _searchField(),
      const SizedBox(height: 22),
      _conversationsHeader(conversations.length),
      const SizedBox(height: 12),
      if (conversations.isEmpty)
        _emptyConversations()
      else
        Arrival(
          // Settles once on open; scrolling the list never replays it.
          enabled: _query.isEmpty,
          step: const Duration(milliseconds: 70),
          children: [
            // Unfolded there is room for the whole recent list, not just
            // the first screenful.
            for (final c in conversations.take(expanded ? 14 : 8))
              _conversationTile(c),
          ],
        ),
    ];

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      body: PageBackdrop(
        child: SafeArea(
          // Measured against the room Home actually has, not the screen:
          // beside the rail on the upright inner screen that is ~577pt, and
          // two columns there would each be narrower than the folded phone.
          child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth >= _twoColumnMinWidth) {
              return _twoColumns(welcome, threads);
            }
            // One column, with the margins the larger screen can afford.
            final side = expanded ? 32.0 : 20.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 8, side, 24),
              children: [
                ...welcome,
                const SizedBox(height: 18),
                ...threads,
              ],
            );
          }),
        ),
      ),
    );
  }

  static const double _twoColumnMinWidth = 640;

  /// Unfolded: what is said to you on the left, what you have said on the
  /// right. Each column scrolls on its own, and the gap between them sits
  /// in the middle so neither column's content falls into the fold.
  Widget _twoColumns(List<Widget> left, List<Widget> right) {
    const gutter = ExodusLayout.centreGutter;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 11,
          // A vertical list only clips along its own axis, and the community
          // strip scrolls sideways: without this its cards slide under the
          // conversations column.
          child: ClipRect(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, gutter / 2, 28),
              children: left,
            ),
          ),
        ),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ExodusTheme.steel.withValues(alpha: 0),
                ExodusTheme.steel,
                ExodusTheme.steel.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 10,
          child: ListView(
            // Line the search up with the greeting's baseline region rather
            // than with the logo, so the two columns read as one page.
            padding: const EdgeInsets.fromLTRB(gutter / 2, 70, 24, 28),
            children: right,
          ),
        ),
      ],
    );
  }

  Widget _header() {
    // Unfolded, the rail already carries the shield a few points to the
    // left; a second one beside it reads as a stutter.
    final showShield = !ExodusLayout.isExpanded(context);
    return Row(
      children: [
        if (showShield) Semantics(
          button: true,
          label: 'Menu',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onOpenMenu,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: ExodusShield(size: 30, glow: false),
            ),
          ),
        ),
        if (showShield) const SizedBox(width: 12),
        const Text('EXODUS',
            style: TextStyle(
              color: ExodusTheme.brass,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              letterSpacing: 5,
            )),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Profile',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onSeeAll,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: ExodusTheme.brass.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.person_outline_rounded,
                  size: 20, color: ExodusTheme.ironMist),
            ),
          ),
        ),
      ],
    );
  }

  /// The day's verse, over the same photography as the scripture cards in
  /// chat.
  ///
  /// This carried a placeholder gradient for as long as there was no artwork.
  /// There is now, and it is seeded on the reference — so today's verse looks
  /// the same all day on both partners' phones, and tomorrow's looks like
  /// something else.
  Widget _verseCard() {
    final reference = DailyVerse.referenceFor();
    final text = _bibleReady ? DailyVerse.textFor() : '';

    return Semantics(
      button: true,
      label: 'Open $reference in the Bible',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Analytics.instance.track(Events.verseOpen);
          openScriptureRef(context, reference);
        },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: ExodusTheme.brass.withValues(alpha: 0.28)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ScriptureBackground(seed: reference),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TODAY’S VERSE',
                        style: TextStyle(
                          color: ExodusTheme.brassGlow,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                        )),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 250),
                      child: Text(
                        text.isEmpty ? '…' : '“$text”',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: ExodusTheme.serif,
                          color: ExodusTheme.parchment,
                          fontSize: 17,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(reference,
                            style: const TextStyle(
                              color: ExodusTheme.brass,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            )),
                        const Spacer(),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ExodusTheme.obsidian.withValues(alpha: 0.45),
                            border: Border.all(
                                color:
                                    ExodusTheme.brass.withValues(alpha: 0.55)),
                          ),
                          child: const Icon(Icons.chevron_right_rounded,
                              size: 22, color: ExodusTheme.brass),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight.withValues(alpha: 0.7),
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 19, color: ExodusTheme.ironMist),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              style: const TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 15),
              cursorColor: ExodusTheme.brass,
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search conversations…',
                hintStyle:
                    TextStyle(color: ExodusTheme.ironMist, fontSize: 15),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                _search.clear();
                setState(() => _query = '');
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    size: 17, color: ExodusTheme.ironMist),
              ),
            ),
        ],
      ),
    );
  }

  Widget _conversationsHeader(int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Text('Conversations',
            style: TextStyle(
              fontFamily: ExodusTheme.serif,
              color: ExodusTheme.parchment,
              fontSize: 23,
              fontWeight: FontWeight.w600,
            )),
        const Spacer(),
        if (count > 0)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onSeeAll,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text('See all',
                  style: TextStyle(
                      color: ExodusTheme.brass,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _emptyConversations() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: widget.onNewConversation,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight.withValues(alpha: 0.6),
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_rounded, color: ExodusTheme.brass, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _query.isEmpty
                    ? 'Start your first conversation with EXODUS.'
                    : 'Nothing matches “$_query”.',
                style: const TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 14, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationTile(Conversation conv) {
    final preview = conv.messages.isEmpty
        ? 'No messages yet'
        : conv.messages.last.content.replaceAll(RegExp(r'\s+'), ' ').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => widget.onOpenConversation(conv.id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight.withValues(alpha: 0.72),
            border: Border.all(color: ExodusTheme.steel),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ExodusTheme.slate,
                  border: Border.all(
                      color: ExodusTheme.brass.withValues(alpha: 0.30)),
                ),
                child: const ExodusShield(size: 20, glow: false),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ExodusTheme.porcelain,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                        const SizedBox(width: 8),
                        Text(_when(conv.updatedAt),
                            style: const TextStyle(
                                color: ExodusTheme.ironMist, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: ExodusTheme.ironMist,
                            fontSize: 13,
                            height: 1.4)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 12),
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: ExodusTheme.ironMist),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Clock time today, weekday this week, date beyond — the shape the design
  /// shows ("12:51 PM", "Yesterday", "Mon").
  static String _when(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final days = today.difference(that).inDays;

    if (days == 0) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m ${dt.hour < 12 ? 'AM' : 'PM'}';
    }
    if (days == 1) return 'Yesterday';
    if (days < 7) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }
}
