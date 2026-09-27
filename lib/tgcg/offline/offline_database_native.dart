import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../sync/sync_models.dart';
import 'offline_database_contract.dart';

Future<OfflineDatabaseBackend> openOfflineDatabaseBackend() async {
  final directory = await getApplicationSupportDirectory();
  final path = p.join(directory.path, 'tgcg_emcop_offline.sqlite');
  return _SqliteOfflineDatabase(path);
}

class _SqliteOfflineDatabase implements OfflineDatabaseBackend {
  _SqliteOfflineDatabase(this.path);

  final String path;
  Database? _database;

  Database get _db {
    final value = _database;
    if (value == null) {
      throw StateError('Offline database has not been initialized.');
    }
    return value;
  }

  @override
  bool get isDurable => true;

  @override
  Future<void> initialize() async {
    if (_database != null) return;
    final database = sqlite3.open(path);
    _database = database;
    database.execute('PRAGMA journal_mode = WAL;');
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('PRAGMA busy_timeout = 5000;');
    database.execute('''
      CREATE TABLE IF NOT EXISTS offline_entities (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        payload_cipher BLOB NOT NULL,
        nonce BLOB NOT NULL,
        mac BLOB NOT NULL,
        updated_at TEXT NOT NULL,
        scope_key TEXT,
        owner_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity_type, entity_id)
      );
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        mutation_type TEXT NOT NULL,
        payload_cipher BLOB NOT NULL,
        nonce BLOB NOT NULL,
        mac BLOB NOT NULL,
        mutation_version INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        state TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_attempt_at TEXT,
        last_error TEXT
      );
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_outbox_state_created
      ON sync_outbox (state, created_at);
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS sync_receipts (
        outbox_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        server_version INTEGER NOT NULL,
        acknowledged_at TEXT NOT NULL,
        server_reference TEXT
      );
    ''');
  }

  @override
  Future<int> currentEntityVersion({
    required String entityType,
    required String entityId,
  }) async {
    final rows = _db.select(
      'SELECT version FROM offline_entities WHERE entity_type = ? AND entity_id = ? LIMIT 1',
      [entityType, entityId],
    );
    if (rows.isEmpty) return 0;
    return rows.first['version'] as int;
  }

