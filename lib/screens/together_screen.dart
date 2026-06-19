import 'package:flutter/material.dart';
import '../services/amplify_service.dart';
import '../services/together_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';

enum _Phase { loading, unavailable, needsAuth, needsPairing, ready }

/// The "Together" couples space: account → partner pairing → a shared couples
/// chat plus a private confidant thread, all synced via the Amplify backend.
class TogetherScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const TogetherScreen({super.key, this.onOpenMenu});

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  final TogetherService _svc = TogetherService();
  _Phase _phase = _Phase.loading;
  String? _userId;
  Couple? _couple;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _phase = _Phase.loading);
    if (!AmplifyService.ready) {
      setState(() => _phase = _Phase.unavailable);
      return;
    }
    final signedIn = await _svc.isSignedIn();
    if (!signedIn) {
      setState(() => _phase = _Phase.needsAuth);
      return;
    }
    _userId = await _svc.currentUserId();
    final couple = _userId == null ? null : await _svc.myCouple(_userId!);
    setState(() {
      _couple = couple;
      _phase = couple != null && couple.isPaired ? _Phase.ready : _Phase.needsPairing;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Together'),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
          tooltip: 'Menu',
          onPressed: widget.onOpenMenu,
        ),
        actions: [
          if (_phase == _Phase.ready || _phase == _Phase.needsPairing)
            IconButton(
              icon: const Icon(Icons.logout, color: ExodusTheme.ironMist),
              tooltip: 'Sign out',
              onPressed: () async {
                await _svc.signOut();
                _bootstrap();
              },
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator(color: ExodusTheme.brass));
      case _Phase.unavailable:
        return _centeredMessage(
            'Couples Sync is unavailable right now.\nCheck your connection and reopen.');
      case _Phase.needsAuth:
        return _AuthView(svc: _svc, onAuthed: _bootstrap);
      case _Phase.needsPairing:
        return _PairingView(svc: _svc, userId: _userId!, onPaired: _bootstrap);
      case _Phase.ready:
        return _CoupleChatView(svc: _svc, couple: _couple!, userId: _userId!);
    }
  }

  Widget _centeredMessage(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ExodusTheme.ironMist, fontSize: 14, height: 1.5)),
        ),
      );
}

// ======================= Auth =======================

class _AuthView extends StatefulWidget {
  final TogetherService svc;
  final VoidCallback onAuthed;
  const _AuthView({required this.svc, required this.onAuthed});

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _isSignUp = false;
  bool _awaitingCode = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Exception catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: ExodusShield(size: 64)),
          const SizedBox(height: 20),
          Text(_isSignUp ? 'Create your account' : 'Sign in',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Your account lets you pair with your spouse and sync privately.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ExodusTheme.ironMist, fontSize: 13, height: 1.4)),
          const SizedBox(height: 24),
          if (_awaitingCode) ...[
            _field(_code, 'Confirmation code (emailed to you)'),
            const SizedBox(height: 12),
            _primary('Confirm & sign in', () => _run(() async {
                  await widget.svc.confirm(_email.text.trim(), _code.text.trim());
                  await widget.svc.signIn(_email.text.trim(), _password.text);
                  widget.onAuthed();
                })),
          ] else ...[
            _field(_email, 'Email'),
            const SizedBox(height: 12),
            _field(_password, 'Password', obscure: true),
            const SizedBox(height: 16),
            _primary(_isSignUp ? 'Create account' : 'Sign in', () => _run(() async {
                  if (_isSignUp) {
                    await widget.svc.signUp(_email.text.trim(), _password.text);
                    setState(() => _awaitingCode = true);
                  } else {
                    await widget.svc.signIn(_email.text.trim(), _password.text);
                    widget.onAuthed();
                  }
                })),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _isSignUp = !_isSignUp),
              child: Text(
                  _isSignUp ? 'Have an account? Sign in' : "New here? Create an account",
                  style: const TextStyle(color: ExodusTheme.covenantGlow)),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ExodusTheme.crimson, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {bool obscure = false}) => TextField(
        controller: c,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(color: ExodusTheme.porcelain),
        decoration: InputDecoration(hintText: hint),
      );

  Widget _primary(String label, VoidCallback onTap) => FilledButton(
        onPressed: _busy ? null : onTap,
        style: FilledButton.styleFrom(
            backgroundColor: ExodusTheme.covenantBlue,
            padding: const EdgeInsets.symmetric(vertical: 15)),
        child: _busy
            ? const SizedBox(
                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label, style: const TextStyle(color: ExodusTheme.porcelain, fontSize: 15)),
      );
}

// ======================= Pairing =======================

class _PairingView extends StatefulWidget {
  final TogetherService svc;
  final String userId;
  final VoidCallback onPaired;
  const _PairingView({required this.svc, required this.userId, required this.onPaired});

