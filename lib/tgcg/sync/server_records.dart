import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/http_sync_transport.dart' show syncClientId;
import '../offline/offline_persistence.dart';

/// Where a record stands on its way to the server.
enum RecordUpload {
  /// Saved on this device, in the queue. The server has not seen it.
  waiting,

  /// Being sent now. The server has not confirmed it.
  uploading,

  /// The server confirmed it.
  uploaded,

  /// The server refused it.
  refused,
}

/// The server side of a store's records.
///
/// In presentation mode a store holds sample records. Once connected
/// ([connectServer]) it holds what the server returns ([S] is what one load
/// brings): loads run one at a time, asking again while one runs loads once
/// more when it ends, and a load begun for an earlier connection is dropped.
///
/// Records made on this device are saved to the offline outbox first and
/// uploaded by the sync controller, so they can be made offline. Each stays
/// on the list ([keepUntilUploaded]) until the server's copy, matched by the
/// `client_id` it was uploaded with, replaces it.
mixin ServerRecords<S> on ChangeNotifier {
  /// The offline store whose outbox uploads the records made here.
  OfflinePersistenceController? get offlineStore;

  /// Loads the records from the server.
  @protected
  Future<S> fetchServerRecords();

  /// The `client_id` of every record in [snapshot] a device uploaded.
  @protected
  Iterable<String?> clientIdsOf(S snapshot);

  /// Shows [snapshot]. Records still on this device ([isOnDevice]) stay.
  @protected
  void showServerRecords(S snapshot);

  /// Shows presentation mode's sample records.
  @protected
  void showSampleRecords();

  /// Empties the lists as a connection starts.
  @protected
  void clearRecords();

  bool _connected = false;
  String _account = '';
  int _connection = 0;
  Future<void>? _running;
  bool _loadAgain = false;
  bool _disposed = false;
  String? _loadError;
  DateTime? _loadedAt;
  final Map<String, String> _local = {};
  final Set<String> _refreshedFor = {};

  /// True in a server session: the records come from the server.
  bool get isLive => _connected;

  /// The access ID the records are loaded for (empty when not connected).
  String get serverAccount => _account;

  /// Loading from the server now.
  bool get loading => _running != null;

  /// Why the last load failed, if it did.
  String? get loadError => _loadError;

  /// When the server's records were last loaded.
  DateTime? get loadedAt => _loadedAt;

  /// False until a server session's first load succeeds: until then an empty
  /// list says nothing about what the server holds.
  bool get recordsKnown => !_connected || _loadedAt != null;

  /// Starts showing the server's records, loaded for [account] (the
  /// signed-in access ID, which uploads also carry).
  @protected
  void connectServer(String account) {
    if (!_connected) offlineStore?.addListener(_onOutboxChanged);
    _connected = true;
    _account = account;
    _reset();
    clearRecords();
    notifyListeners();
    unawaited(refresh());
  }

  /// Back to presentation mode and its sample records.
  @protected
  void disconnectServer() {
    if (!_connected) return;
    offlineStore?.removeListener(_onOutboxChanged);
    _connected = false;
    _account = '';
    _reset();
    showSampleRecords();
    notifyListeners();
  }

  void _reset() {
    _connection++;
    _local.clear();
    _refreshedFor.clear();
    _running = null;
    _loadAgain = false;
    _loadError = null;
    _loadedAt = null;
  }

  /// Loads what the server holds now. While a load runs, asking again
  /// loads once more when it ends.
  Future<void> refresh() {
    if (!_connected) return Future.value();
    final running = _running;
    if (running != null) {
      _loadAgain = true;
      return running;
    }
    late final Future<void> run;
    run = _load(_connection).whenComplete(() {
      if (!identical(_running, run)) return;
      _running = null;
      if (!_disposed) notifyListeners();
    });
    _running = run;
    notifyListeners();
    return run;
  }

  /// Loads again unless the records are newer than [age] or loading now.
  Future<void> refreshIfOlderThan(Duration age) {
    final running = _running;
    if (running != null) return running;
    final loadedAt = _loadedAt;
    if (loadedAt != null && DateTime.now().difference(loadedAt) < age) return Future.value();
    return refresh();
  }

  Future<void> _load(int connection) async {
    try {
      do {
        _loadAgain = false;
        final snapshot = await fetchServerRecords();
        if (connection != _connection) return;
        final onServer = {...clientIdsOf(snapshot).nonNulls};
        // The server's copy replaces the one made here.
        _local.removeWhere((_, outbox) => onServer.contains(syncClientId(_account, outbox)));
        showServerRecords(snapshot);
        _loadError = null;
        _loadedAt = DateTime.now();
      } while (_loadAgain && connection == _connection);
    } on ApiException catch (error) {
      if (connection == _connection) _loadError = error.message;
    } catch (_) {
      if (connection == _connection) {
        _loadError = 'The server sent records this app cannot read. Update the app.';
      }
    }
  }

  /// Keeps [id], saved on this device, on the list until the server's copy
  /// replaces it; [outboxId] is the outbox entry that uploads it.
  @protected
  void keepUntilUploaded(String id, String outboxId) {
    if (_connected) _local[id] = outboxId;
  }

  SyncOutboxItem? _outboxEntry(String outbox) =>
      offlineStore?.outbox.where((entry) => entry.id == outbox).firstOrNull;

  bool _uploaded(String outbox) {
    final entry = _outboxEntry(outbox);
    return entry == null || entry.state == SyncState.synced;
  }

  void _onOutboxChanged() {
    var uploaded = false;
    for (final outbox in _local.values) {
      if (_uploaded(outbox) && _refreshedFor.add(outbox)) uploaded = true;
    }
    // Whoever shows where a record stands sees it move.
    if (_local.isNotEmpty && !_disposed) notifyListeners();
    if (uploaded) unawaited(refresh());
  }

  /// Made on this device and not yet replaced by the server's copy: it has
  /// no server reference, so it cannot be acted on yet.
  bool isOnDevice(String id) => _local.containsKey(id);

  /// Where [id] stands, from the outbox itself. A record not made here came
  /// from the server. Null without a server connection: nothing is known.
  RecordUpload? uploadState(String id) {
    if (!_connected) return null;
    final outbox = _local[id];
    if (outbox == null) return RecordUpload.uploaded;
    final entry = _outboxEntry(outbox);
    if (entry == null) return RecordUpload.uploaded;
    return switch (entry.state) {
      SyncState.synced => RecordUpload.uploaded,
      SyncState.failed || SyncState.conflict => RecordUpload.refused,
      SyncState.syncing => RecordUpload.uploading,
      SyncState.queued => RecordUpload.waiting,
    };
  }

  /// Where a record made on this device stands, for showing it.
  String? uploadStatus(String id) {
    final outbox = _local[id];
    if (outbox == null) return null;
    final entry = _outboxEntry(outbox);
    if (entry == null || entry.state == SyncState.synced) return 'Uploaded to the server.';
    if (entry.state == SyncState.failed || entry.state == SyncState.conflict) {
      final why = (entry.lastError ?? 'see Sync status').trim();
      return 'The server refused the upload: ${why.endsWith('.') ? why : '$why.'}';
    }
    return 'Saved on this device. It uploads automatically when there is a connection.';
  }

  @override
  void dispose() {
    _disposed = true;
    if (_connected) offlineStore?.removeListener(_onOutboxChanged);
    super.dispose();
  }
}
