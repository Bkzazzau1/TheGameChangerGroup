import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class PvcRecognitionResult {
  const PvcRecognitionResult({
    required this.imagePath,
    required this.imageName,
    required this.rawText,
    this.fullName,
    this.voterId,
  });

  final String imagePath;
  final String imageName;
  final String rawText;
  final String? fullName;
  final String? voterId;

  bool get hasRecognizedText => rawText.trim().isNotEmpty;
}

class PvcRecognitionService {
  PvcRecognitionService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<PvcRecognitionResult?> captureAndRecognize() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 94,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return null;
    return recognizeImage(image);
  }

  Future<PvcRecognitionResult?> pickAndRecognize() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    return recognizeImage(image);
  }

  Future<PvcRecognitionResult> recognizeImage(XFile image) async {
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) {
      return PvcRecognitionResult(
        imagePath: image.path,
        imageName: image.name,
        rawText: '',
      );
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      final text = recognized.text.trim();
      return PvcRecognitionResult(
        imagePath: image.path,
        imageName: image.name,
        rawText: text,
        fullName: _extractName(text),
        voterId: _extractVoterId(text),
      );
    } finally {
      await recognizer.close();
    }
  }

  static String? _extractVoterId(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final direct = RegExp(
        r'(?:VIN|VOTER\s*(?:ID|NUMBER)?)\s*[:#-]?\s*([A-Z0-9-]{8,30})',
        caseSensitive: false,
      ).firstMatch(line);
      if (direct != null) return direct.group(1)?.toUpperCase();
      if (RegExp(r'^(VIN|VOTER\s*(ID|NUMBER)?)$', caseSensitive: false)
              .hasMatch(line) &&
          i + 1 < lines.length) {
        final candidate = lines[i + 1].replaceAll(RegExp(r'\s+'), '');
        if (RegExp(r'^[A-Z0-9-]{8,30}$', caseSensitive: false)
            .hasMatch(candidate)) {
          return candidate.toUpperCase();
        }
      }
    }
    return null;
  }

  static String? _extractName(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final direct = RegExp(
        r"(?:NAME|FULL\s*NAME)\s*[:.-]?\s*([A-Z][A-Z .'-]{4,})",
        caseSensitive: false,
      ).firstMatch(line);
      if (direct != null) return _titleCase(direct.group(1)!.trim());
      if (RegExp(r'^(NAME|FULL\s*NAME)$', caseSensitive: false)
              .hasMatch(line) &&
          i + 1 < lines.length) {
        final candidate = lines[i + 1];
        if (_looksLikeName(candidate)) return _titleCase(candidate);
      }
    }
    return null;
  }

  static bool _looksLikeName(String value) {
    final words = value
        .replaceAll(RegExp(r"[^A-Za-z .'-]"), '')
        .trim()
        .split(RegExp(r'\s+'));
    return words.length >= 2 && words.every((word) => word.length >= 2);
  }

  static String _titleCase(String value) => value
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