  @override
  Future<StoredEntityRecord?> readEntity({
    required String entityType,
    required String entityId,
  }) async {
    final rows = _db.select(
      '''
        SELECT entity_type, entity_id, version, payload_cipher, nonce, mac,
               updated_at, scope_key, owner_id, deleted
        FROM offline_entities
        WHERE entity_type = ? AND entity_id = ?
        LIMIT 1
      ''',
      [entityType, entityId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return StoredEntityRecord(
      entityType: row['entity_type'] as String,
      entityId: row['entity_id'] as String,
      version: row['version'] as int,
      payload: EncryptedPayload(
        cipherText: _blob(row['payload_cipher']),
        nonce: _blob(row['nonce']),
        mac: _blob(row['mac']),
      ),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      scopeKey: row['scope_key'] as String?,
      ownerId: row['owner_id'] as String?,
      deleted: (row['deleted'] as int) == 1,
    );
  }

  @override
  Future<void> writeMutation({
    required StoredEntityRecord entity,
    required SyncOutboxItem outbox,
    required EncryptedPayload outboxPayload,
  }) async {
    final database = _db;
    database.execute('BEGIN IMMEDIATE;');
    try {
      final entityStatement = database.prepare('''
        INSERT INTO offline_entities (
          entity_type, entity_id, version, payload_cipher, nonce, mac,
          updated_at, scope_key, owner_id, deleted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(entity_type, entity_id) DO UPDATE SET
          version = excluded.version,
          payload_cipher = excluded.payload_cipher,
          nonce = excluded.nonce,
          mac = excluded.mac,
          updated_at = excluded.updated_at,
          scope_key = excluded.scope_key,
          owner_id = excluded.owner_id,
          deleted = excluded.deleted
      ''');
      try {
        entityStatement.execute([
          entity.entityType,
          entity.entityId,
          entity.version,
          entity.payload.cipherText,
          entity.payload.nonce,
          entity.payload.mac,
          entity.updatedAt.toUtc().toIso8601String(),
          entity.scopeKey,
          entity.ownerId,
          entity.deleted ? 1 : 0,
        ]);
      } finally {
        entityStatement.close();
      }

      final outboxStatement = database.prepare('''
        INSERT INTO sync_outbox (
          id, entity_type, entity_id, mutation_type, payload_cipher, nonce, mac,
          mutation_version, created_at, state, attempt_count, last_attempt_at,
          last_error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      try {
        outboxStatement.execute([
          outbox.id,
          outbox.entityType,
          outbox.entityId,
          outbox.mutationType.name,
          outboxPayload.cipherText,
          outboxPayload.nonce,
          outboxPayload.mac,
          outbox.mutationVersion,
          outbox.createdAt.toUtc().toIso8601String(),
          outbox.state.name,
          outbox.attemptCount,
          outbox.lastAttemptAt?.toUtc().toIso8601String(),
          outbox.lastError,
        ]);
      } finally {
        outboxStatement.close();
      }
      database.execute('COMMIT;');
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<List<StoredOutboxMutation>> loadOutbox() async {
    final rows = _db.select('''
      SELECT id, entity_type, entity_id, mutation_type, payload_cipher, nonce,
             mac, mutation_version, created_at, state, attempt_count,
             last_attempt_at, last_error
      FROM sync_outbox
      ORDER BY created_at DESC
    ''');
    return rows.map((row) {
      final lastAttempt = row['last_attempt_at'] as String?;
      return StoredOutboxMutation(
        item: SyncOutboxItem(
          id: row['id'] as String,
          entityType: row['entity_type'] as String,
          entityId: row['entity_id'] as String,
          mutationType: SyncMutationType.values.byName(
            row['mutation_type'] as String,
          ),
          payloadJson: '<encrypted-local-payload>',
          mutationVersion: row['mutation_version'] as int,
          createdAt: DateTime.parse(row['created_at'] as String),
          state: SyncState.values.byName(row['state'] as String),
          attemptCount: row['attempt_count'] as int,
          lastAttemptAt:
              lastAttempt == null ? null : DateTime.parse(lastAttempt),
          lastError: row['last_error'] as String?,
        ),
        payload: EncryptedPayload(
          cipherText: _blob(row['payload_cipher']),
          nonce: _blob(row['nonce']),
          mac: _blob(row['mac']),
        ),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> updateOutbox(SyncOutboxItem item) async {
    final statement = _db.prepare('''
      UPDATE sync_outbox
      SET state = ?, attempt_count = ?, last_attempt_at = ?, last_error = ?
      WHERE id = ?
    ''');
    try {
      statement.execute([
        item.state.name,
        item.attemptCount,
        item.lastAttemptAt?.toUtc().toIso8601String(),
        item.lastError,
        item.id,
      ]);
    } finally {
      statement.close();
    }
  }

  @override
  Future<void> saveReceipt(SyncReceipt receipt) async {
    final statement = _db.prepare('''
      INSERT INTO sync_receipts (
        outbox_id, entity_type, entity_id, server_version,
        acknowledged_at, server_reference
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(outbox_id) DO UPDATE SET
        server_version = excluded.server_version,
        acknowledged_at = excluded.acknowledged_at,
        server_reference = excluded.server_reference
    ''');
    try {
      statement.execute([
        receipt.outboxId,
        receipt.entityType,
        receipt.entityId,
        receipt.serverVersion,
        receipt.acknowledgedAt.toUtc().toIso8601String(),
        receipt.serverReference,
      ]);
    } finally {
      statement.close();
    }
  }

  @override
  Future<SyncReceipt?> receiptFor(String outboxId) async {
    final rows = _db.select(
      '''
        SELECT outbox_id, entity_type, entity_id, server_version,
               acknowledged_at, server_reference
        FROM sync_receipts
        WHERE outbox_id = ?
        LIMIT 1
      ''',
      [outboxId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SyncReceipt(
      outboxId: row['outbox_id'] as String,
      entityType: row['entity_type'] as String,
      entityId: row['entity_id'] as String,
      serverVersion: row['server_version'] as int,
      acknowledgedAt: DateTime.parse(row['acknowledged_at'] as String),
      serverReference: row['server_reference'] as String?,
    );
  }

  @override
  Future<void> clearAll() async {
    final database = _db;
    database.execute('BEGIN IMMEDIATE;');
    try {
      database.execute('DELETE FROM sync_receipts;');
      database.execute('DELETE FROM sync_outbox;');
      database.execute('DELETE FROM offline_entities;');
      database.execute('COMMIT;');
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _database?.close();
    _database = null;
  }

  static Uint8List _blob(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw StateError('Expected SQLite BLOB value, got ${value.runtimeType}.');
  }
}
