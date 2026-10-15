import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show promptText, showDone;

import '../domain/permissions.dart';
import '../evidence/evidence_upload.dart';
import '../evidence/evidence_viewer.dart';
import '../evidence/voice_note.dart';
import '../location/gps_prompt.dart';
import '../location/gps_service.dart';
import '../session.dart';
import '../sync/server_records.dart';
import '../ui/server_feed.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';
import 'incident_actions.dart';

class FieldMonitoringPage extends StatefulWidget {
  const FieldMonitoringPage({
    super.key,
    this.gps = const GpsService(),
    this.newVoiceRecorder = deviceVoiceRecorder,
  });

  final GpsService gps;
  final VoiceRecorder Function() newVoiceRecorder;

  @override
  State<FieldMonitoringPage> createState() => _FieldMonitoringPageState();
}

class _FieldMonitoringPageState extends State<FieldMonitoringPage> with ServerAutoRefresh {
  @override
  List<ServerRecords<Object?>> refreshedRecords(BuildContext context) =>
      [FieldOperations.of(context, listen: false)];

  String? selectedIncidentId;
  IncidentStatus? statusFilter;
  IncidentSeverity? severityFilter;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    var incidents = store.incidentsForScope(session.scope);
    final reports = store.reportsForScope(session.scope);
    final canCreateIncident = session.can(TgcgCapability.createIncident);
    final canSubmitFieldReport = session.can(TgcgCapability.submitFieldReport);

    if (statusFilter != null) {
      incidents = incidents
          .where((item) => item.status == statusFilter)
          .toList(growable: false);
    }
    if (severityFilter != null) {
      incidents = incidents
          .where((item) => item.severity == severityFilter)
          .toList(growable: false);
    }

    incidents = List<FieldIncident>.from(incidents)
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final allScoped = store.incidentsForScope(session.scope);
    final selected = selectedIncidentId == null
        ? (incidents.isEmpty ? null : incidents.first)
        : allScoped.where((item) => item.id == selectedIncidentId).firstOrNull;

