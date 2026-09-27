import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

class FieldMonitoringPage extends StatefulWidget {
  const FieldMonitoringPage({super.key});

  @override
  State<FieldMonitoringPage> createState() => _FieldMonitoringPageState();
}

class _FieldMonitoringPageState extends State<FieldMonitoringPage> {
  IncidentSeverity? severityFilter;
  IncidentStatus? statusFilter;
  String? selectedIncidentId;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    final role = session.role!;
    final canCreateIncident = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.createIncident,
    );
    final canSubmitReport = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.submitFieldReport,
    );

    final scopedIncidents = store.incidentsForScope(session.scope);
    final reports = store.reportsForScope(session.scope);
    var incidents = scopedIncidents;

    if (severityFilter != null) {
      incidents = incidents
          .where((item) => item.severity == severityFilter)
          .toList(growable: false);
    }
    if (statusFilter != null) {
      incidents = incidents
          .where((item) => item.status == statusFilter)
          .toList(growable: false);
    }

    final open = scopedIncidents
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .toList(growable: false);
    final high = open
        .where(
          (item) =>
              item.severity == IncidentSeverity.high ||
              item.severity == IncidentSeverity.critical,
        )
        .length;
    final evidence = scopedIncidents.fold<int>(
      0,
      (total, item) => total + item.evidence.length,
    );
    final geoTagged = scopedIncidents
        .where((item) => item.latitude != null && item.longitude != null)
        .length;

    FieldIncident? selected;
    if (selectedIncidentId != null) {
      for (final item in scopedIncidents) {
        if (item.id == selectedIncidentId) {
          selected = item;
          break;
        }
      }
    }
    selected ??= incidents.isEmpty ? null : incidents.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'FIELD OPERATIONS',
          title: 'Field Monitoring',
          subtitle:
              '${session.scope.label}: incident capture, evidence context, geotag readiness, structured reports and operational follow-up.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canSubmitReport)
                OutlinedButton.icon(
                  onPressed: () => _showFieldReportDialog(context),
                  icon: const Icon(Icons.post_add_rounded),
                  label: const Text('Field report'),
                ),
              if (canCreateIncident)
                FilledButton.icon(
                  onPressed: () => _showIncidentDialog(context),
                  icon: const Icon(Icons.add_alert_outlined),
                  label: const Text('Report incident'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          openIncidents: open.length,
          highPriority: high,
          fieldReports: reports.length,
          evidenceItems: evidence,
          geoTagged: geoTagged,
        ),
        const SizedBox(height: 16),
        _CaptureReadinessBanner(),
        const SizedBox(height: 16),
        _FilterBar(
          severity: severityFilter,
          status: statusFilter,
          onSeverityChanged: (value) => setState(() => severityFilter = value),
          onStatusChanged: (value) => setState(() => statusFilter = value),
          onClear: () => setState(() {
            severityFilter = null;
            statusFilter = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final feed = _IncidentFeed(
              incidents: incidents,
              selectedIncidentId: selected?.id,
              onSelect: (id) => setState(() => selectedIncidentId = id),
            );
            final inspector = _IncidentInspector(
              incident: selected,
              role: role,
              userScope: session.scope,
            );
            if (constraints.maxWidth < 1060) {
              return Column(
                children: [
                  feed,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: feed),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: inspector),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ActivityTimeline(incidents: scopedIncidents, reports: reports),
      ],
    );
  }

  Future<void> _showIncidentDialog(BuildContext context) async {
    final session = TgcgSession.of(context, listen: false);
    final membership = MembershipOperations.of(context, listen: false);
    final store = FieldOperations.of(context, listen: false);
    final title = TextEditingController();
    final summary = TextEditingController();
    var category = _incidentCategories.first;
    var severity = IncidentSeverity.medium;
    final units = membership.geography.pollingUnitsWithin(session.scope);
    GeographicScope scope = units.isEmpty ? session.scope : units.first.scope;

    final created = await showDialog<FieldIncident>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report field incident'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CaptureWorkflowStrip(),
                  const SizedBox(height: 14),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Incident title',
                      hintText: 'Short operational description',
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final categoryField = DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: _incidentCategories
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setDialogState(
                          () => category = value ?? category,
                        ),
                      );
                      final severityField = DropdownButtonFormField<IncidentSeverity>(
                        initialValue: severity,
                        decoration: const InputDecoration(labelText: 'Severity'),
                        items: IncidentSeverity.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(_label(value.name)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setDialogState(
                          () => severity = value ?? severity,
                        ),
                      );
                      if (constraints.maxWidth < 500) {
                        return Column(
                          children: [
                            categoryField,
                            const SizedBox(height: 10),
                            severityField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: categoryField),
                          const SizedBox(width: 10),
                          Expanded(child: severityField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GeographicScope>(
                    initialValue: scope,
                    decoration: const InputDecoration(
                      labelText: 'Canonical field location',
                    ),
                    isExpanded: true,
                    items: (units.isEmpty
                            ? <GeographicScope>[session.scope]
                            : units.map((unit) => unit.scope).toList())
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => scope = value ?? scope,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summary,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'What happened?',
                      hintText: 'Record observable facts and operational impact.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _DeviceCaptureIntegrationPanel(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                final incident = store.createIncident(
                  title: title.text,
                  category: category,
                  severity: severity,
                  scope: scope,
                  reporterId: session.accessId.isEmpty
                      ? session.operatorName
                      : session.accessId,
                  summary: summary.text,
                );
                Navigator.pop(dialogContext, incident);
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Save incident'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    summary.dispose();
    if (created != null && context.mounted) {
      setState(() => selectedIncidentId = created.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${created.id} saved locally. Media/GPS capture will attach when device integrations are connected.',
          ),
        ),
      );
    }
  }

  Future<void> _showFieldReportDialog(BuildContext context) async {
    final session = TgcgSession.of(context, listen: false);
    final membership = MembershipOperations.of(context, listen: false);
    final store = FieldOperations.of(context, listen: false);
    final summary = TextEditingController();
    var category = _reportCategories.first;
    final units = membership.geography.pollingUnitsWithin(session.scope);
    GeographicScope scope = units.isEmpty ? session.scope : units.first.scope;
    String? incidentId;
    final availableIncidents = store
        .incidentsForScope(session.scope)
        .where(
          (item) =>
              item.status != IncidentStatus.closed &&
              item.status != IncidentStatus.resolved,
        )
        .toList(growable: false);

    final created = await showDialog<FieldReport>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Submit field report'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Report category'),
                    items: _reportCategories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => category = value ?? category,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GeographicScope>(
                    initialValue: scope,
                    decoration: const InputDecoration(labelText: 'Field location'),
                    isExpanded: true,
                    items: (units.isEmpty
                            ? <GeographicScope>[session.scope]
                            : units.map((unit) => unit.scope).toList())
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => scope = value ?? scope,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: incidentId,
                    decoration: const InputDecoration(
                      labelText: 'Related incident (optional)',
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No linked incident'),
                      ),
                      ...availableIncidents.map(
                        (incident) => DropdownMenuItem<String?>(
                          value: incident.id,
                          child: Text(
                            '${incident.id} • ${incident.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => incidentId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summary,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Field update',
                      hintText: 'Record the current operational situation.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (summary.text.trim().isEmpty) return;
                final report = store.submitFieldReport(
                  category: category,
                  summary: summary.text,
                  scope: scope,
                  reporterId: session.accessId.isEmpty
                      ? session.operatorName
                      : session.accessId,
                  incidentId: incidentId,
                );
                Navigator.pop(dialogContext, report);
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    summary.dispose();
    if (created != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${created.id} saved to the local field store.')),
      );
    }
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.openIncidents,
    required this.highPriority,
    required this.fieldReports,
    required this.evidenceItems,
    required this.geoTagged,
  });

  final int openIncidents;
  final int highPriority;
  final int fieldReports;
  final int evidenceItems;
  final int geoTagged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1050
              ? 5
              : constraints.maxWidth >= 650
                  ? 3
                  : constraints.maxWidth >= 430
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
                label: 'Open incidents',
                value: '$openIncidents',
                detail: 'Unresolved operational reports',
                icon: Icons.warning_amber_rounded,
                tone: openIncidents == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'High priority',
                value: '$highPriority',
                detail: 'High and critical severity',
                icon: Icons.crisis_alert_rounded,
                tone: highPriority == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Field reports',
                value: '$fieldReports',
                detail: 'Structured operational updates',
                icon: Icons.feed_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Evidence items',
                value: '$evidenceItems',
                detail: 'Hashed media/document references',
                icon: Icons.attach_file_rounded,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'GPS tagged',
                value: '$geoTagged',
                detail: 'Incidents with stored coordinates',
                icon: Icons.my_location_rounded,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _CaptureReadinessBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(14),
        backgroundColor: TgcgColors.primaryDark,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final status = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                TgcgStatusPill(
                  label: 'OFFLINE-FIRST',
                  color: Color(0xFF87D9BD),
                  icon: Icons.offline_bolt_outlined,
                  compact: true,
                ),
                TgcgStatusPill(
                  label: 'EVIDENCE HASH',
                  color: Color(0xFF87D9BD),
                  icon: Icons.fingerprint_rounded,
                  compact: true,
                ),
                TgcgStatusPill(
                  label: 'CAMERA PENDING',
                  color: Color(0xFFFFD76A),
                  icon: Icons.camera_alt_outlined,
                  compact: true,
                ),
                TgcgStatusPill(
                  label: 'GPS PENDING',
                  color: Color(0xFFFFD76A),
                  icon: Icons.gps_not_fixed_rounded,
                  compact: true,
                ),
              ],
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Device capture readiness',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'The field workflow is ready for offline records and evidence provenance; native camera/audio/video and GPS capture still require device-service integration.',
                    style: TextStyle(
                      color: Color(0xFFB8CEC6),
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  status,
                ],
              );
            }
            return Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device capture readiness',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Offline records and evidence provenance are modelled. Native media/GPS capture remains an integration point.',
                        style: TextStyle(
                          color: Color(0xFFB8CEC6),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                status,
              ],
            );
          },
        ),
      );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.severity,
    required this.status,
    required this.onSeverityChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final IncidentSeverity? severity;
  final IncidentStatus? status;
  final ValueChanged<IncidentSeverity?> onSeverityChanged;
  final ValueChanged<IncidentStatus?> onStatusChanged;
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
                'Incident filters',
                style: TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<IncidentSeverity?>(
                initialValue: severity,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All severities'),
                  ),
                  ...IncidentSeverity.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                  ),
                ],
                onChanged: onSeverityChanged,
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<IncidentStatus?>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  ...IncidentStatus.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                  ),
                ],
                onChanged: onStatusChanged,
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

