import 'package:flutter/material.dart';
import '../config/master_prompt.dart';
import '../services/check_in_service.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService.instance;

  late TextEditingController _maxTokensCtrl;
  late double _temperature;
  late int _maxTokens;
  String? _maxTokensError;
  late bool _checkInsEnabled = StorageService.instance.loadCheckInsEnabled();
  late String _provider;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _temperature = MasterPrompt.temperature;
    _maxTokens   = MasterPrompt.maxTokens;
    _maxTokensCtrl = TextEditingController(text: _maxTokens.toString());
    _provider    = MasterPrompt.activeProvider;
  }

  @override
  void dispose() {
    _maxTokensCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _storage.setTemperature(
      _temperature == MasterPrompt.defaultTemperature ? null : _temperature,
    );
    await _storage.setMaxTokens(
      _maxTokens == MasterPrompt.defaultMaxTokens ? null : _maxTokens,
    );
    await _storage.setActiveProvider(
      _provider == MasterPrompt.defaultActiveProvider ? null : _provider,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Settings saved'),
      duration: Duration(seconds: 2),
    ));
    Navigator.of(context).pop();
  }

  Future<void> _resetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Reset model settings?'),
        content: const Text(
          'Restores provider, temperature, and max tokens to the defaults. '
          'Your conversation is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset',
                style: TextStyle(color: ExodusTheme.crimson)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _storage.resetAllOverrides();
    if (!mounted) return;
    setState(() {
      _temperature     = MasterPrompt.defaultTemperature;
      _maxTokens       = MasterPrompt.defaultMaxTokens;
      _maxTokensCtrl.text = _maxTokens.toString();
      _provider        = MasterPrompt.defaultActiveProvider;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore, color: ExodusTheme.ironMist),
            tooltip: 'Reset to defaults',
            onPressed: _resetAll,
          ),
          IconButton(
            icon: const Icon(Icons.check, color: ExodusTheme.covenantGlow),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _sectionHeader('MODEL'),
            _providerDropdown(),
            const SizedBox(height: 16),
            _temperatureSlider(),
            const SizedBox(height: 16),
            _maxTokensField(),
            const SizedBox(height: 28),
            _sectionHeader('CHECK-INS'),
            _checkInToggle(),
            const SizedBox(height: 8),
            _forceScanTile(),
          ],
        ),
      ),
    );
  }

  /// EXODUS reads stored memory to decide what to follow up on, so this has to
  /// be refusable — and saves immediately rather than waiting for Save, since
  /// turning it off is the kind of thing someone wants to take effect now.
  Widget _checkInToggle() {
    return SwitchListTile(
      value: _checkInsEnabled,
      onChanged: (v) async {
        setState(() => _checkInsEnabled = v);
        await StorageService.instance.saveCheckInsEnabled(v);
      },
      contentPadding: EdgeInsets.zero,
      activeThumbColor: ExodusTheme.covenantGlow,
      title: const Text('Let EXODUS follow up',
          style: TextStyle(color: ExodusTheme.porcelain, fontSize: 15)),
      subtitle: const Text(
        'Looks back over what you have shared and checks in on things left '
        'unresolved. At most one at a time, never sooner than a few days apart.',
        style: TextStyle(color: ExodusTheme.ironMist, fontSize: 12, height: 1.4),
      ),
    );
  }

  /// Check-ins are paced in days, which makes them impossible to look at on a
  /// fresh install. This runs the scan now and pulls one card forward so the
  /// thing can actually be reviewed before release.
  Widget _forceScanTile() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !_scanning,
      onTap: _scanning ? null : _forceScan,
      title: const Text('Check for a follow-up now',
          style: TextStyle(color: ExodusTheme.porcelain, fontSize: 15)),
      subtitle: const Text(
        'Skips the usual few-days wait and raises one check-in immediately, '
        'so you can see how it reads. For testing.',
        style: TextStyle(color: ExodusTheme.ironMist, fontSize: 12, height: 1.4),
      ),
      trailing: _scanning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: ExodusTheme.brass),
            )
          : const Icon(Icons.bolt_outlined, color: ExodusTheme.brass),
    );
  }

  Future<void> _forceScan() async {
    setState(() => _scanning = true);
    final result = await CheckInService.instance.forceScanNow();
    if (!mounted) return;
    setState(() => _scanning = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message),
      duration: const Duration(seconds: 4),
    ));
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        label,
        style: const TextStyle(
          color: ExodusTheme.brass,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
    );
  }

  Widget _providerDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: ExodusTheme.slate,
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButton<String>(
        value: _provider,
        isExpanded: true,
        dropdownColor: ExodusTheme.midnight,
        underline: const SizedBox(),
        style: const TextStyle(color: ExodusTheme.porcelain, fontSize: 15),
        items: MasterPrompt.availableProviders
            .map((p) => DropdownMenuItem(
                  value: p,
                  child: Text('${_providerLabel(p)}  ·  ${MasterPrompt.models[p]}'),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _provider = v);
        },
      ),
    );
  }

  String _providerLabel(String p) => switch (p) {
        'openrouter' => 'OpenRouter',
        'glm'        => 'GLM (Zhipu)',
        'venice'     => 'Venice',
        _ => p,
      };

  Widget _temperatureSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Temperature',
                style: TextStyle(color: ExodusTheme.porcelain, fontSize: 14)),
            Text(_temperature.toStringAsFixed(2),
                style: const TextStyle(color: ExodusTheme.brass, fontSize: 14)),
          ],
        ),
        Slider(
          value: _temperature,
          min: 0.0,
          max: 1.5,
          divisions: 30,
          activeColor: ExodusTheme.covenantBlue,
          inactiveColor: ExodusTheme.steel,
          onChanged: (v) => setState(() => _temperature = v),
        ),
      ],
    );
  }

  Widget _maxTokensField() {
    return TextField(
      controller: _maxTokensCtrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: ExodusTheme.porcelain),
      decoration: InputDecoration(
        labelText: 'Max tokens',
        labelStyle: const TextStyle(color: ExodusTheme.ironMist),
        // Invalid input used to be silently ignored — the field kept whatever
        // it showed and quietly saved the old value.
        errorText: _maxTokensError,
      ),
      onChanged: (v) {
        final parsed = int.tryParse(v.trim());
        setState(() {
          if (v.trim().isEmpty) {
            _maxTokensError = 'Enter a number';
          } else if (parsed == null || parsed <= 0) {
            _maxTokensError = 'Must be a positive whole number';
          } else {
            _maxTokensError = null;
            _maxTokens = parsed;
          }
        });
      },
    );
  }
}
