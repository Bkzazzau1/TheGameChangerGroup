import 'dart:async';
import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

/// The photo turned back the right way round. Browsers mirror the picture
/// of any camera that is not a back camera, as for a selfie (a laptop's
/// webcam among them), and a card's text then reads backwards. Saved as a
/// JPEG, as the camera's own picture is, so it stays well under the
/// server's 8 MB for a card photo.
Future<XFile> unmirrored(XFile photo, {required String name}) async {
  final image = web.HTMLImageElement()..src = photo.path;
  await image.decode().toDart;
  final canvas = web.HTMLCanvasElement()
    ..width = image.naturalWidth
    ..height = image.naturalHeight;
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context
    ..translate(canvas.width, 0)
    ..scale(-1, 1)
    ..drawImage(image, 0, 0);
  final done = Completer<web.Blob?>();
  canvas.toBlob(
    ((web.Blob? blob) {
      done.complete(blob);
    }).toJS,
    'image/jpeg',
    0.92.toJS,
  );
  final blob = await done.future;
  if (blob == null) return photo;
  return XFile(
    web.URL.createObjectURL(blob),
    name: name,
    mimeType: 'image/jpeg',
    length: blob.size,
  );
}