    final open = allScoped
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .length;
    final highPriority = allScoped
        .where(
          (item) =>
              item.severity == IncidentSeverity.high ||
              item.severity == IncidentSeverity.critical,
        )
        .length;
    final evidence = allScoped.fold<int>(
      0,
      (total, item) => total + item.evidence.length,
    );
    final geoTagged = allScoped
        .where((item) => item.latitude != null && item.longitude != null)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'FIELD OPERATIONS',
          title: 'Field Monitoring & Incident Capture',
          subtitle:
              '${session.scope.label}: structured field reporting, incident response, evidence context and operational escalation.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const FieldFeedStatus(),
              if (canSubmitFieldReport)
                OutlinedButton.icon(
                  onPressed: () => _showFieldReportDialog(context),
                  icon: const Icon(Icons.post_add_rounded),
                  label: const Text('Field report'),
                ),
              if (canCreateIncident)
                FilledButton.icon(
                  onPressed: () => _showIncidentDialog(context),
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('Report incident'),
                ),
            ],
          ),
        ),
        const FieldLoadNotice(),
        const SizedBox(height: 18),
        _Metrics(
          openIncidents: open,
          highPriority: highPriority,
          fieldReports: reports.length,
          evidenceItems: evidence,
          geoTagged: geoTagged,
        ),
        const SizedBox(height: 16),
        _CaptureReadinessBanner(),
        const SizedBox(height: 16),
        _Filters(
          status: statusFilter,
          severity: severityFilter,
          onStatusChanged: (value) => setState(() => statusFilter = value),
          onSeverityChanged: (value) => setState(() => severityFilter = value),
          onClear: () => setState(() {
            statusFilter = null;
            severityFilter = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final queue = _IncidentQueue(
              incidents: incidents,
              selectedId: selected?.id,
              onSelect: (id) => setState(() => selectedIncidentId = id),
            );
            final inspector = _IncidentInspector(incident: selected);
            if (constraints.maxWidth < 1050) {
              return Column(
                children: [
                  queue,
                  const SizedBox(height: 16),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: queue),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
        if (session.can(TgcgCapability.verifyFieldReport)) ...[
          const SizedBox(height: 16),
          _ReportReview(reports: reports),
        ],
        const SizedBox(height: 16),
        _FieldActivityFeed(incidents: allScoped, reports: reports),
      ],
    );
  }

  Future<void> _showIncidentDialog(BuildContext context) async {
    final session = TgcgSession.of(context, listen: false);
    final store = FieldOperations.of(context, listen: false);
    final locations = await fieldLocations(context);
    if (!context.mounted) return;
    final title = TextEditingController();
    final summary = TextEditingController();
    var category = _incidentCategories.first;
    var severity = IncidentSeverity.medium;
    var scope = locations.first;
    var photos = <PendingEvidence>[];
    PendingEvidence? voiceNote;

    final created = await showDialog<FieldIncident>(
      context: context,
      builder: (dialogContext) => _DisposeWhenClosed(
        notifiers: [title, summary],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Report field incident'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: 'Incident title',
                        hintText: 'Short factual description',
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final categoryField = DropdownButtonFormField<String>(
                          initialValue: category,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: _incidentCategories
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(
                            () => category = value ?? category,
                          ),
                        );
                        final severityField = DropdownButtonFormField<IncidentSeverity>(
                          initialValue: severity,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Severity'),
                          items: IncidentSeverity.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    _label(value.name),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(
                            () => severity = value ?? severity,
                          ),
                        );
                        // Side by side only where both have room for their words.
                        if (constraints.maxWidth < 440) {
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
                      decoration: const InputDecoration(labelText: 'Field location'),
                      isExpanded: true,
                      items: locations
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
                    if (store.isLive) ...[
                      EvidencePhotoPicker(
                        photos: photos,
                        label: 'Photos (optional)',
                        hint: 'They upload after the incident and are kept as taken.',
                        onChanged: (value) => setDialogState(() => photos = value),
                      ),
                      const SizedBox(height: 14),
                      VoiceNoteField(
                        note: voiceNote,
                        newRecorder: widget.newVoiceRecorder,
                        onChanged: (value) => setDialogState(() => voiceNote = value),
                      ),
                    ] else
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
                onPressed: () async {
                  if (title.text.trim().isEmpty) return;
                  // A report from a polling unit needs GPS, to say how far from
                  // the unit it was made; coordinators may report without it.
                  final fromUnit = session.scope.level == GeographyLevel.pollingUnit;
                  final gps = await captureGps(
                    dialogContext,
                    required: fromUnit,
                    action: 'report this incident',
                    gps: widget.gps,
                  );
                  if (fromUnit && gps == null) return;
                  final incident = await store.createIncident(
                    title: title.text,
                    category: category,
                    severity: severity,
                    scope: scope,
                    reporterId: session.accessId.isEmpty
                        ? session.operatorName
                        : session.accessId,
                    summary: summary.text,
                    gps: gps,
                    photos: [...photos, ?voiceNote],
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, incident);
                  }
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Save incident'),
              ),
            ],
          ),
        ),
      ),
    );
    if (created != null && context.mounted) {
      setState(() => selectedIncidentId = created.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            store.isLive
                ? 'Incident saved on this device'
                    '${photos.isEmpty ? '' : ' with ${photos.length} photo${photos.length == 1 ? '' : 's'}'}'
                    '${voiceNote == null ? '' : photos.isEmpty ? ' with a voice note' : ' and a voice note'}'
                    '. It uploads to the server automatically.'
                : '${created.id} encrypted locally and queued for sync. Media/GPS capture will attach when device integrations are connected.',
          ),
        ),
      );
    }
  }

  Future<void> _showFieldReportDialog(BuildContext context) async {
    final session = TgcgSession.of(context, listen: false);
    final store = FieldOperations.of(context, listen: false);
    final locations = await fieldLocations(context);
    if (!context.mounted) return;
    final summary = TextEditingController();
    var category = _reportCategories.first;
    var scope = locations.first;
    String? incidentId;
    // Only incidents the server holds can be linked to.
    final availableIncidents = store
        .incidentsForScope(session.scope)
        .where(
          (item) =>
              item.status != IncidentStatus.closed &&
              item.status != IncidentStatus.resolved &&
              !store.isOnDevice(item.id),
        )
        .toList(growable: false);

    final created = await showDialog<FieldReport>(
      context: context,
      builder: (dialogContext) => _DisposeWhenClosed(
        notifiers: [summary],
        child: StatefulBuilder(
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
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Report category'),
                      items: _reportCategories
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value, overflow: TextOverflow.ellipsis),
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
                      items: locations
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
                onPressed: () async {
                  if (summary.text.trim().isEmpty) return;
                  final report = await store.submitFieldReport(
                    category: category,
                    summary: summary.text,
                    scope: scope,
                    reporterId: session.accessId.isEmpty
                        ? session.operatorName
                        : session.accessId,
                    incidentId: incidentId,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, report);
                  }
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Submit report'),
              ),
            ],
          ),
        ),
      ),
    );
    if (created != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            store.isLive
                ? 'Report saved on this device. It uploads to the server automatically.'
                : '${created.id} encrypted locally and queued for sync.',
          ),
        ),
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
                detail: 'Requires response or closure',
                icon: Icons.warning_amber_rounded,
                tone: openIncidents > 0
                    ? TgcgMetricTone.warning
                    : TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'High priority',
                value: '$highPriority',
                detail: 'High + critical severity',
                icon: Icons.priority_high_rounded,
                tone: highPriority > 0
                    ? TgcgMetricTone.danger
                    : TgcgMetricTone.success,
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
                detail: 'Media/provenance references',
                icon: Icons.inventory_2_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'GPS tagged',
                value: '$geoTagged',
                detail: 'Stored coordinates only',
                icon: Icons.location_on_outlined,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _CaptureReadinessBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final live = FieldOperations.of(context).isLive;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TgcgColors.primaryDark,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FIELD CAPTURE',
                style: TextStyle(
                  color: TgcgColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.05,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                live
                    ? 'Incidents carry GPS and photos; video and voice notes come next.'
                    : 'Incidents carry GPS; photos attach when signed in to the server.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Photos and coordinates are never fabricated. A record shows when capture data is unavailable.',
                style: TextStyle(
                  color: Color(0xFFB8BDCA),
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ],
          );
          final chips = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _DarkPill('TEXT RECORDS', Icons.check_circle_outline_rounded),
              const _DarkPill('GPS', Icons.my_location_rounded),
              _DarkPill(live ? 'PHOTOS' : 'PHOTOS ON SERVER', Icons.photo_camera_outlined),
              const _DarkPill('VIDEO PENDING', Icons.videocam_outlined),
              const _DarkPill('AUDIO PENDING', Icons.mic_none_rounded),
            ],
          );
          if (constraints.maxWidth < 820) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 14), chips],
            );
          }
          return Row(
            children: [
              Expanded(flex: 6, child: text),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: chips),
            ],
          );
        },
      ),
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFBFC4D0), size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFBFC4D0),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.status,
    required this.severity,
    required this.onStatusChanged,
    required this.onSeverityChanged,
    required this.onClear,
  });

  final IncidentStatus? status;
  final IncidentSeverity? severity;
  final ValueChanged<IncidentStatus?> onStatusChanged;
  final ValueChanged<IncidentSeverity?> onSeverityChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Incident filters',
        subtitle: 'Filter by workflow state or operational severity.',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<IncidentStatus?>(
                initialValue: status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All statuses', overflow: TextOverflow.ellipsis),
                  ),
                  ...IncidentStatus.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: onStatusChanged,
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<IncidentSeverity?>(
                initialValue: severity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All severities', overflow: TextOverflow.ellipsis),
                  ),
                  ...IncidentSeverity.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: onSeverityChanged,
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

