import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/reference_repository.dart';
import '../location/gps_prompt.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'result_operations_store.dart';

/// Result entry against real server data: open elections with their ballot
/// parties, and INEC polling units in the user's area. The result is saved
/// to the offline outbox and uploads automatically.
class ServerResultForm extends StatefulWidget {
  const ServerResultForm({super.key});

  @override
  State<ServerResultForm> createState() => _ServerResultFormState();
}

class _ServerResultFormState extends State<ServerResultForm> {
  late Future<(List<ServerElection>, List<ServerPollingUnit>)> _loading;
  ServerElection? _election;
  ServerPollingUnit? _unit;
  final Map<String, TextEditingController> _votes = {};
  final _total = TextEditingController();
  final _rejected = TextEditingController();
  final _accredited = TextEditingController();
  final _registered = TextEditingController();
  bool _saving = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loading = _load();
    }
  }

  Future<(List<ServerElection>, List<ServerPollingUnit>)> _load() async {
    final services = TgcgBackend.of(context)!;
    final scope = TgcgSession.of(context, listen: false).scope;
    final results = await Future.wait([
      services.reference.openElections(),
      services.reference.pollingUnitsWithin(scope),
    ]);
    final elections = results[0] as List<ServerElection>;
    final units = results[1] as List<ServerPollingUnit>;
    if (mounted) {
      setState(() {
        if (elections.length == 1) _selectElection(elections.single);
        if (units.length == 1) _selectUnit(units.single);
      });
    }
    return (elections, units);
  }

  void _selectElection(ServerElection election) {
    _election = election;
    for (final controller in _votes.values) {
      controller.dispose();
    }
    _votes
      ..clear()
      ..addEntries(
        election.parties.map((p) => MapEntry(p.acronym, TextEditingController()..addListener(_refresh))),
      );
  }

  void _selectUnit(ServerPollingUnit unit) {
    _unit = unit;
    _registered.text = unit.registeredVoters?.toString() ?? '';
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_total, _rejected, _accredited, _registered]) {
      c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final c in [..._votes.values, _total, _rejected, _accredited, _registered]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _n(TextEditingController c) => int.tryParse(c.text.trim());
  int get _partySum => _votes.values.fold(0, (sum, c) => sum + (_n(c) ?? 0));

  List<String> get _problems {
    final problems = <String>[];
    final total = _n(_total), accredited = _n(_accredited), registered = _n(_registered);
    if (total != null && _partySum != total) {
      problems.add('Party votes add up to $_partySum, but the valid total is $total.');
    }
    final ballots = (total ?? 0) + (_n(_rejected) ?? 0);
    if (accredited != null && ballots > accredited) {
      problems.add('Valid plus rejected votes ($ballots) exceed accredited voters ($accredited).');
    }
    if (accredited != null && registered != null && accredited > registered) {
      problems.add('Accredited voters ($accredited) exceed registered voters ($registered).');
    }
    return problems;
  }

  bool get _complete =>
      _election != null &&
      _unit != null &&
      _n(_total) != null &&
      _n(_accredited) != null &&
      _votes.values.every((c) => _n(c) != null);

  Future<void> _submit() async {
    final session = TgcgSession.of(context, listen: false);
    final store = ResultOperations.of(context, listen: false);
    final gps = await captureGps(context, required: true, action: 'submit this result');
    if (gps == null || !mounted) return;
    setState(() => _saving = true);
    final unit = _unit!;
    final scope = session.scope;
    try {
      final saved = await store.submit(
        pollingUnitScope: GeographicScope(
          level: GeographyLevel.pollingUnit,
          country: scope.country,
          zoneId: scope.zoneId,
          zoneName: scope.zoneName,
          stateId: scope.stateId,
          stateName: scope.stateName,
          lgaId: scope.lgaId,
          lgaName: scope.lgaName,
          wardId: unit.wardCode,
          pollingUnitId: unit.code,
          pollingUnitName: unit.name,
        ),
        submittedBy: session.accessId,
        source: SubmissionSource.app,
        partyVotes: {for (final e in _votes.entries) e.key: _n(e.value) ?? 0},
        totalVotesRecorded: _n(_total)!,
        accreditedVoters: _n(_accredited)!,
        rejectedVotes: _n(_rejected),
        registeredVoters: _n(_registered),
        gps: gps,
        electionCode: _election!.code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${saved.id} saved for ${unit.code}. It uploads automatically'
            '${saved.validation?.requiresHumanReview == true ? ' and will be reviewed' : ''}.',
          ),
        ),
      );
      setState(() {
        for (final c in [..._votes.values, _total, _rejected, _accredited]) {
          c.clear();
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Submit a polling unit result',
        subtitle: 'Enter the figures exactly as written on the signed result sheet (EC8A).',
        trailing: const TgcgStatusPill(
          label: 'LIVE SERVER',
          color: TgcgColors.success,
          icon: Icons.cloud_done_outlined,
          compact: true,
        ),
        child: FutureBuilder<(List<ServerElection>, List<ServerPollingUnit>)>(
          future: _loading,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return _Message(
                icon: Icons.cloud_off_outlined,
                text: error is ApiException
                    ? error.message
                    : 'Elections could not be loaded.',
                action: TextButton(
                  onPressed: () => setState(() => _loading = _load()),
                  child: const Text('Try again'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final (elections, units) = snapshot.data!;
            if (elections.isEmpty) {
              return const _Message(
                icon: Icons.event_busy_outlined,
                text: 'No election is open for results right now.',
              );
            }
            if (units.isEmpty) {
              return const _Message(
                icon: Icons.location_off_outlined,
                text: 'No polling units were found in your area.',
              );
            }
            return _form(elections, units);
          },
        ),
      );

  Widget _form(List<ServerElection> elections, List<ServerPollingUnit> units) {
    final problems = _complete ? _problems : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('election'),
          initialValue: _election?.code,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Election'),
          items: [
            for (final e in elections) DropdownMenuItem(value: e.code, child: Text(e.name)),
          ],
          onChanged: (code) => setState(
            () => _selectElection(elections.firstWhere((e) => e.code == code)),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('polling-unit'),
          initialValue: _unit?.code,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Polling unit'),
          items: [
            for (final u in units)
              DropdownMenuItem(value: u.code, child: Text('${u.code} · ${u.name}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: units.length == 1
              ? null
              : (code) => setState(() => _selectUnit(units.firstWhere((u) => u.code == code))),
        ),
        if (_election != null) ...[
          const SizedBox(height: 16),
          const Text('VOTES PER PARTY', style: _label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final party in _election!.parties)
                SizedBox(
                  width: 150,
                  child: _NumberInput(controller: _votes[party.acronym]!, label: party.acronym, hint: party.name),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('TOTALS', style: _label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(width: 190, child: _NumberInput(controller: _total, label: 'Total valid votes')),
              SizedBox(width: 190, child: _NumberInput(controller: _rejected, label: 'Rejected votes')),
              SizedBox(width: 190, child: _NumberInput(controller: _accredited, label: 'Accredited voters')),
              SizedBox(width: 190, child: _NumberInput(controller: _registered, label: 'Registered voters')),
            ],
          ),
          const SizedBox(height: 14),
          if (problems.isNotEmpty)
            for (final p in problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: TgcgColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p, style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              )
          else if (_complete)
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: TgcgColors.success, size: 18),
                SizedBox(width: 8),
                Text('The figures add up.', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          const SizedBox(height: 12),
          if (problems.isNotEmpty)
            const Text(
              'You can still submit: a result that does not add up goes to a coordinator for review.',
              style: TextStyle(color: TgcgColors.muted, fontSize: 12),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _complete && !_saving ? _submit : null,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: const Text('Submit result with GPS'),
          ),
        ],
      ],
    );
  }

  static const _label = TextStyle(
    color: TgcgColors.muted,
    fontSize: 10.5,
    fontWeight: FontWeight.w900,
    letterSpacing: .8,
  );
}

class _NumberInput extends StatelessWidget {
  const _NumberInput({required this.controller, required this.label, this.hint});
  final TextEditingController controller;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, helperText: hint, helperMaxLines: 1),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: TgcgColors.muted, size: 32),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      );
}