class _IncidentFeed extends StatelessWidget {
  const _IncidentFeed({
    required this.incidents,
    required this.selectedIncidentId,
    required this.onSelect,
  });

  final List<FieldIncident> incidents;
  final String? selectedIncidentId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final sorted = [...incidents]
      ..sort((a, b) {
        final severity = _severityRank(b.severity).compareTo(_severityRank(a.severity));
        if (severity != 0) return severity;
        return b.reportedAt.compareTo(a.reportedAt);
      });
    return TgcgSectionCard(
      title: 'Incident feed',
      subtitle: 'Select an incident to inspect evidence, location and response status.',
      trailing: TgcgStatusPill(
        label: '${sorted.length} RECORDS',
        color: TgcgColors.primary,
        compact: true,
      ),
      child: sorted.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.shield_outlined,
              title: 'No matching incidents',
              message: 'Change the filters or report a new field incident.',
            )
          : Column(
              children: sorted.map((incident) {
                final selected = incident.id == selectedIncidentId;
                final color = _severityColor(incident.severity);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: InkWell(
                    onTap: () => onSelect(incident.id),
                    borderRadius: BorderRadius.circular(15),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: selected
                            ? TgcgColors.primarySoft
                            : TgcgColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: selected
                              ? TgcgColors.primary.withValues(alpha: .30)
                              : TgcgColors.border,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.crisis_alert_outlined,
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
                                  incident.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TgcgColors.ink,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  incident.scope.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TgcgColors.muted,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    TgcgStatusPill(
                                      label: _label(incident.severity.name).toUpperCase(),
                                      color: color,
                                      compact: true,
                                    ),
                                    TgcgStatusPill(
                                      label: _label(incident.status.name).toUpperCase(),
                                      color: TgcgColors.primary,
                                      compact: true,
                                    ),
                                    if (incident.evidence.isNotEmpty)
                                      TgcgStatusPill(
                                        label: '${incident.evidence.length} EVIDENCE',
                                        color: TgcgColors.ai,
                                        compact: true,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: TgcgColors.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _IncidentInspector extends StatelessWidget {
  const _IncidentInspector({
    required this.incident,
    required this.role,
    required this.userScope,
  });

  final FieldIncident? incident;
  final TgcgRole role;
  final GeographicScope userScope;

  @override
  Widget build(BuildContext context) {
    if (incident == null) {
      return const TgcgSectionCard(
        child: TgcgEmptyState(
          icon: Icons.manage_search_rounded,
          title: 'Select an incident',
          message: 'Incident evidence, location and response history will appear here.',
        ),
      );
    }
    final item = incident!;
    final color = _severityColor(item.severity);
    final canAcknowledge = TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.acknowledgeIncident,
      targetScope: item.scope,
    );
    final canAssign = TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.assignIncident,
      targetScope: item.scope,
    );
    final canClose = TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.closeIncident,
      targetScope: item.scope,
    );

    return TgcgSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: TgcgColors.primaryDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.crisis_alert_outlined, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.id,
                        style: const TextStyle(
                          color: Color(0xFF9AB8AD),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          TgcgStatusPill(
                            label: _label(item.severity.name).toUpperCase(),
                            color: color,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: _label(item.status.name).toUpperCase(),
                            color: const Color(0xFF87D9BD),
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.summary ?? 'No narrative summary was supplied.',
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _InspectorGrid(incident: item),
                const SizedBox(height: 18),
                const Text(
                  'Location & evidence',
                  style: TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _LocationEvidencePanel(incident: item),
                const SizedBox(height: 18),
                const Text(
                  'Response timeline',
                  style: TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _IncidentTimeline(incident: item),
                if (canAcknowledge || canAssign || canClose) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canAcknowledge && item.status == IncidentStatus.reported)
                        FilledButton.tonalIcon(
                          onPressed: () => FieldOperations.of(context, listen: false)
                              .updateIncidentStatus(
                            item.id,
                            IncidentStatus.acknowledged,
                          ),
                          icon: const Icon(Icons.done_rounded),
                          label: const Text('Acknowledge'),
                        ),
                      if (canAssign)
                        OutlinedButton.icon(
                          onPressed: () => FieldOperations.of(context, listen: false)
                              .updateIncidentStatus(
                            item.id,
                            IncidentStatus.investigating,
                          ),
                          icon: const Icon(Icons.manage_search_rounded),
                          label: const Text('Investigate'),
                        ),
                      if (canAssign &&
                          (item.severity == IncidentSeverity.high ||
                              item.severity == IncidentSeverity.critical))
                        OutlinedButton.icon(
                          onPressed: () => FieldOperations.of(context, listen: false)
                              .updateIncidentStatus(
                            item.id,
                            IncidentStatus.escalated,
                          ),
                          icon: const Icon(Icons.arrow_upward_rounded),
                          label: const Text('Escalate'),
                        ),
                      if (canClose)
                        FilledButton.icon(
                          onPressed: () => FieldOperations.of(context, listen: false)
                              .updateIncidentStatus(
                            item.id,
                            IncidentStatus.resolved,
                          ),
                          icon: const Icon(Icons.task_alt_rounded),
                          label: const Text('Resolve'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorGrid extends StatelessWidget {
  const _InspectorGrid({required this.incident});
  final FieldIncident incident;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _InfoTile(
            icon: Icons.category_outlined,
            label: 'Category',
            value: incident.category,
          ),
          _InfoTile(
            icon: Icons.location_on_outlined,
            label: 'Scope',
            value: incident.scope.label,
          ),
          _InfoTile(
            icon: Icons.person_outline_rounded,
            label: 'Reporter',
            value: incident.reporterId,
          ),
          _InfoTile(
            icon: Icons.groups_2_outlined,
            label: 'Response owner',
            value: incident.assignedTeam ?? 'Unassigned',
          ),
        ],
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: 235,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: TgcgColors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _LocationEvidencePanel extends StatelessWidget {
  const _LocationEvidencePanel({required this.incident});
  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final hasGps = incident.latitude != null && incident.longitude != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                hasGps ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                color: hasGps ? TgcgColors.success : TgcgColors.warning,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasGps ? 'GPS coordinates retained' : 'GPS not captured',
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasGps
                          ? '${incident.latitude}, ${incident.longitude}'
                          : 'Native location capture is not connected in this Flutter prototype.',
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (incident.evidence.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No evidence attachment is currently linked to this incident.',
                style: TextStyle(color: TgcgColors.muted, fontSize: 10.5),
              ),
            )
          else
            ...incident.evidence.map(
              (evidence) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: TgcgColors.ai.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _evidenceIcon(evidence.type),
                        size: 17,
                        color: TgcgColors.ai,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            evidence.fileName,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (evidence.contentHash != null)
                            Text(
                              evidence.contentHash!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9,
                              ),
                            ),
                        ],
                      ),
                    ),
                    TgcgStatusPill(
                      label: _label(evidence.type.name).toUpperCase(),
                      color: TgcgColors.ai,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IncidentTimeline extends StatelessWidget {
  const _IncidentTimeline({required this.incident});
  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final events = <({String title, String detail, IconData icon, Color color})>[
      (
        title: 'Incident reported',
        detail: '${_formatTime(incident.reportedAt)} • ${incident.reporterId}',
        icon: Icons.add_alert_outlined,
        color: TgcgColors.info,
      ),
      if (incident.assignedTeam != null)
        (
          title: 'Response owner assigned',
          detail: incident.assignedTeam!,
          icon: Icons.groups_2_outlined,
          color: TgcgColors.primary,
        ),
      (
        title: 'Current state',
        detail: _label(incident.status.name),
        icon: Icons.flag_outlined,
        color: _statusColor(incident.status),
      ),
    ];
    return Column(
      children: events
          .map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: event.color.withValues(alpha: .09),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(event.icon, size: 15, color: event.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.detail,
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.incidents, required this.reports});

  final List<FieldIncident> incidents;
  final List<FieldReport> reports;

  @override
  Widget build(BuildContext context) {
    final events = <_FieldActivity>[
      ...incidents.map(
        (item) => _FieldActivity(
          at: item.reportedAt,
          title: item.title,
          detail: '${item.scope.label} • ${_label(item.severity.name)} incident',
          icon: Icons.crisis_alert_outlined,
          color: _severityColor(item.severity),
        ),
      ),
      ...reports.map(
        (item) => _FieldActivity(
          at: item.reportedAt,
          title: item.category,
          detail: '${item.scope.label} • ${item.reporterId}',
          icon: Icons.feed_outlined,
          color: TgcgColors.info,
        ),
      ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return TgcgSectionCard(
      title: 'Live field activity',
      subtitle: 'Recent incidents and structured reports in the authorized scope.',
      child: events.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.timeline_rounded,
              title: 'No field activity yet',
              message: 'New incidents and reports will appear here.',
            )
          : Column(
              children: events.take(8).map((event) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: event.color.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(event.icon, size: 17, color: event.color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatTime(event.at),
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _FieldActivity {
  const _FieldActivity({
    required this.at,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final DateTime at;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
}

class _CaptureWorkflowStrip extends StatelessWidget {
  const _CaptureWorkflowStrip();

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 7,
        runSpacing: 7,
        children: const [
          TgcgStatusPill(
            label: '1 DETAILS',
            color: TgcgColors.primary,
            compact: true,
          ),
          TgcgStatusPill(
            label: '2 LOCATION',
            color: TgcgColors.info,
            compact: true,
          ),
          TgcgStatusPill(
            label: '3 EVIDENCE',
            color: TgcgColors.ai,
            compact: true,
          ),
          TgcgStatusPill(
            label: '4 SAVE / SYNC',
            color: TgcgColors.success,
            compact: true,
          ),
        ],
      );
}

class _DeviceCaptureIntegrationPanel extends StatelessWidget {
  const _DeviceCaptureIntegrationPanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device evidence capture',
              style: TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'The document requires photo, video, audio and GPS evidence. Native services are not connected yet, so this form does not fabricate media or coordinates.',
              style: TextStyle(
                color: TgcgColors.muted,
                fontSize: 10,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PendingCaptureButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Photo',
                ),
                _PendingCaptureButton(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                ),
                _PendingCaptureButton(
                  icon: Icons.mic_none_rounded,
                  label: 'Audio',
                ),
                _PendingCaptureButton(
                  icon: Icons.my_location_rounded,
                  label: 'GPS',
                ),
              ],
            ),
          ],
        ),
      );
}

class _PendingCaptureButton extends StatelessWidget {
  const _PendingCaptureButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 17),
        label: Text('$label • integration pending'),
      );
}

const _incidentCategories = <String>[
  'Access',
  'Security',
  'Violence / threat',
  'Evidence quality',
  'Geolocation',
  'Technical',
  'Materials / logistics',
  'Process irregularity',
  'Other',
];

const _reportCategories = <String>[
  'Opening status',
  'Operational update',
  'Connectivity update',
  'Materials status',
  'Closing status',
  'General observation',
];

int _severityRank(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => 5,
      IncidentSeverity.high => 4,
      IncidentSeverity.medium => 3,
      IncidentSeverity.low => 2,
      IncidentSeverity.info => 1,
    };

Color _severityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => TgcgColors.danger,
      IncidentSeverity.high => const Color(0xFFD92D20),
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.low => TgcgColors.info,
      IncidentSeverity.info => TgcgColors.muted,
    };

Color _statusColor(IncidentStatus status) => switch (status) {
      IncidentStatus.reported => TgcgColors.info,
      IncidentStatus.acknowledged => TgcgColors.primary,
      IncidentStatus.assigned => TgcgColors.primaryMid,
      IncidentStatus.investigating => TgcgColors.warning,
      IncidentStatus.escalated => TgcgColors.danger,
      IncidentStatus.resolved => TgcgColors.success,
      IncidentStatus.closed => TgcgColors.muted,
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.image_outlined,
      EvidenceType.video => Icons.videocam_outlined,
      EvidenceType.audio => Icons.graphic_eq_rounded,
      EvidenceType.document => Icons.description_outlined,
      EvidenceType.resultForm => Icons.ballot_outlined,
      EvidenceType.location => Icons.location_on_outlined,
    };

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
