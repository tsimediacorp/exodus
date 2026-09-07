import 'package:flutter/material.dart';

import '../config/community_prompt.dart';
import '../models/community_post.dart';
import '../screens/community_screen.dart';
import '../screens/community_thread_screen.dart';
import '../services/community_service.dart';
import '../theme/exodus_theme.dart';
import 'community_bits.dart';

/// The community, on the home screen, above the verse.
///
/// A horizontal run of three or four threads rather than a list: this sits
/// above the day's verse, and a section that pushes the verse off the screen
/// has taken over the home screen instead of adding to it.
///
/// Renders nothing at all until there are posts. An empty panel promising
/// company is worse than no panel.
class CommunityStrip extends StatefulWidget {
  const CommunityStrip({super.key});

  @override
  State<CommunityStrip> createState() => _CommunityStripState();
}

class _CommunityStripState extends State<CommunityStrip> {
  final CommunityService _service = CommunityService.instance;

  @override
  void initState() {
    super.initState();
    _service.load();
    _service.addListener(_onChanged);
    // Seeds on first run and tops up once a day; a no-op otherwise, so this
    // is safe on every visit to the home screen.
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

  @override
  Widget build(BuildContext context) {
    final posts = _service.posts;

    // Nothing yet, and nothing on the way: stay out of the way entirely.
    if (posts.isEmpty && !_service.isWorking) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 4),
        const Text(
          CommunityPrompt.compositeNotice,
          style: TextStyle(
              color: ExodusTheme.ironMist, fontSize: 11.5, height: 1.45),
        ),
        const SizedBox(height: 12),
        if (posts.isEmpty)
          _placeholder()
        else
          SizedBox(
            height: 158,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: posts.length > 6 ? 6 : posts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _card(posts[i]),
            ),
          ),
      ],
    );
  }

  Widget _header() {
    final unread = _service.unreadCount;
    return Row(
      children: [
        const Flexible(
          child: Text(
            CommunityPrompt.sectionTitle,
            style: TextStyle(
              fontFamily: ExodusTheme.serif,
              color: ExodusTheme.parchment,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (unread > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: ExodusTheme.brass.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('$unread new',
                style: const TextStyle(
                  color: ExodusTheme.brass,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CommunityScreen(),
          )),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            // Not "See all": the conversations section below already has one,
            // and two identical links on one screen are ambiguous to read and
            // worse to hear announced.
            child: Text('All stories',
                style: TextStyle(
                    color: ExodusTheme.brass,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  /// Shown only while the very first batch is being written.
  Widget _placeholder() {
    return Container(
      height: 158,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ExodusTheme.midnight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ExodusTheme.steel),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: ExodusTheme.brass),
          ),
          SizedBox(width: 12),
          Text('Finding people who have been here…',
              style: TextStyle(color: ExodusTheme.ironMist, fontSize: 13.5)),
        ],
      ),
    );
  }

  Widget _card(CommunityPost post) {
    return SizedBox(
      width: 250,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CommunityThreadScreen(post: post),
        )),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: post.read
                  ? ExodusTheme.steel
                  : ExodusTheme.brass.withValues(alpha: 0.30),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CommunityBits.tagChip(post.tag),
                  const Spacer(),
                  if (!post.read)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: ExodusTheme.brass,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: ExodusTheme.parchment,
                  fontSize: 15.5,
                  height: 1.32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  CommunityBits.avatar(post.author, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      post.author,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: ExodusTheme.ironMist, fontSize: 12.5),
                    ),
                  ),
                  const Icon(Icons.forum_outlined,
                      size: 13, color: ExodusTheme.ironMist),
                  const SizedBox(width: 4),
                  Text('${post.replyCount}',
                      style: const TextStyle(
                          color: ExodusTheme.ironMist, fontSize: 12.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
