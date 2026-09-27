import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../membership/membership_store.dart';
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
    var submissions = store.submissionsForScope(session.scope);

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
    final allScoped = store.submissionsForScope(session.scope);
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
              '${session.scope.label}: evidence-led capture, OCR comparison, automated checks and human verification for unofficial field results.',
          trailing: const TgcgStatusPill(
            label: 'UNOFFICIAL FIELD DATA',
            color: TgcgColors.warning,
            icon: Icons.info_outline_rounded,
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
          app: allScoped.where((item) => item.source == SubmissionSource.app).length,
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

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.submissions,
    required this.review,
    required this.verified,
    required this.evidence,
    required this.app,
  });

  final int submissions;
  final int review;
  final int verified;
  final int evidence;
  final int app;

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
                detail: 'All field records in current scope',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Human review',
                value: '$review',
                detail: 'OCR, duplicate or validation flags',
                icon: Icons.psychology_alt_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified',
                value: '$verified',
                detail: 'Reviewer-confirmed field records',
                icon: Icons.verified_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Form evidence',
                value: '$evidence',
                detail: 'Submissions with result-form evidence',
                icon: Icons.document_scanner_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'App sourced',
                value: '$app',
                detail: 'APP source tag retained for audit',
                icon: Icons.phone_android_rounded,
                tone: TgcgMetricTone.neutral,
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
  String? selectedPollingUnitId;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      p1,
      p2,
      p3,
      p4,
      total,
      accredited,
      rejected,
      registered,
    ]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      p1,
      p2,
      p3,
      p4,
      total,
      accredited,
      rejected,
      registered,
    ]) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

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
          'Manual figures remain authoritative field input. OCR assists comparison and never silently overwrites submitted values.',
      trailing: TgcgStatusPill(
        label: requiresReview ? 'REVIEW EXPECTED' : 'CHECKS READY',
        color: requiresReview ? TgcgColors.ai : TgcgColors.success,
        icon: requiresReview
            ? Icons.fact_check_outlined
            : Icons.check_circle_outline_rounded,
      ),
      child: Column(
        children: [
          _WorkflowRail(
            hasEvidence: attachForm,
            ocrAvailable: ocrDemo != _OcrDemo.notAvailable,
            checksPassed: arithmeticValid && turnoutValid && !duplicate,
            reviewExpected: requiresReview,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final evidence = _EvidencePanel(
                attachForm: attachForm,
                source: source,
                selectedUnit: selectedUnit,
                onAttachChanged: (value) => setState(() => attachForm = value),
                onSourceChanged: (value) => setState(() => source = value),
              );
              final extraction = _ExtractionPanel(
                units: units,
                selectedPollingUnitId: selectedPollingUnitId,
                onUnitChanged: (value) =>
                    setState(() => selectedPollingUnitId = value),
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
                onOcrChanged: (value) => setState(() => ocrDemo = value),
              );
              if (constraints.maxWidth < 980) {
                return Column(
                  children: [
                    evidence,
                    const SizedBox(height: 14),
                    extraction,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: evidence),
                  const SizedBox(width: 14),
                  Expanded(flex: 7, child: extraction),
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
            onSubmit: selectedUnit == null
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

  void _submit(
    BuildContext context, {
    required TgcgSessionController session,
    required GeographicScope scope,
  }) {
    final evidence = attachForm
        ? EvidenceAttachment(
            id: 'FORM-LOCAL-${DateTime.now().millisecondsSinceEpoch}',
            type: EvidenceType.resultForm,
            fileName: 'result-form.jpg',
            createdAt: DateTime.now().toUtc(),
            uploaderId: session.accessId.isEmpty
                ? session.operatorName
                : session.accessId,
            contentHash: 'sha256:pending-device-hash',
            mimeType: 'image/jpeg',
            caption:
                'Prototype result-form evidence. Production upload will preserve the original file and device-generated content hash.',
            origin: RecordOrigin.localEntry,
          )
        : null;

    final saved = ResultOperations.of(context, listen: false).submit(
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
    );

    final needsReview = saved.validation?.requiresHumanReview == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          needsReview
              ? '${saved.id} saved and routed to human review.'
              : '${saved.id} saved with automated integrity checks passed.',
        ),
      ),
    );
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
      (
        label: 'Evidence',
        icon: Icons.image_outlined,
        done: hasEvidence,
        color: TgcgColors.primary,
      ),
      (
        label: 'OCR Extraction',
        icon: Icons.document_scanner_outlined,
        done: ocrAvailable,
        color: TgcgColors.ai,
      ),
      (
        label: 'Validation',
        icon: Icons.rule_folder_outlined,
        done: checksPassed,
        color: TgcgColors.info,
      ),
      (
        label: 'Human Review',
        icon: Icons.fact_check_outlined,
        done: !reviewExpected,
        color: TgcgColors.warning,
      ),
      (
        label: 'Submit',
        icon: Icons.send_outlined,
        done: false,
        color: TgcgColors.success,
      ),
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
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: step.color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(step.icon, size: 17, color: step.color),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    step.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: TgcgColors.ink,
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
  final dynamic selectedUnit;
  final ValueChanged<bool> onAttachChanged;
  final ValueChanged<SubmissionSource> onSourceChanged;

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
              style: TextStyle(
                color: TgcgColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'The original result form remains separate from OCR and manual figures.',
              style: TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 13),
            Container(
              height: 260,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2F0),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: TgcgColors.border),
              ),
              child: attachForm
                  ? Stack(
                      children: [
                        const Center(child: _ResultFormPreview()),
                        const Positioned(
                          top: 12,
                          left: 12,
                          child: TgcgStatusPill(
                            label: 'ORIGINAL',
                            color: TgcgColors.primary,
                            icon: Icons.image_outlined,
                            compact: true,
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .94),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.fingerprint_rounded,
                                  size: 15,
                                  color: TgcgColors.primary,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'SHA-256 generated on device before sync',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const TgcgEmptyState(
                      icon: Icons.image_not_supported_outlined,
                      title: 'No image evidence selected',
                      message:
                          'SMS/USSD can submit alphanumeric results without media; app evidence can be attached where available.',
                    ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  selected: attachForm,
                  avatar: const Icon(Icons.attach_file_rounded, size: 17),
                  label: const Text('Result-form evidence'),
                  onSelected: onAttachChanged,
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<SubmissionSource>(
                    initialValue: source,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: SubmissionSource.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onSourceChanged(value);
                    },
                  ),
                ),
              ],
            ),
            if (selectedUnit != null) ...[
              const SizedBox(height: 10),
              Text(
                selectedUnit.scope.label,
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

class _ResultFormPreview extends StatelessWidget {
  const _ResultFormPreview();

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        height: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Text(
                'RESULT FORM',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(height: 5, color: const Color(0xFFE9EEEC)),
            const SizedBox(height: 8),
            ...List.generate(
              5,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 9,
                      color: const Color(0xFFE2E8E5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 9,
                        color: const Color(0xFFF0F3F2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 32,
                      height: 13,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCAD5D0)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD7DFDC)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 28,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD7DFDC)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ExtractionPanel extends StatelessWidget {
  const _ExtractionPanel({
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

  final List<dynamic> units;
  final String? selectedPollingUnitId;
  final ValueChanged<String?> onUnitChanged;
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
  final ValueChanged<_OcrDemo> onOcrChanged;

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
              '2. Extraction & manual entry',
              style: TextStyle(
                color: TgcgColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Compare AI extraction with the operator-entered figures. Differences are flagged for review.',
              style: TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 13),
            LayoutBuilder(
              builder: (context, constraints) {
                final unitField = DropdownButtonFormField<String>(
                  initialValue: selectedPollingUnitId,
                  decoration: const InputDecoration(labelText: 'Canonical polling unit'),
                  isExpanded: true,
                  items: units
                      .map<DropdownMenuItem<String>>(
                        (unit) => DropdownMenuItem(
                          value: unit.code as String,
                          child: Text(
                            '${unit.code} • ${unit.scope.label}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: units.isEmpty ? null : onUnitChanged,
                );
                final ocrField = DropdownButtonFormField<_OcrDemo>(
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
                  onChanged: (value) {
                    if (value != null) onOcrChanged(value);
                  },
                );
                if (constraints.maxWidth < 650) {
                  return Column(
                    children: [
                      unitField,
                      const SizedBox(height: 10),
                      ocrField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: unitField),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: ocrField),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Column(
                children: [
                  const _ComparisonHeader(),
                  const Divider(height: 18),
                  _ComparisonRow(
                    label: 'P1',
                    controller: p1,
                    ocrValue: ocrVotes?['P1'],
                  ),
                  _ComparisonRow(
                    label: 'P2',
                    controller: p2,
                    ocrValue: ocrVotes?['P2'],
                  ),
                  _ComparisonRow(
                    label: 'P3',
                    controller: p3,
                    ocrValue: ocrVotes?['P3'],
                  ),
                  _ComparisonRow(
                    label: 'P4',
                    controller: p4,
                    ocrValue: ocrVotes?['P4'],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _NumberField(
                      width: width,
                      controller: total,
                      label: 'Valid votes total',
                    ),
                    _NumberField(
                      width: width,
                      controller: rejected,
                      label: 'Rejected votes',
                    ),
                    _NumberField(
                      width: width,
                      controller: accredited,
                      label: 'Accredited voters',
                    ),
                    _NumberField(
                      width: width,
                      controller: registered,
                      label: 'Registered voters',
                    ),
                  ],
                );
              },
            ),
            if (ocrConfidence != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.psychology_alt_outlined,
                    size: 18,
                    color: TgcgColors.ai,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'OCR confidence ${(ocrConfidence! * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: TgcgColors.ai,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'AI assistance only',
                    style: TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              'Party',
              style: TextStyle(fontSize: 10, color: TgcgColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              'Manual entry',
              style: TextStyle(fontSize: 10, color: TgcgColors.muted),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              'OCR',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10, color: TgcgColors.muted),
            ),
          ),
          SizedBox(width: 30),
        ],
      );
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
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
            width: 54,
            child: Text(
              label,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 43,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              ocrValue?.toString() ?? '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: mismatch ? TgcgColors.danger : TgcgColors.ai,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Icon(
              ocrValue == null
                  ? Icons.remove_circle_outline_rounded
                  : mismatch
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_rounded,
              size: 18,
              color: ocrValue == null
                  ? TgcgColors.muted
                  : mismatch
                      ? TgcgColors.warning
                      : TgcgColors.success,
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
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: requiresReview
              ? TgcgColors.ai.withValues(alpha: .045)
              : TgcgColors.success.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: requiresReview
                ? TgcgColors.ai.withValues(alpha: .18)
                : TgcgColors.success.withValues(alpha: .17),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final checks = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Check(
                  label: 'Canonical PU',
                  ok: hasCanonicalUnit,
                  detail: hasCanonicalUnit ? 'Matched' : 'Required',
                ),
                _Check(
                  label: 'Arithmetic',
                  ok: arithmeticValid,
                  detail: '$partySum / $enteredTotal',
                ),
                _Check(
                  label: 'Turnout bounds',
                  ok: turnoutValid,
                  detail: turnoutValid ? 'Valid' : 'Review',
                ),
                _Check(
                  label: 'Duplicate',
                  ok: !duplicate,
                  detail: duplicate ? 'Detected' : 'Clear',
                ),
                _Check(
                  label: 'OCR / manual',
                  ok: ocrMatches != false,
                  detail: ocrMatches == null
                      ? 'Not available'
                      : ocrMatches!
                          ? 'Match'
                          : 'Difference',
                ),
              ],
            );
            final action = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TgcgStatusPill(
                  label: requiresReview
                      ? 'ROUTE TO HUMAN REVIEW'
                      : 'AUTOMATED CHECKS PASSED',
                  color: requiresReview ? TgcgColors.ai : TgcgColors.success,
                  icon: requiresReview
                      ? Icons.person_search_outlined
                      : Icons.verified_outlined,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onSubmit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Validate & save'),
                ),
              ],
            );
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  checks,
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: checks),
                const SizedBox(width: 16),
                action,
              ],
            );
          },
        ),
      );
}

