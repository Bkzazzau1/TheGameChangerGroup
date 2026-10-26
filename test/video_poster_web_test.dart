@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/media/video_poster.dart';
import 'package:web/web.dart' as web;

/// A real video made by the browser: a green canvas, recorded for a second.
Future<Uint8List> _recordVideo({required int width, required int height}) async {
  final canvas = web.HTMLCanvasElement()
    ..width = width
    ..height = height;
  final paint = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  final stream = canvas.captureStream(25);
  final recorder = web.MediaRecorder(stream, web.MediaRecorderOptions(mimeType: 'video/webm'));
  final parts = <web.Blob>[];
  final stopped = Completer<void>();
  recorder.ondataavailable = ((web.BlobEvent event) => parts.add(event.data)).toJS;
  recorder.onstop = ((web.Event _) => stopped.complete()).toJS;
  var frame = 0;
  final drawing = Timer.periodic(const Duration(milliseconds: 40), (_) {
    paint.fillStyle = 'rgb(0, ${120 + frame++ % 100}, 60)'.toJS;
    paint.fillRect(0, 0, width, height);
  });
  recorder.start(100);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  recorder.stop();
  await stopped.future;
  drawing.cancel();
  final video = web.Blob(parts.toJS, web.BlobPropertyBag(type: 'video/webm'));
  return (await video.arrayBuffer().toDart).toDart.asUint8List();
}

void main() {
  test('the browser takes a picture from a real video, upright and the right shape', () async {
    final video = await _recordVideo(width: 240, height: 320);
    expect(video.length, greaterThan(100));

    final poster = await videoPoster(video, id: 'test', mimeType: 'video/webm');

    expect(poster, isNotNull);
    expect((poster!.width, poster.height), (240, 320));
    // A JPEG.
    expect(poster.jpeg.sublist(0, 3), [0xff, 0xd8, 0xff]);
  });

  test('something that is not a video gives no picture', () async {
    final poster = await videoPoster(Uint8List.fromList(List.filled(64, 7)), id: 'junk', mimeType: 'video/mp4');
    expect(poster, isNull);
  });
}
