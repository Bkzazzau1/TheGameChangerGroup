import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

class FieldOperationsController extends ChangeNotifier {
  FieldOperationsController._({
    required List<FieldIncident> incidents,
    required List<FieldReport> reports,
    OfflinePersistenceController? persistence,
  })  : _incidents = incidents,
        _reports = reports,
        _persistence = persistence;

  factory FieldOperationsController.prototypeSeed({
    OfflinePersistenceController? persistence,
  }) {
    final now = DateTime.utc(2026, 9, 27, 6, 30);

    GeographicScope lga({
      required String zoneId,
      required String zoneName,
      required String stateId,
      required String stateName,
      required String lgaId,
      required String lgaName,
    }) => GeographicScope(
          level: GeographyLevel.lga,
          country: 'Nigeria',
          zoneId: zoneId,
          zoneName: zoneName,
          stateId: stateId,
          stateName: stateName,
          lgaId: lgaId,
          lgaName: lgaName,
        );

    final kadunaNorth = lga(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
    );
    final makurdi = lga(
      zoneId: 'NC',
      zoneName: 'North Central',
      stateId: 'BN',
      stateName: 'Benue',
      lgaId: 'BN-MAKURDI',
      lgaName: 'Makurdi',
    );
    final ikeja = lga(
      zoneId: 'SW',
      zoneName: 'South West',
      stateId: 'LA',
      stateName: 'Lagos',
      lgaId: 'LA-IKEJA',
      lgaName: 'Ikeja',
    );
    final tarauni = lga(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KN',
      stateName: 'Kano',
      lgaId: 'KN-TARAUNI',
      lgaName: 'Tarauni',
    );

    EvidenceAttachment photo(String id, String uploader, DateTime at) =>
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

    return FieldOperationsController._(
      persistence: persistence,
      incidents: [
        FieldIncident(
          id: 'INC-0001',
          title: 'Polling-unit access obstruction reported',
          category: 'Access',
          severity: IncidentSeverity.high,
          status: IncidentStatus.investigating,
          scope: kadunaNorth,
          reportedAt: now.subtract(const Duration(minutes: 16)),
          reporterId: 'AG-KD-001',
          summary: 'Field team reported delayed access and requested coordinator review.',
          assignedTeam: 'North West Response Desk',
          evidence: [photo('EVD-0001', 'AG-KD-001', now.subtract(const Duration(minutes: 15)))],
          origin: RecordOrigin.systemDerived,
        ),
        FieldIncident(
          id: 'INC-0002',
          title: 'Result-form image quality below review threshold',
          category: 'Evidence quality',
          severity: IncidentSeverity.medium,
          status: IncidentStatus.assigned,
          scope: makurdi,
          reportedAt: now.subtract(const Duration(minutes: 31)),
          reporterId: 'AG-BN-014',
          summary: 'Uploaded form is readable only in part; recapture requested.',
          assignedTeam: 'Evidence Verification Desk',
          evidence: [photo('EVD-0002', 'AG-BN-014', now.subtract(const Duration(minutes: 30)))],
          origin: RecordOrigin.systemDerived,
        ),
        FieldIncident(
          id: 'INC-0003',
          title: 'Agent check-in requires location verification',
          category: 'Geolocation',
          severity: IncidentSeverity.low,
          status: IncidentStatus.acknowledged,
          scope: ikeja,
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
          scope: tarauni,
          reportedAt: now.subtract(const Duration(hours: 1, minutes: 8)),
          reporterId: 'AG-KN-009',
          summary: 'Report remains safely queued locally; technical support escalation required.',
          origin: RecordOrigin.systemDerived,
        ),
      ],
      reports: [
        FieldReport(
          id: 'RPT-0001',
          category: 'Opening status',
          summary: 'Team present; operational checklist completed and communications confirmed.',
          scope: kadunaNorth,
          reporterId: 'AG-KD-002',
          reportedAt: now.subtract(const Duration(minutes: 22)),
          status: RecordStatus.verified,
          origin: RecordOrigin.systemDerived,
        ),
        FieldReport(
          id: 'RPT-0002',
          category: 'Operational update',
          summary: 'Monitoring activity proceeding; one evidence-quality issue referred for review.',
          scope: makurdi,
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
          scope: tarauni,
          reporterId: 'AG-KN-009',
          reportedAt: now.subtract(const Duration(hours: 1)),
          status: RecordStatus.submitted,
          incidentId: 'INC-0004',
          origin: RecordOrigin.systemDerived,
        ),
      ],
    );
  }

  final List<FieldIncident> _incidents;
  final List<FieldReport> _reports;
  final OfflinePersistenceController? _persistence;

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

  Future<FieldIncident> createIncident({
    required String title,
    required String category,
    required IncidentSeverity severity,
    required GeographicScope scope,
    required String reporterId,
    String? summary,
    double? latitude,
    double? longitude,
    List<EvidenceAttachment> evidence = const [],
  }) async {
    final incident = FieldIncident(
      id: 'INC-${(_incidents.length + 1).toString().padLeft(4, '0')}',
      title: title.trim(),
      category: category.trim(),
      severity: severity,
      status: IncidentStatus.reported,
      scope: scope,
      reportedAt: DateTime.now().toUtc(),
      reporterId: reporterId,
      summary: summary?.trim().isEmpty == true ? null : summary?.trim(),
      latitude: latitude,
      longitude: longitude,
      evidence: List.unmodifiable(evidence),
      origin: RecordOrigin.localEntry,
    );
    await _persistence?.persistMutation(
      entityType: 'field_incident',
      entityId: incident.id,
      mutationType: SyncMutationType.create,
      payload: fieldIncidentToJson(incident),
      scopeKey: scopeStorageKey(scope),
      ownerId: reporterId,
    );
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
    List<EvidenceAttachment> evidence = const [],
  }) async {
    final report = FieldReport(
      id: 'RPT-${(_reports.length + 1).toString().padLeft(4, '0')}',
      category: category.trim(),
      summary: summary.trim(),
      scope: scope,
      reporterId: reporterId,
      reportedAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      incidentId: incidentId,
      evidence: List.unmodifiable(evidence),
      origin: RecordOrigin.localEntry,
    );
    await _persistence?.persistMutation(
      entityType: 'field_report',
      entityId: report.id,
      mutationType: SyncMutationType.create,
      payload: fieldReportToJson(report),
      scopeKey: scopeStorageKey(scope),
      ownerId: reporterId,
    );
    _reports.insert(0, report);
    notifyListeners();
    return report;
  }

  void updateIncidentStatus(String incidentId, IncidentStatus status) {
    final index = _incidents.indexWhere((item) => item.id == incidentId);
    if (index < 0) return;
    final incident = _incidents[index];
    _incidents[index] = FieldIncident(
      id: incident.id,
      title: incident.title,
      category: incident.category,
      severity: incident.severity,
      status: status,
      scope: incident.scope,
      reportedAt: incident.reportedAt,
      reporterId: incident.reporterId,
      summary: incident.summary,
      assignedTeam: incident.assignedTeam,
      latitude: incident.latitude,
      longitude: incident.longitude,
      evidence: incident.evidence,
      origin: incident.origin,
    );
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
