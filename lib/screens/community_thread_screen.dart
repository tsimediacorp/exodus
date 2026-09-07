import 'package:flutter/material.dart';

import '../config/community_prompt.dart';
import '../models/community_post.dart';
import '../services/community_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/arrival.dart';
import '../widgets/community_bits.dart';
import '../widgets/page_backdrop.dart';

/// One story and the conversation under it.
class CommunityThreadScreen extends StatefulWidget {
  final CommunityPost post;

  const CommunityThreadScreen({super.key, required this.post});

  @override
  State<CommunityThreadScreen> createState() => _CommunityThreadScreenState();
}

class _CommunityThreadScreenState extends State<CommunityThreadScreen> {
  @override
  void initState() {
    super.initState();
    // Opening it is what counts as reading it.
    CommunityService.instance.markRead(widget.post.id).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: ExodusTheme.ironMist),
        title: Text(
          post.tag,
          style: const TextStyle(
            color: ExodusTheme.ironMist,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ),
      body: PageBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Arrival(
                step: const Duration(milliseconds: 60),
                children: [
                  _postHeader(post),
                  const SizedBox(height: 18),
                  Text(
                    post.title,
                    style: const TextStyle(
                      fontFamily: ExodusTheme.serif,
                      color: ExodusTheme.parchment,
                      fontSize: 25,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    post.body,
                    style: const TextStyle(
                      fontFamily: ExodusTheme.serif,
                      color: ExodusTheme.parchment,
                      fontSize: 16.5,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _replyDivider(post.replyCount),
                  const SizedBox(height: 6),
                  for (final reply in post.replies) _replyTile(reply, post),
                  const SizedBox(height: 22),
                  if (post.composite) _notice(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _postHeader(CommunityPost post) {
    return Row(
      children: [
        CommunityBits.avatar(post.author, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(post.author,
                  style: const TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 2),
              Text(
                [
                  if (post.authorContext.isNotEmpty) post.authorContext,
                  CommunityBits.ago(post.createdAt),
                ].join(' · '),
                style: const TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 12.5),
              ),
            ],
          ),
        ),
        CommunityBits.tagChip(post.tag),
      ],
    );
  }

  Widget _replyDivider(int count) {
    return Row(
      children: [
        Text(
          count == 1 ? '1 REPLY' : '$count REPLIES',
          style: const TextStyle(
            color: ExodusTheme.ironMist,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: ExodusTheme.steel, height: 1)),
      ],
    );
  }

  Widget _replyTile(CommunityReply reply, CommunityPost post) {
    // The original poster answering is the point of a thread, so it is set
    // apart rather than left to the reader to spot the repeated name.
    final isAuthor = reply.fromAuthor;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: isAuthor
              ? ExodusTheme.slate.withValues(alpha: 0.55)
              : ExodusTheme.midnight.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isAuthor
                ? ExodusTheme.brass.withValues(alpha: 0.24)
                : ExodusTheme.steel,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CommunityBits.avatar(reply.author, size: 26),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(reply.author,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      )),
                ),
                if (isAuthor) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ExodusTheme.brass.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('OP',
                        style: TextStyle(
                          color: ExodusTheme.brass,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        )),
                  ),
                ],
                const Spacer(),
                Text(CommunityBits.ago(reply.createdAt),
                    style: const TextStyle(
                        color: ExodusTheme.ironMist, fontSize: 11.5)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              reply.body,
              style: const TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 14.5,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ExodusTheme.steel),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: ExodusTheme.ironMist),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              CommunityPrompt.compositeNotice,
              style: TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
