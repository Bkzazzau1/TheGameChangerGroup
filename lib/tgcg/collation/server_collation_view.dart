import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show areaLabel;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/reference_repository.dart' show ServerElection;
import '../api/results_repository.dart';
import '../session.dart';
import '../ui/server_feed.dart';
import '../ui/tgcg_design.dart';

/// The server's unofficial collation of verified results: one election, one
/// area at a time, with the areas below it. It never replaces INEC's
/// declaration.
class ServerCollationView extends StatefulWidget {
  const ServerCollationView({super.key});

  @override
  State<ServerCollationView> createState() => _ServerCollationViewState();
}

/// One step of the way down: your own area first (no level or code: the
/// server uses yours), then the areas opened below it.
class _Crumb {
  const _Crumb({this.label, this.level, this.code});

  final String? label;
  final GeographyLevel? level;
  final String? code;
}

class _ServerCollationViewState extends State<ServerCollationView> {
  late ResultsRepository _results;
  bool _started = false;
  Timer? _timer;

  List<ServerElection>? _elections;
  String? _electionsError;
  ServerElection? _election;
  final List<_Crumb> _path = [const _Crumb()];
  ServerCollation? _collation;
  String? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _results = TgcgBackend.of(context)!.results;
    if (!_started) {
      _started = true;
      unawaited(_loadElections());
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _loadCollation(quiet: true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadElections() async {
    setState(() => _electionsError = null);
    try {
      final elections = await _results.elections();
      if (!mounted) return;
      setState(() {
        _elections = elections;
        _election = elections.where((e) => e.status == 'open').firstOrNull ?? elections.firstOrNull;
      });
      await _loadCollation();
    } on ApiException catch (error) {
      if (mounted) setState(() => _electionsError = error.message);
    }
  }

  Future<void> _loadCollation({bool quiet = false}) async {
    final election = _election;
    if (!mounted || election == null || (quiet && _loading)) return;
    final request = ++_request;
    final crumb = _path.last;
    setState(() {
      _loading = true;
      if (!quiet) _error = null;
    });
    try {
      final collation = await _results.collation(
        election.code,
        level: crumb.level,
        code: crumb.code,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _collation = collation;
        _error = null;
        if (_path.first.label == null) _path[0] = _Crumb(label: areaLabel(collation.scope));
      });
    } on ApiException catch (error) {
      if (mounted && request == _request) setState(() => _error = error.message);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _selectElection(ServerElection election) {
    setState(() {
      _election = election;
      _path
        ..clear()
        ..add(const _Crumb());
      _collation = null;
    });
    unawaited(_loadCollation());
  }

  void _open(CollationArea area) {
    setState(() {
      _path.add(_Crumb(label: area.name, level: area.level, code: area.code));
      _collation = null;
    });
    unawaited(_loadCollation());
  }

  void _goTo(int index) {
    if (index == _path.length - 1) return;
    setState(() {
      _path.removeRange(index + 1, _path.length);
      _collation = null;
    });
    unawaited(_loadCollation());
  }

  @override
  Widget build(BuildContext context) {
    final elections = _elections;
    final collation = _collation;
    final scope = collation == null ? TgcgSession.of(context).scope : collation.scope;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'VERIFIED-ONLY AGGREGATION',
          title: 'Collation Command',
          subtitle: '${areaLabel(scope)}: unofficial totals of verified polling-unit results.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const TgcgStatusPill(
                label: 'UNOFFICIAL: NOT INEC',
                color: TgcgColors.warning,
                icon: Icons.info_outline_rounded,
              ),
              IconButton(
                tooltip: 'Load again',
                onPressed: _loading || _election == null ? null : () => _loadCollation(),
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_electionsError != null)
          _Problem(text: 'Elections could not be loaded: $_electionsError', onRetry: _loadElections)
        else if (elections == null)
          const _Loading()
        else if (elections.isEmpty)
          const TgcgEmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No elections yet',
            message: 'Collation starts once an election is set up on the server.',
          )
        else ...[
          _ElectionPicker(
            elections: elections,
            selected: _election,
            onChanged: _selectElection,
          ),
          const SizedBox(height: 12),
          _Breadcrumbs(path: _path, onSelect: _goTo),
          const SizedBox(height: 14),
          if (_error != null)
            _Problem(text: _error!, onRetry: _loadCollation)
          else if (collation == null)
            const _Loading()
          else ...[
            _Numbers(collation: collation),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final parties = _PartyTotals(collation: collation, election: _election!);
                final areas = _Breakdown(collation: collation, onOpen: _open);
                if (constraints.maxWidth < 1000) {
                  return Column(children: [parties, const SizedBox(height: 14), areas]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: parties),
                    const SizedBox(width: 14),
                    Expanded(flex: 6, child: areas),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            const ServerNote(
              icon: Icons.gavel_rounded,
              text: 'Unofficial. Only verified polling-unit results are counted; results under '
                  'review or disputed wait until they are decided. INEC declares the official '
                  'result.',
            ),
          ],
        ],
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text, required this.onRetry});

  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerNote(icon: Icons.cloud_off_rounded, text: text),
          TextButton(onPressed: () => unawaited(onRetry()), child: const Text('Try again')),
        ],
      );
}

