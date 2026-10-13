import 'package:flutter/widgets.dart';

import '../api/results_repository.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../evidence/evidence_upload.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';
import '../sync/server_records.dart';
import 'result_integrity.dart';

/// Polling-unit results for every screen that shows them.
///
/// In presentation mode it holds sample results and reviews them locally. In
/// a server session ([connect]) it holds what the server returns, and every
/// review decision is made on the server, which checks it. New results are
/// saved on the device first and stay on the list until the server's copy
/// replaces them (see [ServerRecords]).
class ResultOperationsController extends ChangeNotifier with ServerRecords<ResultsSnapshot> {
  ResultOperationsController._({
    required List<ElectionResultSubmission> submissions,
    OfflinePersistenceController? persistence,
  })  : _submissions = submissions,
        _persistence = persistence;

  factory ResultOperationsController.prototypeSeed({
    OfflinePersistenceController? persistence,
  }) =>
      ResultOperationsController._(persistence: persistence, submissions: _sampleSubmissions());

  static GeographicScope _pollingUnit({
    required String zoneId,
    required String zoneName,
    required String stateId,
    required String stateName,
    required String lgaId,
    required String lgaName,
    required String wardId,
    required String wardName,
    required String pollingUnitId,
    required String pollingUnitName,
  }) =>
      GeographicScope(
        level: GeographyLevel.pollingUnit,
        country: 'Nigeria',
        zoneId: zoneId,
        zoneName: zoneName,
        stateId: stateId,
        stateName: stateName,
        lgaId: lgaId,
        lgaName: lgaName,
        wardId: wardId,
        wardName: wardName,
        pollingUnitId: pollingUnitId,
        pollingUnitName: pollingUnitName,
      );

  static List<ElectionResultSubmission> _sampleSubmissions() {
    final now = DateTime.utc(2026, 9, 27, 6, 45);
    final puKaduna = _pollingUnit(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
      wardId: 'KD-KN-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'KD-KN-W01-PU001',
      pollingUnitName: 'PU 001',
    );
    final puBenue = _pollingUnit(
      zoneId: 'NC',
      zoneName: 'North Central',
      stateId: 'BN',
      stateName: 'Benue',
      lgaId: 'BN-MAKURDI',
      lgaName: 'Makurdi',
      wardId: 'BN-MK-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'BN-MK-W01-PU004',
      pollingUnitName: 'PU 004',
    );
    final puLagos = _pollingUnit(
      zoneId: 'SW',
      zoneName: 'South West',
      stateId: 'LA',
      stateName: 'Lagos',
      lgaId: 'LA-IKEJA',
      lgaName: 'Ikeja',
      wardId: 'LA-IK-W03',
      wardName: 'Ward 03',
      pollingUnitId: 'LA-IK-W03-PU012',
      pollingUnitName: 'PU 012',
    );

    EvidenceAttachment form(String id, String uploader, DateTime at) => EvidenceAttachment(
          id: id,
          type: EvidenceType.resultForm,
          fileName: '$id.jpg',
          createdAt: at,
          uploaderId: uploader,
          contentHash: 'sha256:prototype-$id',
          mimeType: 'image/jpeg',
          caption: 'Prototype result-form evidence. Replace with captured original.',
          origin: RecordOrigin.systemDerived,
        );

    ElectionResultSubmission validated({
      required String id,
      required GeographicScope scope,
      required String agent,
      required SubmissionSource source,
      required Map<String, int> votes,
      required int total,
      required int accredited,
      required int rejected,
      required RecordStatus status,
      required DateTime at,
      bool duplicate = false,
      Map<String, int>? ocrVotes,
      double? ocrConfidence,
      EvidenceAttachment? evidence,
    }) {
      final base = ElectionResultSubmission(
        id: id,
        pollingUnitScope: scope,
        submittedBy: agent,
        submittedAt: at,
        status: status,
        source: source,
        partyVotes: Map.unmodifiable(votes),
        totalVotesRecorded: total,
        accreditedVoters: accredited,
        rejectedVotes: rejected,
        resultForm: evidence,
        origin: RecordOrigin.systemDerived,
      );
      final validation = ResultIntegrityPolicy.validate(
        base,
        duplicateSuspected: duplicate,
        ocrPartyVotes: ocrVotes,
        ocrConfidence: ocrConfidence,
      );
      return _with(base, validation: validation);
    }

    return [
      validated(
        id: 'RES-0001',
        scope: puKaduna,
        agent: 'AG-KD-001',
        source: SubmissionSource.app,
        votes: const {'P1': 118, 'P2': 81, 'P3': 37, 'P4': 14},
        total: 250,
        accredited: 263,
        rejected: 13,
        status: RecordStatus.verified,
        at: now.subtract(const Duration(minutes: 18)),
        ocrVotes: const {'P1': 118, 'P2': 81, 'P3': 37, 'P4': 14},
        ocrConfidence: .97,
        evidence: form('FORM-0001', 'AG-KD-001', now.subtract(const Duration(minutes: 18))),
      ),
      validated(
        id: 'RES-0002',
        scope: puBenue,
        agent: 'AG-BN-014',
        source: SubmissionSource.app,
        votes: const {'P1': 96, 'P2': 104, 'P3': 41, 'P4': 12},
        total: 253,
        accredited: 268,
        rejected: 15,
        status: RecordStatus.underReview,
        at: now.subtract(const Duration(minutes: 34)),
        ocrVotes: const {'P1': 96, 'P2': 101, 'P3': 41, 'P4': 12},
        ocrConfidence: .82,
        evidence: form('FORM-0002', 'AG-BN-014', now.subtract(const Duration(minutes: 34))),
      ),
      validated(
        id: 'RES-0003',
        scope: puLagos,
        agent: 'AG-LA-032',
        source: SubmissionSource.sms,
        votes: const {'P1': 140, 'P2': 74, 'P3': 52, 'P4': 19},
        total: 285,
        accredited: 297,
        rejected: 12,
        status: RecordStatus.submitted,
        at: now.subtract(const Duration(minutes: 49)),
      ),
      validated(
        id: 'RES-0004',
        scope: puKaduna,
        agent: 'AG-KD-009',
        source: SubmissionSource.ussd,
        votes: const {'P1': 118, 'P2': 81, 'P3': 37, 'P4': 14},
        total: 250,
        accredited: 263,
        rejected: 13,
        status: RecordStatus.underReview,
        at: now.subtract(const Duration(minutes: 12)),
        duplicate: true,
      ),
    ];
  }

