import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart' show areaLabel, failureMessage, formatMoment;
import '../api/backend.dart';
import '../api/forum_repository.dart';
import '../ui/tgcg_design.dart';
import 'forum_media.dart';

/// Asks why: hiding or reporting needs a reason. Null when cancelled.
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

/// Asks before something is deleted for everyone.
Future<bool> _sure(BuildContext context, {required String title, required String message}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    ) ==
    true;

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Changes the words of a post (and its assignment) or of a comment. It
/// saves on the server and closes with what was saved.
class _EditDialog<T> extends StatefulWidget {
  const _EditDialog({
    required this.title,
    required this.body,
    required this.maxLength,
    required this.save,
    this.assignment,
  });

  final String title;
  final String body;

  /// Null for a comment, which has no assignment.
  final String? assignment;
  final int maxLength;
  final Future<T> Function(String body, String assignment) save;

  @override
  State<_EditDialog<T>> createState() => _EditDialogState<T>();
}

class _EditDialogState<T> extends State<_EditDialog<T>> {
  late final _body = TextEditingController(text: widget.body);
  late final _assignment = TextEditingController(text: widget.assignment ?? '');
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    _assignment.dispose();
    super.dispose();
  }

  bool get _changed =>
      _body.text.trim() != widget.body.trim() ||
      (widget.assignment != null && _assignment.text.trim() != widget.assignment!.trim());

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(_body.text, _assignment.text);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _body,
            enabled: !_saving,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            inputFormatters: [LengthLimitingTextInputFormatter(widget.maxLength)],
            onChanged: (_) => setState(() {}),
          ),
          if (widget.assignment != null) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _assignment,
              enabled: !_saving,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              decoration: const InputDecoration(labelText: 'Assignment (optional)'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving || !_changed ? null : _save,
        child: const Text('Save'),
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

enum _Action { edit, delete, report, hide, restore }

/// What this account may do with a post or comment.
class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.onSelected,
    this.enabled = true,
    this.edit = false,
    this.report = false,
    this.hide = false,
    this.restore = false,
  });

  final ValueChanged<_Action> onSelected;
  final bool enabled;

  /// Its author edits and deletes.
  final bool edit;
  final bool report;
  final bool hide;
  final bool restore;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_Action>(
    tooltip: 'More',
    enabled: enabled,
    onSelected: onSelected,
    itemBuilder: (_) => [
      if (edit) ...[
        const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
        const PopupMenuItem(value: _Action.delete, child: Text('Delete')),
      ],
      if (report) const PopupMenuItem(value: _Action.report, child: Text('Report')),
      if (hide) const PopupMenuItem(value: _Action.hide, child: Text('Hide')),
      if (restore) const PopupMenuItem(value: _Action.restore, child: Text('Restore')),
    ],
  );
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.likes,
    required this.onPressed,
    this.small = false,
  });

  final bool liked;
  final int likes;
  final VoidCallback? onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: liked ? 'Unlike' : 'Like',
    child: TextButton.icon(
      onPressed: onPressed,
      style: small ? _smallButton : null,
      icon: Icon(
        liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
        size: small ? 16 : 18,
      ),
      label: Text(likes == 0 ? 'Like' : '$likes'),
    ),
  );
}

final _smallButton = TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 8),
  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
);

/// A post: who, where and when, its assignment, words, pictures and videos,
/// its likes and comments. Its author edits or deletes it here; others
/// report it; editors hide or restore it.
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

  /// Opens its comments; null where they are already shown.
  final VoidCallback? onOpen;

  @override
  State<ForumPostCard> createState() => _ForumPostCardState();
}

class _ForumPostCardState extends State<ForumPostCard> {
  bool _busy = false;
  bool _liking = false;

  ForumRepository get _forum => TgcgBackend.of(context)!.forum;