class _ElectionPicker extends StatelessWidget {
  const _ElectionPicker({
    required this.elections,
    required this.selected,
    required this.onChanged,
  });

  final List<ServerElection> elections;
  final ServerElection? selected;
  final ValueChanged<ServerElection> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 460,
        child: DropdownButtonFormField<String>(
          key: ValueKey(selected?.code),
          initialValue: selected?.code,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Election'),
          items: [
            for (final election in elections)
              DropdownMenuItem(
                value: election.code,
                child: Text(
                  '${election.name} (${election.status})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (code) => onChanged(elections.firstWhere((e) => e.code == code)),
        ),
      );
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onSelect});

  final List<_Crumb> path;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var index = 0; index < path.length; index++) ...[
            if (index > 0) const Icon(Icons.chevron_right_rounded, size: 18, color: TgcgColors.muted),
            ActionChip(
              label: Text(path[index].label ?? 'Your areas'),
              onPressed: index == path.length - 1 ? null : () => onSelect(index),
            ),
          ],
        ],
      );
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.collation});

  final ServerCollation collation;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1050
              ? 5
              : constraints.maxWidth >= 640
                  ? 3
                  : constraints.maxWidth >= 420
                      ? 2
                      : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          final c = collation;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Verified units',
                value: '${c.verifiedPollingUnits} of ${c.expectedPollingUnits}',
                detail: '${c.completionPercent.toStringAsFixed(1)}% counted',
                icon: Icons.verified_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Reported units',
                value: '${c.reportedPollingUnits}',
                detail: 'With any result sent',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Under review',
                value: '${c.underReview}',
                detail: 'Flagged, not yet counted',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Disputed',
                value: '${c.disputed}',
                detail: 'Contested, not counted',
                icon: Icons.flag_outlined,
                tone: c.disputed == 0 ? TgcgMetricTone.neutral : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Still to count',
                value: '${c.missingPollingUnits}',
                detail: 'Units without a verified result',
                icon: Icons.hourglass_bottom_rounded,
                tone: TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _PartyTotals extends StatelessWidget {
  const _PartyTotals({required this.collation, required this.election});

  final ServerCollation collation;
  final ServerElection election;

  @override
  Widget build(BuildContext context) {
    final names = {for (final party in election.parties) party.acronym: party.name};
    final total = collation.totalValidVotes;
    final leader = collation.leadingParty;
    final anyVotes = collation.partyVotes.values.any((votes) => votes > 0);
    return TgcgSectionCard(
      title: 'Party totals',
      subtitle: 'Verified votes only. Valid ${collation.totalValidVotes}, '
          'rejected ${collation.rejectedVotes}, accredited ${collation.accreditedVoters}.',
      trailing: TgcgStatusPill(
        label: !anyVotes
            ? 'NO VERIFIED RESULTS'
            : leader == null
                ? 'LEVEL AT THE TOP'
                : 'AHEAD: $leader',
        color: leader == null ? TgcgColors.muted : TgcgColors.primary,
        compact: true,
      ),
      child: Column(
        children: [
          for (final entry in collation.partyVotes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          names[entry.key] == null ? entry.key : '${entry.key} · ${names[entry.key]}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: total == 0 ? 0 : entry.value / total,
                    minHeight: 6,
                    color: entry.key == leader ? TgcgColors.primary : TgcgColors.primaryMid,
                    backgroundColor: TgcgColors.border,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _levelName(GeographyLevel level) => switch (level) {
      GeographyLevel.country => 'Country',
      GeographyLevel.geopoliticalZone => 'Zone',
      GeographyLevel.state => 'State',
      GeographyLevel.senatorialDistrict => 'Senatorial district',
      GeographyLevel.lga => 'LGA',
      GeographyLevel.ward => 'Ward',
      GeographyLevel.pollingUnit => 'Polling unit',
    };

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.collation, required this.onOpen});

  final ServerCollation collation;
  final ValueChanged<CollationArea> onOpen;

  @override
  Widget build(BuildContext context) {
    final areas = collation.children;
    return TgcgSectionCard(
      title: areas.isEmpty ? 'Areas below' : '${_levelName(areas.first.level)} breakdown',
      subtitle: 'Open an area to see its own totals.',
      child: areas.isEmpty
          ? TgcgEmptyState(
              icon: Icons.place_outlined,
              title: 'No areas below this one',
              message: collation.scope.level == GeographyLevel.pollingUnit
                  ? 'This is a polling unit: its verified result is the total shown.'
                  : 'The election covers no smaller areas here.',
            )
          : Column(
              children: [
                for (final area in areas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onOpen(area),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      area.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (area.leadingParty != null)
                                    TgcgStatusPill(
                                      label: area.leadingParty!,
                                      color: TgcgColors.primary,
                                      compact: true,
                                    ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: TgcgColors.muted,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${area.code} · ${area.verifiedPollingUnits} of '
                                '${area.expectedPollingUnits} units verified · '
                                '${area.reportedPollingUnits} reported',
                                style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: area.completionPercent / 100,
                                minHeight: 5,
                                color: TgcgColors.success,
                                backgroundColor: TgcgColors.border,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
