import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/backend.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'election_calendar.dart';
import 'election_countdown.dart';
import 'follow_ups.dart';

/// When each account last saw the daily reminder on this device.
abstract interface class ReminderLog {
  Future<DateTime?> lastShown(String account);
  Future<void> shown(String account, DateTime at);
}

class DeviceReminderLog implements ReminderLog {
  DeviceReminderLog([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String account) => 'tgcg.reminder.$account';

  @override
  Future<DateTime?> lastShown(String account) async {
    final value = await _storage.read(key: _key(account));
    return value == null ? null : DateTime.tryParse(value);
  }

  @override
  Future<void> shown(String account, DateTime at) =>
      _storage.write(key: _key(account), value: at.toUtc().toIso8601String());
}

class MemoryReminderLog implements ReminderLog {
  final _times = <String, DateTime>{};

  @override
  Future<DateTime?> lastShown(String account) async => _times[account];

  @override
  Future<void> shown(String account, DateTime at) async => _times[account] = at;
}

/// Once every 24 hours, when someone signs in or comes back to the app: the
/// days to the election, the reminder to get their PVC ready, and whatever
/// they have to follow up.
class DailyReminder extends StatefulWidget {
  const DailyReminder({
    super.key,
    required this.log,
    required this.child,
    this.clock = DateTime.now,
  });

  /// Null: no reminders.
  final ReminderLog? log;
  final Widget child;

  /// The time now (replaced in tests).
  final DateTime Function() clock;

  @override
  State<DailyReminder> createState() => _DailyReminderState();
}

class _DailyReminderState extends State<DailyReminder> with WidgetsBindingObserver {
  static const _every = Duration(hours: 24);

  String? _account;
  DateTime? _nextAt;
  Timer? _timer;
  bool _checking = false;
  Route<void>? _popup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = TgcgSession.of(context);
    final account = session.isAuthenticated ? session.accessId : null;
    if (account != _account) {
      _account = account;
      _nextAt = null;
      _timer?.cancel();
      if (_popup case final popup?) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _remove(popup));
      }
    }
    unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  /// Nothing else is open on top: a page stays undisturbed, and coming back
  /// from it checks again.
  bool get _onTop => ModalRoute.isCurrentOf(context) ?? false;

  void _waitUntil(DateTime next) {
    _nextAt = next;
    _timer?.cancel();
    _timer = Timer(next.difference(widget.clock()), () {
      // The log has the last word: a timer may fire a moment early.
      _nextAt = null;
      unawaited(_check());
    });
  }

  Future<void> _check() async {
    if (!mounted) return;
    final log = widget.log;
    final account = _account;
    final services = TgcgBackend.of(context);
    if (log == null || account == null || services == null || _checking || !_onTop) return;
    final due = _nextAt;
    if (due != null && widget.clock().isBefore(due)) return;
    _checking = true;
    try {
      final last = await log.lastShown(account);
      final now = widget.clock();
      // A date ahead of now is a phone's clock that was wrong: it counts for nothing.
      if (last != null && !now.isBefore(last) && now.isBefore(last.add(_every))) {
        _waitUntil(last.add(_every));
        return;
      }
      if (!mounted) return;
      final session = TgcgSession.of(context, listen: false);
      final followUps = await loadFollowUps(services, session, now);
      if (!mounted || account != _account || !_onTop) return;
      _waitUntil(widget.clock().add(_every));
      final phase = ElectionStatus.of(nextPresidentialElection, now).phase;
      if (phase == ElectionPhase.completed && followUps.items.isEmpty) return;
      await log.shown(account, now);
      if (mounted && account == _account && _onTop) _show(followUps);
    } catch (_) {
      // A device that cannot remember stays quiet, rather than ask at every open.
      _waitUntil(widget.clock().add(_every));
    } finally {
      _checking = false;
    }
  }

  void _show(FollowUps followUps) {
    final popup = DialogRoute<void>(
      context: context,
      builder: (_) => DailyReminderDialog(
        followUps: followUps,
        clock: widget.clock,
        onFollow: (item) {
          if (_popup case final open?) _remove(open);
          item.open(context);
        },
      ),
    );
    _popup = popup;
    unawaited(
      Navigator.of(context).push(popup).whenComplete(() {
        if (identical(_popup, popup)) _popup = null;
      }),
    );
  }

  void _remove(Route<void> popup) {
    if (popup.isActive) popup.navigator?.removeRoute(popup);
    if (identical(_popup, popup)) _popup = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What the reminder says. Follow-ups list only what was found: the list
/// never says that nothing is waiting.
class DailyReminderDialog extends StatelessWidget {
  const DailyReminderDialog({
    super.key,
    required this.followUps,
    required this.onFollow,
    this.clock = DateTime.now,
  });

  final FollowUps followUps;
  final ValueChanged<FollowUp> onFollow;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final phase = ElectionStatus.of(nextPresidentialElection, clock()).phase;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (phase != ElectionPhase.completed) ...[
                      ElectionCountdown(clock: clock),
                      const SizedBox(height: 14),
                      _PvcReminder(today: phase == ElectionPhase.electionDay),
                    ],
                    if (followUps.items.isNotEmpty) ...[
                      if (phase != ElectionPhase.completed) const SizedBox(height: 16),
                      const Text('TO FOLLOW UP', style: TgcgType.eyebrow),
                      const SizedBox(height: 8),
                      TgcgRowGroup(
                        children: [
                          for (final item in followUps.items)
                            TgcgActionRow(
                              icon: item.icon,
                              color: TgcgColors.accentDeep,
                              title: item.title,
                              detail: item.detail,
                              onTap: () => onFollow(item),
                            ),
                        ],
                      ),
                    ],
                    if (!followUps.complete) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Your assignments could not be checked just now.',
                        style: TgcgType.caption,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PvcReminder extends StatelessWidget {
  const _PvcReminder({required this.today});

  /// It is election day.
  final bool today;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const TgcgIconBadge(icon: Icons.credit_card_rounded, color: TgcgColors.accentDeep),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(today ? 'Take your PVC with you' : 'Get your PVC ready', style: TgcgType.section),
            const SizedBox(height: 2),
            Text(
              today
                  ? "You need your Permanent Voter's Card to vote today."
                  : "You will need your Permanent Voter's Card to vote. Keep it safe and "
                        'know where your polling unit is.',
              style: TgcgType.support,
            ),
          ],
        ),
      ),
    ],
  );
}
