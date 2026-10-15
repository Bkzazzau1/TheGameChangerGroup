import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../access/access_widgets.dart' show failureMessage;
import '../api/backend.dart';
import '../api/forum_repository.dart';
import '../ui/tgcg_design.dart';
import 'video_source.dart';

/// Where a new post's pictures and videos come from.
enum ForumMediaSource { photo, video, gallery }

typedef PickForumMedia = Future<List<ForumUpload>> Function(ForumMediaSource source);

/// As on the server: FORUM_MAX_VIDEO_MB, FORUM_MAX_POST_MB, FORUM_MAX_ATTACHMENTS.
const forumMaxVideoBytes = 50 * 1024 * 1024;
const forumMaxPostBytes = 100 * 1024 * 1024;
const forumMaxFiles = 10;

/// Takes a picture, records a video (up to two minutes) or chooses from the
/// gallery. Pictures are sized for a phone screen to keep uploads small.
Future<List<ForumUpload>> pickForumMedia(ForumMediaSource source, {ImagePicker? picker}) async {
  final picking = picker ?? ImagePicker();
  final files = switch (source) {
    ForumMediaSource.photo => [
      ?await picking.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      ),
    ],
    ForumMediaSource.video => [
      ?await picking.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 2),
      ),
    ],
    ForumMediaSource.gallery => await picking.pickMultipleMedia(
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    ),
  };
  return [
    for (final file in files) ?forumUploadFrom(file.name, await file.readAsBytes()),
  ];
}

/// What a file really is, from its first bytes; null when the forum does not
/// take it. The server checks the same bytes against the name's extension.
(ForumMediaKind, String mime, String extension)? _sniff(Uint8List bytes) {
  bool starts(List<int> prefix, [int offset = 0]) =>
      bytes.length >= offset + prefix.length &&
      [for (var i = 0; i < prefix.length; i++) bytes[offset + i] == prefix[i]].every((same) => same);
  const photo = ForumMediaKind.photo;
  const video = ForumMediaKind.video;
  if (starts([0xff, 0xd8, 0xff])) return (photo, 'image/jpeg', '.jpg');
  if (starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return (photo, 'image/png', '.png');
  if (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) {
    return (photo, 'image/webp', '.webp');
  }
  if (starts([0x1a, 0x45, 0xdf, 0xa3])) return (video, 'video/webm', '.webm');
  if (starts(ascii.encode('ftyp'), 4) && bytes.length >= 12) {
    final brand = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
    const heic = ['heic', 'heix', 'heis', 'hevc', 'hevx', 'mif1', 'msf1'];
    if (heic.contains(brand)) return (photo, 'image/heic', '.heic');
    if (brand == 'qt  ') return (video, 'video/quicktime', '.mov');
    if (brand.startsWith('3g')) return (video, 'video/3gpp', '.3gp');
    return (video, 'video/mp4', '.mp4');
  }
  return null;
}

/// A picture or video for a new post, named with the extension of what it
/// really is; null when it is neither.
ForumUpload? forumUploadFrom(String name, Uint8List bytes) {
  final sniffed = _sniff(bytes);
  if (sniffed == null) return null;
  final (kind, mime, extension) = sniffed;
  var stem = name.split(RegExp(r'[\\/]')).last.trim();
  final dot = stem.lastIndexOf('.');
  if (dot > 0) stem = stem.substring(0, dot);
  if (stem.isEmpty) stem = kind == ForumMediaKind.photo ? 'picture' : 'video';
  return ForumUpload(kind: kind, fileName: '$stem$extension', mimeType: mime, bytes: bytes);
}

String megabytes(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Downloads of pictures seen recently, so scrolling does not fetch them again.
final _photos = <String, Future<Uint8List>>{};

Future<Uint8List> _photo(BuildContext context, String id) {
  final cached = _photos.remove(id);
  final bytes = cached ?? TgcgBackend.of(context)!.forum.attachment(id);
  _photos[id] = bytes;
  if (_photos.length > 60) _photos.remove(_photos.keys.first);
  return bytes;
}

/// A post's pictures and videos.
class ForumMediaGrid extends StatelessWidget {
  const ForumMediaGrid({super.key, required this.attachments});

  final List<ForumAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final photos = [for (final item in attachments) if (item.kind == ForumMediaKind.photo) item];
    final videos = [for (final item in attachments) if (item.kind == ForumMediaKind.video) item];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photos.length == 1)
          AspectRatio(aspectRatio: 4 / 3, child: ForumPhoto(attachment: photos.single))
        else if (photos.isNotEmpty)
          GridView.count(
            crossAxisCount: photos.length == 2 || photos.length == 4 ? 2 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [for (final photo in photos) ForumPhoto(attachment: photo)],
          ),
        for (final video in videos) ...[
          if (photos.isNotEmpty || video != videos.first) const SizedBox(height: 6),
          ForumVideoTile(attachment: video),
        ],
      ],
    );
  }
}

/// A post's picture; tapped, it opens full screen.
class ForumPhoto extends StatefulWidget {
  const ForumPhoto({super.key, required this.attachment});

  final ForumAttachment attachment;

  @override
  State<ForumPhoto> createState() => _ForumPhotoState();
}

class _ForumPhotoState extends State<ForumPhoto> {
  Future<Uint8List>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TgcgBackend.of(context) != null) _bytes ??= _photo(context, widget.attachment.id);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return ColoredBox(
            color: TgcgColors.surfaceSoft,
            child: Center(
              child: snapshot.hasError
                  ? const Icon(Icons.broken_image_outlined, color: TgcgColors.muted)
                  : const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          );
        }
        return Semantics(
          label: 'Picture',
          button: true,
          child: GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                backgroundColor: Colors.black,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(child: Center(child: Image.memory(bytes))),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        tooltip: 'Close',
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        );
      },
    ),
  );
}

/// A post's video: tapped, it downloads and plays.
class ForumVideoTile extends StatelessWidget {
  const ForumVideoTile({super.key, required this.attachment});

  final ForumAttachment attachment;

  @override
  Widget build(BuildContext context) => Material(
    color: TgcgColors.primaryDark,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ForumVideoPage(attachment: attachment)),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          children: [
            const Center(
              child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 56),
            ),
            Positioned(
              left: 12,
              bottom: 10,
              child: Text(
                'Video • ${megabytes(attachment.size)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ForumVideoPage extends StatefulWidget {
  const ForumVideoPage({super.key, required this.attachment});

  final ForumAttachment attachment;

  @override
  State<ForumVideoPage> createState() => _ForumVideoPageState();
}

class _ForumVideoPageState extends State<ForumVideoPage> {
  VideoPlayerController? _controller;
  Future<void> Function()? _release;
  Object? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _open();
  }

  Future<void> _open() async {
    try {
      final attachment = widget.attachment;
      final bytes = await TgcgBackend.of(context)!.forum.attachment(attachment.id);
      final (controller, release) = await playableVideo(
        bytes,
        id: attachment.id,
        mimeType: attachment.mimeType,
      );
      _release = release;
      if (!mounted) {
        await release();
        return;
      }
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        await release();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    final release = _release;
    controller?.dispose().then((_) => release?.call());
    if (controller == null) release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Video'),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'The video could not be played. ${failureMessage(_error!)}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              )
            : controller == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                  VideoProgressIndicator(controller, allowScrubbing: true),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => IconButton(
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      color: Colors.white,
                      iconSize: 40,
                      onPressed: value.isPlaying ? controller.pause : controller.play,
                      icon: Icon(
                        value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
