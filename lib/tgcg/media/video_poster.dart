import 'dart:typed_data';

import 'video_poster_io.dart' if (dart.library.js_interop) 'video_poster_web.dart' as platform;

/// A picture from a video, with the video's shape and length.
class VideoPoster {
  const VideoPoster({required this.jpeg, required this.width, required this.height, this.duration});

  final Uint8List jpeg;

  /// The video's own size, upright as it plays.
  final int width;
  final int height;
  final Duration? duration;
}

typedef MakeVideoPoster = Future<VideoPoster?> Function(Uint8List video, {required String id, required String mimeType});

/// A frame from about a second into [video]; null when this device cannot
/// read it (the video still plays).
Future<VideoPoster?> videoPoster(Uint8List video, {required String id, required String mimeType}) async {
  try {
    return await platform.videoPoster(video, id: id, mimeType: mimeType).timeout(const Duration(seconds: 20));
  } catch (_) {
    return null;
  }
}

/// How long a video runs, as m:ss (or h:mm:ss).
String videoLength(Duration value) {
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  if (value.inHours > 0) {
    return '${value.inHours}:${(value.inMinutes % 60).toString().padLeft(2, '0')}:$seconds';
  }
  return '${value.inMinutes}:$seconds';
}
