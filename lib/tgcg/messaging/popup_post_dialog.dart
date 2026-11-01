import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/backend.dart';
import '../api/popups_repository.dart';
import '../askme/ask_me_chat.dart' show openSourceInBrowser;
import '../election/follow_ups.dart';
import '../ui/tgcg_design.dart';

/// A posted message as people see it: its picture, words and button, then
/// whatever they have to follow up.
class PopupPostDialog extends StatelessWidget {
  const PopupPostDialog({
    super.key,
    required this.post,
    this.picture,
    this.followUps = const FollowUps([], complete: true),
    this.onFollow,
    this.openLink = openSourceInBrowser,
  });

  final PopupPost post;
  final Uint8List? picture;
  final FollowUps followUps;
  final ValueChanged<FollowUp>? onFollow;

  /// Opens the button's link (replaced in tests).
  final Future<bool> Function(Uri uri) openLink;

  @override
  Widget build(BuildContext context) {
    final bytes = picture;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (bytes != null)
                      Image.memory(
                        bytes,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(post.title, style: TgcgType.title),
                          const SizedBox(height: 8),
                          SelectableText(post.body, style: TgcgType.body),
                          if (followUps.items.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('TO FOLLOW UP', style: TgcgType.eyebrow),
                            const SizedBox(height: 8),
                            TgcgRowGroup(
                              children: [
                                for (final item in followUps.items)
                                  TgcgActionRow(
                                    icon: item.icon,
                                    color: TgcgColors.accentDeep,
                                    title: item.title,
                                    detail: item.detail,
                                    onTap: () => onFollow?.call(item),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  if (post.hasLink) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => openLink(Uri.parse(post.linkUrl)),
                        child: Text(post.linkLabel, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A posted message's picture, fetched once; nothing shows if it cannot be.
class PopupPicture extends StatefulWidget {
  const PopupPicture({super.key, required this.id, this.height = 160});

  final String id;
  final double height;

  @override
  State<PopupPicture> createState() => _PopupPictureState();
}

class _PopupPictureState extends State<PopupPicture> {
  Future<Uint8List>? _picture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _picture ??= TgcgBackend.of(context)?.popups.picture(widget.id);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _picture,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          child: Image.memory(
            bytes,
            height: widget.height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
    },
  );
}
