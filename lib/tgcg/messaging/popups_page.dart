import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../access/access_widgets.dart' show failureMessage, formatMoment, pickMoment, showFailure;
import '../api/access_repository.dart' show ApiPage;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/popups_repository.dart';
import '../ui/tgcg_design.dart';
import 'popup_post_dialog.dart';

typedef PopupImage = ({Uint8List bytes, String name});
typedef PickPopupImage = Future<PopupImage?> Function();

/// A picture from the gallery, sized for a phone screen to keep it small.
Future<PopupImage?> pickPopupImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
  );
  return file == null ? null : (bytes: await file.readAsBytes(), name: file.name);
}

(String, Color) _stateOf(PopupPost post) => switch (post.state) {
  'showing' => ('Showing', TgcgColors.success),
  'scheduled' => ('Starts later', TgcgColors.info),
  'ended' => ('Ended', TgcgColors.muted),
  _ => ('Stopped', TgcgColors.danger),
};

/// Pop-up messages to everyone, for those whose role allows them nationwide.
class PopupsPage extends StatefulWidget {
  const PopupsPage({super.key, this.pickImage = pickPopupImage});

  final PickPopupImage pickImage;

  @override
  State<PopupsPage> createState() => _PopupsPageState();
}

class _PopupsPageState extends State<PopupsPage> {
  Future<ApiPage<PopupPost>>? _posts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _posts ??= TgcgBackend.of(context)?.popups.posted();
  }

  void _reload() => setState(() {
    _posts = TgcgBackend.of(context)?.popups.posted();
  });

  Future<void> _new() async {
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopupFormDialog(pickImage: widget.pickImage),
    );
    if (posted == true && mounted) _reload();
  }

  Future<void> _stop(PopupPost post) async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop this message?'),
        content: Text(post.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop it'),
          ),
        ],
      ),
    );
    if (stop != true || !mounted) return;
    try {
      await TgcgBackend.of(context)!.popups.stop(post.id);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      padding: tgcgPagePadding(constraints.maxWidth, bottom: 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'COMMUNICATIONS',
          title: 'Pop-up Messages',
          subtitle: 'Messages everyone sees on signing in.',
          trailing: FilledButton.icon(
            onPressed: _new,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('New message'),
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<ApiPage<PopupPost>>(
          future: _posts,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TgcgEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'The messages could not be loaded',
                message: failureMessage(snapshot.error!),
                action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            final posts = snapshot.data?.items;
            if (posts == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            if (posts.isEmpty) {
              return const TgcgEmptyState(
                icon: Icons.campaign_outlined,
                title: 'No messages yet',
                message: 'Messages you post appear here.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final post in posts) ...[
                  _PostCard(post: post, onStop: () => _stop(post)),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onStop});

  final PopupPost post;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final (state, color) = _stateOf(post);
    final live = post.state == 'showing' || post.state == 'scheduled';
    return TgcgSectionCard(
      key: ValueKey('popup-${post.id}'),
      padding: const EdgeInsets.all(16),
      title: post.title,
      subtitle: [
        popupFrequencyLabel(post.frequency),
        if (post.startsAt case final start?) 'From ${formatMoment(start)}',
        if (post.endsAt case final end?) 'until ${formatMoment(end)}',
        if (post.author.isNotEmpty) post.author,
      ].join(' · '),
      trailing: TgcgStatusPill(label: state, color: color, compact: true),
      trailingBeside: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (post.hasPicture) PopupPicture(id: post.id),
          SelectableText(post.body, style: TgcgType.body),
          if (post.hasLink) ...[
            const SizedBox(height: 6),
            Text('${post.linkLabel}: ${post.linkUrl}', style: TgcgType.caption),
          ],
          if (live)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onStop, child: const Text('Stop')),
            ),
        ],
      ),
    );
  }
}

/// Writes a new message; closes with true once it is posted.
class PopupFormDialog extends StatefulWidget {
  const PopupFormDialog({super.key, this.pickImage = pickPopupImage});

  final PickPopupImage pickImage;

  @override
  State<PopupFormDialog> createState() => _PopupFormDialogState();
}

