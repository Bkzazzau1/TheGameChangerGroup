import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show formatMoment, promptText, showDone;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/field_repository.dart';
import '../domain/permissions.dart';
import '../evidence/evidence_upload.dart';
import '../evidence/evidence_viewer.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/server_feed.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

// The incident workflow, as the server runs it (tgcg_backend
// apps/field/services.py). The app offers only these moves; the server checks
// each one again, with the caller's authority in the incident's area.

const _moves = <IncidentStatus, Set<IncidentStatus>>{
  IncidentStatus.reported: {
    IncidentStatus.acknowledged,
    IncidentStatus.escalated,
    IncidentStatus.closed,
  },
  IncidentStatus.acknowledged: {
    IncidentStatus.investigating,
    IncidentStatus.escalated,
    IncidentStatus.resolved,
    IncidentStatus.closed,
  },
  IncidentStatus.assigned: {
    IncidentStatus.investigating,
    IncidentStatus.escalated,
    IncidentStatus.resolved,
  },
  IncidentStatus.investigating: {IncidentStatus.escalated, IncidentStatus.resolved},
  IncidentStatus.escalated: {IncidentStatus.investigating, IncidentStatus.resolved},
  IncidentStatus.resolved: {IncidentStatus.investigating, IncidentStatus.closed},
  IncidentStatus.closed: {},
};

const _assignableFrom = {
  IncidentStatus.reported,
  IncidentStatus.acknowledged,
  IncidentStatus.assigned,
  IncidentStatus.investigating,
  IncidentStatus.escalated,
};

bool _mayMoveTo(TgcgActor actor, IncidentStatus status) => switch (status) {
      IncidentStatus.acknowledged ||
      IncidentStatus.investigating ||
      IncidentStatus.escalated =>
        actor.can(TgcgCapability.acknowledgeIncident),
      IncidentStatus.resolved =>
        actor.can(TgcgCapability.assignIncident) || actor.can(TgcgCapability.closeIncident),
      IncidentStatus.closed => actor.can(TgcgCapability.closeIncident),
      IncidentStatus.reported || IncidentStatus.assigned => false,
    };

/// The moves [actor] may make on [incident] now.
List<IncidentStatus> incidentMovesFor(FieldIncident incident, TgcgActor actor) => [
      for (final status in IncidentStatus.values)
        if (_moves[incident.status]!.contains(status) && _mayMoveTo(actor, status)) status,
    ];

/// Whether [actor] may give [incident] to a response team now.
bool canAssignIncident(FieldIncident incident, TgcgActor actor) =>
    actor.can(TgcgCapability.assignIncident) && _assignableFrom.contains(incident.status);

bool _reopens(IncidentStatus from, IncidentStatus to) =>
    from == IncidentStatus.resolved && to == IncidentStatus.investigating;

/// The server asks for a note on these moves.
bool _needsNote(IncidentStatus from, IncidentStatus to) =>
    to == IncidentStatus.escalated ||
    to == IncidentStatus.resolved ||
    to == IncidentStatus.closed ||
    _reopens(from, to);

String _moveLabel(IncidentStatus from, IncidentStatus to) => switch (to) {
      IncidentStatus.acknowledged => 'Acknowledge',
      IncidentStatus.investigating => _reopens(from, to) ? 'Reopen' : 'Investigate',
      IncidentStatus.escalated => 'Escalate',
      IncidentStatus.resolved => 'Resolve',
      IncidentStatus.closed => 'Close',
      IncidentStatus.reported || IncidentStatus.assigned => to.name,
    };

String _moveDone(IncidentStatus from, IncidentStatus to) => switch (to) {
      IncidentStatus.acknowledged => 'acknowledged',
      IncidentStatus.investigating => _reopens(from, to) ? 'reopened' : 'under investigation',
      IncidentStatus.escalated => 'escalated',
      IncidentStatus.resolved => 'resolved',
      IncidentStatus.closed => 'closed',
      IncidentStatus.reported || IncidentStatus.assigned => to.name,
    };

IconData _moveIcon(IncidentStatus from, IncidentStatus to) => switch (to) {
      IncidentStatus.acknowledged => Icons.done_rounded,
      IncidentStatus.investigating =>
        _reopens(from, to) ? Icons.replay_rounded : Icons.manage_search_rounded,
      IncidentStatus.escalated => Icons.north_east_rounded,
      IncidentStatus.resolved => Icons.task_alt_rounded,
      IncidentStatus.closed => Icons.lock_outline_rounded,
      IncidentStatus.reported || IncidentStatus.assigned => Icons.flag_outlined,
    };