  Future<void> _run(Future<void> Function(ForumRepository forum) work) async {
    final forum = _forum;
    setState(() => _busy = true);
    try {
      await work(forum);
    } catch (error) {
      if (mounted) _say(context, failureMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _like() async {
    final post = widget.post;
    final forum = _forum;
    setState(() => _liking = true);
    try {
      final likes = await forum.like(post.id, on: !post.liked);
      widget.onChanged?.call((mounted ? widget.post : post).withLikes(likes));
    } catch (error) {
      if (mounted) _say(context, failureMessage(error));
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _act(_Action action) async {
    final post = widget.post;
    final forum = _forum;
    switch (action) {
      case _Action.edit:
        final edited = await showDialog<ForumPost>(
          context: context,
          builder: (_) => _EditDialog<ForumPost>(
            title: 'Edit post',
            body: post.body,
            assignment: post.assignment,
            maxLength: 4000,
            save: (body, assignment) => forum.edit(post.id, body: body, assignment: assignment),
          ),
        );
        if (edited != null) widget.onChanged?.call(edited);
      case _Action.delete:
        final sure = await _sure(
          context,
          title: 'Delete this post?',
          message: 'Its words, pictures and videos are removed for everyone.',
        );
        if (!sure || !mounted) return;
        await _run((forum) async {
          await forum.delete(post.id);
          widget.onRemoved?.call();
        });
      case _Action.report:
        final reason = await askForumReason(context, title: 'Report this post', action: 'Report');
        if (reason == null || !mounted) return;
        await _run((forum) async {
          await forum.report(post.id, reason);
          if (mounted) _say(context, 'Reported to the editors.');
        });
      case _Action.hide:
        final reason = await askForumReason(context, title: 'Hide this post', action: 'Hide');
        if (reason == null || !mounted) return;
        await _run((forum) async => widget.onChanged?.call(await forum.hide(post.id, reason)));
      case _Action.restore:
        await _run((forum) async => widget.onChanged?.call(await forum.restore(post.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final role = post.authorRole.isEmpty ? null : post.authorRole;
    final (statusLabel, statusColor) = switch (post.status) {
      'hidden' => ('HIDDEN', TgcgColors.muted),
      'rejected' => ('NOT APPROVED', TgcgColors.danger),
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
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
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
                        [
                          formatMoment(post.publishedAt ?? post.createdAt),
                          if (post.editedAt != null) 'edited',
                        ].join(' • '),
                        style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
                      ),
                    ],
                  ),
                ),
                if (post.canEdit || post.canReport || post.canHide)
                  _ActionMenu(
                    enabled: !_busy,
                    onSelected: _act,
                    edit: post.canEdit,
                    report: post.canReport,
                    hide: post.canHide,
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
                  if (post.canRestore) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _act(_Action.restore),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Restore'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (post.isPublished)
              Row(
                children: [
                  _LikeButton(
                    liked: post.liked,
                    likes: post.likes,
                    onPressed: _liking ? null : _like,
                  ),
                  if (widget.onOpen != null)
                    TextButton.icon(
                      onPressed: widget.onOpen,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: Text(switch (post.replies) {
                        0 => 'Comment',
                        1 => '1 comment',
                        final count => '$count comments',
                      }),
                    ),
                ],
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Comments in order, each with its answers. An answer whose comment is gone
/// (deleted, or hidden from this account) stands on its own.
List<(ForumReply, List<ForumReply>)> _threads(List<ForumReply> replies) {
  final ids = {for (final reply in replies) reply.id};
  final tops = {
    for (final reply in replies)
      if (reply.parent == null || !ids.contains(reply.parent)) reply.id,
  };
  final answers = <String, List<ForumReply>>{};
  final comments = <ForumReply>[];
  for (final reply in replies) {
    final parent = reply.parent;
    if (parent != null && tops.contains(parent)) {
      answers.putIfAbsent(parent, () => []).add(reply);
    } else {
      comments.add(reply);
    }
  }
  return [for (final comment in comments) (comment, answers[comment.id] ?? const [])];
}

/// A post with its comments and their answers, which appear at once.
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
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();

  /// The comment being answered; null for a comment on the post.
  ForumReply? _answering;
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
    _comment.dispose();
    _commentFocus.dispose();
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
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    final answering = _answering;
    setState(() => _sending = true);
    try {
      final reply = await _forum.reply(_post.id, text, parent: answering?.id);
      _comment.clear();
      if (mounted) {
        setState(() {
          _replies = [...?_replies, reply];
          _answering = null;
        });
      }
    } catch (error) {
      if (mounted) _say(context, failureMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _answer(ForumReply reply) {
    setState(() => _answering = reply);
    _commentFocus.requestFocus();
  }

  void _replace(ForumReply reply) => setState(
    () => _replies = [for (final item in _replies ?? const <ForumReply>[]) item.id == reply.id ? reply : item],
  );

  Future<void> _like(ForumReply reply) async {
    try {
      final likes = await _forum.likeReply(reply.id, on: !reply.liked);
      if (!mounted) return;
      final current = _replies?.where((item) => item.id == reply.id).firstOrNull ?? reply;
      _replace(current.withLikes(likes));
    } catch (error) {
      if (mounted) _say(context, failureMessage(error));
    }
  }

  Future<void> _act(ForumReply reply, _Action action) async {
    final forum = _forum;
    try {
      switch (action) {
        case _Action.edit:
          final edited = await showDialog<ForumReply>(
            context: context,
            builder: (_) => _EditDialog<ForumReply>(
              title: 'Edit comment',
              body: reply.body,
              maxLength: 2000,
              save: (body, _) => forum.editReply(reply.id, body),
            ),
          );
          if (edited != null && mounted) _replace(edited);
        case _Action.delete:
          final sure = await _sure(
            context,
            title: 'Delete this comment?',
            message: 'It is removed for everyone.',
          );
          if (!sure || !mounted) return;
          await forum.deleteReply(reply.id);
          if (!mounted) return;
          setState(() {
            _replies = [for (final item in _replies!) if (item.id != reply.id) item];
            if (_answering?.id == reply.id) _answering = null;
          });
        case _Action.report:
          final reason = await askForumReason(
            context,
            title: 'Report this comment',
            action: 'Report',
          );
          if (reason == null) return;
          await forum.reportReply(reply.id, reason);
          if (mounted) _say(context, 'Reported to the editors.');
        case _Action.hide:
          final reason = await askForumReason(context, title: 'Hide this comment', action: 'Hide');
          if (reason == null) return;
          final hidden = await forum.hideReply(reply.id, reason);
          if (mounted) _replace(hidden);
        case _Action.restore:
          final restored = await forum.restoreReply(reply.id);
          if (mounted) _replace(restored);
      }
    } catch (error) {
      if (mounted) _say(context, failureMessage(error));
    }
  }

  Widget _tile(ForumReply reply, {bool answer = false}) => _CommentTile(
    key: ValueKey(reply.id),
    reply: reply,
    open: _post.isPublished,
    answer: answer,
    onLike: () => _like(reply),
    onAnswer: () => _answer(reply),
    onAction: (action) => _act(reply, action),
  );

  @override
  Widget build(BuildContext context) {
    final replies = _replies;
    final answering = _answering;
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
                  replies == null || replies.isEmpty ? 'Comments' : 'Comments (${replies.length})',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink),
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  TgcgEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load the comments',
                    message: failureMessage(_error!),
                    action: TextButton(onPressed: _load, child: const Text('Try again')),
                  )
                else if (replies == null)
                  const Center(child: CircularProgressIndicator())
                else
                  for (final (comment, answers) in _threads(replies)) ...[
                    _tile(comment),
                    for (final answer in answers)
                      Padding(
                        padding: const EdgeInsets.only(left: 42),
                        child: _tile(answer, answer: true),
                      ),
                  ],
              ],
            ),
          ),
          if (_post.isPublished)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: const BoxDecoration(
                  color: TgcgColors.surface,
                  border: Border(top: BorderSide(color: TgcgColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (answering != null)
                      Row(
                        children: [
                          const Icon(Icons.reply_rounded, size: 16, color: TgcgColors.muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Answering ${answering.authorName}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: TgcgColors.muted),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Stop answering',
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _answering = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _comment,
                            focusNode: _commentFocus,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.newline,
                            inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                            decoration: InputDecoration(
                              hintText: answering == null ? 'Write a comment' : 'Write an answer',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: 'Send',
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
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

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.reply,
    required this.open,
    required this.onLike,
    required this.onAnswer,
    required this.onAction,
    this.answer = false,
  });

  final ForumReply reply;

  /// The post takes comments: it is published.
  final bool open;
  final VoidCallback onLike;
  final VoidCallback onAnswer;
  final ValueChanged<_Action> onAction;

  /// An answer to a comment, drawn smaller.
  final bool answer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Initials(name: reply.authorName, radius: answer ? 13 : 16),
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
                [
                  if (reply.authorRole.isNotEmpty) reply.authorRole,
                  formatMoment(reply.createdAt),
                  if (reply.editedAt != null) 'edited',
                ].join(' • '),
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
              if (open && reply.isVisible)
                Row(
                  children: [
                    _LikeButton(liked: reply.liked, likes: reply.likes, onPressed: onLike, small: true),
                    TextButton.icon(
                      onPressed: onAnswer,
                      style: _smallButton,
                      icon: const Icon(Icons.reply_rounded, size: 16),
                      label: const Text('Reply'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (reply.canEdit || reply.canReport || reply.canHide || reply.canRestore)
          _ActionMenu(
            onSelected: onAction,
            edit: reply.canEdit,
            report: reply.canReport,
            hide: reply.canHide,
            restore: reply.canRestore,
          ),
      ],
    ),
  );
}
