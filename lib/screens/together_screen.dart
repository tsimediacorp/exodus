import 'package:amplify_flutter/amplify_flutter.dart' show AuthException;
import 'package:flutter/material.dart';
import '../config/quiz_bank.dart';
import '../services/amplify_service.dart';
import '../services/together_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import 'prayer_wall_screen.dart';

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
          if (_phase == _Phase.ready)
            IconButton(
              icon: const Icon(Icons.volunteer_activism_outlined,
                  color: ExodusTheme.ironMist),
              tooltip: 'Prayer wall',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrayerWallScreen(
                    coupleId: _couple!.id,
                    userId: _userId!,
                    members: _svc.memberIds(_couple!),
                  ),
                ),
              ),
            ),
          if (_phase == _Phase.ready || _phase == _Phase.needsPairing)
            IconButton(
              icon: const Icon(Icons.logout, color: ExodusTheme.ironMist),
              tooltip: 'Sign out',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: ExodusTheme.midnight,
                    title: const Text('Sign out?'),
                    content: const Text(
                        'You\'ll need to sign back in to reach your couples '
                        'space, prayer wall, and daily question.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign out',
                              style: TextStyle(color: ExodusTheme.crimson))),
                    ],
                  ),
                );
                if (confirmed != true) return;
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

/// The password rules Cognito actually enforces on this pool, mirrored from
/// `amplify_outputs.dart` (`password_policy`).
///
/// They are duplicated here deliberately. The server is the authority, but a
/// user should never have to discover a rule by failing — before this, the
/// only way to learn a symbol was required was to submit and be handed a raw
/// InvalidPasswordException.
class _PasswordRule {
  final String label;
  final bool Function(String) met;
  const _PasswordRule(this.label, this.met);
}

final List<_PasswordRule> _passwordRules = [
  _PasswordRule('At least 8 characters', (p) => p.length >= 8),
  _PasswordRule('An uppercase letter', (p) => RegExp(r'[A-Z]').hasMatch(p)),
  _PasswordRule('A lowercase letter', (p) => RegExp(r'[a-z]').hasMatch(p)),
  _PasswordRule('A number', (p) => RegExp(r'[0-9]').hasMatch(p)),
  _PasswordRule(
      'A symbol (like ! ? \$ #)', (p) => RegExp(r'[^A-Za-z0-9]').hasMatch(p)),
];

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
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The requirements checklist ticks as you type, so it has to rebuild.
    _password.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _password.removeListener(_onPasswordChanged);
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    if (_isSignUp) setState(() {});
  }

  List<_PasswordRule> get _unmet =>
      [for (final r in _passwordRules) if (!r.met(_password.text)) r];

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Exception catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turn an Amplify/Cognito failure into something a person can act on.
  ///
  /// `AuthException.toString()` renders a JSON blob with the message nested
  /// inside an `underlyingException` string — which is what used to land on
  /// screen, in red, under the sign-up button.
  String _friendly(Exception e) {
    final type = e.runtimeType.toString();
    final raw = e is AuthException ? e.message : e.toString();

    if (type.contains('InvalidPassword')) {
      return 'That password does not meet the requirements below.';
    }
    if (type.contains('UsernameExists')) {
      return 'An account already exists for that email. Try signing in.';
    }
    if (type.contains('UserNotFound')) {
      return 'No account found for that email.';
    }
    if (type.contains('NotAuthorized')) {
      return 'That email and password do not match.';
    }
    if (type.contains('UserNotConfirmed')) {
      return 'This account still needs confirming. Check your email for the '
          'code.';
    }
    if (type.contains('CodeMismatch')) {
      return 'That confirmation code is not right. Check the email and try '
          'again.';
    }
    if (type.contains('ExpiredCode')) {
      return 'That confirmation code has expired. Request a new one.';
    }
    if (type.contains('LimitExceeded') || type.contains('TooManyRequests')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (type.contains('Network') ||
        raw.contains('SocketException') ||
        raw.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    if (type.contains('InvalidParameter')) {
      // Almost always a malformed email at this point in the flow.
      return 'Check the email address and password and try again.';
    }
    // Anything unmapped: show Cognito's own sentence, never its JSON.
    return raw.isEmpty ? 'Something went wrong. Try again.' : raw;
  }

  /// Catch what we can before the network does, so the common mistake costs
  /// nothing and names itself.
  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'That email address does not look right.';
    }
    if (_password.text.isEmpty) return 'Enter a password.';
    if (_isSignUp && _unmet.isNotEmpty) {
      return 'Your password is missing: ${_unmet.map((r) => r.label.toLowerCase()).join(', ')}.';
    }
    return null;
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
            _field(_email, 'Email', keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _field(_password, 'Password', obscure: !_showPassword, toggle: true),
            // Shown while composing a password, not after the fact as an
            // error. Nothing here is a surprise by the time you press submit.
            if (_isSignUp) _requirements(),
            const SizedBox(height: 16),
            _primary(_isSignUp ? 'Create account' : 'Sign in', () {
              final problem = _validate();
              if (problem != null) {
                setState(() => _error = problem);
                return;
              }
              _run(() async {
                if (_isSignUp) {
                  await widget.svc.signUp(_email.text.trim(), _password.text);
                  setState(() => _awaitingCode = true);
                } else {
                  await widget.svc.signIn(_email.text.trim(), _password.text);
                  widget.onAuthed();
                }
              });
            }),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _isSignUp = !_isSignUp;
                        _error = null;
                      }),
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

  /// The live checklist. Each rule ticks as it is satisfied.
  Widget _requirements() {
    final empty = _password.text.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your password needs:',
              style: TextStyle(color: ExodusTheme.ironMist, fontSize: 12)),
          const SizedBox(height: 8),
          for (final rule in _passwordRules)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(
                    rule.met(_password.text)
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 14,
                    color: rule.met(_password.text)
                        ? ExodusTheme.brass
                        : ExodusTheme.steel,
                  ),
                  const SizedBox(width: 8),
                  Text(rule.label,
                      style: TextStyle(
                        color: rule.met(_password.text)
                            ? ExodusTheme.porcelain
                            : ExodusTheme.ironMist,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
          if (empty) const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
          {bool obscure = false,
          bool toggle = false,
          TextInputType? keyboard}) =>
      TextField(
        controller: c,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,
        style: const TextStyle(color: ExodusTheme.porcelain),
        decoration: InputDecoration(
          hintText: hint,
          // Composing a password with five rules to satisfy is miserable
          // blind.
          suffixIcon: toggle
              ? IconButton(
                  icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: ExodusTheme.ironMist),
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                )
              : null,
        ),
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
  int _tab = 0; // 0 = shared space, 1 = private confidant, 2 = daily
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
      _all.where((m) => m.visibility == (_tab == 0 ? 'shared' : 'private')).toList();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() { _busy = true; _input.clear(); });
    try {
      await widget.svc.ask(coupleId: widget.couple.id, text: text, shared: _tab == 0);
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
    if (_tab == 2) {
      return Column(
        children: [
          _modeToggle(),
          Expanded(child: _DailyView(svc: widget.svc, couple: widget.couple, userId: widget.userId)),
        ],
      );
    }
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
          _seg('Shared', 0),
          const SizedBox(width: 8),
          _seg('Private', 1),
          const SizedBox(width: 8),
          _seg('Daily', 2),
        ],
      ),
    );
  }

  Widget _seg(String label, int tabVal) {
    final on = _tab == tabVal;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = tabVal),
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
                hintText: _tab == 0 ? 'Share with both of you…' : 'Private to you & EXODUS…',
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

