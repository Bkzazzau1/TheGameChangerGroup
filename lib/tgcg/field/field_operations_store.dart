import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/field_repository.dart';
import '../domain/models.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';
import '../sync/server_records.dart';

/// Incidents and field reports for every screen that shows them.
///
/// In presentation mode it holds sample records and changes them locally. In
/// a server session ([connect]) it holds what the server returns, and every
/// change is made on the server, which checks it. New records are saved on
/// the device first and stay on the list until the server's copy replaces
/// them (see [ServerRecords]).
class FieldOperationsController extends ChangeNotifier with ServerRecords<FieldSnapshot> {
  FieldOperationsController._({
    required List<FieldIncident> incidents,
    required List<FieldReport> reports,
    OfflinePersistenceController? persistence,
  })  : _incidents = incidents,
        _reports = reports,
        _persistence = persistence;

  factory FieldOperationsController.prototypeSeed({
    OfflinePersistenceController? persistence,
  }) =>
      FieldOperationsController._(
        persistence: persistence,
        incidents: _sampleIncidents(),
        reports: _sampleReports(),
      );

  static final _sampleTime = DateTime.utc(2026, 9, 27, 6, 30);

  static GeographicScope _lga({
    required String zoneId,
    required String zoneName,
    required String stateId,
    required String stateName,
    required String lgaId,
    required String lgaName,
  }) =>
      GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: zoneId,
        zoneName: zoneName,
        stateId: stateId,
        stateName: stateName,
        lgaId: lgaId,
        lgaName: lgaName,
      );

  static final _kadunaNorth = _lga(
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
    lgaId: 'KD-KADUNA-NORTH',
    lgaName: 'Kaduna North',
  );
  static final _makurdi = _lga(
    zoneId: 'NC',
    zoneName: 'North Central',
    stateId: 'BN',
    stateName: 'Benue',
    lgaId: 'BN-MAKURDI',
    lgaName: 'Makurdi',
  );
  static final _ikeja = _lga(
    zoneId: 'SW',
    zoneName: 'South West',
    stateId: 'LA',
    stateName: 'Lagos',
    lgaId: 'LA-IKEJA',
    lgaName: 'Ikeja',
  );
  static final _tarauni = _lga(
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KN',
    stateName: 'Kano',
    lgaId: 'KN-TARAUNI',
    lgaName: 'Tarauni',
  );

  static EvidenceAttachment _photo(String id, String uploader, DateTime at) =>
      EvidenceAttachment(
        id: id,
        type: EvidenceType.photo,
        fileName: '$id.jpg',
        createdAt: at,
        uploaderId: uploader,
        contentHash: 'sha256:prototype-$id',
        mimeType: 'image/jpeg',
        caption: 'Prototype evidence record. Replace with verified field media.',
        origin: RecordOrigin.systemDerived,
      );

  static List<FieldIncident> _sampleIncidents() {
    final now = _sampleTime;
    return [
      FieldIncident(
        id: 'INC-0001',
        title: 'Polling-unit access obstruction reported',
        category: 'Access',
        severity: IncidentSeverity.high,
        status: IncidentStatus.investigating,
        scope: _kadunaNorth,
        reportedAt: now.subtract(const Duration(minutes: 16)),
        reporterId: 'AG-KD-001',
        summary: 'Field team reported delayed access and requested coordinator review.',
        assignedTeam: 'North West Response Desk',
        evidence: [_photo('EVD-0001', 'AG-KD-001', now.subtract(const Duration(minutes: 15)))],
        origin: RecordOrigin.systemDerived,
      ),
      FieldIncident(
        id: 'INC-0002',
        title: 'Result-form image quality below review threshold',
        category: 'Evidence quality',
        severity: IncidentSeverity.medium,
        status: IncidentStatus.assigned,
        scope: _makurdi,
        reportedAt: now.subtract(const Duration(minutes: 31)),
        reporterId: 'AG-BN-014',
        summary: 'Uploaded form is readable only in part; recapture requested.',
        assignedTeam: 'Evidence Verification Desk',
        evidence: [_photo('EVD-0002', 'AG-BN-014', now.subtract(const Duration(minutes: 30)))],
        origin: RecordOrigin.systemDerived,
      ),
      FieldIncident(
        id: 'INC-0003',
        title: 'Agent check-in requires location verification',
        category: 'Geolocation',
        severity: IncidentSeverity.low,
        status: IncidentStatus.acknowledged,
        scope: _ikeja,
        reportedAt: now.subtract(const Duration(minutes: 48)),
        reporterId: 'AG-LA-032',
        summary: 'Reported GPS position is outside the configured operational radius.',
        assignedTeam: 'Lagos State Coordination Desk',
        origin: RecordOrigin.systemDerived,
      ),
      FieldIncident(
        id: 'INC-0004',
        title: 'Field device unable to synchronize queued report',
        category: 'Technical',
        severity: IncidentSeverity.medium,
        status: IncidentStatus.reported,
        scope: _tarauni,
        reportedAt: now.subtract(const Duration(hours: 1, minutes: 8)),
        reporterId: 'AG-KN-009',
        summary: 'Report remains safely queued locally; technical support escalation required.',
        origin: RecordOrigin.systemDerived,
      ),
    ];
  }

  static List<FieldReport> _sampleReports() {
    final now = _sampleTime;
    return [
      FieldReport(
        id: 'RPT-0001',
        category: 'Opening status',
        summary: 'Team present; operational checklist completed and communications confirmed.',
        scope: _kadunaNorth,
        reporterId: 'AG-KD-002',
        reportedAt: now.subtract(const Duration(minutes: 22)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      FieldReport(
        id: 'RPT-0002',
        category: 'Operational update',
        summary: 'Monitoring activity proceeding; one evidence-quality issue referred for review.',
        scope: _makurdi,
        reporterId: 'AG-BN-014',
        reportedAt: now.subtract(const Duration(minutes: 37)),
        status: RecordStatus.underReview,
        incidentId: 'INC-0002',
        origin: RecordOrigin.systemDerived,
      ),
      FieldReport(
        id: 'RPT-0003',
        category: 'Connectivity update',
        summary: 'Intermittent connectivity detected. Offline queue operating normally.',
        scope: _tarauni,
        reporterId: 'AG-KN-009',
        reportedAt: now.subtract(const Duration(hours: 1)),
        status: RecordStatus.submitted,
        incidentId: 'INC-0004',
        origin: RecordOrigin.systemDerived,
      ),
    ];
  }

  final List<FieldIncident> _incidents;
  final List<FieldReport> _reports;
  final OfflinePersistenceController? _persistence;

  // --- server session ---------------------------------------------------------

  FieldRepository? _server;
  int _openOnServer = 0;

  /// Every open incident on the server in your areas. The list holds the
  /// most urgent of them when there are more than it loads.
  int get openOnServer => _openOnServer;

  /// Read from and act on the server, as [account] (the signed-in access ID,
  /// which the uploads also carry).
  void connect(FieldRepository server, {required String account}) {
    if (identical(server, _server) && account == serverAccount) return;
    _server = server;
    connectServer(account);
  }

  /// Back to presentation mode and its sample records.
  void disconnect() {
    _server = null;
    disconnectServer();
  }

  @override
  OfflinePersistenceController? get offlineStore => _persistence;

  @override
  Future<FieldSnapshot> fetchServerRecords() => _server!.load();

  @override
  Iterable<String?> clientIdsOf(FieldSnapshot snapshot) => [
        for (final item in snapshot.incidents) item.clientId,
        for (final item in snapshot.reports) item.clientId,
      ];

  @override
  void showServerRecords(FieldSnapshot snapshot) {
    final incidents = _incidents.where((item) => isOnDevice(item.id)).toList();
    final reports = _reports.where((item) => isOnDevice(item.id)).toList();
    _incidents
      ..clear()
      ..addAll(incidents)
      ..addAll(snapshot.incidents);
    _reports
      ..clear()
      ..addAll(reports)
      ..addAll(snapshot.reports);
    _openOnServer = snapshot.openIncidents;
  }

  @override
  void showSampleRecords() {
    _openOnServer = 0;
    _incidents
      ..clear()
      ..addAll(_sampleIncidents());
    _reports
      ..clear()
      ..addAll(_sampleReports());
  }

  @override
  void clearRecords() {
    _openOnServer = 0;
    _incidents.clear();
    _reports.clear();
  }

  // --- records ----------------------------------------------------------------

  List<FieldIncident> get incidents => List.unmodifiable(_incidents);
  List<FieldReport> get reports => List.unmodifiable(_reports);

  List<FieldIncident> incidentsForScope(GeographicScope scope) =>
      _incidents.where((item) => _within(scope, item.scope)).toList(growable: false);

  List<FieldReport> reportsForScope(GeographicScope scope) =>
      _reports.where((item) => _within(scope, item.scope)).toList(growable: false);

  int get unresolvedIncidentCount => _incidents
      .where((item) => item.status != IncidentStatus.resolved && item.status != IncidentStatus.closed)
      .length;

  int get highPriorityIncidentCount => _incidents
      .where((item) =>
          item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical)
      .length;

  int get evidenceCount => _incidents.fold<int>(
        0,
        (total, incident) => total + incident.evidence.length,
      );

  String _newId(String prefix) => isLive
      // Unique on this device; the server gives the record its reference.
      ? 'NEW-${DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase()}'
      : '$prefix-${((prefix == 'INC' ? _incidents : _reports).length + 1).toString().padLeft(4, '0')}';

  Future<FieldIncident> createIncident({
    required String title,
    required String category,
    required IncidentSeverity severity,
    required GeographicScope scope,
    required String reporterId,
    String? summary,
    double? latitude,
    double? longitude,
    GpsFix? gps,
    List<EvidenceAttachment> evidence = const [],
  }) async {
    final incident = FieldIncident(
      id: _newId('INC'),
      title: title.trim(),
      category: category.trim(),
      severity: severity,
      status: IncidentStatus.reported,
      scope: scope,
      reportedAt: DateTime.now().toUtc(),
      reporterId: reporterId,
      summary: summary?.trim().isEmpty == true ? null : summary?.trim(),
      latitude: gps?.latitude ?? latitude,
      longitude: gps?.longitude ?? longitude,
      gps: gps,
      evidence: List.unmodifiable(evidence),
      origin: RecordOrigin.localEntry,
    );
    final receipt = await _persistence?.persistMutation(
      entityType: 'field_incident',
      entityId: incident.id,
      mutationType: SyncMutationType.create,
      payload: fieldIncidentToJson(incident),
      scopeKey: scopeStorageKey(scope),
      ownerId: reporterId,
    );
    if (receipt != null) keepUntilUploaded(incident.id, receipt.outbox.id);
    _incidents.insert(0, incident);
    notifyListeners();
    return incident;
  }

  Future<FieldReport> submitFieldReport({
    required String category,
    required String summary,
    required GeographicScope scope,
    required String reporterId,
    String? incidentId,
    GpsFix? gps,
    List<EvidenceAttachment> evidence = const [],
  }) async {
    final report = FieldReport(
      id: _newId('RPT'),
      category: category.trim(),
      summary: summary.trim(),
      scope: scope,
      reporterId: reporterId,
      reportedAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      incidentId: incidentId,
      gps: gps,
      evidence: List.unmodifiable(evidence),
      origin: RecordOrigin.localEntry,
    );
    final receipt = await _persistence?.persistMutation(
      entityType: 'field_report',
      entityId: report.id,
      mutationType: SyncMutationType.create,
      payload: fieldReportToJson(report),
      scopeKey: scopeStorageKey(scope),
      ownerId: reporterId,
    );
    if (receipt != null) keepUntilUploaded(report.id, receipt.outbox.id);
    _reports.insert(0, report);
    notifyListeners();
    return report;
  }

  // --- changes ----------------------------------------------------------------

  /// Moves an incident on. On the server in a server session, which checks
  /// the move, the note and your authority there; locally otherwise.
  Future<void> changeIncidentStatus(
    String incidentId,
    IncidentStatus status, {
    String note = '',
  }) async {
    final server = _server;
    if (server == null) {
      updateIncidentStatus(incidentId, status);
    } else {
      _replaceIncident(await server.changeStatus(incidentId, status, note: note));
    }
  }

  /// Gives a response team the incident.
  Future<void> assignIncident(String incidentId, String team, {String note = ''}) async {
    final server = _server;
    if (server != null) {
      _replaceIncident(await server.assign(incidentId, team: team, note: note));
      return;
    }
    final incident = _incidents.where((item) => item.id == incidentId).firstOrNull;
    if (incident == null) return;
    _replaceIncident(
      _incidentWith(incident, status: IncidentStatus.assigned, assignedTeam: team.trim()),
    );
  }

  /// Accepts or rejects a field report (a reason is needed to reject).
  Future<void> reviewReport(String reportId, {required bool accepted, String reason = ''}) async {
    final server = _server;
    if (server != null) {
      _replaceReport(await server.review(reportId, accepted: accepted, reason: reason));
      return;
    }
    final report = _reports.where((item) => item.id == reportId).firstOrNull;
    if (report == null) return;
    _replaceReport(FieldReport(
      id: report.id,
      category: report.category,
      summary: report.summary,
      scope: report.scope,
      reporterId: report.reporterId,
      reportedAt: report.reportedAt,
      status: accepted ? RecordStatus.verified : RecordStatus.rejected,
      incidentId: report.incidentId,
      gps: report.gps,
      evidence: report.evidence,
      origin: report.origin,
      clientId: report.clientId,
    ));
  }

  /// Every step taken on the incident, from the server (none in presentation mode).
  Future<List<IncidentHistoryEntry>> incidentHistory(String incidentId) async =>
      await _server?.history(incidentId) ?? const [];

  void updateIncidentStatus(String incidentId, IncidentStatus status) {
    final incident = _incidents.where((item) => item.id == incidentId).firstOrNull;
    if (incident == null) return;
    _replaceIncident(_incidentWith(incident, status: status));
  }

  FieldIncident _incidentWith(
    FieldIncident incident, {
    required IncidentStatus status,
    String? assignedTeam,
  }) =>
      FieldIncident(
        id: incident.id,
        title: incident.title,
        category: incident.category,
        severity: incident.severity,
        status: status,
        scope: incident.scope,
        reportedAt: incident.reportedAt,
        reporterId: incident.reporterId,
        summary: incident.summary,
        assignedTeam: assignedTeam ?? incident.assignedTeam,
        latitude: incident.latitude,
        longitude: incident.longitude,
        gps: incident.gps,
        evidence: incident.evidence,
        origin: incident.origin,
        clientId: incident.clientId,
      );

  void _replaceIncident(FieldIncident incident) {
    final index = _incidents.indexWhere((item) => item.id == incident.id);
    if (index < 0) return;
    _incidents[index] = incident;
    notifyListeners();
  }

  void _replaceReport(FieldReport report) {
    final index = _reports.indexWhere((item) => item.id == report.id);
    if (index < 0) return;
    _reports[index] = report;
    notifyListeners();
  }

  bool _within(GeographicScope parent, GeographicScope child) {
    if (parent.country != child.country) return false;
    if (parent.level == GeographyLevel.country) return true;
    if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
    if (parent.level == GeographyLevel.geopoliticalZone) return true;
    if (parent.stateId != null && parent.stateId != child.stateId) return false;
    if (parent.level == GeographyLevel.state) return true;
    if (parent.senatorialDistrictId != null &&
        parent.senatorialDistrictId != child.senatorialDistrictId) {
      return false;
    }
    if (parent.level == GeographyLevel.senatorialDistrict) return true;
    if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
    if (parent.level == GeographyLevel.lga) return true;
    if (parent.wardId != null && parent.wardId != child.wardId) return false;
    if (parent.level == GeographyLevel.ward) return true;
    return parent.pollingUnitId == child.pollingUnitId;
  }
}

class FieldOperations extends InheritedNotifier<FieldOperationsController> {
  const FieldOperations({
    super.key,
    required FieldOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static FieldOperationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<FieldOperations>();
      assert(value != null, 'FieldOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<FieldOperations>();
    final value = element?.widget as FieldOperations?;
    assert(value != null, 'FieldOperations is missing above this context.');
    return value!.notifier!;
  }
}
