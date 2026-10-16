import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser downloads the bytes through an in-memory link.
Future<String?> saveDownload(Uint8List bytes, String name, String mimeType) async {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(link);
  link.click();
  link.remove();
  // Give the browser a moment to start the download before the link goes.
  Future<void>.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return null;
}