  final List<ElectionResultSubmission> _submissions;
  final OfflinePersistenceController? _persistence;

  // --- server session ---------------------------------------------------------

  ResultsRepository? _server;
  int _awaitingOnServer = 0;

  /// Every result awaiting a decision on the server in your areas. The list
  /// holds the oldest of them when there are more than it loads.
  int get awaitingOnServer => _awaitingOnServer;

  /// Read from and decide on the server, as [account] (the signed-in access
  /// ID, which the uploads also carry).
  void connect(ResultsRepository server, {required String account}) {
    if (identical(server, _server) && account == serverAccount) return;
    _server = server;
    connectServer(account);
  }

  /// Back to presentation mode and its sample results.
  void disconnect() {
    _server = null;
    disconnectServer();
  }

  @override
  OfflinePersistenceController? get offlineStore => _persistence;

  @override
  Future<ResultsSnapshot> fetchServerRecords() => _server!.load();

  @override
  Iterable<String?> clientIdsOf(ResultsSnapshot snapshot) =>
      snapshot.results.map((item) => item.clientId);

  @override
  void showServerRecords(ResultsSnapshot snapshot) {
    final local = _submissions.where((item) => isOnDevice(item.id)).toList();
    _submissions
      ..clear()
      ..addAll(local)
      ..addAll(snapshot.results);
    _awaitingOnServer = snapshot.awaitingDecision;
  }

  @override
  void showSampleRecords() {
    _awaitingOnServer = 0;
    _submissions
      ..clear()
      ..addAll(_sampleSubmissions());
  }

  @override
  void clearRecords() {
    _awaitingOnServer = 0;
    _submissions.clear();
  }

  // --- results ----------------------------------------------------------------

  List<ElectionResultSubmission> get submissions => List.unmodifiable(_submissions);

  List<ElectionResultSubmission> submissionsForScope(GeographicScope scope) =>
      _submissions.where((item) => _within(scope, item.pollingUnitScope)).toList(growable: false);

  /// Flagged results that need a person to look closely.
  List<ElectionResultSubmission> reviewQueueForScope(GeographicScope scope) =>
      submissionsForScope(scope).where(_needsReview).toList(growable: false);

  /// Results still waiting for a decision (only verified results count in
  /// collation): flagged ones first, then the oldest.
  List<ElectionResultSubmission> awaitingDecisionForScope(GeographicScope scope) =>
      submissionsForScope(scope).where(awaitsDecision).toList()
        ..sort((a, b) {
          final flagged = (_needsReview(a) ? 0 : 1).compareTo(_needsReview(b) ? 0 : 1);
          return flagged != 0 ? flagged : a.submittedAt.compareTo(b.submittedAt);
        });