/// What to say when a change to field records failed.
String fieldFailureMessage(Object error) => switch (error) {
      ApiException(isOffline: true) =>
        'The server cannot be reached. Changes to incidents and reports need a connection.',
      ApiException(:final message) => message,
      _ => 'Something went wrong. Try again.',
    };

void showFieldFailure(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(fieldFailureMessage(error)), backgroundColor: TgcgColors.danger),
  );
}

/// The command actions on one incident: only the moves the workflow allows
/// from its status and the session's permissions give.
class IncidentCommandPanel extends StatefulWidget {
  const IncidentCommandPanel({super.key, required this.incident});

  final FieldIncident incident;

  @override
  State<IncidentCommandPanel> createState() => _IncidentCommandPanelState();
}

class _IncidentCommandPanelState extends State<IncidentCommandPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() change, String done) async {
    setState(() => _busy = true);
    try {
      await change();
      if (mounted) showDone(context, done);
    } catch (error) {
      if (mounted) showFieldFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(IncidentStatus to) async {
    final incident = widget.incident;
    final from = incident.status;
    var note = '';
    if (_needsNote(from, to)) {
      final written = await promptText(
        context,
        title: '${_moveLabel(from, to)} ${incident.id}',
        label: 'Note',
        message: 'Say what was done or why. It is kept in the incident history.',
        action: _moveLabel(from, to),
        required: true,
      );
      if (written == null || !mounted) return;
      note = written;
    }
    final store = FieldOperations.of(context, listen: false);
    await _run(
      () => store.changeIncidentStatus(incident.id, to, note: note),
      '${incident.id} ${_moveDone(from, to)}.',
    );
  }

  Future<void> _assign() async {
    final incident = widget.incident;
    final team = await promptText(
      context,
      title: 'Assign ${incident.id}',
      label: 'Response team',
      message: 'Name the team or desk that will handle it, for example '
          '"Kaduna North Response Desk".',
      action: 'Assign',
      required: true,
    );
    if (team == null || !mounted) return;
    final store = FieldOperations.of(context, listen: false);
    await _run(() => store.assignIncident(incident.id, team), '${incident.id} assigned to $team.');
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final store = FieldOperations.of(context);
    final upload = store.uploadStatus(incident.id);
    if (upload != null) return ServerNote(icon: Icons.cloud_upload_outlined, text: upload);

    final actor = TgcgSession.of(context).actor;
    final moves = incidentMovesFor(incident, actor);
    final assign = canAssignIncident(incident, actor);
    if (moves.isEmpty && !assign) return const SizedBox.shrink();

    final from = incident.status;
    Widget button(IncidentStatus to) {
      final onPressed = _busy ? null : () => _move(to);
      final icon = Icon(_moveIcon(from, to), size: 17);
      final label = Text(_moveLabel(from, to));
      return to == IncidentStatus.resolved
          ? FilledButton.icon(onPressed: onPressed, icon: icon, label: label)
          : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Command actions',
              style: TextStyle(color: TgcgColors.ink, fontSize: 11.5, fontWeight: FontWeight.w900),
            ),
            if (_busy) ...[
              const SizedBox(width: 10),
              const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final to in moves) button(to),
            if (assign)
              OutlinedButton.icon(
                onPressed: _busy ? null : _assign,
                icon: const Icon(Icons.groups_2_outlined, size: 17),
                label: Text(incident.assignedTeam == null ? 'Assign team' : 'Reassign'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Every step taken on an incident, from the server (who, when, and notes).
class IncidentHistoryPanel extends StatefulWidget {
  const IncidentHistoryPanel({super.key, required this.incident});

  final FieldIncident incident;

  @override
  State<IncidentHistoryPanel> createState() => _IncidentHistoryPanelState();
}

class _IncidentHistoryPanelState extends State<IncidentHistoryPanel> {
  Future<List<IncidentHistoryEntry>>? _history;

  // A new status, team or piece of evidence means a new step to show.
  String _version(FieldIncident incident) =>
      '${incident.id}|${incident.status.name}|${incident.assignedTeam}|${incident.evidence.length}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _history ??= _load();
  }

  @override
  void didUpdateWidget(IncidentHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_version(oldWidget.incident) != _version(widget.incident)) _history = _load();
  }

  Future<List<IncidentHistoryEntry>> _load() =>
      FieldOperations.of(context, listen: false).incidentHistory(widget.incident.id);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'History',
            style: TextStyle(color: TgcgColors.ink, fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<IncidentHistoryEntry>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ServerNote(
                  icon: Icons.history_toggle_off_rounded,
                  text: 'The history could not be loaded. ${fieldFailureMessage(snapshot.error!)}',
                );
              }
              final entries = snapshot.data;
              if (entries == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final entry in entries.reversed) _HistoryLine(entry)],
              );
            },
          ),
        ],
      );
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine(this.entry);

  final IncidentHistoryEntry entry;

  String get _title {
    final to = entry.toStatus;
    return switch (entry.action) {
      'reported' => 'Reported',
      'assigned' => 'Assigned',
      'evidenceAdded' => 'Evidence added',
      _ when to != null && entry.fromStatus == IncidentStatus.resolved &&
              to == IncidentStatus.investigating =>
        'Reopened',
      _ when to != null => 'Moved to ${incidentStatusLabel(to).toLowerCase()}',
      _ => entry.action,
    };
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.circle, size: 8, color: TgcgColors.primaryMid),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (entry.note.isNotEmpty)
                    Text(
                      entry.note,
                      style: const TextStyle(color: TgcgColors.ink, fontSize: 10, height: 1.35),
                    ),
                  Text(
                    [entry.actor ?? 'System', formatMoment(entry.at.toLocal())].join(' · '),
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// "Under review", "Investigating"... for a status.
String incidentStatusLabel(IncidentStatus status) => switch (status) {
      IncidentStatus.reported => 'Reported',
      IncidentStatus.acknowledged => 'Acknowledged',
      IncidentStatus.assigned => 'Assigned',
      IncidentStatus.investigating => 'Investigating',
      IncidentStatus.escalated => 'Escalated',
      IncidentStatus.resolved => 'Resolved',
      IncidentStatus.closed => 'Closed',
    };

/// Where the incidents on a page come from, and a way to load them again.
class FieldFeedStatus extends StatelessWidget {
  const FieldFeedStatus({super.key});

  @override
  Widget build(BuildContext context) =>
      ServerFeedStatus(records: FieldOperations.of(context, listen: false));
}

/// Says when the server's records could not be loaded, or when an area has
/// more open incidents than the page holds.
class FieldLoadNotice extends StatelessWidget {
  const FieldLoadNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FieldOperations.of(context);
    if (!store.isLive) return const SizedBox.shrink();
    final error = store.loadError;
    final open = store.incidents
        .where((item) => !store.isOnDevice(item.id))
        .where((item) => item.status != IncidentStatus.resolved && item.status != IncidentStatus.closed)
        .length;
    final String text;
    if (error != null) {
      text = 'Incidents and reports could not be loaded from the server: $error';
    } else if (store.openOnServer > open) {
      text = 'Showing the $open most urgent of ${store.openOnServer} open incidents in your areas.';
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ServerNote(
        icon: error != null ? Icons.cloud_off_rounded : Icons.filter_list_rounded,
        text: text,
      ),
    );
  }
}

