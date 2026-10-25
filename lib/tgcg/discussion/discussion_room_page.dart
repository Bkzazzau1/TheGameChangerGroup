import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart' show failureMessage, formatMoment;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/forum_repository.dart';
import '../ui/tgcg_design.dart';
import 'forum_media.dart';
import 'forum_post.dart';

/// The Social Forum, for every member: posts appear at once, and everyone
/// comments, answers, likes and reports. Editors (everyone holding a role or
/// position) hide and restore, and see the reports. The server decides who
/// does what.
class DiscussionRoomPage extends StatefulWidget {
  const DiscussionRoomPage({super.key, this.pickMedia = pickForumMedia, this.bottomPadding});

  final PickForumMedia pickMedia;

  /// Room below the feed (more where a floating button covers its end).
  final double? bottomPadding;

  @override
  State<DiscussionRoomPage> createState() => _DiscussionRoomPageState();
}

enum _View { all, assignments, mine, hidden, reports }

class _DiscussionRoomPageState extends State<DiscussionRoomPage> {
  var _view = _View.all;
  String? _tag;
  final _posts = <ForumPost>[];
  final _reports = <ForumReport>[];
  var _hasMore = false;
  var _loading = false;
  Object? _error;
  ForumMe? _me;

  /// Open reports, for editors.
  int? _openReports;
  final _busyReports = <String>{};
  var _tags = const <AssignmentTag>[];
  var _started = false;
  var _generation = 0;

