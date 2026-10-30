import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show formatMoment;
import '../security/incident_security_panel.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';
import 'incident_actions.dart';

/// Opens one incident's full report: what was reported, where, evidence,
/// live video and the command actions the account may take.
Future<void> openIncidentReport(BuildContext context, FieldIncident incident) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => IncidentReportPage(incident: incident)),
    );

class IncidentReportPage extends StatelessWidget {
  const IncidentReportPage({super.key, required this.incident});

  /// The incident as it was when opened; the page follows later changes.
  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final current = FieldOperations.of(context)
            .incidents
            .where((item) => item.id == incident.id)
            .firstOrNull ??
        incident;
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [IncidentReportCard(incident: current, title: 'Incident report')],
      ),
    );
  }
}

/// An incident in full, as the Situation Room inspects it.
class IncidentReportCard extends StatelessWidget {
  const IncidentReportCard({
    super.key,
    required this.incident,
    this.title = 'Incident inspector',
  });

  final FieldIncident incident;
  final String title;

  @override
  Widget build(BuildContext context) {
    final item = incident;
    final color = incidentSeverityColor(item.severity);
    final store = FieldOperations.of(context);

    return TgcgSectionCard(
      title: title,
      subtitle: item.id,
      trailing: TgcgStatusPill(
        label: incidentSeverityLabel(item.severity),
        color: color,
        compact: true,
      ),
      trailingBeside: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(item.title, style: TgcgType.section),
          const SizedBox(height: 6),
          Text(
            item.summary ?? 'No additional incident summary was supplied.',
            style: TgcgType.support,
          ),
          const SizedBox(height: 14),
          _InspectorLine(
            icon: Icons.category_outlined,
            label: 'Category',
            value: item.category,
          ),
          _InspectorLine(
            icon: Icons.location_on_outlined,
            label: 'Location',
            value: item.scope.label,
          ),
          if (incidentLocationText(item) case final where?)
            _InspectorLine(
              icon: Icons.near_me_outlined,
              label: 'From the unit',
              value: where,
            ),
          _InspectorLine(
            icon: Icons.person_outline_rounded,
            label: 'Reporter',
            value: item.reporterId,
          ),
          _InspectorLine(
            icon: Icons.groups_2_outlined,
            label: 'Response owner',
            value: item.assignedTeam ?? 'Unassigned',
          ),
          _InspectorLine(
            icon: Icons.schedule_rounded,
            label: 'Reported',
            value: formatMoment(item.reportedAt.toLocal()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TgcgStatusPill(
                label: incidentStatusLabel(item.status),
                color: TgcgColors.primaryMid,
                compact: true,
              ),
              const Spacer(),
              Text('${item.evidence.length} evidence', style: TgcgType.caption),
            ],
          ),
          const SizedBox(height: 12),
          if (item.evidence.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceSoft,
                borderRadius: BorderRadius.circular(TgcgRadius.md),
                border: Border.all(color: TgcgColors.border),
              ),
              child: const Text(
                'No linked media evidence for this incident.',
                style: TgcgType.caption,
              ),
            )
          else
            ...item.evidence.map(
              (evidence) => EvidenceRow(evidence: evidence, icon: _evidenceIcon(evidence.type)),
            ),
          IncidentPhotoButton(incident: item),
          LiveVideoActions(incident: item),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          IncidentCommandPanel(incident: item),
          if (store.isLive && !store.isOnDevice(item.id)) ...[
            IncidentSecurityPanel(incident: item),
            const SizedBox(height: 14),
            IncidentHistoryPanel(key: ValueKey(item.id), incident: item),
          ],
        ],
      ),
    );
  }
}

/// One open incident as a line in a list, opening its report when tapped.
class IncidentReportLine extends StatelessWidget {
  const IncidentReportLine({super.key, required this.incident, this.showPlace = false});

  final FieldIncident incident;

  /// Adds where it was reported, for a list covering more than one place.
  final bool showPlace;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openIncidentReport(context, incident),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: incidentSeverityColor(incident.severity), width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(incident.title, style: TgcgType.label),
                        const SizedBox(height: 3),
                        Text(
                          '${incident.severity.name.toUpperCase()} • '
                          '${incidentStatusLabel(incident.status)} • '
                          '${formatMoment(incident.reportedAt.toLocal())}'
                          '${incident.evidence.isEmpty ? '' : ' • ${incident.evidence.length} evidence'}',
                          style: TgcgType.caption,
                        ),
                        if (showPlace) Text(incident.scope.label, style: TgcgType.caption),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted),
                ],
              ),
            ),
          ),
        ),
      );
}

class _InspectorLine extends StatelessWidget {
  const _InspectorLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: TgcgColors.muted),
            const SizedBox(width: 8),
            SizedBox(width: 92, child: Text(label, style: TgcgType.caption)),
            Expanded(child: Text(value, style: TgcgType.label)),
          ],
        ),
      );
}

/// Open means not yet resolved or closed.
bool isOpenIncident(FieldIncident incident) =>
    incident.status != IncidentStatus.resolved && incident.status != IncidentStatus.closed;

/// Most severe first.
int incidentSeverityRank(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => 5,
      IncidentSeverity.high => 4,
      IncidentSeverity.medium => 3,
      IncidentSeverity.low => 2,
      IncidentSeverity.info => 1,
    };

String incidentSeverityLabel(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => 'Critical',
      IncidentSeverity.high => 'High',
      IncidentSeverity.medium => 'Medium',
      IncidentSeverity.low => 'Low',
      IncidentSeverity.info => 'Info',
    };

Color incidentSeverityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => TgcgColors.danger,
      IncidentSeverity.high => const Color(0xFFD92D20),
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.low => TgcgColors.info,
      IncidentSeverity.info => TgcgColors.muted,
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.image_outlined,
      EvidenceType.video => Icons.videocam_outlined,
      EvidenceType.audio => Icons.mic_none_rounded,
      EvidenceType.document => Icons.attach_file_rounded,
      EvidenceType.resultForm => Icons.description_outlined,
      EvidenceType.location => Icons.location_on_outlined,
    };