class _Check extends StatelessWidget {
  const _Check({required this.label, required this.ok, required this.detail});

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            '$label • $detail',
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Submission filters',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: TgcgColors.ink,
                ),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<RecordStatus?>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All statuses'),
                  ),
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
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All sources'),
                  ),
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
            'Source, evidence and validation state remain attached to each unofficial field record.',
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
    final validation = submission.validation;
    final review = validation?.requiresHumanReview == true &&
        submission.status != RecordStatus.verified;
    final color = review ? TgcgColors.ai : _statusColor(submission.status);

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  review
                      ? Icons.fact_check_outlined
                      : Icons.ballot_outlined,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submission.id,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: TgcgColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      submission.pollingUnitScope.label,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              TgcgStatusPill(
                label: submission.source.name.toUpperCase(),
                color: TgcgColors.muted,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...submission.partyVotes.entries.map(
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
                label: _label(submission.status.name).toUpperCase(),
                color: _statusColor(submission.status),
                compact: true,
              ),
              if (submission.resultForm != null)
                const TgcgStatusPill(
                  label: 'FORM EVIDENCE',
                  color: TgcgColors.ai,
                  icon: Icons.image_outlined,
                  compact: true,
                ),
            ],
          ),
          if (validation != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  review
                      ? Icons.person_search_outlined
                      : Icons.check_circle_outline_rounded,
                  size: 17,
                  color: review ? TgcgColors.ai : TgcgColors.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    review
                        ? 'Human review required'
                        : submission.status == RecordStatus.verified
                            ? 'Reviewer verified'
                            : 'Automated integrity checks passed',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: TgcgColors.ink,
                    ),
                  ),
                ),
                if (validation.ocrConfidence != null)
                  Text(
                    'OCR ${(validation.ocrConfidence! * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: TgcgColors.ai,
                      fontWeight: FontWeight.w800,
                    ),
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
          'Automated checks explain concerns; reviewers decide whether a record is verified or disputed.',
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
              message:
                  'No current submission in this scope requires reviewer action.',
            )
          : Column(
              children: submissions.map((item) {
                final notes = item.validation?.notes ?? const <String>[];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TgcgColors.ai.withValues(alpha: .045),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: TgcgColors.ai.withValues(alpha: .16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.id,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
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
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (notes.isEmpty)
                        const Text(
                          'Record is awaiting reviewer action.',
                          style: TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 11,
                          ),
                        )
                      else
                        ...notes.map(
                          (note) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 15,
                                  color: TgcgColors.warning,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    note,
                                    style: const TextStyle(
                                      color: TgcgColors.muted,
                                      fontSize: 10.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (item.disputeReason != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Dispute: ${item.disputeReason}',
                          style: const TextStyle(
                            color: TgcgColors.danger,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (canVerify || canDispute) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (canVerify)
                              FilledButton.icon(
                                onPressed: () {
                                  final ok = ResultOperations.of(
                                    context,
                                    listen: false,
                                  ).verify(
                                    submissionId: item.id,
                                    verifierId: session.accessId.isEmpty
                                        ? session.operatorName
                                        : session.accessId,
                                    role: session.role!,
                                    userScope: session.scope,
                                  );
                                  if (!ok) _showDenied(context);
                                },
                                icon: const Icon(Icons.verified_outlined, size: 17),
                                label: const Text('Verify'),
                              ),
                            if (canDispute)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openDispute(context, item, session),
                                icon: const Icon(Icons.flag_outlined, size: 17),
                                label: const Text('Dispute'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
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
            labelText: 'Review reason',
            hintText: 'State the verification concern',
          ),
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
    if (reason == null || !context.mounted) return;

    final ok = ResultOperations.of(context, listen: false).dispute(
      submissionId: item.id,
      reviewerId:
          session.accessId.isEmpty ? session.operatorName : session.accessId,
      reason: reason,
      role: session.role!,
      userScope: session.scope,
    );
    if (!ok && context.mounted) _showDenied(context);
  }

  void _showDenied(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This role or geographic scope cannot perform that action.',
        ),
      ),
    );
  }
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
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
