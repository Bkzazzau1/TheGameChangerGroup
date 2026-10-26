import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'video_poster.dart';

/// The longest side of a picture taken from a video.
const _side = 720;

/// The browser plays the video silently off screen and draws a frame onto a
/// canvas.
Future<VideoPoster?> videoPoster(Uint8List video, {required String id, required String mimeType}) async {
  final url = web.URL.createObjectURL(web.Blob(<JSAny>[video.toJS].toJS, web.BlobPropertyBag(type: mimeType)));
  final player = web.HTMLVideoElement()
    ..muted = true
    ..playsInline = true
    ..preload = 'auto';
  try {
    final loaded = _next(player, 'loadeddata');
    player.src = url;
    await loaded;
    final seconds = player.duration;
    final length = seconds.isFinite && seconds > 0 ? seconds : 0.0;
    // A second in, or a tenth of a shorter clip: the very first frame is
    // often black.
    final at = math.min(1.0, length / 10);
    if (at > 0) {
      final seeked = _next(player, 'seeked');
      player.currentTime = at;
      await seeked;
    }
    final width = player.videoWidth;
    final height = player.videoHeight;
    if (width == 0 || height == 0) return null;
    final scale = math.min(1.0, _side / math.max(width, height));
    final canvas = web.HTMLCanvasElement()
      ..width = (width * scale).round()
      ..height = (height * scale).round();
    (canvas.getContext('2d')! as web.CanvasRenderingContext2D).drawImage(player, 0, 0, canvas.width, canvas.height);
    final data = canvas.toDataURL('image/jpeg', 0.8.toJS);
    final comma = data.indexOf(',');
    if (!data.startsWith('data:image/jpeg') || comma < 0) return null;
    return VideoPoster(
      jpeg: base64Decode(data.substring(comma + 1)),
      width: width,
      height: height,
      duration: length > 0 ? Duration(milliseconds: (length * 1000).round()) : null,
    );
  } finally {
    player.removeAttribute('src');
    player.load();
    web.URL.revokeObjectURL(url);
  }
}

/// The video's next [event], or its failure to load.
Future<void> _next(web.HTMLVideoElement player, String event) {
  final done = Completer<void>();
  final onEvent = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  final onError = ((web.Event _) {
    if (!done.isCompleted) done.completeError(StateError('This browser cannot read the video.'));
  }).toJS;
  player.addEventListener(event, onEvent);
  player.addEventListener('error', onError);
  return done.future.whenComplete(() {
    player.removeEventListener(event, onEvent);
    player.removeEventListener('error', onError);
  });
}