  @override
  State<_PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<_PairingView> {
  final _code = TextEditingController();
  Couple? _myCouple;
  bool _busy = false;
  String? _error;

  Future<void> _createInvite() async {
    setState(() { _busy = true; _error = null; });
    try {
      final c = await widget.svc.createCouple(widget.userId);
      setState(() => _myCouple = c);
    } on Exception catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redeem() async {
    setState(() { _busy = true; _error = null; });
    try {
      final id = await widget.svc.redeemInvite(_code.text);
      if (id == null) {
        setState(() => _error = 'That invite code didn\'t match. Double-check it with your spouse.');
      } else {
        widget.onPaired();
      }
    } on Exception catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: ExodusShield(size: 64)),
          const SizedBox(height: 20),
          const Text('Pair with your spouse',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          // Invite code
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: ExodusTheme.midnight,
              border: Border.all(color: ExodusTheme.steel),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Text('Invite your spouse',
                    style: TextStyle(color: ExodusTheme.porcelain, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                if (_myCouple?.inviteCode != null)
                  SelectableText(_myCouple!.inviteCode!,
                      style: const TextStyle(
                          color: ExodusTheme.brass,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8))
                else
                  FilledButton(
                    onPressed: _busy ? null : _createInvite,
                    style: FilledButton.styleFrom(backgroundColor: ExodusTheme.covenantBlue),
                    child: const Text('Generate invite code'),
                  ),
                if (_myCouple?.inviteCode != null) ...[
                  const SizedBox(height: 6),
                  const Text('Share this code. They enter it below to link.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ExodusTheme.ironMist, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Center(child: Text('— or —', style: TextStyle(color: ExodusTheme.ironMist))),
          const SizedBox(height: 20),
          const Text('Enter your spouse\'s code',
              style: TextStyle(color: ExodusTheme.porcelain, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: ExodusTheme.porcelain, letterSpacing: 4),
            decoration: const InputDecoration(hintText: 'ABC123'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _redeem,
            style: FilledButton.styleFrom(
                backgroundColor: ExodusTheme.covenantBlue,
                padding: const EdgeInsets.symmetric(vertical: 15)),
            child: const Text('Link with my spouse'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ExodusTheme.crimson, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ======================= Couple chat =======================

class _CoupleChatView extends StatefulWidget {
  final TogetherService svc;
  final Couple couple;
  final String userId;
  const _CoupleChatView({required this.svc, required this.couple, required this.userId});

  @override
  State<_CoupleChatView> createState() => _CoupleChatViewState();
}

class _CoupleChatViewState extends State<_CoupleChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<TogetherMessage> _all = [];
  bool _shared = true; // shared couples space vs. private confidant
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final msgs = await widget.svc.listMessages(widget.couple.id);
      if (mounted) setState(() { _all = msgs; _loading = false; });
      _scrollEnd();
    } on Exception {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TogetherMessage> get _visible =>
      _all.where((m) => m.visibility == (_shared ? 'shared' : 'private')).toList();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() { _busy = true; _input.clear(); });
    try {
      await widget.svc.ask(coupleId: widget.couple.id, text: text, shared: _shared);
      await _refresh();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _modeToggle(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: ExodusTheme.brass))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _visible.length,
                    itemBuilder: (_, i) => _bubble(_visible[i]),
                  ),
                ),
        ),
        _inputBar(),
      ],
    );
  }

  Widget _modeToggle() {
    return Container(
      color: ExodusTheme.obsidian,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          _seg('Shared space', true),
          const SizedBox(width: 8),
          _seg('Private', false),
        ],
      ),
    );
  }

  Widget _seg(String label, bool sharedVal) {
    final on = _shared == sharedVal;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _shared = sharedVal),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? ExodusTheme.covenantBlue.withValues(alpha: 0.18) : ExodusTheme.midnight,
            border: Border.all(color: on ? ExodusTheme.covenantGlow : ExodusTheme.steel),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? ExodusTheme.porcelain : ExodusTheme.ironMist,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ),
    );
  }

  Widget _bubble(TogetherMessage m) {
    final mine = m.authorId == widget.userId;
    final isExodus = m.isExodus;
    final align = isExodus
        ? Alignment.centerLeft
        : (mine ? Alignment.centerRight : Alignment.centerLeft);
    final color = isExodus
        ? ExodusTheme.midnight
        : (mine ? ExodusTheme.covenantBlue : ExodusTheme.slate);
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: color,
          border: isExodus ? Border.all(color: ExodusTheme.steel) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isExodus)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('EXODUS',
                    style: TextStyle(
                        color: ExodusTheme.brass, fontSize: 11, fontWeight: FontWeight.w700)),
              )
            else if (!mine)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('Your spouse',
                    style: TextStyle(color: ExodusTheme.ironMist, fontSize: 11)),
              ),
            Text(m.text,
                style: const TextStyle(color: ExodusTheme.porcelain, fontSize: 15, height: 1.45)),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: ExodusTheme.obsidian,
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(color: ExodusTheme.porcelain),
              decoration: InputDecoration(
                hintText: _shared ? 'Share with both of you…' : 'Private to you & EXODUS…',
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_upward, color: ExodusTheme.covenantGlow),
          ),
        ],
      ),
    );
  }
}
