import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'video_source_io.dart' if (dart.library.js_interop) 'video_source_web.dart' as platform;

/// A downloaded video, ready to play; [release] frees what playing needed.
typedef PlayableVideo = (VideoPlayerController controller, Future<void> Function() release);

/// Plays [bytes] already fetched with the session's token: the server never
/// hands out a link that works without it.
Future<PlayableVideo> playableVideo(Uint8List bytes, {required String id, required String mimeType}) =>
    platform.playableVideo(bytes, id: id, mimeType: mimeType);