class _PopupFormDialogState extends State<PopupFormDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _linkLabel = TextEditingController();
  final _linkUrl = TextEditingController();
  String _frequency = 'daily';
  PopupImage? _image;
  DateTime? _startsAt;
  DateTime? _endsAt;
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  static const _fields = [
    'title',
    'body',
    'frequency',
    'picture',
    'link_url',
    'link_label',
    'starts_at',
    'ends_at',
  ];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _linkLabel.dispose();
    _linkUrl.dispose();
    super.dispose();
  }

  bool get _ready => !_saving && _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;

  Future<void> _pick() async {
    final image = await widget.pickImage();
    if (image != null && mounted) setState(() => _image = image);
  }

  void _preview() => showDialog<void>(
    context: context,
    builder: (_) => PopupPostDialog(
      post: PopupPost(
        id: 'preview',
        title: _title.text.trim(),
        body: _body.text.trim(),
        frequency: _frequency,
        linkUrl: _linkUrl.text.trim(),
        linkLabel: _linkLabel.text.trim(),
      ),
      picture: _image?.bytes,
      openLink: (_) async => false,
    ),
  );

  Future<void> _post() async {
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    try {
      await TgcgBackend.of(context)!.popups.post(
        title: _title.text,
        body: _body.text,
        frequency: _frequency,
        picture: _image,
        linkUrl: _linkUrl.text,
        linkLabel: _linkLabel.text,
        startsAt: _startsAt,
        endsAt: _endsAt,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final fields = <String, String>{
        if (error is ApiException)
          for (final field in _fields)
            if (error.fieldError(field) case final message?) field: message,
      };
      setState(() {
        _saving = false;
        _errors = fields;
        _error = fields.isEmpty ? failureMessage(error) : null;
      });
    }
  }

  Widget _moment(
    String label,
    String empty,
    DateTime? value,
    String field,
    ValueChanged<DateTime?> set,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      _errors[field] ?? (value == null ? empty : formatMoment(value)),
      style: TextStyle(color: _errors.containsKey(field) ? TgcgColors.danger : null),
    ),
    trailing: Wrap(
      children: [
        if (value != null)
          TextButton(onPressed: () => setState(() => set(null)), child: const Text('Clear')),
        TextButton(
          onPressed: () async {
            final moment = await pickMoment(context, value);
            if (moment != null) setState(() => set(moment));
          },
          child: const Text('Choose'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return AlertDialog(
      title: const Text('New pop-up message'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                maxLength: 160,
                decoration: InputDecoration(labelText: 'Title', errorText: _errors['title']),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: InputDecoration(labelText: 'Message', errorText: _errors['body']),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              if (image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(TgcgRadius.sm),
                  child: Image.memory(image.bytes, height: 150, fit: BoxFit.cover),
                ),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(image == null ? 'Add a picture' : 'Change the picture'),
                  ),
                  if (image != null)
                    TextButton(
                      onPressed: () => setState(() => _image = null),
                      child: const Text('Remove the picture'),
                    ),
                ],
              ),
              if (_errors['picture'] case final problem?)
                Text(problem, style: const TextStyle(color: TgcgColors.danger)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('popup-frequency'),
                initialValue: _frequency,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'How often each person sees it',
                  errorText: _errors['frequency'],
                ),
                items: [
                  for (final (code, label) in popupFrequencies)
                    DropdownMenuItem(value: code, child: Text(label)),
                ],
                onChanged: (value) => setState(() => _frequency = value ?? _frequency),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _linkLabel,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: 'Words on a button (optional)',
                  errorText: _errors['link_label'],
                ),
              ),
              TextField(
                controller: _linkUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Link the button opens',
                  hintText: 'https://',
                  errorText: _errors['link_url'],
                ),
              ),
              const SizedBox(height: 6),
              _moment('Starts', 'As soon as it is posted', _startsAt, 'starts_at', (value) {
                _startsAt = value;
              }),
              _moment('Ends', 'When you stop it', _endsAt, 'ends_at', (value) {
                _endsAt = value;
              }),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _ready ? _preview : null, child: const Text('Preview')),
        FilledButton(
          onPressed: _ready ? _post : null,
          child: Text(_saving ? 'Posting' : 'Post to everyone'),
        ),
      ],
    );
  }
}