class _IncidentQueue extends StatelessWidget {
  const _IncidentQueue({
    required this.incidents,
    required this.selectedId,
    required this.onSelect,
  });

  final List<FieldIncident> incidents;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Incident queue',
        subtitle: 'Newest scoped incidents first.',
        child: incidents.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'No incident in this view',
                message: 'Change the filters or report a new field incident.',
              )
            : Column(
                children: incidents
                    .map(
                      (incident) => _IncidentRow(
                        incident: incident,
                        selected: incident.id == selectedId,
                        onTap: () => onSelect(incident.id),
                      ),
                    )
                    .toList(),
              ),
      );
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({
    required this.incident,
    required this.selected,
    required this.onTap,
  });

  final FieldIncident incident;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(incident.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: .055)
                : TgcgColors.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: .22)
                  : TgcgColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.warning_amber_rounded, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      incident.title,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${incident.id} • ${incident.category} • ${incident.scope.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TgcgStatusPill(
                    label: _label(incident.severity.name).toUpperCase(),
                    color: color,
                    compact: true,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _shortTime(incident.reportedAt),
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9,
                    ),
                  ),
                  if (FieldOperations.of(context).isOnDevice(incident.id)) ...[
                    const SizedBox(height: 5),
                    const TgcgStatusPill(
                      label: 'ON THIS DEVICE',
                      color: TgcgColors.accentDeep,
                      compact: true,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncidentInspector extends StatelessWidget {
  const _IncidentInspector({required this.incident});

  final FieldIncident? incident;

  @override
  Widget build(BuildContext context) {
    final current = incident;
    if (current == null) {
      return const TgcgSectionCard(
        title: 'Incident inspector',
        subtitle: 'Select an incident to inspect its operational record.',
        child: TgcgEmptyState(
          icon: Icons.manage_search_rounded,
          title: 'No incident selected',
          message: 'Choose an incident from the queue.',
        ),
      );
    }

    final severityColor = _severityColor(current.severity);
    final store = FieldOperations.of(context);
    final history = store.isLive && !store.isOnDevice(current.id);
    return TgcgSectionCard(
      title: 'Incident inspector',
      subtitle: 'Field evidence and response workflow remain traceable to the source record.',
      trailing: TgcgStatusPill(
        label: _label(current.status.name).toUpperCase(),
        color: _statusColor(current.status),
        icon: Icons.flag_outlined,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: severityColor.withValues(alpha: .18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.title,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${current.id} • ${current.category}',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Detail('Severity', _label(current.severity.name)),
          _Detail('Scope', current.scope.label),
          _Detail('Reporter', current.reporterId),
          _Detail('Reported', _fullTime(current.reportedAt)),
          _Detail('Response owner', current.assignedTeam ?? 'Unassigned'),
          _Detail(
            'GPS',
            current.gps != null
                ? '${current.gps!.label}${current.gps!.isMocked ? ' · MOCK LOCATION' : ''}'
                : current.latitude != null && current.longitude != null
                    ? '${current.latitude}, ${current.longitude}'
                    : 'Not captured',
          ),
          if (incidentLocationText(current) case final where?)
            _Detail('From the unit', where),
          if (current.summary != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Summary',
              style: TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              current.summary!,
              style: const TextStyle(
                color: TgcgColors.muted,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _EvidencePanel(evidence: current.evidence),
          IncidentPhotoButton(incident: current),
          const SizedBox(height: 14),
          if (history)
            IncidentHistoryPanel(key: ValueKey(current.id), incident: current)
          else
            _ResponseTimeline(incident: current),
          const SizedBox(height: 14),
          IncidentCommandPanel(incident: current),
        ],
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({required this.evidence});

  final List<EvidenceAttachment> evidence;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evidence',
            style: TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          if (evidence.isEmpty)
            const Text(
              'No evidence attachment stored with this incident.',
              style: TextStyle(color: TgcgColors.muted, fontSize: 10.5),
            )
          else
            for (final item in evidence) EvidenceRow(evidence: item, icon: _evidenceIcon(item.type)),
        ],
      );
}

class _ResponseTimeline extends StatelessWidget {
  const _ResponseTimeline({required this.incident});

  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final steps = <({String title, String detail, bool active})>[
      (
        title: 'Reported',
        detail: _fullTime(incident.reportedAt),
        active: true,
      ),
      (
        title: 'Acknowledged',
        detail: 'Response workflow entered',
        active: incident.status != IncidentStatus.reported,
      ),
      (
        title: 'Response ownership',
        detail: incident.assignedTeam ?? 'Awaiting assignment',
        active: incident.assignedTeam != null,
      ),
      (
        title: 'Resolved',
        detail: incident.status == IncidentStatus.closed
            ? 'Closed after resolution'
            : 'Operational closure pending',
        active: incident.status == IncidentStatus.resolved ||
            incident.status == IncidentStatus.closed,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Response timeline',
          style: TextStyle(
            color: TgcgColors.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        ...steps.map(
          (step) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  step.active
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: step.active ? TgcgColors.success : TgcgColors.muted,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        step.detail,
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
        ),
      ],
    );
  }
}

/// Field reports from your areas waiting for someone to review them (never
/// your own: the server refuses that too).
class _ReportReview extends StatelessWidget {
  const _ReportReview({required this.reports});

  final List<FieldReport> reports;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    final waiting = reports
        .where(
          (item) =>
              (item.status == RecordStatus.submitted || item.status == RecordStatus.underReview) &&
              item.reporterId != session.accessId &&
              !store.isOnDevice(item.id),
        )
        .toList(growable: false);
    return TgcgSectionCard(
      title: 'Reports to review',
      subtitle: 'Accept what you can confirm. Rejecting needs a reason.',
      child: waiting.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.fact_check_outlined,
              title: 'Nothing to review',
              message: 'Field reports from your areas appear here when they arrive.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final report in waiting.take(10)) _ReportReviewRow(report: report),
                if (waiting.length > 10)
                  Text(
                    '${waiting.length - 10} more waiting.',
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                  ),
              ],
            ),
    );
  }
}

class _ReportReviewRow extends StatefulWidget {
  const _ReportReviewRow({required this.report});

  final FieldReport report;

  @override
  State<_ReportReviewRow> createState() => _ReportReviewRowState();
}

class _ReportReviewRowState extends State<_ReportReviewRow> {
  bool _busy = false;

  Future<void> _review({required bool accepted}) async {
    final report = widget.report;
    var reason = '';
    if (!accepted) {
      final written = await promptText(
        context,
        title: 'Reject ${report.id}',
        label: 'Reason',
        message: 'Say why the report cannot be accepted. It is kept with the report.',
        action: 'Reject',
        required: true,
        destructive: true,
      );
      if (written == null || !mounted) return;
      reason = written;
    }
    final store = FieldOperations.of(context, listen: false);
    setState(() => _busy = true);
    try {
      await store.reviewReport(report.id, accepted: accepted, reason: reason);
      if (mounted) showDone(context, '${report.id} ${accepted ? 'accepted' : 'rejected'}.');
    } catch (error) {
      if (mounted) showFieldFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.category,
            style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(report.summary, style: const TextStyle(color: TgcgColors.ink, height: 1.4)),
          const SizedBox(height: 4),
          Text(
            '${report.id} • ${report.reporterId} • ${report.scope.label} • '
            '${_fullTime(report.reportedAt)}',
            style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
          ),
          if (report.incidentId != null)
            Text(
              'About incident ${report.incidentId}',
              style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
            ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _review(accepted: true),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('Accept'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _review(accepted: false),
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldActivityFeed extends StatelessWidget {
  const _FieldActivityFeed({required this.incidents, required this.reports});

  final List<FieldIncident> incidents;
  final List<FieldReport> reports;

  @override
  Widget build(BuildContext context) {
    final events = <_FeedEvent>[
      ...incidents.map(
        (item) => _FeedEvent(
          at: item.reportedAt,
          title: item.title,
          detail: 'Incident • ${item.id} • ${_label(item.status.name)}',
          icon: Icons.warning_amber_rounded,
          color: _severityColor(item.severity),
        ),
      ),
      ...reports.map(
        (item) => _FeedEvent(
          at: item.reportedAt,
          title: item.category,
          detail: 'Field report • ${item.id} • ${_label(item.status.name)}',
          icon: Icons.feed_outlined,
          color: TgcgColors.info,
        ),
      ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return TgcgSectionCard(
      title: 'Live field activity',
      subtitle: 'Combined incident and structured-report feed for the current scope.',
      child: events.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.sensors_off_outlined,
              title: 'No field activity in scope',
              message: 'Incident and field-report activity will appear here.',
            )
          : Column(
              children: events
                  .take(20)
                  .map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: event.color.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(event.icon, color: event.color, size: 18),
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
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  event.detail,
                                  style: const TextStyle(
                                    color: TgcgColors.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _shortTime(event.at),
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _FeedEvent {
  const _FeedEvent({
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

class _DeviceCaptureIntegrationPanel extends StatelessWidget {
  const _DeviceCaptureIntegrationPanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Evidence capture',
              style: TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Device services are not connected yet. These controls are intentionally disabled rather than fabricating evidence.',
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
              children: const [
                _PendingCapture('Photo', Icons.photo_camera_outlined),
                _PendingCapture('Video', Icons.videocam_outlined),
                _PendingCapture('Audio', Icons.mic_none_rounded),
                _PendingCapture('GPS', Icons.my_location_rounded),
              ],
            ),
          ],
        ),
      );
}

class _PendingCapture extends StatelessWidget {
  const _PendingCapture(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 17),
        label: Text('$label • integration pending'),
      );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
  'Materials update',
  'Queue / turnout observation',
  'Connectivity update',
  'Closing status',
  'Other',
];

Color _severityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.info => TgcgColors.info,
      IncidentSeverity.low => TgcgColors.success,
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.high => const Color(0xFFE25C2A),
      IncidentSeverity.critical => TgcgColors.danger,
    };

Color _statusColor(IncidentStatus status) => switch (status) {
      IncidentStatus.reported => TgcgColors.warning,
      IncidentStatus.acknowledged => TgcgColors.info,
      IncidentStatus.assigned => TgcgColors.ai,
      IncidentStatus.investigating => TgcgColors.ai,
      IncidentStatus.escalated => TgcgColors.danger,
      IncidentStatus.resolved => TgcgColors.success,
      IncidentStatus.closed => TgcgColors.muted,
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.image_outlined,
      EvidenceType.video => Icons.videocam_outlined,
      EvidenceType.audio => Icons.audio_file_outlined,
      EvidenceType.document => Icons.description_outlined,
      EvidenceType.resultForm => Icons.document_scanner_outlined,
      EvidenceType.location => Icons.location_on_outlined,
    };

String _shortTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _fullTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Disposes a dialog's text controllers once the dialog has gone, after its
/// closing animation: disposed as soon as it is popped, they break it.
class _DisposeWhenClosed extends StatefulWidget {
  const _DisposeWhenClosed({required this.notifiers, required this.child});

  final List<ChangeNotifier> notifiers;
  final Widget child;

  @override
  State<_DisposeWhenClosed> createState() => _DisposeWhenClosedState();
}

class _DisposeWhenClosedState extends State<_DisposeWhenClosed> {
  @override
  void dispose() {
    for (final notifier in widget.notifiers) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