// ======================= Daily quiz + alignment =======================

class _DailyView extends StatefulWidget {
  final TogetherService svc;
  final Couple couple;
  final String userId;
  const _DailyView({required this.svc, required this.couple, required this.userId});

  @override
  State<_DailyView> createState() => _DailyViewState();
}

class _DailyViewState extends State<_DailyView> {
  final _answer = TextEditingController();
  late final DateTime _day;
  late final String _roundId;
  late final String _question;

  Map<String, String> _answers = {};
  Map<String, dynamic>? _alignment;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now();
    _roundId = TogetherService.roundId(widget.couple.id, _day);
    _question = QuizBank.forDay(_day);
    _load();
  }

  Future<void> _load() async {
    try {
      final ans = await widget.svc.answers(_roundId);
      final align = await widget.svc.alignment(_roundId);
      if (mounted) setState(() { _answers = ans; _alignment = align; _loading = false; });
    } on Exception {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _iAnswered => _answers.containsKey(widget.userId);
  bool get _bothAnswered => _answers.length >= 2;

  Future<void> _submit() async {
    final text = _answer.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.svc.submitAnswer(
        roundId: _roundId,
        answer: text,
        members: widget.svc.memberIds(widget.couple),
      );
      _answer.clear();
      await _load();
    } on Exception catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reveal() async {
    setState(() => _busy = true);
    try {
      final r = await widget.svc.scoreDay(
        coupleId: widget.couple.id, roundId: _roundId, day: _day, prompt: _question);
      if (mounted) setState(() => _alignment = r);
    } on Exception catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: ExodusTheme.brass));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("TODAY'S QUESTION",
              style: TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_question,
              style: const TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 20, fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 20),
          if (!_iAnswered) ...[
            TextField(
              controller: _answer,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(color: ExodusTheme.porcelain),
              decoration: const InputDecoration(hintText: 'Your answer…'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                  backgroundColor: ExodusTheme.covenantBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Submit my answer'),
            ),
          ] else ...[
            _card('You answered', _answers[widget.userId] ?? ''),
            const SizedBox(height: 12),
            if (_bothAnswered)
              _card('Your spouse answered',
                  _answers.entries.firstWhere((e) => e.key != widget.userId).value)
            else
              const Text('Waiting for your spouse to answer…',
                  style: TextStyle(color: ExodusTheme.ironMist, fontSize: 14)),
          ],
          const SizedBox(height: 20),
          if (_alignment != null)
            _alignmentCard(_alignment!)
          else if (_bothAnswered)
            FilledButton.icon(
              onPressed: _busy ? null : _reveal,
              style: FilledButton.styleFrom(
                  backgroundColor: ExodusTheme.brass,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.favorite, color: ExodusTheme.obsidian, size: 18),
              label: const Text('See how aligned we are',
                  style: TextStyle(color: ExodusTheme.obsidian, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _card(String label, String body) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight,
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(color: ExodusTheme.porcelain, fontSize: 15, height: 1.4)),
          ],
        ),
      );

  Widget _alignmentCard(Map<String, dynamic> a) {
    final score = (a['score'] as num?)?.toInt() ?? 0;
    final recap = (a['recap'] as String?) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [ExodusTheme.covenantBlue, Color(0xFF2D5BC8)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text('ALIGNMENT TODAY',
              style: TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('$score%',
              style: const TextStyle(
                  color: ExodusTheme.porcelain, fontSize: 48, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(recap,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ExodusTheme.porcelain, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}
