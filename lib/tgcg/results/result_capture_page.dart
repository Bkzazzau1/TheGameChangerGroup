import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../location/gps_prompt.dart';
import '../membership/membership_store.dart';
import '../offline/offline_persistence.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
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
    final offline = OfflinePersistence.of(context);
    final allScoped = store.submissionsForScope(session.scope);
    var submissions = List<ElectionResultSubmission>.from(allScoped);

    if (statusFilter != null) {
      submissions = submissions
          .where((item) => item.status == statusFilter)
          .toList(growable: false);
    }
    if (sourceFilter != null) {
      submissions = submissions
          .where((item) => item.source == sourceFilter)
          .toList(growable: false);
    }

    final review = store.reviewQueueForScope(session.scope);
    final canSubmit = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.submitElectionResult,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'RESULT INTEGRITY',
          title: 'Result Capture & Verification',
          subtitle:
              '${session.scope.label}: evidence-led capture, validation and human review for unofficial field results.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const TgcgStatusPill(
                label: 'UNOFFICIAL FIELD DATA',
                color: TgcgColors.warning,
                icon: Icons.info_outline_rounded,
              ),
              _PersistencePill(offline: offline),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          submissions: allScoped.length,
          review: review.length,
          verified: allScoped
              .where((item) => item.status == RecordStatus.verified)
              .length,
          evidence: allScoped.where((item) => item.resultForm != null).length,
          queued: offline.pendingOutbox
              .where((item) => item.entityType == 'election_result')
              .length,
        ),
        if (canSubmit) ...[
          const SizedBox(height: 16),
          const _CaptureWorkspace(),
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
            final ledger = _SubmissionLedger(submissions: submissions);
            final queue = _ReviewQueue(submissions: review);
            if (constraints.maxWidth < 1060) {
              return Column(
                children: [
                  queue,
                  const SizedBox(height: 16),
                  ledger,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: ledger),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: queue),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PersistencePill extends StatelessWidget {
  const _PersistencePill({required this.offline});

  final OfflinePersistenceController offline;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (offline.state) {
      OfflinePersistenceState.ready when offline.isDurable => (
          'ENCRYPTED LOCAL STORE',
          TgcgColors.success,
          Icons.storage_rounded,
        ),
      OfflinePersistenceState.ready => (
          'VOLATILE WEB STORE',
          TgcgColors.warning,
          Icons.memory_rounded,
        ),
      OfflinePersistenceState.failed => (
          'LOCAL STORE ERROR',
          TgcgColors.danger,
          Icons.error_outline_rounded,
        ),
      _ => (
          'LOCAL STORE STARTING',
          TgcgColors.info,
          Icons.sync_rounded,
        ),
    };
    return TgcgStatusPill(label: label, color: color, icon: icon);
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.submissions,
    required this.review,
    required this.verified,
    required this.evidence,
    required this.queued,
  });

  final int submissions;
  final int review;
  final int verified;
  final int evidence;
  final int queued;

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
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Submissions',
                value: '$submissions',
                detail: 'All field records in scope',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Human review',
                value: '$review',
                detail: 'Validation or reconciliation attention',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified',
                value: '$verified',
                detail: 'Reviewer-confirmed records',
                icon: Icons.verified_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Form evidence',
                value: '$evidence',
                detail: 'Records with result-form metadata',
                icon: Icons.document_scanner_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Queued locally',
                value: '$queued',
                detail: 'Awaiting server acknowledgement',
                icon: Icons.cloud_upload_outlined,
                tone: queued == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _CaptureWorkspace extends StatefulWidget {
  const _CaptureWorkspace();

  @override
  State<_CaptureWorkspace> createState() => _CaptureWorkspaceState();
}

class _CaptureWorkspaceState extends State<_CaptureWorkspace> {
  final p1 = TextEditingController(text: '120');
  final p2 = TextEditingController(text: '80');
  final p3 = TextEditingController(text: '40');
  final p4 = TextEditingController(text: '10');
  final total = TextEditingController(text: '250');
  final accredited = TextEditingController(text: '262');
  final rejected = TextEditingController(text: '12');
  final registered = TextEditingController(text: '600');

  SubmissionSource source = SubmissionSource.app;
  _OcrDemo ocrDemo = _OcrDemo.match;
  bool attachForm = true;
  bool saving = false;
  String? selectedPollingUnitId;

  List<TextEditingController> get _controllers => [
        p1,
        p2,
        p3,
        p4,
        total,
        accredited,
        rejected,
        registered,
      ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  int _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  Map<String, int> get _votes => {
        'P1': _int(p1),
        'P2': _int(p2),
        'P3': _int(p3),
        'P4': _int(p4),
      };

  Map<String, int>? get _ocrVotes {
    if (ocrDemo == _OcrDemo.notAvailable) return null;
    final values = Map<String, int>.of(_votes);
    if (ocrDemo == _OcrDemo.difference) {
      values.update('P2', (value) => value > 0 ? value - 1 : 1);
    }
    return values;
  }

  double? get _ocrConfidence => switch (ocrDemo) {
        _OcrDemo.notAvailable => null,
        _OcrDemo.match => .96,
        _OcrDemo.difference => .84,
      };

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final results = ResultOperations.of(context);
    final units = membership.geography.pollingUnitsWithin(session.scope);

    if (units.isNotEmpty &&
        !units.any((unit) => unit.code == selectedPollingUnitId)) {
      selectedPollingUnitId = units.first.code;
      if (units.first.registeredVoters != null) {
        registered.text = '${units.first.registeredVoters}';
      }
    }

    final selectedUnit = selectedPollingUnitId == null
        ? null
        : membership.geography.pollingUnit(selectedPollingUnitId!);
    final sum = _votes.values.fold<int>(0, (value, item) => value + item);
    final arithmeticValid = sum == _int(total);
    final turnoutValid =
        _int(total) + _int(rejected) <= _int(accredited) &&
            _int(accredited) <= _int(registered);
    final ocrVotes = _ocrVotes;
    final ocrMatches = ocrVotes == null
        ? null
        : _votes.entries.every((entry) => ocrVotes[entry.key] == entry.value);
    final duplicate = selectedUnit == null
        ? false
        : results.submissions.any(
            (existing) =>
                existing.pollingUnitScope.pollingUnitId ==
                    selectedUnit.scope.pollingUnitId &&
                existing.status != RecordStatus.rejected &&
                existing.status != RecordStatus.archived,
          );
    final requiresReview =
        !arithmeticValid || !turnoutValid || duplicate || ocrMatches == false;

    return TgcgSectionCard(
      title: 'New result workflow',
      subtitle:
          'Original evidence, manual figures and OCR-derived values remain separate. Saving waits for the encrypted local journal before reporting success.',
      trailing: TgcgStatusPill(
        label: saving
            ? 'SAVING LOCALLY'
            : requiresReview
                ? 'REVIEW EXPECTED'
                : 'CHECKS READY',
        color: saving
            ? TgcgColors.info
            : requiresReview
                ? TgcgColors.ai
                : TgcgColors.success,
        icon: saving
            ? Icons.sync_rounded
            : requiresReview
                ? Icons.fact_check_outlined
                : Icons.check_circle_outline_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WorkflowRail(
            hasEvidence: attachForm,
            ocrAvailable: ocrDemo != _OcrDemo.notAvailable,
            checksPassed: arithmeticValid && turnoutValid && !duplicate,
            reviewExpected: requiresReview,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final evidence = _EvidencePanel(
                attachForm: attachForm,
                source: source,
                selectedUnit: selectedUnit,
                onAttachChanged: saving
                    ? null
                    : (value) => setState(() => attachForm = value),
                onSourceChanged: saving
                    ? null
                    : (value) => setState(() => source = value),
              );
              final entry = _EntryPanel(
                units: units,
                selectedPollingUnitId: selectedPollingUnitId,
                onUnitChanged: saving
                    ? null
                    : (value) => _selectUnit(value, membership.geography),
                p1: p1,
                p2: p2,
                p3: p3,
                p4: p4,
                total: total,
                accredited: accredited,
                rejected: rejected,
                registered: registered,
                ocrDemo: ocrDemo,
                ocrVotes: ocrVotes,
                ocrConfidence: _ocrConfidence,
                onOcrChanged: saving
                    ? null
                    : (value) => setState(() => ocrDemo = value),
              );
              if (constraints.maxWidth < 980) {
                return Column(
                  children: [
                    evidence,
                    const SizedBox(height: 14),
                    entry,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: evidence),
                  const SizedBox(width: 14),
                  Expanded(flex: 7, child: entry),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _ValidationPanel(
            partySum: sum,
            enteredTotal: _int(total),
            arithmeticValid: arithmeticValid,
            turnoutValid: turnoutValid,
            duplicate: duplicate,
            ocrMatches: ocrMatches,
            hasCanonicalUnit: selectedUnit != null,
            requiresReview: requiresReview,
            saving: saving,
            onSubmit: selectedUnit == null || saving
                ? null
                : () => _submit(
                      context,
                      session: session,
                      scope: selectedUnit.scope,
                    ),
          ),
        ],
      ),
    );
  }

  void _selectUnit(String? value, GeographyRegistry geography) {
    setState(() {
      selectedPollingUnitId = value;
      if (value != null) {
        final unit = geography.pollingUnit(value);
        final voters = unit?.registeredVoters;
        if (voters != null) registered.text = '$voters';
      }
    });
  }

  Future<void> _submit(
    BuildContext context, {
    required TgcgSessionController session,
    required GeographicScope scope,
  }) async {
    GpsFix? gps;
    if (source == SubmissionSource.app) {
      gps = await captureGps(context, required: true, action: 'submit this result');
      if (gps == null || !context.mounted) return;
    }
    setState(() => saving = true);
    try {
      final evidence = attachForm
          ? EvidenceAttachment(
              id: 'FORM-LOCAL-${DateTime.now().microsecondsSinceEpoch}',
              type: EvidenceType.resultForm,
              fileName: 'result-form.jpg',
              createdAt: DateTime.now().toUtc(),
              uploaderId: session.accessId.isEmpty
                  ? session.operatorName
                  : session.accessId,
              contentHash: 'sha256:pending-device-hash',
              mimeType: 'image/jpeg',
              caption:
                  'Metadata placeholder until native image capture and device hashing are connected.',
              origin: RecordOrigin.localEntry,
            )
          : null;

      final saved = await ResultOperations.of(context, listen: false).submit(
        pollingUnitScope: scope,
        submittedBy:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        source: source,
        partyVotes: _votes,
        totalVotesRecorded: _int(total),
        accreditedVoters: _int(accredited),
        rejectedVotes: _int(rejected),
        registeredVoters: _int(registered),
        resultForm: evidence,
        ocrPartyVotes: _ocrVotes,
        ocrConfidence: _ocrConfidence,
        gps: gps,
      );
      if (!context.mounted) return;
      final needsReview = saved.validation?.requiresHumanReview == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needsReview
                ? '${saved.id} encrypted locally, queued for sync and routed to human review.'
                : '${saved.id} encrypted locally and queued for server acknowledgement.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Result was not saved: $error')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

enum _OcrDemo { notAvailable, match, difference }

class _WorkflowRail extends StatelessWidget {
  const _WorkflowRail({
    required this.hasEvidence,
    required this.ocrAvailable,
    required this.checksPassed,
    required this.reviewExpected,
  });

  final bool hasEvidence;
  final bool ocrAvailable;
  final bool checksPassed;
  final bool reviewExpected;

  @override
  Widget build(BuildContext context) {
    final steps = <({String label, IconData icon, bool done, Color color})>[
      (label: 'Evidence', icon: Icons.image_outlined, done: hasEvidence, color: TgcgColors.primary),
      (label: 'OCR Extraction', icon: Icons.document_scanner_outlined, done: ocrAvailable, color: TgcgColors.ai),
      (label: 'Validation', icon: Icons.rule_folder_outlined, done: checksPassed, color: TgcgColors.info),
      (label: 'Human Review', icon: Icons.fact_check_outlined, done: !reviewExpected, color: TgcgColors.warning),
      (label: 'Local Journal', icon: Icons.storage_rounded, done: false, color: TgcgColors.success),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: steps.map((step) {
          final width = constraints.maxWidth >= 900
              ? (constraints.maxWidth - 32) / 5
              : constraints.maxWidth >= 520
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
          return Container(
            width: width,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: step.done
                  ? step.color.withValues(alpha: .07)
                  : TgcgColors.surfaceSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: step.done
                    ? step.color.withValues(alpha: .20)
                    : TgcgColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(step.icon, size: 17, color: step.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  step.done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 15,
                  color: step.done ? step.color : TgcgColors.muted,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.attachForm,
    required this.source,
    required this.selectedUnit,
    required this.onAttachChanged,
    required this.onSourceChanged,
  });

  final bool attachForm;
  final SubmissionSource source;
  final CanonicalPollingUnit? selectedUnit;
  final ValueChanged<bool>? onAttachChanged;
  final ValueChanged<SubmissionSource>? onSourceChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Original evidence',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'The original form remains distinct from OCR and manually entered figures.',
              style: TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 13),
            Container(
              height: 210,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEFF2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: TgcgColors.border),
              ),
              child: attachForm
                  ? const Center(child: _FormPlaceholder())
                  : const TgcgEmptyState(
                      icon: Icons.image_not_supported_outlined,
                      title: 'No image evidence selected',
                      message:
                          'Alphanumeric fallback submissions can be recorded without media.',
                    ),
            ),
            const SizedBox(height: 12),
            FilterChip(
              selected: attachForm,
              avatar: const Icon(Icons.attach_file_rounded, size: 17),
              label: const Text('Result-form evidence'),
              onSelected: onAttachChanged,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<SubmissionSource>(
              initialValue: source,
              decoration: const InputDecoration(labelText: 'Submission source'),
              items: SubmissionSource.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.name.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: onSourceChanged == null
                  ? null
                  : (value) {
                      if (value != null) onSourceChanged!(value);
                    },
            ),
            if (selectedUnit != null) ...[
              const SizedBox(height: 10),
              Text(
                selectedUnit!.scope.label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      );
}

class _FormPlaceholder extends StatelessWidget {
  const _FormPlaceholder();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.document_scanner_outlined, size: 42, color: TgcgColors.primary),
          SizedBox(height: 10),
          Text(
            'RESULT FORM METADATA',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 4),
          Text(
            'Native camera/file capture is the next device integration.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TgcgColors.muted, fontSize: 10),
          ),
        ],
      );
}

class _EntryPanel extends StatelessWidget {
  const _EntryPanel({
    required this.units,
    required this.selectedPollingUnitId,
    required this.onUnitChanged,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.p4,
    required this.total,
    required this.accredited,
    required this.rejected,
    required this.registered,
    required this.ocrDemo,
    required this.ocrVotes,
    required this.ocrConfidence,
    required this.onOcrChanged,
  });

  final List<CanonicalPollingUnit> units;
  final String? selectedPollingUnitId;
  final ValueChanged<String?>? onUnitChanged;
  final TextEditingController p1;
  final TextEditingController p2;
  final TextEditingController p3;
  final TextEditingController p4;
  final TextEditingController total;
  final TextEditingController accredited;
  final TextEditingController rejected;
  final TextEditingController registered;
  final _OcrDemo ocrDemo;
  final Map<String, int>? ocrVotes;
  final double? ocrConfidence;
  final ValueChanged<_OcrDemo>? onOcrChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2. Manual entry & OCR comparison',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'OCR is advisory. Manual figures are never silently replaced.',
              style: TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 13),
            DropdownButtonFormField<String>(
              initialValue: selectedPollingUnitId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Canonical polling unit'),
              items: units
                  .map(
                    (unit) => DropdownMenuItem(
                      value: unit.code,
                      child: Text(
                        '${unit.code} • ${unit.scope.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: units.isEmpty ? null : onUnitChanged,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<_OcrDemo>(
              initialValue: ocrDemo,
              decoration: const InputDecoration(labelText: 'OCR prototype state'),
              items: const [
                DropdownMenuItem(
                  value: _OcrDemo.notAvailable,
                  child: Text('Not available'),
                ),
                DropdownMenuItem(
                  value: _OcrDemo.match,
                  child: Text('Extraction matches manual'),
                ),
                DropdownMenuItem(
                  value: _OcrDemo.difference,
                  child: Text('Difference detected'),
                ),
              ],
              onChanged: onOcrChanged == null
                  ? null
                  : (value) {
                      if (value != null) onOcrChanged!(value);
                    },
            ),
            const SizedBox(height: 13),
            _VoteRow(label: 'P1', controller: p1, ocrValue: ocrVotes?['P1']),
            _VoteRow(label: 'P2', controller: p2, ocrValue: ocrVotes?['P2']),
            _VoteRow(label: 'P3', controller: p3, ocrValue: ocrVotes?['P3']),
            _VoteRow(label: 'P4', controller: p4, ocrValue: ocrVotes?['P4']),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _NumberField(width: width, controller: total, label: 'Valid votes total'),
                    _NumberField(width: width, controller: rejected, label: 'Rejected votes'),
                    _NumberField(width: width, controller: accredited, label: 'Accredited voters'),
                    _NumberField(width: width, controller: registered, label: 'Registered voters'),
                  ],
                );
              },
            ),
            if (ocrConfidence != null) ...[
              const SizedBox(height: 12),
              Text(
                'OCR confidence ${(ocrConfidence! * 100).toStringAsFixed(1)}% • AI assistance only',
                style: const TextStyle(
                  color: TgcgColors.ai,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      );
}

class _VoteRow extends StatelessWidget {
  const _VoteRow({
    required this.label,
    required this.controller,
    required this.ocrValue,
  });

  final String label;
  final TextEditingController controller;
  final int? ocrValue;

  @override
  Widget build(BuildContext context) {
    final manual = int.tryParse(controller.text.trim());
    final mismatch = ocrValue != null && manual != ocrValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Manual'),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              'OCR ${ocrValue?.toString() ?? '—'}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: mismatch ? TgcgColors.danger : TgcgColors.ai,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({
    required this.partySum,
    required this.enteredTotal,
    required this.arithmeticValid,
    required this.turnoutValid,
    required this.duplicate,
    required this.ocrMatches,
    required this.hasCanonicalUnit,
    required this.requiresReview,
    required this.saving,
    required this.onSubmit,
  });

  final int partySum;
  final int enteredTotal;
  final bool arithmeticValid;
  final bool turnoutValid;
  final bool duplicate;
  final bool? ocrMatches;
  final bool hasCanonicalUnit;
  final bool requiresReview;
  final bool saving;
  final Future<void> Function()? onSubmit;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: requiresReview
              ? TgcgColors.ai.withValues(alpha: .045)
              : TgcgColors.success.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Check('Canonical PU', hasCanonicalUnit, hasCanonicalUnit ? 'Matched' : 'Required'),
                _Check('Arithmetic', arithmeticValid, '$partySum / $enteredTotal'),
                _Check('Turnout bounds', turnoutValid, turnoutValid ? 'Valid' : 'Review'),
                _Check('Duplicate', !duplicate, duplicate ? 'Detected' : 'Clear'),
                _Check(
                  'OCR / manual',
                  ocrMatches != false,
                  ocrMatches == null
                      ? 'Not available'
                      : ocrMatches!
                          ? 'Match'
                          : 'Difference',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSubmit == null
                    ? null
                    : () async {
                        await onSubmit!();
                      },
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  saving
                      ? 'Encrypting & journaling…'
                      : requiresReview
                          ? 'Save & route to review'
                          : 'Validate & save locally',
                ),
              ),
            ),
          ],
        ),
      );
}

class _Check extends StatelessWidget {
  const _Check(this.label, this.ok, this.detail);

  final String label;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final color = ok ? TgcgColors.success : TgcgColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Text(
        '$label • $detail',
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<RecordStatus?>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All statuses')),
                  ...RecordStatus.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                  ),
                ],
                onChanged: onStatusChanged,
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<SubmissionSource?>(
                initialValue: source,
                decoration: const InputDecoration(labelText: 'Source'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All sources')),
                  ...SubmissionSource.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.name.toUpperCase()),
                    ),
                  ),
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
      );
}

