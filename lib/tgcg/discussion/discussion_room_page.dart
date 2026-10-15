import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart' show failureMessage;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/forum_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'forum_media.dart';
import 'forum_post.dart';

/// The discussion forum, for everyone with a role. Posts made at a polling
/// unit wait for the ward coordinator while approval is on; the server
/// decides who sees, posts, approves and hides.
class DiscussionRoomPage extends StatefulWidget {
  const DiscussionRoomPage({super.key, this.pickMedia = pickForumMedia});

  final PickForumMedia pickMedia;

  @override
  State<DiscussionRoomPage> createState() => _DiscussionRoomPageState();
}

enum _View { all, assignments, mine, review }

class _DiscussionRoomPageState extends State<DiscussionRoomPage> {
  var _view = _View.all;
  String? _tag;
  final _posts = <ForumPost>[];
  var _hasMore = false;
  var _loading = false;
  Object? _error;

  /// Posts waiting for this account's approval.
  int? _waiting;
  ForumSettings? _settings;
  var _tags = const <AssignmentTag>[];
  var _started = false;
  var _generation = 0;

  ForumRepository? get _forum => TgcgBackend.of(context)?.forum;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _forum == null) return;
    _started = true;
    _load(reset: true);
    _loadSettings();
    _loadTags();
    _loadWaiting();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _forum!.settings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Without them, only the settings button is missing.
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

  Future<void> _loadWaiting() async {
    if (!TgcgSession.of(context, listen: false).can(TgcgCapability.moderateDiscussion)) return;
    try {
      final page = await _forum!.posts(show: ForumShow.review);
      if (mounted) setState(() => _waiting = page.count);
    } catch (_) {
      // The tab still opens the list.
    }
  }

  Future<void> _load({bool reset = false}) async {
    final forum = _forum;
    if (forum == null) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      if (reset) {
        _posts.clear();
        _hasMore = false;
      }
      _loading = true;
      _error = null;
    });
    try {
      final page = await forum.posts(
        show: switch (_view) {
          _View.mine => ForumShow.mine,
          _View.review => ForumShow.review,
          _ => ForumShow.feed,
        },
        assignment: _view == _View.assignments ? _tag : null,
        assignmentsOnly: _view == _View.assignments,
        offset: _posts.length,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _posts.addAll(page.items);
        _hasMore = page.hasMore;
        if (_view == _View.review) _waiting = page.count;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _show(_View view, {String? tag}) {
    setState(() {
      _view = view;
      _tag = tag;
    });
    _load(reset: true);
  }

  void _posted(ForumPost post) {
    final fits = switch (_view) {
      _View.all => post.isPublished,
      _View.mine => true,
      _View.assignments =>
        post.isPublished &&
            post.assignment.isNotEmpty &&
            (_tag == null || _tag!.toLowerCase() == post.assignment.toLowerCase()),
      _View.review => false,
    };
    if (fits) setState(() => _posts.insert(0, post));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          post.isPending ? 'Sent to your ward coordinator for approval.' : 'Posted.',
        ),
      ),
    );
    if (post.assignment.isNotEmpty) _loadTags();
  }

  void _changed(ForumPost post) {
    final index = _posts.indexWhere((item) => item.id == post.id);
    if (index < 0) return;
    setState(() {
      if (_view == _View.review && !post.isPending) {
        // Approved, refused or hidden: no longer waiting.
        _posts.removeAt(index);
        _waiting = ((_waiting ?? 1) - 1).clamp(0, 1 << 30);
      } else if ((_view == _View.all || _view == _View.assignments) && !post.isPublished) {
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
    // Its replies or status may have changed meanwhile.
    try {
      _changed(await _forum!.post(post.id));
    } on ApiException catch (error) {
      if (error.statusCode == 404 && mounted) _removed(post);
    } catch (_) {
      // The card keeps what it showed.
    }
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    final changed = await showDialog<ForumSettings>(
      context: context,
      builder: (_) => _ForumSettingsDialog(settings: settings),
    );
    if (changed != null && mounted) setState(() => _settings = changed);
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final moderator = session.can(TgcgCapability.moderateDiscussion);
    final waiting = _waiting ?? 0;
    final phone = MediaQuery.sizeOf(context).width < 600;
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
      padding: EdgeInsets.all(phone ? 16 : 24),
      children: [
        TgcgPageHeader(
          eyebrow: 'COORDINATION',
          title: 'Discussion Forum',
          subtitle: 'Updates, pictures and assignments from everyone with a role.',
          trailing: _settings?.canChange == true
              ? IconButton(
                  tooltip: 'Forum settings',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.tune_rounded),
                )
              : null,
        ),
        const SizedBox(height: 16),
        if (session.can(TgcgCapability.createDiscussionThread)) ...[
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
            if (moderator)
              ChoiceChip(
                label: Text(waiting == 0 ? 'To approve' : 'To approve ($waiting)'),
                selected: _view == _View.review,
                onSelected: (_) => _show(_View.review),
              ),
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
            action: TextButton(
              onPressed: () => _load(reset: _posts.isEmpty),
              child: const Text('Try again'),
            ),
          )
        else if (!_loading && _posts.isEmpty)
          TgcgEmptyState(
            icon: Icons.forum_outlined,
            title: switch (_view) {
              _View.all => 'No posts yet',
              _View.assignments => 'No assignment posts yet',
              _View.mine => 'You have not posted yet',
              _View.review => 'Nothing to approve',
            },
            message: switch (_view) {
              _View.review => 'Posts from your polling units will appear here.',
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

/// The one switch: whether posts from polling units wait for approval.
class _ForumSettingsDialog extends StatefulWidget {
  const _ForumSettingsDialog({required this.settings});

  final ForumSettings settings;

  @override
  State<_ForumSettingsDialog> createState() => _ForumSettingsDialogState();
}

class _ForumSettingsDialogState extends State<_ForumSettingsDialog> {
  late bool _required = widget.settings.approvalRequired;
  var _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await TgcgBackend.of(context)!.forum.setApprovalRequired(_required);
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
    title: const Text('Forum settings'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _required,
          onChanged: _saving ? null : (value) => setState(() => _required = value),
          title: const Text('Approve polling unit posts'),
          subtitle: const Text('The ward coordinator approves them before everyone sees them.'),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving || _required == widget.settings.approvalRequired ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}