/// Where a new incident or report can be placed. On the server, the session's
/// own area, and the polling units in it when it is an LGA or smaller (from
/// the server). In presentation mode, the sample polling units.
Future<List<GeographicScope>> fieldLocations(BuildContext context) async {
  final session = TgcgSession.of(context, listen: false);
  final scope = session.scope;
  final backend = TgcgBackend.of(context);
  if (!session.isServerSession || backend == null) {
    final units = MembershipOperations.of(context, listen: false)
        .geography
        .pollingUnitsWithin(scope);
    return units.isEmpty ? [scope] : [for (final unit in units) unit.scope];
  }
  const small = {GeographyLevel.lga, GeographyLevel.ward};
  if (!small.contains(scope.level)) return [scope];
  try {
    final units = await backend.reference.pollingUnitsWithin(scope);
    return [
      scope,
      for (final unit in units)
        GeographicScope(
          level: GeographyLevel.pollingUnit,
          country: scope.country,
          zoneId: scope.zoneId,
          zoneName: scope.zoneName,
          stateId: scope.stateId,
          stateName: scope.stateName,
          senatorialDistrictId: scope.senatorialDistrictId,
          senatorialDistrictName: scope.senatorialDistrictName,
          lgaId: scope.lgaId,
          lgaName: scope.lgaName,
          wardId: unit.wardCode,
          wardName: scope.level == GeographyLevel.ward ? scope.wardName : unit.wardCode,
          pollingUnitId: unit.code,
          pollingUnitName: unit.name,
        ),
    ];
  } on ApiException {
    // Offline: the area itself still works, and the record uploads later.
    return [scope];
  }
}

