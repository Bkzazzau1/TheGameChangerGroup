import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'video_poster.dart';

/// Android reads the frame (MainActivity, with MediaMetadataRetriever).
const _channel = MethodChannel('tgcg/video_poster');

/// Only Android takes pictures from videos; elsewhere there are none.
Future<VideoPoster?> videoPoster(Uint8List video, {required String id, required String mimeType}) async {
  if (!Platform.isAndroid) return null;
  final folder = await getTemporaryDirectory();
  final file = File('${folder.path}${Platform.pathSeparator}tgcg-poster-$id');
  await file.writeAsBytes(video, flush: true);
  try {
    final found = await _channel.invokeMapMethod<String, Object?>('poster', {'path': file.path});
    final jpeg = found?['jpeg'];
    if (found == null || jpeg is! Uint8List) return null;
    final milliseconds = (found['durationMs'] as num?)?.toInt() ?? 0;
    return VideoPoster(
      jpeg: jpeg,
      width: (found['width'] as num?)?.toInt() ?? 0,
      height: (found['height'] as num?)?.toInt() ?? 0,
      duration: milliseconds > 0 ? Duration(milliseconds: milliseconds) : null,
    );
  } on MissingPluginException {
    return null;
  } finally {
    if (await file.exists()) await file.delete();
  }
}
