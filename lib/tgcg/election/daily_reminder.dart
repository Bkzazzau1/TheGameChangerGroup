import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/backend.dart';
import '../api/popups_repository.dart';
import '../messaging/popup_post_dialog.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'election_calendar.dart';
import 'election_countdown.dart';
import 'follow_ups.dart';

/// When each account last saw the daily reminder, and each posted message,
/// on this device.
abstract interface class ReminderLog {
  Future<DateTime?> lastShown(String account);
  Future<void> shown(String account, DateTime at);
}

/// Kept on the device; for this visit only when a browser refuses this site
/// its storage (see SecureTokenStore).
class DeviceReminderLog implements ReminderLog {
  DeviceReminderLog([FlutterSecureStorage? storage, bool? visitWhenRefused])
    : _storage = storage ?? const FlutterSecureStorage(),
      _visitWhenRefused = visitWhenRefused ?? kIsWeb;

  final FlutterSecureStorage _storage;
  final bool _visitWhenRefused;
  final _visit = MemoryReminderLog();
  bool _refused = false;

  String _key(String account) => 'tgcg.reminder.$account';

  @override
  Future<DateTime?> lastShown(String account) async {
    if (_refused) return _visit.lastShown(account);
    try {
      final value = await _storage.read(key: _key(account));
      return value == null ? null : DateTime.tryParse(value);
    } catch (_) {
      if (!_visitWhenRefused) rethrow;
      _refused = true;
      return _visit.lastShown(account);
    }
  }

  @override
  Future<void> shown(String account, DateTime at) async {
    if (_refused) return _visit.shown(account, at);
    try {
      await _storage.write(key: _key(account), value: at.toUtc().toIso8601String());
    } catch (_) {
      if (!_visitWhenRefused) rethrow;
      _refused = true;
      await _visit.shown(account, at);
    }
  }
}

class MemoryReminderLog implements ReminderLog {
  final _times = <String, DateTime>{};

  @override
  Future<DateTime?> lastShown(String account) async => _times[account];

  @override
  Future<void> shown(String account, DateTime at) async => _times[account] = at;
}

/// When someone signs in or comes back to the app: a message posted for
/// everyone, as often as its poster chose. When none is due, once every 24
/// hours, the days to the election, the reminder to get their PVC ready, and
/// whatever they have to follow up; that list then goes with a posted message.
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

  /// How long posted messages are taken as they were last read.
  static const _postsLast = Duration(minutes: 5);

  /// Away from the app this long, coming back counts as opening it again.
  static const _newOpenAfter = Duration(minutes: 30);

  String? _account;
  DateTime? _nextAt;
  Timer? _timer;
  bool _checking = false;
  Route<void>? _popup;
  List<PopupPost> _posts = const [];
  DateTime? _postsAt;
  DateTime? _leftAt;

  /// Messages for every sign-in that this opening of the app has shown.
  final _shownThisOpen = <String>{};

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
      _posts = const [];
      _postsAt = null;
      _shownThisOpen.clear();
      if (_popup case final popup?) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _remove(popup));
      }
    }
    unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= widget.clock();
    }
    if (state != AppLifecycleState.resumed) return;
    final left = _leftAt;
    _leftAt = null;
    if (left != null && widget.clock().difference(left) >= _newOpenAfter) {
      _shownThisOpen.clear();
    }
    unawaited(_check());
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

  String _postKey(String account, PopupPost post) => '$account.popup.${post.id}';

  /// A date ahead of now is a phone's clock that was wrong: it counts for nothing.
  bool _passed(DateTime now, DateTime last, Duration gap) =>
      now.isBefore(last) || !now.isBefore(last.add(gap));

  /// What is posted now. Without an answer, what was read last stands.
  Future<void> _readPosts(BackendServices services, DateTime now) async {
    _postsAt = now;
    try {
      _posts = await services.popups.showing().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline, or a server without pop-ups.
    }
  }

  /// The newest posted message this person is due to see.
  Future<PopupPost?> _duePost(ReminderLog log, String account, DateTime now) async {
    for (final post in _posts) {
      if (post.everyOpen) {
        if (!_shownThisOpen.contains(post.id)) return post;
        continue;
      }
      final last = await log.lastShown(_postKey(account, post));
      final gap = post.repeatEvery;
      if (last == null || (gap != null && _passed(now, last, gap))) return post;
    }
    return null;
  }

  Future<Uint8List?> _pictureOf(BackendServices services, PopupPost post) async {
    if (!post.hasPicture) return null;
    try {
      return await services.popups.picture(post.id).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null; // the words still show
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    final log = widget.log;
    final account = _account;
    final services = TgcgBackend.of(context);
    if (log == null || account == null || services == null || _checking || !_onTop) return;
    final started = widget.clock();
    final postsAt = _postsAt;
    final readPosts = postsAt == null || started.difference(postsAt).abs() >= _postsLast;
    final due = _nextAt;
    if (!readPosts && _posts.isEmpty && due != null && started.isBefore(due)) return;
    _checking = true;
    try {
      if (readPosts) await _readPosts(services, started);
      final now = widget.clock();
      final post = await _duePost(log, account, now);
      final last = await log.lastShown(account);
      final dailyDue = last == null || _passed(now, last, _every);
      if (last != null && !dailyDue) _waitUntil(last.add(_every));
      if (post == null && !dailyDue) return;
      if (!mounted) return;
      final session = TgcgSession.of(context, listen: false);
      final followUps = dailyDue
          ? await loadFollowUps(services, session, now)
          : const FollowUps([], complete: true);
      if (post != null) {
        final picture = await _pictureOf(services, post);
        if (!mounted || account != _account || !_onTop) return;
        await log.shown(_postKey(account, post), now);
        _shownThisOpen.add(post.id);
        if (dailyDue) {
          await log.shown(account, now);
          _waitUntil(widget.clock().add(_every));
        }
        if (mounted && account == _account && _onTop) _showPost(post, picture, followUps);
        return;
      }
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

  void _follow(FollowUp item) {
    if (_popup case final open?) _remove(open);
    item.open(context);
  }

  void _show(FollowUps followUps) =>
      _open(DailyReminderDialog(followUps: followUps, clock: widget.clock, onFollow: _follow));

  void _showPost(PopupPost post, Uint8List? picture, FollowUps followUps) =>
      _open(PopupPostDialog(post: post, picture: picture, followUps: followUps, onFollow: _follow));

  void _open(Widget dialog) {
    final popup = DialogRoute<void>(context: context, builder: (_) => dialog);
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
