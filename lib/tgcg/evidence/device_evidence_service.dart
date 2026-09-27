import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../domain/models.dart';

class CapturedEvidence {
  const CapturedEvidence({
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
    this.path,
    this.contentHash,
    this.latitude,
    this.longitude,
  });

  final EvidenceType type;
  final String fileName;
  final String mimeType;
  final DateTime createdAt;
  final String? path;
  final String? contentHash;
  final double? latitude;
  final double? longitude;
}

class DeviceEvidenceService {
  DeviceEvidenceService({
    ImagePicker? imagePicker,
    AudioRecorder? recorder,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _recorder = recorder ?? AudioRecorder();

  final ImagePicker _imagePicker;
  final AudioRecorder _recorder;
  final Sha256 _sha256 = Sha256();
  String? _activeAudioPath;

  Future<CapturedEvidence?> capturePhoto() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (file == null) return null;
    return _fromXFile(
      file,
      type: EvidenceType.photo,
      mimeType: file.mimeType ?? 'image/jpeg',
    );
  }

  Future<CapturedEvidence?> captureVideo() async {
    final file = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 3),
    );
    if (file == null) return null;
    return _fromXFile(
      file,
      type: EvidenceType.video,
      mimeType: file.mimeType ?? 'video/mp4',
    );
  }

  Future<CapturedEvidence?> pickPhoto() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return _fromXFile(
      file,
      type: EvidenceType.photo,
      mimeType: file.mimeType ?? 'image/jpeg',
    );
  }

  Future<CapturedEvidence?> pickVideo() async {
    final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    return _fromXFile(
      file,
      type: EvidenceType.video,
      mimeType: file.mimeType ?? 'video/mp4',
    );
  }

  Future<void> startAudioRecording() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission is required.');
    }
    if (kIsWeb) {
      throw UnsupportedError('Audio file recording is not enabled on web.');
    }
    final directory = await getTemporaryDirectory();
    final path = p.join(
      directory.path,
      'tgcg_audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    _activeAudioPath = path;
  }

  Future<CapturedEvidence?> stopAudioRecording() async {
    final path = await _recorder.stop() ?? _activeAudioPath;
    _activeAudioPath = null;
    if (path == null || path.isEmpty) return null;
    final file = XFile(path);
    return _fromXFile(
      file,
      type: EvidenceType.audio,
      mimeType: 'audio/mp4',
    );
  }

  Future<bool> get isRecording => _recorder.isRecording();

  Future<CapturedEvidence> captureLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    return CapturedEvidence(
      type: EvidenceType.location,
      fileName: 'GPS-${DateTime.now().millisecondsSinceEpoch}',
      mimeType: 'application/vnd.tgcg.location+json',
      createdAt: DateTime.now().toUtc(),
      latitude: position.latitude,
      longitude: position.longitude,
      contentHash: await _hashString(
        jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
    );
  }

  Future<CapturedEvidence> _fromXFile(
    XFile file, {
    required EvidenceType type,
    required String mimeType,
  }) async {
    final bytes = await file.readAsBytes();
    final hash = await _sha256.hash(bytes);
    return CapturedEvidence(
      type: type,
      fileName: file.name,
      mimeType: mimeType,
      createdAt: DateTime.now().toUtc(),
      path: file.path,
      contentHash: 'sha256:${_hex(hash.bytes)}',
    );
  }

  Future<String> _hashString(String value) async {
    final hash = await _sha256.hash(utf8.encode(value));
    return 'sha256:${_hex(hash.bytes)}';
  }

  String _hex(List<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  Future<void> dispose() => _recorder.dispose();
}
