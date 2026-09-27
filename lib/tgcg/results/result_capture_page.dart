import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../session.dart';
import 'result_operations_store.dart';

class ResultCapturePage extends StatefulWidget {
  const ResultCapturePage({super.key});

  @override
  State<ResultCapturePage> createState() => _ResultCapturePageState();
}

class _ResultCapturePageState extends State<ResultCapturePage> {
  RecordStatus? statusFilter;
  SubmissionSource? sourceFilter;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = ResultOperations.of(context);
    var submissions = store.submissionsForScope(session.scope);

    if (statusFilter != null) {
      submissions = submissions.where((item) => item.status == statusFilter).toList();
    }
    if (sourceFilter != null) {
      submissions = submissions.where((item) => item.source == sourceFilter).toList();
    }

    final review = store.reviewQueueForScope(session.scope);
    final canSubmit = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.submitElectionResult,
    );

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Result Capture & Verification',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${session.scope.label}: unofficial field submissions, validation and human review.',
                    style: const TextStyle(color: TgcgApp.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const _UnofficialBadge(),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric('Submissions', '${submissions.length}', Icons.ballot_outlined),
            _Metric('Human review', '${review.length}', Icons.fact_check_outlined),
            _Metric(
              'Verified',
              '${submissions.where((item) => item.status == RecordStatus.verified).length}',
              Icons.verified_outlined,
            ),
            _Metric(
              'With evidence',
              '${submissions.where((item) => item.resultForm != null).length}',
              Icons.document_scanner_outlined,
            ),
          ],
        ),
        if (canSubmit) ...[
          const SizedBox(height: 16),
          _SubmissionPanel(session: session),
        ],
        const SizedBox(height: 16),
        _FilterBar(
          status: statusFilter,
          source: sourceFilter,
          onStatusChanged: (value) => setState(() => statusFilter = value),
          onSourceChanged: (value) => setState(() => sourceFilter = value),
          onClear: () => setState(() {
            statusFilter = null;
            sourceFilter = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 1040) {
              return Column(
                children: [
                  _SubmissionList(submissions: submissions),
                  const SizedBox(height: 16),
                  _ReviewQueue(submissions: review),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: _SubmissionList(submissions: submissions)),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: _ReviewQueue(submissions: review)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SubmissionPanel extends StatefulWidget {
  const _SubmissionPanel({required this.session});

  final TgcgSessionController session;

  @override
  State<_SubmissionPanel> createState() => _SubmissionPanelState();
}

class _SubmissionPanelState extends State<_SubmissionPanel> {
  final p1 = TextEditingController(text: '120');
  final p2 = TextEditingController(text: '80');
  final p3 = TextEditingController(text: '40');
  final p4 = TextEditingController(text: '10');
  final total = TextEditingController(text: '250');
  final accredited = TextEditingController(text: '262');
  final rejected = TextEditingController(text: '12');
  final registered = TextEditingController(text: '600');

  SubmissionSource source = SubmissionSource.app;
  _OcrDemo ocrDemo = _OcrDemo.notAvailable;
  bool attachForm = true;
  bool expanded = false;
  int pollingUnitIndex = 0;

  @override
  void dispose() {
    for (final controller in [p1, p2, p3, p4, total, accredited, rejected, registered]) {
      controller.dispose();
    }
    super.dispose();
  }

  static const samplePollingUnits = <GeographicScope>[
    GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
      wardId: 'KD-KN-W02',
      wardName: 'Ward 02',
      pollingUnitId: 'KD-KN-W02-PU007',
      pollingUnitName: 'PU 007',
    ),
    GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NC',
      zoneName: 'North Central',
      stateId: 'BN',
      stateName: 'Benue',
      lgaId: 'BN-MAKURDI',
      lgaName: 'Makurdi',
      wardId: 'BN-MK-W02',
      wardName: 'Ward 02',
      pollingUnitId: 'BN-MK-W02-PU009',
      pollingUnitName: 'PU 009',
    ),
    GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'SW',
      zoneName: 'South West',
      stateId: 'LA',
      stateName: 'Lagos',
      lgaId: 'LA-IKEJA',
      lgaName: 'Ikeja',
      wardId: 'LA-IK-W04',
      wardName: 'Ward 04',
      pollingUnitId: 'LA-IK-W04-PU015',
      pollingUnitName: 'PU 015',
    ),
  ];

  int _int(TextEditingController controller) => int.tryParse(controller.text.trim()) ?? 0;

  void _submit() {
    final scope = samplePollingUnits[pollingUnitIndex];
    final votes = <String, int>{
      'P1': _int(p1),
      'P2': _int(p2),
      'P3': _int(p3),
      'P4': _int(p4),
    };

    Map<String, int>? ocrVotes;
    double? confidence;
    if (ocrDemo == _OcrDemo.match) {
      ocrVotes = Map.of(votes);
      confidence = .96;
    } else if (ocrDemo == _OcrDemo.difference) {
      ocrVotes = Map.of(votes)..update('P2', (value) => value > 0 ? value - 1 : 1);
      confidence = .84;
    }

    final evidence = attachForm
        ? EvidenceAttachment(
            id: 'FORM-LOCAL-${DateTime.now().millisecondsSinceEpoch}',
            type: EvidenceType.resultForm,
            fileName: 'result-form.jpg',
            createdAt: DateTime.now().toUtc(),
            uploaderId: widget.session.accessId.isEmpty
                ? widget.session.operatorName
                : widget.session.accessId,
            contentHash: 'sha256:pending-device-hash',
            mimeType: 'image/jpeg',
            caption: 'Prototype attached result-form record.',
            origin: RecordOrigin.localEntry,
          )
        : null;

    final saved = ResultOperations.of(context, listen: false).submit(
      pollingUnitScope: scope,
      submittedBy: widget.session.accessId.isEmpty
          ? widget.session.operatorName
          : widget.session.accessId,
      source: source,
      partyVotes: votes,
      totalVotesRecorded: _int(total),
      accreditedVoters: _int(accredited),
      rejectedVotes: _int(rejected),
      registeredVoters: _int(registered),
      resultForm: evidence,
      ocrPartyVotes: ocrVotes,
      ocrConfidence: confidence,
    );

    final needsReview = saved.validation?.requiresHumanReview == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          needsReview
              ? '${saved.id} saved and routed to human review.'
              : '${saved.id} saved with validation checks passed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New result submission',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: TgcgApp.ink,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Prototype form. Party codes and polling units will come from verified election configuration.',
                          style: TextStyle(color: TgcgApp.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => expanded = !expanded),
                    icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    label: Text(expanded ? 'Close form' : 'Open form'),
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final fields = [
                    DropdownButtonFormField<int>(
                      initialValue: pollingUnitIndex,
                      decoration: const InputDecoration(labelText: 'Polling unit'),
                      items: List.generate(
                        samplePollingUnits.length,
                        (index) => DropdownMenuItem(
                          value: index,
                          child: Text(samplePollingUnits[index].label),
                        ),
                      ),
                      onChanged: (value) => setState(() => pollingUnitIndex = value ?? 0),
                    ),
                    DropdownButtonFormField<SubmissionSource>(
                      initialValue: source,
                      decoration: const InputDecoration(labelText: 'Submission source'),
                      items: SubmissionSource.values
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.name.toUpperCase()),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => source = value ?? SubmissionSource.app),
                    ),
                  ];
                  if (compact) {
                    return Column(children: [fields[0], const SizedBox(height: 12), fields[1]]);
                  }
                  return Row(children: [Expanded(child: fields[0]), const SizedBox(width: 12), Expanded(child: fields[1])]);
                }),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth < 760
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 24) / 4;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _NumberField(width: width, controller: p1, label: 'P1 votes'),
                      _NumberField(width: width, controller: p2, label: 'P2 votes'),
                      _NumberField(width: width, controller: p3, label: 'P3 votes'),
                      _NumberField(width: width, controller: p4, label: 'P4 votes'),
                    ],
                  );
                }),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth < 760
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 24) / 4;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _NumberField(width: width, controller: total, label: 'Valid votes total'),
                      _NumberField(width: width, controller: rejected, label: 'Rejected votes'),
                      _NumberField(width: width, controller: accredited, label: 'Accredited voters'),
                      _NumberField(width: width, controller: registered, label: 'Registered voters'),
                    ],
                  );
                }),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      selected: attachForm,
                      label: const Text('Attach result-form evidence'),
                      avatar: const Icon(Icons.image_outlined, size: 18),
                      onSelected: (value) => setState(() => attachForm = value),
                    ),
                    SizedBox(
                      width: 250,
                      child: DropdownButtonFormField<_OcrDemo>(
                        initialValue: ocrDemo,
                        decoration: const InputDecoration(labelText: 'OCR comparison hook'),
                        items: const [
                          DropdownMenuItem(value: _OcrDemo.notAvailable, child: Text('Not available')),
                          DropdownMenuItem(value: _OcrDemo.match, child: Text('Matches manual entry')),
                          DropdownMenuItem(value: _OcrDemo.difference, child: Text('Difference detected')),
                        ],
                        onChanged: (value) => setState(() => ocrDemo = value ?? _OcrDemo.notAvailable),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Validate & save'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

enum _OcrDemo { notAvailable, match, difference }

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.width,
    required this.controller,
    required this.label,
  });

  final double width;
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.source,
    required this.onStatusChanged,
    required this.onSourceChanged,
    required this.onClear,
  });

  final RecordStatus? status;
  final SubmissionSource? source;
  final ValueChanged<RecordStatus?> onStatusChanged;
  final ValueChanged<SubmissionSource?> onSourceChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<RecordStatus?>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All statuses')),
                    ...RecordStatus.values.map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(_label(value.name)),
                        )),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<SubmissionSource?>(
                  initialValue: source,
                  decoration: const InputDecoration(labelText: 'Source'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All sources')),
                    ...SubmissionSource.values.map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name.toUpperCase()),
                        )),
                  ],
                  onChanged: onSourceChanged,
                ),
              ),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
      );
}

