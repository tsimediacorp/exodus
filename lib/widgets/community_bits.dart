import 'package:flutter/material.dart';

import '../theme/exodus_theme.dart';

/// Small pieces shared by the home strip, the feed and a thread, so a post
/// looks like the same post wherever it appears.
class CommunityBits {
  CommunityBits._();

  /// "3h ago". Deliberately coarse: a feed that says "2 minutes ago" invites
  /// the reader to work out that nobody was actually typing two minutes ago.
  static String ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 60) return 'just now';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    final weeks = d.inDays ~/ 7;
    if (weeks < 5) return '${weeks}w ago';
    return '${d.inDays ~/ 30}mo ago';
  }

  /// A name's initials, for the avatar.
  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Stable per name, so one person keeps one colour across the whole feed.
  static Color tint(String name) {
    const palette = [
      Color(0xFF3B6FE3), Color(0xFF7A5FD3), Color(0xFF2F8F7A),
      Color(0xFFB07A3C), Color(0xFF9C4F6B), Color(0xFF4A7BA8),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  static Widget avatar(String name, {double size = 38}) {
    final colour = tint(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.22),
        border: Border.all(color: colour.withValues(alpha: 0.55)),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: Color.lerp(colour, Colors.white, 0.55),
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Widget tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ExodusTheme.brass.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ExodusTheme.brass.withValues(alpha: 0.32)),
      ),
      child: Text(
        tag.toUpperCase(),
        style: const TextStyle(
          color: ExodusTheme.brass,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}
