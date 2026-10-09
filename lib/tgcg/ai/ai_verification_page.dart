import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/tgcg_design.dart';

enum _AiWorkflow { pvc, result, identity }

class AiVerificationPage extends StatefulWidget {
  const AiVerificationPage({super.key});

  @override
  State<AiVerificationPage> createState() => _AiVerificationPageState();
}

class _AiVerificationPageState extends State<AiVerificationPage> {
  _AiWorkflow selected = _AiWorkflow.result;
  final reviewed = <String>{};

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'AI ASSISTED REVIEW',
          title: 'AI Verification Centre',
          subtitle:
              '${session.scope.label}: assisted PVC extraction, result-form verification and identity checks with human confirmation.',
          trailing: const TgcgStatusPill(
            label: 'HUMAN REVIEW',
            color: TgcgColors.accent,
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 18),
        const _Metrics(),
        const SizedBox(height: 16),
        _WorkflowSelector(
          selected: selected,
          onChanged: (value) => setState(() => selected = value),
        ),
        const SizedBox(height: 16),
        switch (selected) {
          _AiWorkflow.pvc => _PvcPanel(
              reviewed: reviewed,
              onConfirm: (id) => setState(() => reviewed.add(id)),
            ),
          _AiWorkflow.result => _ResultPanel(
              reviewed: reviewed,
              onConfirm: (id) => setState(() => reviewed.add(id)),
            ),
          _AiWorkflow.identity => _IdentityPanel(
              reviewed: reviewed,
              onConfirm: (id) => setState(() => reviewed.add(id)),
            ),
        },
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 520 ? 2 : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'PVC scans',
                value: '184',
                detail: '172 high-confidence reads',
                icon: Icons.credit_card_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Result forms',
                value: '63',
                detail: '7 require human review',
                icon: Icons.document_scanner_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Identity checks',
                value: '129',
                detail: '125 matched',
                icon: Icons.face_retouching_natural_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Review queue',
                value: '11',
                detail: 'Manual confirmation required',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _WorkflowSelector extends StatelessWidget {
  const _WorkflowSelector({required this.selected, required this.onChanged});

  final _AiWorkflow selected;
  final ValueChanged<_AiWorkflow> onChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
              value: _AiWorkflow.pvc,
              selected: selected,
              icon: Icons.credit_card_outlined,
              label: 'PVC Recognition',
              onChanged: onChanged,
            ),
            _Chip(
              value: _AiWorkflow.result,
              selected: selected,
              icon: Icons.document_scanner_outlined,
              label: 'Result OCR',
              onChanged: onChanged,
            ),
            _Chip(
              value: _AiWorkflow.identity,
              selected: selected,
              icon: Icons.face_outlined,
              label: 'Face & Liveness',
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.value,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onChanged,
  });

  final _AiWorkflow value;
  final _AiWorkflow selected;
  final IconData icon;
  final String label;
  final ValueChanged<_AiWorkflow> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value == selected;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? TgcgColors.primary : TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: active ? TgcgColors.primary : TgcgColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: active ? Colors.white : TgcgColors.muted),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : TgcgColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PvcPanel extends StatelessWidget {
  const _PvcPanel({required this.reviewed, required this.onConfirm});

  final Set<String> reviewed;
  final ValueChanged<String> onConfirm;

  @override
  Widget build(BuildContext context) => _ReviewLayout(
        preview: const _DocumentPreview(
          title: 'PVC image',
          icon: Icons.credit_card_rounded,
          badge: 'OCR 98.4%',
          lines: ['YUSUF, AMINA', 'VIN •••• 1842', 'Kaduna North', 'Ward 01'],
        ),
        details: _ReviewCard(
          title: 'Recognized voter identity',
          status: reviewed.contains('PVC-1842') ? 'CONFIRMED' : 'READY TO CONFIRM',
          statusColor: reviewed.contains('PVC-1842') ? TgcgColors.success : TgcgColors.accent,
          rows: const [
            ('Full name', 'Amina Yusuf'),
            ('VIN', '90F5 •••• 1842'),
            ('State', 'Kaduna'),
            ('LGA', 'Kaduna North'),
            ('Confidence', '98.4%'),
          ],
          checks: const [
            'PVC layout recognized',
            'Name fields extracted',
            'VIN pattern validated',
            'Geography resolved',
          ],
          buttonLabel: reviewed.contains('PVC-1842') ? 'Identity confirmed' : 'Confirm extracted identity',
          onPressed: reviewed.contains('PVC-1842') ? null : () => onConfirm('PVC-1842'),
        ),
      );
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.reviewed, required this.onConfirm});

  final Set<String> reviewed;
  final ValueChanged<String> onConfirm;

  @override
  Widget build(BuildContext context) => _ReviewLayout(
        preview: const _DocumentPreview(
          title: 'Polling-unit result form',
          icon: Icons.description_rounded,
          badge: 'OCR 96.8%',
          lines: ['PU 001 • Ward 01', 'ACCREDITED 312', 'REJECTED 6', 'TOTAL VALID 306'],
        ),
        details: _ReviewCard(
          title: 'Result comparison',
          status: reviewed.contains('RES-0001') ? 'VERIFIED' : 'MATCH FOUND',
          statusColor: TgcgColors.success,
          rows: const [
            ('Manual total votes', '306'),
            ('OCR total votes', '306'),
            ('Accredited voters', '312'),
            ('Rejected ballots', '6'),
            ('OCR confidence', '96.8%'),
          ],
          checks: const [
            'Arithmetic check passed',
            'Manual and OCR totals match',
            'Polling-unit code matched',
            'Result-form image linked',
          ],
          buttonLabel: reviewed.contains('RES-0001') ? 'Human review completed' : 'Confirm result review',
          onPressed: reviewed.contains('RES-0001') ? null : () => onConfirm('RES-0001'),
        ),
      );
}

