import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show areaLabel, failureMessage, formatMoment;
import '../api/backend.dart';
import '../api/forum_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'forum_media.dart';

/// Asks why: refusing or hiding needs a reason. Null when cancelled.
Future<String?> askForumReason(
  BuildContext context, {
  required String title,
  required String action,
}) => showDialog<String>(
  context: context,
  builder: (context) => _ReasonDialog(title: title, action: action),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.action});

  final String title;
  final String action;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLines: 3,
      decoration: const InputDecoration(labelText: 'Reason'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_reason.text.trim()),
        child: Text(widget.action),
      ),
    ],
  );
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, this.radius = 20});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: TgcgColors.primarySoft,
    foregroundColor: TgcgColors.primary,
    child: Text(
      name.split(' ').where((part) => part.isNotEmpty).take(2).map((part) => part[0]).join().toUpperCase(),
      style: TextStyle(fontWeight: FontWeight.w900, fontSize: radius * .7),
    ),
  );
}

enum _PostAction { hide, delete }

/// A post: who, where and when, its assignment, words, pictures and videos.
/// Its moderators approve, refuse or hide it here; its author deletes it.
class ForumPostCard extends StatefulWidget {
  const ForumPostCard({
    super.key,
    required this.post,
    this.onChanged,
    this.onRemoved,
    this.onTag,
    this.onOpen,
  });

  final ForumPost post;
  final ValueChanged<ForumPost>? onChanged;
  final VoidCallback? onRemoved;

  /// The post's assignment was tapped.
  final ValueChanged<String>? onTag;

  /// Opens its replies; null where they are already shown.
  final VoidCallback? onOpen;

  @override
  State<ForumPostCard> createState() => _ForumPostCardState();
}

