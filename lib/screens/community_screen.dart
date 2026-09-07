import 'package:flutter/material.dart';

import '../config/community_prompt.dart';
import '../models/community_post.dart';
import '../services/community_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/arrival.dart';
import '../widgets/community_bits.dart';
import '../widgets/page_backdrop.dart';
import 'community_thread_screen.dart';

/// The whole feed, filterable by what it is about.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final CommunityService _service = CommunityService.instance;
  String? _tag;

  @override
  void initState() {
    super.initState();
    _service.load();
    _service.addListener(_onChanged);
    _service.ensureFresh();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<String> get _tags {
    final seen = <String>{for (final p in _service.posts) p.tag};
    final list = seen.toList()..sort();
    return list;
  }

  List<CommunityPost> get _visible {
    final all = _service.posts;
    if (_tag == null) return all;
    return all.where((p) => p.tag == _tag).toList();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _visible;

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      body: PageBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              const Text(CommunityPrompt.sectionTitle,
                  style: TextStyle(
                    fontFamily: ExodusTheme.serif,
                    color: ExodusTheme.parchment,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    letterSpacing: -0.3,
                  )),
              const SizedBox(height: 18),
              if (_tags.length > 1) _filters(),
              if (_tags.length > 1) const SizedBox(height: 16),
              if (_service.isWorking && posts.isEmpty)
                _working()
              else if (posts.isEmpty)
                _empty()
              else
                Arrival(
                  step: const Duration(milliseconds: 60),
                  children: [for (final p in posts) _postCard(p)],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All', _tag == null, () => setState(() => _tag = null)),
          for (final t in _tags)
            _filterChip(t, _tag == t, () => setState(() => _tag = t)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? ExodusTheme.brass.withValues(alpha: 0.16)
                : ExodusTheme.midnight.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? ExodusTheme.brass.withValues(alpha: 0.5)
                  : ExodusTheme.steel,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                color: active ? ExodusTheme.brass : ExodusTheme.ironMist,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              )),
        ),
      ),
    );
  }

  Widget _postCard(CommunityPost post) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(post),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ExodusTheme.steel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CommunityBits.avatar(post.author, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.author,
                            style: const TextStyle(
                              color: ExodusTheme.porcelain,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            )),
                        Text(
                          [
                            if (post.authorContext.isNotEmpty)
                              post.authorContext,
                            CommunityBits.ago(post.createdAt),
                          ].join(' · '),
                          style: const TextStyle(
                              color: ExodusTheme.ironMist, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  CommunityBits.tagChip(post.tag),
                ],
              ),
              const SizedBox(height: 12),
              Text(post.title,
                  style: const TextStyle(
                    fontFamily: ExodusTheme.serif,
                    color: ExodusTheme.parchment,
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 8),
              Text(
                post.body.replaceAll('\n', ' ').trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.forum_outlined,
                      size: 15, color: ExodusTheme.ironMist),
                  const SizedBox(width: 6),
                  Text(
                    post.replyCount == 1
                        ? '1 reply'
                        : '${post.replyCount} replies',
                    style: const TextStyle(
                        color: ExodusTheme.ironMist, fontSize: 12.5),
                  ),
                  const Spacer(),
                  if (!post.read)
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: ExodusTheme.brass,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _working() {
    return const Padding(
      padding: EdgeInsets.only(top: 40),
      child: Column(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: ExodusTheme.brass),
          ),
          SizedBox(height: 16),
          Text('Finding people who have been here…',
              style: TextStyle(color: ExodusTheme.ironMist, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          const Icon(Icons.forum_outlined, size: 34, color: ExodusTheme.steel),
          const SizedBox(height: 14),
          Text(
            _service.lastError ?? 'Nothing here yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ExodusTheme.ironMist, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _service.ensureFresh(),
            child: const Text('Try again',
                style: TextStyle(color: ExodusTheme.brass)),
          ),
        ],
      ),
    );
  }

  void _open(CommunityPost post) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CommunityThreadScreen(post: post),
    ));
  }
}
