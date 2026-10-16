import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Phones open the share sheet with the file; a computer keeps it in its
/// Downloads folder.
Future<String?> saveDownload(Uint8List bytes, String name, String mimeType) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
        fileNameOverrides: [name],
      ),
    );
    return null;
  }
  final folder = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${folder.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
