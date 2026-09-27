import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class DiscussionRoomPage extends StatefulWidget {
  const DiscussionRoomPage({super.key});

  @override
  State<DiscussionRoomPage> createState() => _DiscussionRoomPageState();
}

class _SocialComment {
  const _SocialComment({
    required this.author,
    required this.role,
    required this.body,
    required this.time,
  });

  final String author;
  final String role;
  final String body;
  final String time;
}

class _SocialPost {
  _SocialPost({
    required this.id,
    required this.author,
    required this.role,
    required this.scope,
    required this.body,
    required this.time,
    required this.category,
    required this.icon,
    this.mediaLabel,
    this.mediaIcon,
    this.pinned = false,
    this.reactions = 0,
    List<_SocialComment>? comments,
  }) : comments = List<_SocialComment>.of(comments ?? const []);

  final String id;
  final String author;
  final String role;
  final String scope;
  final String body;
  final String time;
  final String category;
  final IconData icon;
  final String? mediaLabel;
  final IconData? mediaIcon;
  bool pinned;
  int reactions;
  final List<_SocialComment> comments;
  bool reacted = false;
}

class _DiscussionRoomPageState extends State<DiscussionRoomPage> {
  final postController = TextEditingController();
  final commentController = TextEditingController();
  String selectedFeed = 'All';
  String? expandedPostId = 'POST-1001';

  late final List<_SocialPost> posts = [
    _SocialPost(
      id: 'POST-1001',
      author: 'National Operations Desk',
      role: 'Situation Room',
      scope: 'Nigeria',
      body:
          'Morning coordination is active. State and zonal desks can post field updates, operational needs and verified observations here for shared visibility.',
      time: '08:05',
      category: 'Operations',
      icon: Icons.public_rounded,
      pinned: true,
      reactions: 18,
      comments: const [
        _SocialComment(
          author: 'North West Desk',
          role: 'Zonal Coordinator',
          body: 'Coverage check completed and priority support items have been routed.',
          time: '08:18',
        ),
        _SocialComment(
          author: 'Technical Support',
          role: 'Support Desk',
          body: 'Field support desk is active and responding to device-access requests.',
          time: '08:24',
        ),
      ],
    ),
    _SocialPost(
      id: 'POST-1002',
      author: 'Field Coordination',
      role: 'State Coordinator',
      scope: 'Kaduna',
      body:
          'Agent check-in coverage is progressing across assigned polling units. Teams should keep incident reports factual and attach evidence references where available.',
      time: '08:37',
      category: 'Field',
      icon: Icons.sensors_rounded,
      mediaLabel: 'Field coverage snapshot',
      mediaIcon: Icons.map_outlined,
      reactions: 11,
      comments: const [
        _SocialComment(
          author: 'Kaduna North Desk',
          role: 'LGA Coordinator',
          body: 'Acknowledged. Outstanding assignments are being followed up.',
          time: '08:45',
        ),
      ],
    ),
    _SocialPost(
      id: 'POST-1003',
      author: 'Media Monitoring Desk',
      role: 'Media Intelligence',
      scope: 'National',
      body:
          'Public-source monitoring is showing increased discussion around polling access and election logistics. Verification teams are reviewing high-visibility claims before escalation.',
      time: '09:04',
      category: 'Media',
      icon: Icons.insights_outlined,
      mediaLabel: 'Media monitoring brief',
      mediaIcon: Icons.article_outlined,
      reactions: 9,
    ),
    _SocialPost(
      id: 'POST-1004',
      author: 'Legal & Evidence Desk',
      role: 'Legal Officer',
      scope: 'National',
      body:
          'For evidence handoff, retain the original submission reference, polling-unit code and reviewer notes so the record can be traced end to end.',
      time: '09:16',
      category: 'Legal',
      icon: Icons.gavel_rounded,
      reactions: 7,
    ),
  ];

  static const categories = ['All', 'Operations', 'Field', 'Media', 'Legal'];