class _ForumPostCardState extends State<ForumPostCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(ForumRepository forum) work) async {
    setState(() => _busy = true);
    try {
      await work(TgcgBackend.of(context)!.forum);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() => _run((forum) async {
    final post = await forum.approve(widget.post.id);
    widget.onChanged?.call(post);
  });

  Future<void> _refuse() async {
    final reason = await askForumReason(context, title: 'Refuse this post', action: 'Refuse');
    if (reason == null || !mounted) return;
    await _run((forum) async => widget.onChanged?.call(await forum.reject(widget.post.id, reason)));
  }

  Future<void> _act(_PostAction action) async {
    switch (action) {
      case _PostAction.hide:
        final reason = await askForumReason(context, title: 'Hide this post', action: 'Hide');
        if (reason == null || !mounted) return;
        await _run((forum) async => widget.onChanged?.call(await forum.hide(widget.post.id, reason)));
      case _PostAction.delete:
        final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this post?'),
            content: const Text('Its words, pictures and videos are removed for everyone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (sure != true || !mounted) return;
        await _run((forum) async {
          await forum.delete(widget.post.id);
          widget.onRemoved?.call();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final role = post.authorRole.isEmpty ? null : post.authorRole;
    final canHide = post.canModerate && (post.isPublished || post.isPending);
    final (statusLabel, statusColor) = switch (post.status) {
      'pending' => ('WAITING FOR APPROVAL', TgcgColors.warning),
      'rejected' => ('NOT APPROVED', TgcgColors.danger),
      'hidden' => ('HIDDEN', TgcgColors.muted),
      _ => ('', TgcgColors.muted),
    };
    return Material(
      color: TgcgColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: TgcgColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Initials(name: post.authorName),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink),
                      ),
                      Text(
                        [?role, areaLabel(post.scope)].join(' • '),
                        style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted),
                      ),
                      Text(
                        formatMoment(post.publishedAt ?? post.createdAt),
                        style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
                      ),
                    ],
                  ),
                ),
                if (post.isMine || canHide)
                  PopupMenuButton<_PostAction>(
                    tooltip: 'More',
                    enabled: !_busy,
                    onSelected: _act,
                    itemBuilder: (_) => [
                      if (canHide) const PopupMenuItem(value: _PostAction.hide, child: Text('Hide')),
                      if (post.isMine)
                        const PopupMenuItem(value: _PostAction.delete, child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (statusLabel.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TgcgStatusPill(label: statusLabel, color: statusColor, compact: true),
                    ),
                    if (post.reviewReason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        post.reviewReason,
                        style: const TextStyle(fontSize: 12, color: TgcgColors.muted),
                      ),
                    ],
                  ],
                  if (post.assignment.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(Icons.assignment_turned_in_outlined, size: 16),
                        label: Text(
                          'Assignment: ${post.assignment}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: widget.onTag == null
                            ? null
                            : () => widget.onTag!(post.assignment),
                      ),
                    ),
                  ],
                  if (post.body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(post.body, style: const TextStyle(color: TgcgColors.ink, height: 1.4)),
                  ],
                  if (post.attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ForumMediaGrid(attachments: post.attachments),
                  ],
                  if (post.canModerate && post.isPending) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _approve,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Approve'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _refuse,
                          icon: const Icon(Icons.block_rounded),
                          label: const Text('Refuse'),
                        ),
                      ],
                    ),
                  ],
                  if (widget.onOpen != null && post.isPublished)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.onOpen,
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                        label: Text(switch (post.replies) {
                          0 => 'Reply',
                          1 => '1 reply',
                          final count => '$count replies',
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A post with its replies, which appear at once.
class ForumPostPage extends StatefulWidget {
  const ForumPostPage({super.key, required this.post});

  final ForumPost post;

  @override
  State<ForumPostPage> createState() => _ForumPostPageState();
}

class _ForumPostPageState extends State<ForumPostPage> {
  late ForumPost _post = widget.post;
  List<ForumReply>? _replies;
  Object? _error;
  final _reply = TextEditingController();
  bool _sending = false;
  bool _started = false;

  ForumRepository get _forum => TgcgBackend.of(context)!.forum;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final replies = await _forum.replies(_post.id);
      if (mounted) {
        setState(() {
          _replies = replies;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final reply = await _forum.reply(_post.id, text);
      _reply.clear();
      if (mounted) setState(() => _replies = [...?_replies, reply]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _hide(ForumReply reply) async {
    final reason = await askForumReason(context, title: 'Hide this reply', action: 'Hide');
    if (reason == null || !mounted) return;
    try {
      final hidden = await _forum.hideReply(reply.id, reason);
      if (mounted) setState(() => _replies = [for (final r in _replies!) r.id == reply.id ? hidden : r]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(error))));
      }
    }
  }

  Future<void> _delete(ForumReply reply) async {
    try {
      await _forum.deleteReply(reply.id);
      if (mounted) setState(() => _replies = [for (final r in _replies!) if (r.id != reply.id) r]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final canReply = _post.isPublished && session.can(TgcgCapability.postDiscussionReply);
    final replies = _replies;
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                ForumPostCard(
                  post: _post,
                  onChanged: (post) => setState(() => _post = post),
                  onRemoved: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 18),
                Text(
                  replies == null || replies.isEmpty ? 'Replies' : 'Replies (${replies.length})',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink),
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  TgcgEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load the replies',
                    message: failureMessage(_error!),
                    action: TextButton(onPressed: _load, child: const Text('Try again')),
                  )
                else if (replies == null)
                  const Center(child: CircularProgressIndicator())
                else
                  for (final reply in replies)
                    _ReplyTile(
                      reply: reply,
                      canHide: _post.canModerate && !reply.isHidden,
                      onHide: () => _hide(reply),
                      onDelete: () => _delete(reply),
                    ),
              ],
            ),
          ),
          if (canReply)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: const BoxDecoration(
                  color: TgcgColors.surface,
                  border: Border(top: BorderSide(color: TgcgColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(hintText: 'Write a reply'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Send reply',
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.reply,
    required this.canHide,
    required this.onHide,
    required this.onDelete,
  });

  final ForumReply reply;
  final bool canHide;
  final VoidCallback onHide;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Initials(name: reply.authorName, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reply.authorName,
                style: const TextStyle(fontWeight: FontWeight.w800, color: TgcgColors.ink),
              ),
              Text(
                [if (reply.authorRole.isNotEmpty) reply.authorRole, formatMoment(reply.createdAt)]
                    .join(' • '),
                style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
              ),
              const SizedBox(height: 4),
              if (reply.isHidden)
                Text(
                  'Hidden${reply.hideReason.isEmpty ? '' : ': ${reply.hideReason}'}',
                  style: const TextStyle(color: TgcgColors.muted, fontStyle: FontStyle.italic),
                ),
              if (reply.body.isNotEmpty)
                Text(reply.body, style: const TextStyle(color: TgcgColors.ink, height: 1.35)),
            ],
          ),
        ),
        if (reply.isMine || canHide)
          PopupMenuButton<_PostAction>(
            tooltip: 'More',
            onSelected: (action) => action == _PostAction.hide ? onHide() : onDelete(),
            itemBuilder: (_) => [
              if (canHide) const PopupMenuItem(value: _PostAction.hide, child: Text('Hide')),
              if (reply.isMine) const PopupMenuItem(value: _PostAction.delete, child: Text('Delete')),
            ],
          ),
      ],
    ),
  );
}
