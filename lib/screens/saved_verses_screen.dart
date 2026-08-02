import 'package:flutter/material.dart';
import '../models/saved_verse.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/verse_card.dart';

/// Passages the couple kept from devotionals and journey days, newest first.
class SavedVersesScreen extends StatefulWidget {
  const SavedVersesScreen({super.key});

  @override
  State<SavedVersesScreen> createState() => _SavedVersesScreenState();
}

class _SavedVersesScreenState extends State<SavedVersesScreen> {
  final StorageService _storage = StorageService.instance;
  List<SavedVerse> _verses = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _verses = _storage.loadSavedVerses());

  Future<void> _remove(SavedVerse verse) async {
    await _storage.removeVerse(verse.reference);
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${verse.reference}'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await _storage.saveVerse(verse);
            if (mounted) _load();
          },
        ),
      ),
    );
  }

  void _share(SavedVerse verse) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          VerseCardSheet(reference: verse.reference, text: verse.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kept verses')),
      body: SafeArea(
        child: _verses.isEmpty ? _empty() : _list(),
      ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded,
                size: 44, color: ExodusTheme.steel),
            SizedBox(height: 16),
            Text(
              'Nothing kept yet',
              style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Tap "Keep verse" on a devotional or a journey day and it will '
              'wait for you here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: _verses.length,
      itemBuilder: (_, i) {
        final v = _verses[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ExodusTheme.midnight,
              border: Border.all(color: ExodusTheme.steel),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.reference.toUpperCase(),
                    style: const TextStyle(
                        color: ExodusTheme.brass,
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SelectableText(v.text,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 15,
                        height: 1.55,
                        fontStyle: FontStyle.italic)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(v.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: ExodusTheme.ironMist, fontSize: 12)),
                    ),
                    _iconAction(
                      icon: Icons.ios_share_rounded,
                      label: 'Share ${v.reference}',
                      onTap: () => _share(v),
                    ),
                    _iconAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove ${v.reference}',
                      onTap: () => _remove(v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: ExodusTheme.ironMist),
        ),
      ),
    );
  }
}
