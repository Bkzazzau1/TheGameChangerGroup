import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/backend.dart';
import '../api/forum_repository.dart';
import '../media/media_player_page.dart';
import '../media/video_poster.dart';
import '../ui/tgcg_design.dart';

/// Where a new post's pictures and videos come from.
enum ForumMediaSource { photo, video, gallery }

typedef PickForumMedia = Future<List<ForumUpload>> Function(ForumMediaSource source);

/// As on the server: FORUM_MAX_VIDEO_MB, FORUM_MAX_POST_MB, FORUM_MAX_ATTACHMENTS.
const forumMaxVideoBytes = 50 * 1024 * 1024;
const forumMaxPostBytes = 100 * 1024 * 1024;
const forumMaxFiles = 10;

/// Takes a picture, records a video (up to two minutes) or chooses from the
/// gallery. Pictures are sized for a phone screen to keep uploads small;
/// videos get a picture taken from them.
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
  final uploads = [
    for (final file in files) ?forumUploadFrom(file.name, await file.readAsBytes()),
  ];
  return [for (final upload in uploads) await withVideoPoster(upload)];
}

/// A video with a picture taken from it, sent with it so the feed shows it
/// before anyone plays it. Pictures, and videos this device cannot read,
/// stay as they are.
Future<ForumUpload> withVideoPoster(ForumUpload upload, {MakeVideoPoster makePoster = videoPoster}) async {
  if (upload.kind != ForumMediaKind.video) return upload;
  final poster = await makePoster(
    upload.bytes,
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    mimeType: upload.mimeType,
  );
  return poster == null ? upload : upload.withPoster(poster);
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

/// Videos without a picture on the server (posted before 26 October 2026, or
/// from an older app) up to this size are fetched to take one here.
const forumPosterFromVideoBytes = 5 * 1024 * 1024;

/// The tallest a video stands in a post.
const forumVideoMaxHeight = 420.0;

/// Pictures of videos seen recently, from the server or taken here.
final _posters = <String, Future<VideoPoster?>>{};

/// The ones already at hand, so a video scrolled back into view shows its
/// picture at once.
final _postersReady = <String, VideoPoster>{};

/// Small videos fetched for their picture, kept so playing one does not
/// fetch it again.
final _videos = <String, Future<Uint8List>>{};

Future<VideoPoster?> _posterOf(ForumRepository forum, ForumAttachment video, MakeVideoPoster make) {
  final poster = _posters.remove(video.id) ?? _fetchPoster(forum, video, make);
  _posters[video.id] = poster;
  if (_posters.length > 40) _posters.remove(_posters.keys.first);
  return poster;
}

Future<VideoPoster?> _fetchPoster(ForumRepository forum, ForumAttachment video, MakeVideoPoster make) async {
  try {
    final VideoPoster? poster;
    if (video.hasPoster) {
      poster = VideoPoster(
        jpeg: await forum.poster(video.id),
        width: video.width,
        height: video.height,
        duration: video.duration,
      );
    } else if (video.size > forumPosterFromVideoBytes) {
      return null;
    } else {
      final bytes = _videos.remove(video.id) ?? forum.attachment(video.id);
      _videos[video.id] = bytes;
      if (_videos.length > 3) _videos.remove(_videos.keys.first);
      poster = await make(await bytes, id: video.id, mimeType: video.mimeType);
    }
    if (poster != null) {
      _postersReady[video.id] = poster;
      if (_postersReady.length > 40) _postersReady.remove(_postersReady.keys.first);
    }
    return poster;
  } catch (_) {
    // Tried again the next time the video is shown.
    _posters.remove(video.id);
    _videos.remove(video.id);
    return null;
  }
}

/// A post's video, showing a picture from it and how long it runs: tapped,
/// it downloads and plays. Upright phone videos stand upright.
class ForumVideoTile extends StatefulWidget {
  const ForumVideoTile({super.key, required this.attachment, this.makePoster = videoPoster});

  final ForumAttachment attachment;

  /// Takes a picture from a video without one on the server (replaced in tests).
  final MakeVideoPoster makePoster;

  @override
  State<ForumVideoTile> createState() => _ForumVideoTileState();
}

class _ForumVideoTileState extends State<ForumVideoTile> {
  Future<VideoPoster?>? _poster;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = TgcgBackend.of(context);
    if (backend != null) _poster ??= _posterOf(backend.forum, widget.attachment, widget.makePoster);
  }

  void _play(VideoPoster? poster) {
    final forum = TgcgBackend.of(context)!.forum;
    final video = widget.attachment;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaPlayerPage(
          title: 'Video',
          id: video.id,
          mimeType: video.mimeType,
          cover: poster?.jpeg,
          load: () => _videos[video.id] ?? forum.attachment(video.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VideoPoster?>(
    future: _poster,
    initialData: _postersReady[widget.attachment.id],
    builder: (context, snapshot) {
      final video = widget.attachment;
      final poster = snapshot.data;
      final width = poster != null && poster.width > 0 ? poster.width : video.width;
      final height = poster != null && poster.height > 0 ? poster.height : video.height;
      final ratio = width > 0 && height > 0 ? width / height : 16 / 9;
      final duration = video.duration ?? poster?.duration;
      return LayoutBuilder(
        builder: (context, constraints) {
          final full = constraints.maxWidth;
          final tall = math.min(full / ratio, forumVideoMaxHeight);
          final wide = math.min(full, tall * ratio);
          return Semantics(
            button: true,
            label: 'Play video',
            child: Material(
              color: TgcgColors.primaryDark,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _play(poster),
                child: SizedBox(
                  height: tall,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null) ...[
                        // An upright or narrow video: the same picture,
                        // blurred, fills the sides.
                        if (wide < full - 1) ...[
                          ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            child: Image.memory(poster.jpeg, fit: BoxFit.cover, gaplessPlayback: true),
                          ),
                          const ColoredBox(color: Color(0x59000000)),
                        ],
                        Center(
                          child: SizedBox(
                            width: wide,
                            height: tall,
                            child: Image.memory(
                              poster.jpeg,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                      // Shade at the bottom, so the length reads on any picture.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.6, 1],
                            colors: [Color(0x00000000), Color(0x99000000)],
                          ),
                        ),
                      ),
                      const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color(0x8C000000), shape: BoxShape.circle),
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 10,
                        child: Text(
                          '${duration == null ? 'Video' : videoLength(duration)} • ${megabytes(video.size)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (poster == null && snapshot.connectionState == ConnectionState.waiting)
                        const Positioned(
                          right: 12,
                          bottom: 12,
                          child: SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
