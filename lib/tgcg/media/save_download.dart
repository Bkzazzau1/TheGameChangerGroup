import 'dart:typed_data';

import 'save_download_io.dart' if (dart.library.js_interop) 'save_download_web.dart' as platform;

/// Hands a downloaded file to the person: the browser saves it; a phone
/// offers its share sheet (save to Files or Drive, print, send); a computer
/// saves it in Downloads. Returns where it was saved, when that is known.
typedef SaveDownload = Future<String?> Function(Uint8List bytes, String name, String mimeType);

Future<String?> saveDownload(Uint8List bytes, String name, String mimeType) =>
    platform.saveDownload(bytes, name, mimeType);