  /// Not yet verified or rejected.
  static bool awaitsDecision(ElectionResultSubmission item) =>
      item.status == RecordStatus.submitted ||
      item.status == RecordStatus.underReview ||
      item.status == RecordStatus.disputed;

  int get pendingReviewCount => _submissions.where(_needsReview).length;

  int get verifiedCount =>
      _submissions.where((item) => item.status == RecordStatus.verified).length;

  Future<ElectionResultSubmission> submit({
    required GeographicScope pollingUnitScope,
    required String submittedBy,
    required SubmissionSource source,
    required Map<String, int> partyVotes,
    required int totalVotesRecorded,
    required int accreditedVoters,
    int? rejectedVotes,
    int? registeredVoters,
    EvidenceAttachment? resultForm,
    Map<String, int>? ocrPartyVotes,
    double? ocrConfidence,
    GpsFix? gps,
    String? electionCode,
    PendingEvidence? sheetPhoto,
  }) async {
    if (source == SubmissionSource.app && gps == null) {
      throw ArgumentError('Results submitted from the app need a GPS reading.');
    }
    final duplicate = _submissions.any((existing) =>
        existing.pollingUnitScope.pollingUnitId == pollingUnitScope.pollingUnitId &&
        existing.status != RecordStatus.rejected &&
        existing.status != RecordStatus.archived);

    final id = isLive
        // Unique on this device; the server gives the result its reference.
        ? 'NEW-${DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase()}'
        : 'RES-${(_submissions.length + 1).toString().padLeft(4, '0')}';
    final base = ElectionResultSubmission(
      id: id,
      pollingUnitScope: pollingUnitScope,
      submittedBy: submittedBy,
      submittedAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      source: source,
      partyVotes: Map.unmodifiable(partyVotes),
      totalVotesRecorded: totalVotesRecorded,
      accreditedVoters: accreditedVoters,
      rejectedVotes: rejectedVotes,
      registeredVoters: registeredVoters,
      resultForm: resultForm ?? sheetPhoto?.toAttachment(id: '$id-SHEET', uploaderId: submittedBy),
      gps: gps,
      electionCode: electionCode,
      origin: RecordOrigin.localEntry,
    );

    final validation = ResultIntegrityPolicy.validate(
      base,
      duplicateSuspected: duplicate,
      ocrPartyVotes: ocrPartyVotes,
      ocrConfidence: ocrConfidence,
    );
    final status = validation.requiresHumanReview
        ? RecordStatus.underReview
        : RecordStatus.submitted;
    final saved = _with(base, validation: validation, status: status);
    final receipt = await _persistence?.persistMutation(
      entityType: 'election_result',
      entityId: saved.id,
      mutationType: SyncMutationType.create,
      payload: resultSubmissionToJson(saved),
      scopeKey: scopeStorageKey(saved.pollingUnitScope),
      ownerId: submittedBy,
    );
    if (receipt != null) {
      keepUntilUploaded(saved.id, receipt.outbox.id);
      // The sheet photo uploads after the result, to its server reference.
      if (sheetPhoto != null) {
        await queueEvidence(
          _persistence!,
          parent: EvidenceParent.result,
          recordOutboxId: receipt.outbox.id,
          evidence: sheetPhoto,
          ownerId: submittedBy,
        );
      }
    }
    _submissions.insert(0, saved);
    notifyListeners();
    return saved;
  }

  // --- decisions --------------------------------------------------------------
  //
  // In a server session the server decides who may do what, area by area,
  // and these return true or throw its refusal. In presentation mode the
  // built-in permissions decide, and false means refused.

  /// Confirms a result; only verified results count in collation.
  Future<bool> verify({
    required String submissionId,
    required String verifierId,
    required TgcgActor role,
    required GeographicScope userScope,
    String note = '',
  }) async {
    final server = _server;
    if (server != null) {
      _replace(await server.verify(submissionId, note: note));
      return true;
    }
    final index = _submissions.indexWhere((item) => item.id == submissionId);
    if (index < 0) return false;
    final current = _submissions[index];
    if (!TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.verifyElectionResult,
      targetScope: current.pollingUnitScope,
    )) {
      return false;
    }