class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({required this.reviewed, required this.onConfirm});

  final Set<String> reviewed;
  final ValueChanged<String> onConfirm;

  @override
  Widget build(BuildContext context) => _ReviewLayout(
        preview: const _FacePreview(),
        details: _ReviewCard(
          title: 'Agent identity check',
          status: reviewed.contains('AG-KD-001') ? 'CONFIRMED' : 'MATCH 97.9%',
          statusColor: TgcgColors.success,
          rows: const [
            ('Agent', 'Amina Yusuf'),
            ('Agent ID', 'AG-KD-001'),
            ('Liveness', 'Passed'),
            ('Face match', '97.9%'),
            ('Assigned PU', 'PU 001'),
          ],
          checks: const [
            'Live face detected',
            'Anti-spoof check passed',
            'Enrollment portrait matched',
            'Agent assignment resolved',
          ],
          buttonLabel: reviewed.contains('AG-KD-001') ? 'Identity confirmed' : 'Confirm agent identity',
          onPressed: reviewed.contains('AG-KD-001') ? null : () => onConfirm('AG-KD-001'),
        ),
      );
}

class _ReviewLayout extends StatelessWidget {
  const _ReviewLayout({required this.preview, required this.details});
  final Widget preview;
  final Widget details;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(children: [preview, const SizedBox(height: 16), details]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: preview),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: details),
            ],
          );
        },
      );
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.title,
    required this.icon,
    required this.badge,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final String badge;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: title,
        trailing: TgcgStatusPill(label: badge, color: TgcgColors.info, compact: true),
        child: Container(
          height: 330,
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: TgcgColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 38, color: TgcgColors.primary),
                  const Spacer(),
                  const Icon(Icons.center_focus_strong_rounded, color: TgcgColors.accent),
                ],
              ),
              const Spacer(),
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: TgcgColors.primarySoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(line, style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _FacePreview extends StatelessWidget {
  const _FacePreview();

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Live identity frame',
        trailing: const TgcgStatusPill(label: 'LIVENESS PASSED', color: TgcgColors.success, compact: true),
        child: Container(
          height: 330,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF04102C), Color(0xFF092565)]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const CircleAvatar(
                radius: 82,
                backgroundColor: Color(0xFF162B5D),
                child: Icon(Icons.person_rounded, size: 112, color: Color(0xFFAAB1C3)),
              ),
              Container(
                width: 196,
                height: 242,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(90),
                  border: Border.all(color: TgcgColors.accent, width: 2),
                ),
              ),
              const Positioned(
                bottom: 20,
                child: TgcgStatusPill(label: 'FACE MATCH 97.9%', color: TgcgColors.success),
              ),
            ],
          ),
        ),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.title,
    required this.status,
    required this.statusColor,
    required this.rows,
    required this.checks,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String status;
  final Color statusColor;
  final List<(String, String)> rows;
  final List<String> checks;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: title,
        trailing: TgcgStatusPill(label: status, color: statusColor, compact: true),
        child: Column(
          children: [
            ...rows.map((row) => _KeyValue(label: row.$1, value: row.$2)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Column(
                children: checks
                    .map(
                      (check) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: TgcgColors.success, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(check, style: const TextStyle(fontWeight: FontWeight.w700, color: TgcgColors.ink))),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPressed,
                icon: Icon(onPressed == null ? Icons.verified_rounded : Icons.fact_check_outlined),
                label: Text(buttonLabel),
              ),
            ),
          ],
        ),
      );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 11))),
            Text(value, style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900, fontSize: 12)),
          ],
        ),
      );
}