  @override
  void dispose() {
    postController.dispose();
    commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final canPost = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.createDiscussionThread,
    );
    final canComment = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.postDiscussionReply,
    );

    final visible = selectedFeed == 'All'
        ? posts
        : posts.where((item) => item.category == selectedFeed).toList(growable: false);
    final totalComments = posts.fold<int>(0, (sum, item) => sum + item.comments.length);
    final totalReactions = posts.fold<int>(0, (sum, item) => sum + item.reactions);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'TGCG COMMUNITY',
          title: 'Discussion Forum',
          subtitle:
              '${session.scope.label}: internal social feed for updates, conversations and operational collaboration.',
          trailing: TgcgStatusPill(
            label: '${posts.length} POSTS',
            color: TgcgColors.primary,
            icon: Icons.dynamic_feed_rounded,
          ),
        ),
        const SizedBox(height: 18),
        _CommunitySummary(
          posts: posts.length,
          comments: totalComments,
          reactions: totalReactions,
          contributors: posts.map((item) => item.author).toSet().length,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final feed = Column(
              children: [
                if (canPost) ...[
                  _PostComposer(
                    controller: postController,
                    operatorName: session.operatorName,
                    role: roleLabel(session.role!),
                    onPost: () => _publishPost(session),
                  ),
                  const SizedBox(height: 14),
                ],
                _FeedFilters(
                  selected: selectedFeed,
                  onSelect: (value) => setState(() => selectedFeed = value),
                ),
                const SizedBox(height: 14),
                ...visible.map(
                  (post) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _SocialPostCard(
                      post: post,
                      expanded: expandedPostId == post.id,
                      canComment: canComment,
                      commentController: commentController,
                      onToggleExpanded: () => setState(() {
                        expandedPostId = expandedPostId == post.id ? null : post.id;
                      }),
                      onReact: () => setState(() {
                        post.reacted = !post.reacted;
                        post.reactions += post.reacted ? 1 : -1;
                      }),
                      onComment: () => _postComment(session, post),
                    ),
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 1040) return feed;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: feed),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _ProfileCard(session: session),
                      const SizedBox(height: 14),
                      const _TrendingPanel(),
                      const SizedBox(height: 14),
                      const _CommunityPanel(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _publishPost(TgcgSessionController session) {
    final text = postController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      final post = _SocialPost(
        id: 'POST-${1000 + posts.length + 1}',
        author: session.operatorName,
        role: roleLabel(session.role!),
        scope: session.scope.label,
        body: text,
        time: _timeNow(),
        category: 'Operations',
        icon: Icons.person_rounded,
      );
      posts.insert(0, post);
      selectedFeed = 'All';
      expandedPostId = post.id;
      postController.clear();
    });
  }

  void _postComment(TgcgSessionController session, _SocialPost post) {
    final text = commentController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      post.comments.add(
        _SocialComment(
          author: session.operatorName,
          role: roleLabel(session.role!),
          body: text,
          time: _timeNow(),
        ),
      );
      commentController.clear();
      expandedPostId = post.id;
    });
  }
}

class _CommunitySummary extends StatelessWidget {
  const _CommunitySummary({
    required this.posts,
    required this.comments,
    required this.reactions,
    required this.contributors,
  });

  final int posts;
  final int comments;
  final int reactions;
  final int contributors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 520
                  ? 2
                  : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Posts',
                value: '$posts',
                detail: 'Community updates',
                icon: Icons.dynamic_feed_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Comments',
                value: '$comments',
                detail: 'Team conversations',
                icon: Icons.mode_comment_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Reactions',
                value: '$reactions',
                detail: 'Post engagement',
                icon: Icons.thumb_up_alt_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Contributors',
                value: '$contributors',
                detail: 'Active team voices',
                icon: Icons.groups_outlined,
                tone: TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _PostComposer extends StatelessWidget {
  const _PostComposer({
    required this.controller,
    required this.operatorName,
    required this.role,
    required this.onPost,
  });

  final TextEditingController controller;
  final String operatorName;
  final String role;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(name: operatorName, size: 44),
                const SizedBox(width: 11),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Share an update with the TGCG community…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                _ComposerAction(icon: Icons.image_outlined, label: 'Photo'),
                _ComposerAction(icon: Icons.videocam_outlined, label: 'Video'),
                _ComposerAction(icon: Icons.attach_file_rounded, label: 'File'),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onPost,
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Post'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TextButton.icon(
          onPressed: () {},
          icon: Icon(icon, size: 17),
          label: Text(label),
        ),
      );
}

class _FeedFilters extends StatelessWidget {
  const _FeedFilters({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(9),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _DiscussionRoomPageState.categories.map((category) {
            final active = selected == category;
            return ChoiceChip(
              selected: active,
              label: Text(category),
              onSelected: (_) => onSelect(category),
            );
          }).toList(),
        ),
      );
}

