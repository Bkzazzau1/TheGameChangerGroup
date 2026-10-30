import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';
import 'election_calendar.dart';

enum ElectionCountdownSize {
  /// A navy panel, for the member's home.
  full,

  /// One quiet row, for the agent's home, where the day's work comes first.
  compact,

  /// White on navy, inside the command band of the operations dashboard.
  band,
}

/// The days to an election, from the central calendar: no network, and it
/// keeps itself right at Nigerian midnight and when the app comes back.
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
  Timer? _midnight;
  late DateTime _now = widget.clock();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _waitForMidnight();
  }

  void _waitForMidnight() {
    _midnight?.cancel();
    final now = widget.clock();
    _midnight = Timer(nextLagosMidnight(now).difference(now), _update);
  }

  void _update() {
    if (!mounted) return;
    setState(() => _now = widget.clock());
    _waitForMidnight();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers stand still while a phone sleeps, and the date may have moved on.
    if (state == AppLifecycleState.resumed) _update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
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
          ),
          ElectionCountdownSize.compact => _CompactCountdown(
            election: election,
            status: status,
            sentence: sentence,
          ),
          ElectionCountdownSize.band => _BandCountdown(
            election: election,
            status: status,
            headline: headline,
          ),
        },
      ),
    );
  }
}

class _FullCountdown extends StatelessWidget {
  const _FullCountdown({required this.election, required this.status, required this.headline});

  final ScheduledElection election;
  final ElectionStatus status;
  final String headline;

  @override
  Widget build(BuildContext context) {
    final upcoming = status.phase == ElectionPhase.upcoming;
    return TgcgNavyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            election.name.toUpperCase(),
            style: TgcgType.eyebrow.copyWith(color: TgcgColors.accentBright),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: upcoming ? 46 : 30,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (upcoming) ...[
                const SizedBox(width: 10),
                Text(
                  status.daysLeft == 1 ? 'day to go' : 'days to go',
                  style: const TextStyle(
                    color: TgcgColors.onNavyMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
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
        ],
      ),
    );
  }
}

class _BandCountdown extends StatelessWidget {
  const _BandCountdown({required this.election, required this.status, required this.headline});

  final ScheduledElection election;
  final ElectionStatus status;
  final String headline;

  @override
  Widget build(BuildContext context) {
    final upcoming = status.phase == ElectionPhase.upcoming;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          style: TextStyle(
            color: TgcgColors.accentBright,
            fontSize: upcoming ? 34 : 20,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -.4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
  const _CompactCountdown({required this.election, required this.status, required this.sentence});

  final ScheduledElection election;
  final ElectionStatus status;
  final String sentence;

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
        const TgcgIconBadge(icon: Icons.event_rounded, color: TgcgColors.accentDeep),
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
