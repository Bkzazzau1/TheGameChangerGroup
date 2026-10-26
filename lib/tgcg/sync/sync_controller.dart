import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';

import '../offline/offline_persistence.dart';
import 'sync_worker.dart';

/// Runs the outbox sync while signed in to the server: shortly after new
/// records are queued, every [interval], and on demand ("Sync now").
///
/// When the server cannot be reached or is busy, the phone waits longer each
/// time (about [interval], then twice that, and so on up to [longestWait]),
/// at a random point around each wait so phones do not all come back at
/// once, and never sooner than the server asked. "Sync now" does not wait.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.persistence,
    required this.transport,
    this.interval = const Duration(seconds: 45),
    this.debounce = const Duration(seconds: 2),
    this.longestWait = const Duration(minutes: 15),
    math.Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? math.Random(),
       _clock = clock ?? DateTime.now;

  final OfflinePersistenceController persistence;
  final SyncTransport transport;
  final Duration interval;
  final Duration debounce;
  final Duration longestWait;
  final math.Random _random;
  final DateTime Function() _clock;

  /// Server trouble in a row, and when the phone tries again.
  int _setbacks = 0;
  DateTime? _nextTry;

  Timer? _timer;
  Timer? _soon;
  bool _enabled = false;
  bool _running = false;
  bool _again = false;
  DateTime? _lastSyncedAt;
  String? _problem;
  int _pendingAtStart = 0;

  bool get enabled => _enabled;
  bool get running => _running;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Why the last run could not finish (e.g. offline), if it couldn't.
  String? get problem => _problem;

  /// When the phone next tries, while it waits after server trouble.
  DateTime? get nextTry => _nextTry;

  /// Queued records this app can deliver to the server.
  int get waiting => persistence.outbox
      .where((item) => item.state == SyncState.queued && transport.supports(item.entityType))
      .length;

  /// Records the server refused; they need attention.
  int get rejected => persistence.outbox
      .where((item) =>
          (item.state == SyncState.failed || item.state == SyncState.conflict) &&
          transport.supports(item.entityType))
      .length;

  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      persistence.addListener(_onOutboxChanged);
      _timer = Timer.periodic(interval, (_) => syncNow());
      unawaited(syncNow());
    } else {
      persistence.removeListener(_onOutboxChanged);
      _timer?.cancel();
      _soon?.cancel();
    }
    notifyListeners();
  }

  void _onOutboxChanged() {
    if (waiting == _pendingAtStart) return;
    _soon?.cancel();
    _soon = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Runs until the outbox is empty or a temporary problem stops it.
  /// [manual]: the person asked, so any wait after server trouble is skipped.
  Future<void> syncNow({bool manual = false}) async {
    if (!_enabled) return;
    final next = _nextTry;
    if (!manual && next != null && _clock().isBefore(next)) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    notifyListeners();
    var trouble = false;
    Duration? asked;
    try {
      final worker = SyncWorker(persistence: persistence, transport: transport);
      do {
        _again = false;
        _pendingAtStart = waiting;
        if (_pendingAtStart == 0) break;
        final summary = await worker.runOnce();
        _problem = summary.stoppedReason;
        trouble = summary.serverTrouble;
        asked = summary.retryAfter;
        if (summary.stoppedReason != null) break;
        if (summary.attempted == 0) break;
      } while (_again || waiting > 0);
      if (_problem == null) _lastSyncedAt = DateTime.now();
    } catch (error) {
      _problem = error.toString();
      trouble = true;
    } finally {
      _waitAfter(trouble: trouble, asked: asked);
      _pendingAtStart = waiting;
      _running = false;
      notifyListeners();
    }
  }

  /// After server trouble, waits longer each time (with a random spread);
  /// otherwise clears the wait.
  void _waitAfter({required bool trouble, Duration? asked}) {
    if (!trouble) {
      _setbacks = 0;
      _nextTry = null;
      return;
    }
    _setbacks += 1;
    final doubling = math.min(_setbacks - 1, 10);
    final base = math.min(interval.inMilliseconds * (1 << doubling), longestWait.inMilliseconds);
    var wait = Duration(milliseconds: (base * (0.5 + _random.nextDouble())).round());
    if (wait > longestWait) wait = longestWait;
    if (asked != null && asked > wait) wait = asked;
    _nextTry = _clock().add(wait);
  }

  /// Puts records the server refused back in the queue.
  Future<void> retryRejected() async {
    for (final item in persistence.outbox.where((item) =>
        (item.state == SyncState.failed || item.state == SyncState.conflict) &&
        transport.supports(item.entityType))) {
      await persistence.queueForRetry(item.id);
    }
    await syncNow(manual: true);
  }

  @override
  void dispose() {
    setEnabled(false);
    super.dispose();
  }
}

/// Makes the [SyncController] available below it (null without a server).
class TgcgSync extends InheritedNotifier<SyncController> {
  const TgcgSync({super.key, required SyncController? controller, required super.child})
      : super(notifier: controller);

  static SyncController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TgcgSync>()?.notifier;
}

/// Upload status for field users: what is waiting, refused, and a manual sync.
/// Renders nothing in presentation mode.
class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = TgcgSync.of(context);
    if (sync == null || !sync.enabled) return const SizedBox.shrink();
    final waiting = sync.waiting;
    final rejected = sync.rejected;
    final problem = sync.problem;
    final last = sync.lastSyncedAt;
    final (title, detail) = sync.running
        ? ('Uploading…', 'Sending $waiting record${waiting == 1 ? '' : 's'} to the server.')
        : problem != null
            ? (
                '$waiting waiting to upload',
                [
                  problem,
                  if (sync.nextTry case final next?)
                    'Next try ${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}.',
                ].join(' '),
              )
            : waiting > 0
                ? ('$waiting waiting to upload', 'Uploads start automatically when online.')
                : (
                    'All uploaded',
                    last == null
                        ? 'Everything on this phone is on the server.'
                        : 'Last upload ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}.',
                  );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    problem != null
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                    color: problem != null ? TgcgColors.warning : TgcgColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text(detail, style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted)),
                      ],
                    ),
                  ),
                  _SyncButton(sync: sync),
                ],
              ),
              if (rejected > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$rejected record${rejected == 1 ? ' was' : 's were'} refused by the server. '
                          'Open Sync Status to see why.',
                          style: const TextStyle(fontSize: 11.5, color: TgcgColors.danger),
                        ),
                      ),
                      _RetryButton(sync: sync),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.sync});
  final SyncController sync;

  @override
  Widget build(BuildContext context) => _TextAction(
        label: 'Sync now',
        onTap: sync.running ? null : () => unawaited(sync.syncNow(manual: true)),
      );
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.sync});
  final SyncController sync;

  @override
  Widget build(BuildContext context) => _TextAction(
        label: 'Retry',
        onTap: sync.running ? null : () => unawaited(sync.retryRejected()),
      );
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(onPressed: onTap, child: Text(label));
}