class _SubmissionList extends StatelessWidget {
  const _SubmissionList({required this.submissions});

  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Submission ledger',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink),
              ),
              const SizedBox(height: 4),
              const Text(
                'Every field record remains unofficial and keeps its source, evidence and validation state.',
                style: TextStyle(color: TgcgApp.muted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              if (submissions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('No result submissions match this view.')),
                )
              else
                ...submissions.map((item) => _SubmissionTile(submission: item)),
            ],
          ),
        ),
      );
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission});

  final ElectionResultSubmission submission;

  @override
  Widget build(BuildContext context) {
    final validation = submission.validation;
    final review = validation?.requiresHumanReview == true;
    final accent = review ? const Color(0xFFB54708) : TgcgApp.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E9E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(review ? Icons.fact_check_outlined : Icons.ballot_outlined, color: accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submission.id,
                      style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      submission.pollingUnitScope.label,
                      style: const TextStyle(color: TgcgApp.muted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              _Pill(submission.source.name.toUpperCase(), const Color(0xFF52606D)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...submission.partyVotes.entries.map((entry) => _Pill('${entry.key}: ${entry.value}', TgcgApp.primary)),
              _Pill('Total: ${submission.totalVotesRecorded}', const Color(0xFF355C7D)),
              _Pill(_label(submission.status.name), _statusColor(submission.status)),
              if (submission.resultForm != null)
                const _Pill('Form evidence', Color(0xFF6B4F9B)),
            ],
          ),
          if (validation != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  validation.requiresHumanReview ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: validation.requiresHumanReview ? const Color(0xFFB54708) : TgcgApp.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    validation.requiresHumanReview
                        ? 'Human review required'
                        : 'Automated integrity checks passed',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
                if (validation.ocrConfidence != null)
                  Text(
                    'OCR ${(validation.ocrConfidence! * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewQueue extends StatelessWidget {
  const _ReviewQueue({required this.submissions});

  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final canVerify = TgcgPermissionPolicy.allows(session.role!, TgcgCapability.verifyElectionResult);
    final canDispute = TgcgPermissionPolicy.allows(session.role!, TgcgCapability.disputeElectionResult);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Human review queue',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'Flags are explanations for a reviewer; automated checks do not silently change submitted figures.',
              style: TextStyle(color: TgcgApp.muted, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (submissions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('No submissions currently require review.')),
              )
            else
              ...submissions.map((item) {
                final notes = item.validation?.notes ?? const <String>[];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFAF2),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFF1DEC0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.id,
                          style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                      const SizedBox(height: 4),
                      Text(item.pollingUnitScope.label,
                          style: const TextStyle(color: TgcgApp.muted, fontSize: 10.5)),
                      const SizedBox(height: 9),
                      if (notes.isEmpty)
                        const Text('Record is awaiting reviewer action.',
                            style: TextStyle(color: TgcgApp.muted, fontSize: 11))
                      else
                        ...notes.map((note) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 5),
                                    child: Icon(Icons.circle, size: 5, color: Color(0xFFB54708)),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(note,
                                        style: const TextStyle(color: TgcgApp.muted, fontSize: 11, height: 1.35)),
                                  ),
                                ],
                              ),
                            )),
                      if (item.disputeReason != null) ...[
                        const SizedBox(height: 6),
                        Text('Dispute: ${item.disputeReason}',
                            style: const TextStyle(color: Color(0xFFB42318), fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                      if (canVerify || canDispute) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (canVerify)
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  final ok = ResultOperations.of(context, listen: false).verify(
                                    submissionId: item.id,
                                    verifierId: session.accessId.isEmpty ? session.operatorName : session.accessId,
                                    role: session.role!,
                                    userScope: session.scope,
                                  );
                                  if (!ok) _showDenied(context);
                                },
                                icon: const Icon(Icons.verified_outlined, size: 18),
                                label: const Text('Verify'),
                              ),
                            if (canDispute)
                              OutlinedButton.icon(
                                onPressed: () => _openDispute(context, item, session),
                                icon: const Icon(Icons.flag_outlined, size: 18),
                                label: const Text('Dispute'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _openDispute(
    BuildContext context,
    ElectionResultSubmission item,
    TgcgSessionController session,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Dispute ${item.id}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'State the verification concern',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Flag dispute'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;

    final ok = ResultOperations.of(context, listen: false).dispute(
      submissionId: item.id,
      reviewerId: session.accessId.isEmpty ? session.operatorName : session.accessId,
      reason: reason,
      role: session.role!,
      userScope: session.scope,
    );
    if (!ok && context.mounted) _showDenied(context);
  }

  void _showDenied(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This role or geographic scope cannot perform that action.')),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: TgcgApp.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: TgcgApp.primary),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                    Text(label, style: const TextStyle(color: TgcgApp.muted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
      );
}

class _UnofficialBadge extends StatelessWidget {
  const _UnofficialBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF8B6513).withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF8B6513).withValues(alpha: .22)),
        ),
        child: const Text(
          'UNOFFICIAL FIELD DATA',
          style: TextStyle(
            color: Color(0xFF8B6513),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      );
}

Color _statusColor(RecordStatus status) => switch (status) {
      RecordStatus.verified => TgcgApp.primary,
      RecordStatus.disputed || RecordStatus.rejected => const Color(0xFFB42318),
      RecordStatus.underReview => const Color(0xFFB54708),
      RecordStatus.submitted => const Color(0xFF2563EB),
      _ => const Color(0xFF52606D),
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty ? spaced : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