  ForumRepository? get _forum => TgcgBackend.of(context)?.forum;
  bool get _editor => _me?.editor ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _forum == null) return;
    _started = true;
    _load(reset: true);
    _loadMe();
    _loadTags();
  }

  Future<void> _loadMe() async {
    try {
      final me = await _forum!.me();
      if (!mounted) return;
      setState(() => _me = me);
      if (me.editor) _countReports();
    } catch (_) {
      // Without it the composer and the editors' lists stay away; the feed
      // still loads.
    }
  }

  Future<void> _countReports() async {
    try {
      final page = await _forum!.reports();
      if (mounted) setState(() => _openReports = page.count);
    } catch (_) {
      // The tab still opens the list.
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _forum!.assignments();
      if (mounted) setState(() => _tags = tags);
    } catch (_) {
      // Assignment filters are a convenience; the feed still works.
    }
  }

  Future<void> _load({bool reset = false}) async {
    final forum = _forum;
    if (forum == null) return;
    final generation = reset ? ++_generation : _generation;
    final view = _view;
    setState(() {
      if (reset) {
        _posts.clear();
        _reports.clear();
        _hasMore = false;
      }
      _loading = true;
      _error = null;
    });
    try {
      if (view == _View.reports) {
        final page = await forum.reports(offset: _reports.length);
        if (!mounted || generation != _generation) return;
        setState(() {
          _reports.addAll(page.items);
          _hasMore = page.hasMore;
          _openReports = page.count;
        });
      } else {
        final page = await forum.posts(
          show: switch (view) {
            _View.mine => ForumShow.mine,
            _View.hidden => ForumShow.hidden,
            _ => ForumShow.feed,
          },
          assignment: view == _View.assignments ? _tag : null,
          assignmentsOnly: view == _View.assignments,
          offset: _posts.length,
        );
        if (!mounted || generation != _generation) return;
        setState(() {
          _posts.addAll(page.items);
          _hasMore = page.hasMore;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  bool get _empty => _view == _View.reports ? _reports.isEmpty : _posts.isEmpty;

  void _retry() {
    if (_me == null) _loadMe();
    _load(reset: _empty);
  }

  void _show(_View view, {String? tag}) {
    setState(() {
      _view = view;
      _tag = tag;
    });
    _load(reset: true);
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void _posted(ForumPost post) {
    final fits = switch (_view) {
      _View.all => post.isPublished,
      _View.mine => true,
      _View.assignments =>
        post.isPublished &&
            post.assignment.isNotEmpty &&
            (_tag == null || _tag!.toLowerCase() == post.assignment.toLowerCase()),
      _View.hidden || _View.reports => false,
    };
    if (fits) setState(() => _posts.insert(0, post));
    _say('Posted.');
    if (post.assignment.isNotEmpty) _loadTags();
  }

  void _changed(ForumPost post) {
    final index = _posts.indexWhere((item) => item.id == post.id);
    if (index < 0) return;
    setState(() {
      final gone = switch (_view) {
        _View.all || _View.assignments => !post.isPublished,
        _View.hidden => !post.isHidden,
        _ => false,
      };
      if (gone) {
        _posts.removeAt(index);
      } else {
        _posts[index] = post;
      }
    });
  }

  void _removed(ForumPost post) =>
      setState(() => _posts.removeWhere((item) => item.id == post.id));

  Future<void> _open(ForumPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ForumPostPage(post: post)),
    );
    if (!mounted) return;
    // Its comments, likes or status may have changed meanwhile.
    try {
      _changed(await _forum!.post(post.id));
    } on ApiException catch (error) {
      if (error.statusCode == 404 && mounted) _removed(post);
    } catch (_) {
      // The card keeps what it showed.
    }
  }

  Future<void> _openReport(ForumReport report) async {
    setState(() => _busyReports.add(report.id));
    ForumPost? found;
    try {
      found = await _forum!.post(report.postId);
    } on ApiException catch (error) {
      if (mounted) _say(error.statusCode == 404 ? 'This post was deleted.' : failureMessage(error));
    } catch (error) {
      if (mounted) _say(failureMessage(error));
    } finally {
      if (mounted) setState(() => _busyReports.remove(report.id));
    }
    final post = found;
    if (post == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ForumPostPage(post: post)),
    );
    // Hiding it there closes its reports.
    if (!mounted || _view != _View.reports) return;
    _load(reset: true);
  }

  Future<void> _hideReported(ForumReport report) async {
    final reason = await askForumReason(
      context,
      title: report.isComment ? 'Hide this comment' : 'Hide this post',
      action: 'Hide',
    );
    if (reason == null || !mounted) return;
    await _settle(report, sameTarget: true, (forum) async {
      if (report.isComment) {
        await forum.hideReply(report.replyId!, reason);
      } else {
        await forum.hide(report.postId, reason);
      }
    });
  }

  Future<void> _dismiss(ForumReport report) =>
      _settle(report, (forum) => forum.dismissReport(report.id));

  /// Hiding closes every open report on the same post or comment;
  /// dismissing closes only this one.
  Future<void> _settle(
    ForumReport report,
    Future<void> Function(ForumRepository forum) work, {
    bool sameTarget = false,
  }) async {
    final forum = _forum!;
    setState(() => _busyReports.add(report.id));
    try {
      await work(forum);
      if (!mounted) return;
      setState(() {
        final before = _reports.length;
        _reports.removeWhere(
          (item) =>
              item.id == report.id ||
              (sameTarget && item.postId == report.postId && item.replyId == report.replyId),
        );
        final closed = before - _reports.length;
        _openReports = ((_openReports ?? before) - closed).clamp(0, 1 << 30);
      });
    } catch (error) {
      if (mounted) _say(failureMessage(error));
    } finally {
      if (mounted) setState(() => _busyReports.remove(report.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final reports = _openReports ?? 0;
    if (_forum == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: TgcgEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Connect to the TGCG server',
            message: 'Sign in with a server account to use the forum.',
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        phone ? 16 : 24,
        phone ? 16 : 24,
        phone ? 16 : 24,
        widget.bottomPadding ?? (phone ? 16 : 24),
      ),
      children: [
        TgcgPageHeader(
          eyebrow: 'COMMUNITY',
          title: 'Social Forum',
          subtitle: 'Posts, pictures and assignments from every member.',
        ),
        const SizedBox(height: 16),
        if (_me?.takesPart ?? false) ...[
          ForumComposer(pickMedia: widget.pickMedia, tags: _tags, onPosted: _posted),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All posts'),
              selected: _view == _View.all,
              onSelected: (_) => _show(_View.all),
            ),
            ChoiceChip(
              label: const Text('Assignments'),
              selected: _view == _View.assignments,
              onSelected: (_) => _show(_View.assignments),
            ),
            ChoiceChip(
              label: const Text('My posts'),
              selected: _view == _View.mine,
              onSelected: (_) => _show(_View.mine),
            ),
            if (_editor) ...[
              ChoiceChip(
                label: const Text('Hidden'),
                selected: _view == _View.hidden,
                onSelected: (_) => _show(_View.hidden),
              ),
              ChoiceChip(
                label: Text(reports == 0 ? 'Reports' : 'Reports ($reports)'),
                selected: _view == _View.reports,
                onSelected: (_) => _show(_View.reports),
              ),
            ],
          ],
        ),
        if (_view == _View.assignments && _tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in _tags)
                FilterChip(
                  label: Text('${tag.tag} (${tag.posts})', overflow: TextOverflow.ellipsis),
                  selected: _tag?.toLowerCase() == tag.tag.toLowerCase(),
                  onSelected: (on) => _show(_View.assignments, tag: on ? tag.tag : null),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (_view == _View.reports)
          for (final report in _reports)
            Padding(
              key: ValueKey(report.id),
              padding: const EdgeInsets.only(bottom: 12),
              child: _ReportCard(
                report: report,
                busy: _busyReports.contains(report.id),
                onOpen: () => _openReport(report),
                onHide: () => _hideReported(report),
                onDismiss: () => _dismiss(report),
              ),
            )
        else
          for (final post in _posts)
            Padding(
              key: ValueKey(post.id),
              padding: const EdgeInsets.only(bottom: 12),
              child: ForumPostCard(
                post: post,
                onChanged: _changed,
                onRemoved: () => _removed(post),
                onTag: (tag) => _show(_View.assignments, tag: tag),
                onOpen: () => _open(post),
              ),
            ),
        if (_error != null)
          TgcgEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load the forum',
            message: failureMessage(_error!),
            action: TextButton(onPressed: _retry, child: const Text('Try again')),
          )
        else if (!_loading && _empty)
          TgcgEmptyState(
            icon: _view == _View.reports ? Icons.flag_outlined : Icons.forum_outlined,
            title: switch (_view) {
              _View.all => 'No posts yet',
              _View.assignments => 'No assignment posts yet',
              _View.mine => 'You have not posted yet',
              _View.hidden => 'No hidden posts',
              _View.reports => 'No reports',
            },
            message: switch (_view) {
              _View.hidden => 'Posts an editor hides appear here.',
              _View.reports => 'Posts and comments people report appear here.',
              _ => 'New posts will appear here.',
            },
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_hasMore && _error == null)
          OutlinedButton(onPressed: _load, child: const Text('Show more')),
      ],
    );
  }
}

/// A report waiting for an editor: what was reported, who reported it and
/// why.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onOpen,
    required this.onHide,
    required this.onDismiss,
  });

  final ForumReport report;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onHide;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TgcgStatusPill(
              label: report.isComment ? 'COMMENT' : 'POST',
              color: TgcgColors.primary,
              compact: true,
            ),
            if (!report.canHide) ...[
              const SizedBox(width: 6),
              TgcgStatusPill(
                label: report.targetStatus.toUpperCase(),
                color: TgcgColors.muted,
                compact: true,
              ),
            ],
            const Spacer(),
            Text(
              formatMoment(report.createdAt),
              style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          report.authorName,
          style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink),
        ),
        if (report.excerpt.isNotEmpty)
          Text(
            report.excerpt,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: TgcgColors.ink, height: 1.35),
          ),
        const SizedBox(height: 10),
        Text(
          'Reported by ${report.reporter}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TgcgColors.muted,
          ),
        ),
        Text(report.reason, style: const TextStyle(color: TgcgColors.ink)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open post'),
            ),
            if (report.canHide)
              FilledButton.icon(
                onPressed: busy ? null : onHide,
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('Hide'),
              ),
            TextButton(onPressed: busy ? null : onDismiss, child: const Text('Dismiss')),
          ],
        ),
      ],
    ),
  );
}

