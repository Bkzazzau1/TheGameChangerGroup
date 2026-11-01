import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';
import 'election_calendar.dart';
import 'election_watch.dart';

enum ElectionCountdownSize {
  /// A navy panel, for the member's home.
  full,

  /// One quiet row, for the agent's home, where the day's work comes first.
  compact,

  /// White on navy, inside the command band of the operations dashboard.
  band,
}

/// The days to an election, on a watch that runs on Nigerian time, from the
/// central calendar: no network, and it keeps itself right every second and
/// when the app comes back.
class ElectionCountdown extends StatefulWidget {
  const ElectionCountdown({
    super.key,
    this.election = nextPresidentialElection,
    this.size = ElectionCountdownSize.full,
    this.clock = DateTime.now,
  });

  final ScheduledElection election;
  final ElectionCountdownSize size;

  /// The time now (replaced in tests).
  final DateTime Function() clock;

  @override
  State<ElectionCountdown> createState() => _ElectionCountdownState();
}

class _ElectionCountdownState extends State<ElectionCountdown> with WidgetsBindingObserver {
  late final Timer _tick;
  late DateTime _now = widget.clock();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (mounted) setState(() => _now = widget.clock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers stand still while a phone sleeps, and the date may have moved on.
    if (state == AppLifecycleState.resumed) _update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final election = widget.election;
    final status = ElectionStatus.of(election, _now);
    final (headline, sentence) = switch (status.phase) {
      ElectionPhase.upcoming => (
        '${status.daysLeft}',
        '${status.daysLeft == 1 ? '1 day' : '${status.daysLeft} days'} to the '
            '${election.name.toLowerCase()}',
      ),
      ElectionPhase.electionDay => ('Election Day', '${election.name} today'),
      ElectionPhase.completed => ('Held', '${election.name} held'),
    };
    return Semantics(
      container: true,
      label: '$sentence. ${election.fullDate}. Date from ${election.source}.',
      child: ExcludeSemantics(
        child: switch (widget.size) {
          ElectionCountdownSize.full => _FullCountdown(
            election: election,
            status: status,
            headline: headline,
            now: _now,
          ),
          ElectionCountdownSize.compact => _CompactCountdown(
            election: election,
            status: status,
            sentence: sentence,
            now: _now,
          ),
          ElectionCountdownSize.band => _BandCountdown(
            election: election,
            status: status,
            headline: headline,
            now: _now,
          ),
        },
      ),
    );
  }
}

/// "13:59:42": hours, minutes and seconds.
String _clockText(Duration left) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(left.inHours)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
}

class _FullCountdown extends StatelessWidget {
  const _FullCountdown({
    required this.election,
    required this.status,
    required this.headline,
    required this.now,
  });

  final ScheduledElection election;
  final ElectionStatus status;
  final String headline;
  final DateTime now;

  /// Narrower than this, the words go below the watch.
  static const _sideBySide = 240.0;

  @override
  Widget build(BuildContext context) {
    final upcoming = status.phase == ElectionPhase.upcoming;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          election.name.toUpperCase(),
          style: TgcgType.eyebrow.copyWith(color: TgcgColors.accentBright),
        ),
        const SizedBox(height: 8),
        Text(
          status.phase == ElectionPhase.completed
              ? 'Held on ${election.fullDate}'
              : election.fullDate,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'Date from ${election.source}',
          style: const TextStyle(color: TgcgColors.onNavyMuted, fontSize: 12),
        ),
        if (upcoming) ...[
          const SizedBox(height: 10),
          Text(
            '${_clockText(leftOfLagosDay(now))} left today',
            style: const TextStyle(
              color: TgcgColors.onNavyMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
    return TgcgNavyPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < _sideBySide;
          final watch = ElectionWatch(
            now: now,
            size: narrow ? 168 : (constraints.maxWidth * .5).clamp(126.0, 180.0),
            counting: status.phase != ElectionPhase.completed,
            headline: headline,
            caption: upcoming ? (status.daysLeft == 1 ? 'day to go' : 'days to go') : null,
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: watch),
                const SizedBox(height: 12),
                words,
              ],
            );
          }
          return Row(
            children: [
              watch,
              const SizedBox(width: 16),
              Expanded(child: words),
            ],
          );
        },
      ),
    );
  }
}

class _BandCountdown extends StatelessWidget {
  const _BandCountdown({
    required this.election,
    required this.status,
    required this.headline,
    required this.now,
  });

  final ScheduledElection election;
  final ElectionStatus status;
  final String headline;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final upcoming = status.phase == ElectionPhase.upcoming;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElectionWatch(
          now: now,
          size: 92,
          counting: status.phase != ElectionPhase.completed,
          headline: upcoming ? headline : null,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!upcoming)
                Text(
                  headline,
                  style: const TextStyle(
                    color: TgcgColors.accentBright,
                    fontSize: 20,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
              Text(
                upcoming
                    ? '${status.daysLeft == 1 ? 'day' : 'days'} to the '
                          '${election.name.toLowerCase()}'
                    : election.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                status.phase == ElectionPhase.completed
                    ? 'Held on ${election.fullDate}'
                    : election.fullDate,
                style: const TextStyle(color: TgcgColors.onNavyMuted, fontSize: 12, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactCountdown extends StatelessWidget {
  const _CompactCountdown({
    required this.election,
    required this.status,
    required this.sentence,
    required this.now,
  });

  final ScheduledElection election;
  final ElectionStatus status;
  final String sentence;
  final DateTime now;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: TgcgColors.surface,
      borderRadius: BorderRadius.circular(TgcgRadius.md),
      border: Border.all(color: TgcgColors.border),
    ),
    child: Row(
      children: [
        ElectionWatch(
          now: now,
          size: 60,
          counting: status.phase != ElectionPhase.completed,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sentence, style: TgcgType.bodyStrong),
              const SizedBox(height: 2),
              Text(
                '${status.phase == ElectionPhase.completed ? 'Held on ' : ''}'
                '${election.fullDate} · ${election.source}',
                style: TgcgType.caption,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
