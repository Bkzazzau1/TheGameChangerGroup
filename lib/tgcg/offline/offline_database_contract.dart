import 'dart:typed_data';

import '../sync/sync_models.dart';

class EncryptedPayload {
  const EncryptedPayload({
    required this.cipherText,
    required this.nonce,
    required this.mac,
  });

  final Uint8List cipherText;
  final Uint8List nonce;
  final Uint8List mac;
}

class StoredEntityRecord {
  const StoredEntityRecord({
    required this.entityType,
    required this.entityId,
    required this.version,
    required this.payload,
    required this.updatedAt,
    required this.scopeKey,
    required this.ownerId,
    required this.deleted,
  });

  final String entityType;
  final String entityId;
  final int version;
  final EncryptedPayload payload;
  final DateTime updatedAt;
  final String? scopeKey;
  final String? ownerId;
  final bool deleted;
}

class StoredOutboxMutation {
  const StoredOutboxMutation({
    required this.item,
    required this.payload,
  });

  final SyncOutboxItem item;
  final EncryptedPayload payload;
}

abstract interface class OfflineDatabaseBackend {
  bool get isDurable;

  Future<void> initialize();

  Future<int> currentEntityVersion({
    required String entityType,
    required String entityId,
  });

  Future<StoredEntityRecord?> readEntity({
    required String entityType,
    required String entityId,
  });

  Future<void> writeMutation({
    required StoredEntityRecord entity,
    required SyncOutboxItem outbox,
    required EncryptedPayload outboxPayload,
  });

  Future<List<StoredOutboxMutation>> loadOutbox();

  Future<void> updateOutbox(SyncOutboxItem item);

  Future<void> saveReceipt(SyncReceipt receipt);

  Future<SyncReceipt?> receiptFor(String outboxId);

  Future<void> close();
}
