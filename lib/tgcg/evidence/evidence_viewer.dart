import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show formatMoment;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../domain/models.dart';
import '../ui/tgcg_design.dart';
import 'evidence_upload.dart';

final _serverId = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// On the server (not still on this device), and a picture the app shows.
bool canShowEvidence(EvidenceAttachment evidence) =>
    _serverId.hasMatch(evidence.id) &&
    (evidence.type == EvidenceType.photo || evidence.type == EvidenceType.resultForm) &&
    (evidence.mimeType?.startsWith('image/') ?? true);

/// Opens a photo or result sheet from the server, which checks that you may
/// see it (your own, or evidence in your areas).
Future<void> showEvidence(BuildContext context, EvidenceAttachment evidence) => showDialog<void>(
      context: context,
      builder: (_) => _EvidenceDialog(evidence: evidence),
    );

class _EvidenceDialog extends StatefulWidget {
  const _EvidenceDialog({required this.evidence});

  final EvidenceAttachment evidence;

  @override
  State<_EvidenceDialog> createState() => _EvidenceDialogState();
}

class _EvidenceDialogState extends State<_EvidenceDialog> {
  Future<Uint8List>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= TgcgBackend.of(context)!
        .client
        .getBytes('evidence/${widget.evidence.id}/download/');
  }

  @override
  Widget build(BuildContext context) {
    final evidence = widget.evidence;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(evidence.fileName, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${evidence.type == EvidenceType.resultForm ? 'Result sheet' : 'Photo'} · '
                '${formatMoment(evidence.createdAt.toLocal())} · by ${evidence.uploaderId}',
              ),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Flexible(
              child: FutureBuilder<Uint8List>(
                future: _bytes,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final error = snapshot.error;
                    return _Message(
                      error is ApiException ? error.message : 'The photo could not be loaded.',
                    );
                  }
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return InteractiveViewer(
                    maxScale: 6,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const _Message('This photo cannot be shown on this device.'),
                    ),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Pinch or scroll to zoom.',
                style: TextStyle(color: TgcgColors.muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center),
      );
}

/// Picks a photo; tests replace the device's camera and gallery.
typedef PickPhoto = Future<PendingEvidence?> Function({
  required EvidenceType type,
  required bool camera,
});

/// Photos for a new record: taken with the camera or chosen, shown small,
/// each removable before saving.
class EvidencePhotoPicker extends StatefulWidget {
  const EvidencePhotoPicker({
    super.key,
    required this.photos,
    required this.onChanged,
    this.type = EvidenceType.photo,
    this.label = 'Photos',
    this.hint,
    this.max = 3,
    this.pick = pickEvidencePhoto,
  });

  final List<PendingEvidence> photos;
  final ValueChanged<List<PendingEvidence>> onChanged;
  final EvidenceType type;
  final String label;
  final String? hint;
  final int max;
  final PickPhoto pick;

  @override
  State<EvidencePhotoPicker> createState() => _EvidencePhotoPickerState();
}

class _EvidencePhotoPickerState extends State<EvidencePhotoPicker> {
  bool _busy = false;

  Future<void> _add({required bool camera}) async {
    setState(() => _busy = true);
    try {
      final photo = await widget.pick(type: widget.type, camera: camera);
      if (photo != null && mounted) widget.onChanged([...widget.photos, photo]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The photo could not be taken: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.photos.length >= widget.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
        ),
        if (widget.hint != null)
          Text(widget.hint!, style: const TextStyle(color: TgcgColors.muted, fontSize: 11)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (index, photo) in widget.photos.indexed)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      photo.bytes,
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 76,
                        height: 76,
                        color: TgcgColors.surfaceSoft,
                        child: const Icon(Icons.image_outlined, color: TgcgColors.muted),
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
                      onPressed: () =>
                          widget.onChanged([...widget.photos]..removeAt(index)),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            if (!full) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _add(camera: true),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take photo'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _add(camera: false),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Choose photo'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