class _SocialPostCard extends StatelessWidget {
  const _SocialPostCard({
    required this.post,
    required this.expanded,
    required this.canComment,
    required this.commentController,
    required this.onToggleExpanded,
    required this.onReact,
    required this.onComment,
  });

  final _SocialPost post;
  final bool expanded;
  final bool canComment;
  final TextEditingController commentController;
  final VoidCallback onToggleExpanded;
  final VoidCallback onReact;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(name: post.author, size: 46),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (post.pinned) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.push_pin_rounded,
                                color: TgcgColors.accent,
                                size: 15,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${post.role} • ${post.scope} • ${post.time}',
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TgcgStatusPill(
                    label: post.category.toUpperCase(),
                    color: _categoryColor(post.category),
                    compact: true,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                post.body,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
            ),
            if (post.mediaLabel != null) ...[
              const SizedBox(height: 14),
              Container(
                height: 178,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [TgcgColors.primaryDark, TgcgColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        post.mediaIcon ?? Icons.image_outlined,
                        size: 42,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post.mediaLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${post.reactions} reactions',
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onToggleExpanded,
                    child: Text(
                      '${post.comments.length} comments',
                      style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onReact,
                    icon: Icon(
                      post.reacted
                          ? Icons.thumb_up_alt_rounded
                          : Icons.thumb_up_alt_outlined,
                      size: 18,
                    ),
                    label: Text(post.reacted ? 'Liked' : 'Like'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onToggleExpanded,
                    icon: const Icon(Icons.mode_comment_outlined, size: 18),
                    label: const Text('Comment'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.bookmark_border_rounded, size: 18),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ...post.comments.map(
                      (comment) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Avatar(name: comment.author, size: 34),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: TgcgColors.surfaceSoft,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      comment.author,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${comment.role} • ${comment.time}',
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 8.8,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      comment.body,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontSize: 10.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (canComment)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: commentController,
                              decoration: const InputDecoration(
                                hintText: 'Write a comment…',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: onComment,
                            icon: const Icon(Icons.send_rounded, size: 18),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.session});
  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Container(
              height: 72,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [TgcgColors.primaryDark, TgcgColors.primary],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Column(
                children: [
                  _Avatar(name: session.operatorName, size: 58),
                  const SizedBox(height: 8),
                  Text(
                    session.operatorName,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    roleLabel(session.role!),
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.scope.label,
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TrendingPanel extends StatelessWidget {
  const _TrendingPanel();

  @override
  Widget build(BuildContext context) => const TgcgSectionCard(
        title: 'Trending now',
        subtitle: 'Topics active in the internal community.',
        child: Column(
          children: [
            _TrendRow('#FieldCoverage', '28 posts'),
            _TrendRow('#IncidentUpdates', '21 posts'),
            _TrendRow('#AgentSupport', '17 posts'),
            _TrendRow('#MediaWatch', '12 posts'),
          ],
        ),
      );
}

class _TrendRow extends StatelessWidget {
  const _TrendRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
            ),
          ],
        ),
      );
}

class _CommunityPanel extends StatelessWidget {
  const _CommunityPanel();

  @override
  Widget build(BuildContext context) => const TgcgSectionCard(
        title: 'Community spaces',
        subtitle: 'Follow conversations by operational area.',
        child: Column(
          children: [
            _SpaceRow(Icons.public_rounded, 'National Operations', '128 members'),
            _SpaceRow(Icons.radar_rounded, 'Situation Room', '46 members'),
            _SpaceRow(Icons.support_agent_rounded, 'Field Support', '89 members'),
            _SpaceRow(Icons.gavel_rounded, 'Legal & Evidence', '24 members'),
          ],
        ),
      );
}

class _SpaceRow extends StatelessWidget {
  const _SpaceRow(this.icon, this.label, this.detail);
  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: TgcgColors.primary, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((item) => item.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? 'TG'
        : parts.take(2).map((item) => item[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: TgcgColors.primarySoft,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: TgcgColors.primary,
          fontSize: size * .28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

Color _categoryColor(String category) => switch (category) {
      'Field' => TgcgColors.info,
      'Media' => TgcgColors.ai,
      'Legal' => TgcgColors.warning,
      _ => TgcgColors.primary,
    };

String _timeNow() {
  final now = DateTime.now();
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
