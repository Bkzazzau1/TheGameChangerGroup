import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// The web plays from an in-memory link to the downloaded bytes.
Future<(VideoPlayerController, Future<void> Function())> playableVideo(
  Uint8List bytes, {
  required String id,
  required String mimeType,
}) async {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  return (
    VideoPlayerController.networkUrl(Uri.parse(url)),
    () async => web.URL.revokeObjectURL(url),
  );
}
