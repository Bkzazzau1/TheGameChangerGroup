import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Phones and desktops play from a file in the app's own temporary folder,
/// deleted when it is closed.
Future<(VideoPlayerController, Future<void> Function())> playableMedia(
  Uint8List bytes, {
  required String id,
  required String mimeType,
}) async {
  final folder = await getTemporaryDirectory();
  final extension = switch (mimeType) {
    'video/quicktime' => '.mov',
    'video/3gpp' => '.3gp',
    'video/webm' => '.webm',
    'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' => '.m4a',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => '.wav',
    'audio/mpeg' => '.mp3',
    'audio/aac' => '.aac',
    'audio/ogg' => '.ogg',
    _ => '.mp4',
  };
  final file = File('${folder.path}${Platform.pathSeparator}tgcg-media-$id$extension');
  await file.writeAsBytes(bytes, flush: true);
  return (
    VideoPlayerController.file(file),
    () async {
      if (await file.exists()) await file.delete();
    },
  );
}