/// Writing a post: words, an assignment tag, pictures and videos.
class ForumComposer extends StatefulWidget {
  const ForumComposer({
    super.key,
    required this.pickMedia,
    required this.tags,
    required this.onPosted,
  });

  final PickForumMedia pickMedia;

  /// Assignments already in use, offered while typing one.
  final List<AssignmentTag> tags;
  final ValueChanged<ForumPost> onPosted;

  @override
  State<ForumComposer> createState() => _ForumComposerState();
}

class _ForumComposerState extends State<ForumComposer> {
  final _body = TextEditingController();
  final _assignment = TextEditingController();
  final _assignmentFocus = FocusNode();
  final _files = <ForumUpload>[];
  var _sending = false;
  var _picking = false;
  String? _error;

  /// Sent with the post, so a retry after a lost answer never posts twice.
  String _clientId = _newClientId();

  static String _newClientId() =>
      'forum-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  @override
  void dispose() {
    _body.dispose();
    _assignment.dispose();
    _assignmentFocus.dispose();
    super.dispose();
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _add(ForumMediaSource source) async {
    setState(() => _picking = true);
    try {
      final picked = await widget.pickMedia(source);
      var total = _files.fold<int>(0, (sum, file) => sum + file.bytes.length);
      final accepted = <ForumUpload>[];
      String? problem;
      for (final file in picked) {
        if (_files.length + accepted.length >= forumMaxFiles) {
          problem = 'A post takes at most $forumMaxFiles pictures and videos.';
          break;
        }
        if (file.kind == ForumMediaKind.video && file.bytes.length > forumMaxVideoBytes) {
          problem = 'A video can be at most 50 MB.';
          continue;
        }
        if (total + file.bytes.length > forumMaxPostBytes) {
          problem = 'A post\'s pictures and videos can total at most 100 MB.';
          continue;
        }
        total += file.bytes.length;
        accepted.add(file);
      }
      if (mounted) setState(() => _files.addAll(accepted));
      if (problem != null && mounted) _say(problem);
    } catch (error) {
      if (mounted) _say('It could not be added: $error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    final body = _body.text.trim();
    if (body.isEmpty && _files.isEmpty) {
      setState(() => _error = 'Write something, or add a picture or video.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final post = await TgcgBackend.of(context)!.forum.create(
        body: body,
        assignment: _assignment.text.trim(),
        files: List.of(_files),
        clientId: _clientId,
      );
      _body.clear();
      _assignment.clear();
      _clientId = _newClientId();
      if (!mounted) return;
      setState(() => _files.clear());
      widget.onPosted(post);
    } catch (error) {
      if (mounted) setState(() => _error = failureMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _picking;
    return TgcgSectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _body,
            enabled: !_sending,
            minLines: 2,
            maxLines: 6,
            inputFormatters: [LengthLimitingTextInputFormatter(4000)],
            decoration: const InputDecoration(hintText: 'Share an update'),
          ),
          const SizedBox(height: 10),
          RawAutocomplete<String>(
            textEditingController: _assignment,
            focusNode: _assignmentFocus,
            optionsBuilder: (value) {
              final typed = value.text.trim().toLowerCase();
              return [
                for (final tag in widget.tags)
                  if (typed.isEmpty || tag.tag.toLowerCase().contains(typed)) tag.tag,
              ];
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !_sending,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              decoration: const InputDecoration(
                labelText: 'Assignment (optional)',
                prefixIcon: Icon(Icons.assignment_turned_in_outlined),
              ),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final option in options)
                        ListTile(dense: true, title: Text(option), onTap: () => onSelected(option)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, file) in _files.indexed)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox.square(
                          dimension: 72,
                          child: file.kind == ForumMediaKind.photo
                              ? Image.memory(
                                  file.bytes,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: TgcgColors.surfaceSoft,
                                    child: Icon(Icons.image_outlined, color: TgcgColors.muted),
                                  ),
                                )
                              : ColoredBox(
                                  color: TgcgColors.primaryDark,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.videocam_rounded, color: Colors.white),
                                      Text(
                                        megabytes(file.bytes.length),
                                        style: const TextStyle(color: Colors.white, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton.filledTonal(
                          tooltip: 'Remove',
                          iconSize: 16,
                          visualDensity: VisualDensity.compact,
                          onPressed: _sending
                              ? null
                              : () => setState(() => _files.removeAt(index)),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
          ],
          if (_sending) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: 'Take a picture',
                onPressed: busy ? null : () => _add(ForumMediaSource.photo),
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              IconButton(
                tooltip: 'Record a video',
                onPressed: busy ? null : () => _add(ForumMediaSource.video),
                icon: const Icon(Icons.videocam_outlined),
              ),
              IconButton(
                tooltip: 'Choose from the gallery',
                onPressed: busy ? null : () => _add(ForumMediaSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: busy ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(_sending ? 'Posting…' : 'Post'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
