import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/models.dart';
import '../offline/offline_persistence.dart';

/// The kind of record a piece of evidence belongs to on the server.
enum EvidenceParent { incident, fieldReport, result }

/// A photo chosen on this device, ready to attach to a record.
class PendingEvidence {
  const PendingEvidence({
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.sha256,
    required this.takenAt,
  });

  final EvidenceType type;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  /// Hex SHA-256 of [bytes]. The server computes its own and refuses the
  /// upload if they differ, so a damaged upload is never kept.
  final String sha256;
  final DateTime takenAt;

  /// How the record shows it until the server has it.
  EvidenceAttachment toAttachment({required String id, required String uploaderId}) =>
      EvidenceAttachment(
        id: id,
        type: type,
        fileName: fileName,
        createdAt: takenAt,
        uploaderId: uploaderId,
        contentHash: 'sha256:$sha256',
        mimeType: mimeType,
        origin: RecordOrigin.localEntry,
      );
}

/// What the file really is, from its first bytes: the server checks them
/// against the name's extension.
(String mime, String extension)? _sniff(Uint8List bytes) {
  bool starts(List<int> prefix, [int offset = 0]) =>
      bytes.length >= offset + prefix.length &&
      [for (var i = 0; i < prefix.length; i++) bytes[offset + i] == prefix[i]].every((same) => same);
  if (starts([0xff, 0xd8, 0xff])) return ('image/jpeg', '.jpg');
  if (starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return ('image/png', '.png');
  if (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) return ('image/webp', '.webp');
  const heicBrands = ['heic', 'heix', 'heis', 'hevc', 'hevx', 'mif1', 'msf1'];
  if (starts(ascii.encode('ftyp'), 4) && heicBrands.any((brand) => starts(ascii.encode(brand), 8))) {
    return ('image/heic', '.heic');
  }
  if (starts(ascii.encode('%PDF-'))) return ('application/pdf', '.pdf');
  return null;
}

/// Evidence from a file's [bytes], named so the server accepts it: [name]
/// gets the extension of what the file really is when it lacks it.
Future<PendingEvidence> evidenceFromBytes({
  required EvidenceType type,
  required String name,
  required Uint8List bytes,
  String? mimeType,
  DateTime? takenAt,
}) async {
  final sniffed = _sniff(bytes);
  var fileName = name.trim().isEmpty ? 'evidence' : name.trim().split(RegExp(r'[\\/]')).last;
  if (sniffed != null) {
    final (_, extension) = sniffed;
    final lower = fileName.toLowerCase();
    final known = extension == '.jpg' ? ['.jpg', '.jpeg'] : [extension];
    if (!known.any(lower.endsWith)) fileName = '$fileName$extension';
  }
  final hash = await Sha256().hash(bytes);
  return PendingEvidence(
    type: type,
    fileName: fileName,
    mimeType: sniffed?.$1 ?? mimeType ?? 'application/octet-stream',
    bytes: bytes,
    sha256: [for (final byte in hash.bytes) byte.toRadixString(16).padLeft(2, '0')].join(),
    takenAt: (takenAt ?? DateTime.now()).toUtc(),
  );
}

/// Takes or chooses a photo: sized so a result sheet stays readable while
/// the upload stays small enough for a weak network.
Future<PendingEvidence?> pickEvidencePhoto({
  required EvidenceType type,
  required bool camera,
  ImagePicker? picker,
}) async {
  final file = await (picker ?? ImagePicker()).pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 85,
  );
  if (file == null) return null;
  return evidenceFromBytes(
    type: type,
    name: file.name,
    mimeType: file.mimeType,
    bytes: await file.readAsBytes(),
  );
}

/// Saves [evidence] in the offline outbox; the sync controller uploads it
/// after its record. Give the record's server [reference] when it is on the
/// server already, otherwise [recordOutboxId], the outbox entry that uploads
/// the record. Returns the id the record can show it under meanwhile.
Future<String> queueEvidence(
  OfflinePersistenceController persistence, {
  required EvidenceParent parent,
  required PendingEvidence evidence,
  required String ownerId,
  String? reference,
  String? recordOutboxId,
}) async {
  assert((reference == null) != (recordOutboxId == null), 'Give a reference or an outbox id.');
  final id = 'EVD-${DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase()}';
  await persistence.persistMutation(
    entityType: 'evidence_upload',
    entityId: id,
    mutationType: SyncMutationType.create,
    payload: {
      'parent': parent.name,
      'reference': ?reference,
      'recordOutboxId': ?recordOutboxId,
      'type': evidence.type.name,
      'fileName': evidence.fileName,
      'mimeType': evidence.mimeType,
      'sha256': evidence.sha256,
      'takenAt': evidence.takenAt.toIso8601String(),
      'bytes': base64Encode(evidence.bytes),
    },
    ownerId: ownerId,
  );
  return id;
}