/// Adds a photo to an incident on the server: the reporter's own, or any in
/// the areas where one may manage evidence. It is saved on this device and
/// uploads with the rest; the server checks the uploader again.
class IncidentPhotoButton extends StatefulWidget {
  const IncidentPhotoButton({super.key, required this.incident, this.pick = pickEvidencePhoto});

  final FieldIncident incident;
  final PickPhoto pick;

  @override
  State<IncidentPhotoButton> createState() => _IncidentPhotoButtonState();
}

class _IncidentPhotoButtonState extends State<IncidentPhotoButton> {
  bool _busy = false;

  Future<void> _add({required bool camera}) async {
    final store = FieldOperations.of(context, listen: false);
    final session = TgcgSession.of(context, listen: false);
    setState(() => _busy = true);
    try {
      final photo = await widget.pick(type: EvidenceType.photo, camera: camera);
      if (photo == null || !mounted) return;
      await store.addIncidentPhoto(widget.incident.id, photo, uploaderId: session.accessId);
      if (mounted) {
        showDone(
          context,
          'Photo saved. It uploads automatically and shows here once it is on the server.',
        );
      }
    } catch (error) {
      if (mounted) showFieldFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final store = FieldOperations.of(context);
    final session = TgcgSession.of(context);
    final allowed = store.isLive &&
        !store.isOnDevice(incident.id) &&
        incident.status != IncidentStatus.closed &&
        (incident.reporterId == session.accessId ||
            session.can(TgcgCapability.manageEvidence));
    if (!allowed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _add(camera: true),
            icon: const Icon(Icons.add_a_photo_outlined, size: 17),
            label: const Text('Take photo'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _add(camera: false),
            icon: const Icon(Icons.photo_library_outlined, size: 17),
            label: const Text('Choose photo'),
          ),
        ],
      ),
    );
  }
}

/// One piece of an incident's evidence; pictures on the server open when tapped.
class EvidenceRow extends StatelessWidget {
  const EvidenceRow({super.key, required this.evidence, required this.icon});

  final EvidenceAttachment evidence;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final viewable = canShowEvidence(evidence);
    final playable = canPlayEvidence(evidence);
    final onDevice = !viewable && !playable &&
        evidence.contentHash?.startsWith('sha256:') == true &&
        evidence.id.contains('-PHOTO-');
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: viewable
              ? () => showEvidence(context, evidence)
              : playable
                  ? () => playEvidence(context, evidence)
                  : null,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, color: TgcgColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        evidence.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        onDevice
                            ? 'On this device; uploads after the incident.'
                            : 'By ${evidence.uploaderId}',
                        style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                if (viewable || playable)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        viewable ? Icons.visibility_outlined : Icons.play_circle_outline_rounded,
                        size: 16,
                        color: TgcgColors.primaryMid,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        viewable ? 'View' : 'Play',
                        style: const TextStyle(
                          color: TgcgColors.primaryMid,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where an incident was reported, judged against its polling unit, in words;
/// null until the server has judged it.
String? incidentLocationText(FieldIncident incident) {
  final meters = incident.distanceToUnitMeters;
  final distance = meters == null
      ? null
      : meters < 1000
          ? '$meters m'
          : '${(meters / 1000).toStringAsFixed(1)} km';
  return switch (incident.locationStatus) {
    'onSite' => 'At the polling unit${distance == null ? '' : ' ($distance away)'}',
    'away' => '${distance ?? 'Away'} from the polling unit',
    'unverified' => distance == null
        ? 'The polling unit is not mapped yet'
        : 'About $distance from the polling unit (weak GPS)',
    'suspect' => 'The location may be faked',
    'noGps' => 'No GPS',
    _ => null,
  };
}
