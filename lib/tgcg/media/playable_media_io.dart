import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Phones and desktops play from a file in the app's own temporary folder,
/// deleted when the video is closed.
Future<(VideoPlayerController, Future<void> Function())> playableVideo(
  Uint8List bytes, {
  required String id,
  required String mimeType,
}) async {
  final folder = await getTemporaryDirectory();
  final extension = switch (mimeType) {
    'video/quicktime' => '.mov',
    'video/3gpp' => '.3gp',
    'video/webm' => '.webm',
    _ => '.mp4',
  };
  final file = File('${folder.path}${Platform.pathSeparator}forum-$id$extension');
  await file.writeAsBytes(bytes, flush: true);
  return (
    VideoPlayerController.file(file),
    () async {
      if (await file.exists()) await file.delete();
    },
  );
}