    final updated = _with(
      current,
      status: RecordStatus.verified,
      verifiedBy: verifierId,
      verifiedAt: DateTime.now().toUtc(),
      disputeReason: null,
    );
    await _persistLocal(updated, verifierId);
    _submissions[index] = updated;
    notifyListeners();
    return true;
  }

  /// Flags a result as contested; a reason is required.
  Future<bool> dispute({
    required String submissionId,
    required String reviewerId,
    required String reason,
    required TgcgActor role,
    required GeographicScope userScope,
  }) async {
    final server = _server;
    if (server != null) {
      _replace(await server.dispute(submissionId, reason: reason));
      return true;
    }
    final index = _submissions.indexWhere((item) => item.id == submissionId);
    if (index < 0) return false;
    final current = _submissions[index];
    if (!TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.disputeElectionResult,
      targetScope: current.pollingUnitScope,
    )) {
      return false;
    }

    final updated = _with(
      current,
      status: RecordStatus.disputed,
      disputeReason: reason.trim().isEmpty ? 'Flagged for review.' : reason.trim(),
      verifiedBy: reviewerId,
      verifiedAt: DateTime.now().toUtc(),
    );
    await _persistLocal(updated, reviewerId);
    _submissions[index] = updated;
    notifyListeners();
    return true;
  }

  /// Refuses a result, so the agent submits a corrected one; a reason is required.
  Future<bool> reject({
    required String submissionId,
    required String reviewerId,
    required String reason,
    required TgcgActor role,
    required GeographicScope userScope,
  }) async {
    final server = _server;
    if (server != null) {
      _replace(await server.reject(submissionId, reason: reason));
      return true;
    }
    final index = _submissions.indexWhere((item) => item.id == submissionId);
    if (index < 0) return false;
    final current = _submissions[index];
    if (!TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.verifyElectionResult,
      targetScope: current.pollingUnitScope,
    )) {
      return false;
    }
    final updated = _with(current, status: RecordStatus.rejected, disputeReason: reason.trim());
    await _persistLocal(updated, reviewerId);
    _submissions[index] = updated;
    notifyListeners();
    return true;
  }

  /// Every decision on the result, from the server (none in presentation mode).
  Future<List<ResultHistoryEntry>> resultHistory(String submissionId) async =>
      await _server?.history(submissionId) ?? const [];

  Future<void> _persistLocal(ElectionResultSubmission updated, String actorId) async {
    await _persistence?.persistMutation(
      entityType: 'election_result',
      entityId: updated.id,
      mutationType: SyncMutationType.update,
      payload: resultSubmissionToJson(updated),
      scopeKey: scopeStorageKey(updated.pollingUnitScope),
      ownerId: actorId,
    );
  }

  void _replace(ElectionResultSubmission updated) {
    final index = _submissions.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;
    _submissions[index] = updated;
    notifyListeners();
  }

  static bool _needsReview(ElectionResultSubmission item) {
    if (item.status == RecordStatus.verified ||
        item.status == RecordStatus.rejected ||
        item.status == RecordStatus.archived) {
      return false;
    }
    return item.status == RecordStatus.underReview ||
        item.status == RecordStatus.disputed ||
        item.validation?.requiresHumanReview == true;
  }

  static ElectionResultSubmission _with(
    ElectionResultSubmission current, {
    RecordStatus? status,
    ResultValidationSummary? validation,
    String? verifiedBy,
    DateTime? verifiedAt,
    String? disputeReason,
  }) =>
      ElectionResultSubmission(
        id: current.id,
        pollingUnitScope: current.pollingUnitScope,
        submittedBy: current.submittedBy,
        submittedAt: current.submittedAt,
        status: status ?? current.status,
        source: current.source,
        partyVotes: current.partyVotes,
        totalVotesRecorded: current.totalVotesRecorded,
        accreditedVoters: current.accreditedVoters,
        rejectedVotes: current.rejectedVotes,
        registeredVoters: current.registeredVoters,
        resultForm: current.resultForm,
        validation: validation ?? current.validation,
        verifiedBy: verifiedBy ?? current.verifiedBy,
        verifiedAt: verifiedAt ?? current.verifiedAt,
        disputeReason: disputeReason,
        sourceReference: current.sourceReference,
        gps: current.gps,
        electionCode: current.electionCode,
        origin: current.origin,
        clientId: current.clientId,
      );

  static bool _within(GeographicScope parent, GeographicScope child) {
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

class ResultOperations extends InheritedNotifier<ResultOperationsController> {
  const ResultOperations({
    super.key,
    required ResultOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ResultOperationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<ResultOperations>();
      assert(value != null, 'ResultOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<ResultOperations>();
    final value = element?.widget as ResultOperations?;
    assert(value != null, 'ResultOperations is missing above this context.');
    return value!.notifier!;
  }
}
