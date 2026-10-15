import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'playable_media_io.dart' if (dart.library.js_interop) 'playable_media_web.dart' as platform;

/// Downloaded video or sound, ready to play; [release] frees what playing needed.
typedef PlayableMedia = (VideoPlayerController controller, Future<void> Function() release);

/// Plays [bytes] already fetched with the session's token: the server never
/// hands out a link that works without it.
Future<PlayableMedia> playableMedia(Uint8List bytes, {required String id, required String mimeType}) =>
    platform.playableMedia(bytes, id: id, mimeType: mimeType);