class _SubmissionLedger extends StatelessWidget {
  const _SubmissionLedger({required this.submissions});

  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Submission ledger',
        subtitle:
            'Every record retains source, evidence and validation state. Totals are shown as submitted, not ranked.',
        child: submissions.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.ballot_outlined,
                title: 'No submissions in this view',
                message: 'Change the filters or capture a new field result.',
              )
            : Column(
                children: submissions
                    .map((item) => _SubmissionTile(submission: item))
                    .toList(),
              ),
      );
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission});

  final ElectionResultSubmission submission;

  @override
  Widget build(BuildContext context) {
    final review = submission.validation?.requiresHumanReview == true &&
        submission.status != RecordStatus.verified;
    final color = review ? TgcgColors.ai : _statusColor(submission.status);
    final parties = submission.partyVotes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ballot_outlined, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(submission.id, style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      submission.pollingUnitScope.label,
                      style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              TgcgStatusPill(
                label: _label(submission.status.name).toUpperCase(),
                color: _statusColor(submission.status),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...parties.map(
                (entry) => TgcgStatusPill(
                  label: '${entry.key}: ${entry.value}',
                  color: TgcgColors.primary,
                  compact: true,
                ),
              ),
              TgcgStatusPill(
                label: 'TOTAL ${submission.totalVotesRecorded}',
                color: TgcgColors.info,
                compact: true,
              ),
              TgcgStatusPill(
                label: submission.source.name.toUpperCase(),
                color: TgcgColors.muted,
                compact: true,
              ),
              if (submission.resultForm != null)
                const TgcgStatusPill(
                  label: 'FORM EVIDENCE',
                  color: TgcgColors.ai,
                  compact: true,
                ),
            ],
          ),
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
    final canVerify = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.verifyElectionResult,
    );
    final canDispute = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.disputeElectionResult,
    );

    return TgcgSectionCard(
      title: 'Human review queue',
      subtitle:
          'Automated checks identify concerns; authorized reviewers make the verification decision.',
      trailing: TgcgStatusPill(
        label: '${submissions.length} PENDING',
        color: submissions.isEmpty ? TgcgColors.success : TgcgColors.ai,
        icon: Icons.fact_check_outlined,
        compact: true,
      ),
      child: submissions.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.verified_outlined,
              title: 'Review queue is clear',
              message: 'No submission in this scope currently needs reviewer action.',
            )
          : Column(
              children: submissions
                  .map(
                    (item) => _ReviewTile(
                      item: item,
                      canVerify: canVerify,
                      canDispute: canDispute,
                      session: session,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _ReviewTile extends StatefulWidget {
  const _ReviewTile({
    required this.item,
    required this.canVerify,
    required this.canDispute,
    required this.session,
  });

  final ElectionResultSubmission item;
  final bool canVerify;
  final bool canDispute;
  final TgcgSessionController session;

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final notes = item.validation?.notes ?? const <String>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.ai.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TgcgColors.ai.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.id, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              TgcgStatusPill(
                label: _label(item.status.name).toUpperCase(),
                color: _statusColor(item.status),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.pollingUnitScope.label,
            style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 9),
            ...notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $note',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                ),
              ),
            ),
          ],
          if (widget.canVerify || widget.canDispute) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.canVerify)
                  FilledButton.icon(
                    onPressed: busy ? null : _verify,
                    icon: const Icon(Icons.verified_outlined, size: 17),
                    label: const Text('Verify'),
                  ),
                if (widget.canDispute)
                  OutlinedButton.icon(
                    onPressed: busy ? null : _dispute,
                    icon: const Icon(Icons.flag_outlined, size: 17),
                    label: const Text('Dispute'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _verify() async {
    setState(() => busy = true);
    try {
      final session = widget.session;
      final ok = await ResultOperations.of(context, listen: false).verify(
        submissionId: widget.item.id,
        verifierId: session.accessId.isEmpty ? session.operatorName : session.accessId,
        role: session.role!,
        userScope: session.scope,
      );
      if (!mounted) return;
      if (!ok) _showDenied(context);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _dispute() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Dispute ${widget.item.id}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Review reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Flag dispute'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;

    setState(() => busy = true);
    try {
      final session = widget.session;
      final ok = await ResultOperations.of(context, listen: false).dispute(
        submissionId: widget.item.id,
        reviewerId: session.accessId.isEmpty ? session.operatorName : session.accessId,
        reason: reason,
        role: session.role!,
        userScope: session.scope,
      );
      if (!mounted) return;
      if (!ok) _showDenied(context);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

void _showDenied(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('This role or geographic scope cannot perform that action.'),
    ),
  );
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Local persistence failed: $error')),
  );
}

Color _statusColor(RecordStatus status) => switch (status) {
      RecordStatus.verified => TgcgColors.success,
      RecordStatus.disputed || RecordStatus.rejected => TgcgColors.danger,
      RecordStatus.underReview => TgcgColors.ai,
      RecordStatus.submitted => TgcgColors.info,
      _ => TgcgColors.muted,
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  final clean = spaced.replaceAll('_', ' ');
  return clean.isEmpty
      ? clean
      : '${clean[0].toUpperCase()}${clean.substring(1)}';
}
