import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart' show geographicScopeFromJson;
import 'field_repository.dart' show evidenceFromJson;
import 'reference_repository.dart' show ServerElection;

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

double? _decimal(Object? value) => value == null ? null : double.tryParse('$value');

Map<String, int> _votes(Object? value) => {
      for (final entry in (value as Map<String, dynamic>? ?? const {}).entries)
        entry.key: (entry.value as num).toInt(),
    };

ElectionResultSubmission resultFromJson(Map<String, dynamic> json) {
  final checks = json['validation'] as Map<String, dynamic>?;
  final gps = json['gps'] as Map<String, dynamic>?;
  final latitude = _decimal(gps?['latitude']);
  final longitude = _decimal(gps?['longitude']);
  final accuracy = (gps?['accuracy_m'] as num?)?.toDouble();
  final capturedAt = DateTime.tryParse('${gps?['captured_at']}');
  final form = json['result_form'];
  return ElectionResultSubmission(
    id: json['reference'] as String,
    pollingUnitScope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
    submittedBy: json['submitted_by'] as String? ?? '',
    submittedAt: DateTime.parse(json['submitted_at'] as String),
    status: RecordStatus.values.byName(json['status'] as String),
    source: SubmissionSource.values.byName(json['source'] as String),
    partyVotes: Map.unmodifiable(_votes(json['party_votes'])),
    totalVotesRecorded: json['total_valid_votes'] as int,
    accreditedVoters: json['accredited_voters'] as int,
    rejectedVotes: json['rejected_votes'] as int?,
    registeredVoters: json['registered_voters'] as int?,
    resultForm: form is Map<String, dynamic> ? evidenceFromJson(form) : null,
    validation: checks == null
        ? null
        : ResultValidationSummary(
            arithmeticValid: checks['arithmetic_valid'] as bool,
            duplicateSuspected: checks['duplicate_suspected'] as bool,
            pollingUnitMatched: checks['polling_unit_matched'] as bool? ?? true,
            agentScopeMatched: checks['agent_scope_matched'] as bool,
            ocrConfidence: (checks['ocr_confidence'] as num?)?.toDouble(),
            ocrMatchedManualEntry: checks['ocr_matched_manual_entry'] as bool?,
            notes: [for (final note in checks['notes'] as List<dynamic>? ?? const []) '$note'],
          ),
    verifiedBy: _text(json['verified_by']),
    verifiedAt: DateTime.tryParse('${json['verified_at']}'),
    disputeReason: _text(json['review_reason']),
    sourceReference: _text(json['source_reference']),
    gps: latitude != null && longitude != null && accuracy != null && capturedAt != null
        ? GpsFix(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy,
            capturedAt: capturedAt,
            isMocked: gps?['is_mocked'] as bool? ?? false,
          )
        : null,
    electionCode: _text(json['election']),
    origin: RecordOrigin.values.asNameMap()[json['origin']] ?? RecordOrigin.localEntry,
    clientId: _text(json['client_id']),
  );
}

/// One step in a result's history (`/results/<reference>/events/`).
class ResultHistoryEntry {
  const ResultHistoryEntry({
    required this.toStatus,
    required this.at,
    this.fromStatus,
    this.note = '',
    this.actor,
  });

  final RecordStatus? fromStatus;
  final RecordStatus toStatus;
  final DateTime at;
  final String note;
  final String? actor;

  factory ResultHistoryEntry.fromJson(Map<String, dynamic> json) => ResultHistoryEntry(
        fromStatus: RecordStatus.values.asNameMap()[json['from_status']],
        toStatus: RecordStatus.values.byName(json['to_status'] as String),
        at: DateTime.parse(json['created_at'] as String),
        note: json['note'] as String? ?? '',
        actor: _text(json['actor']),
      );
}

/// The results the server holds for the caller's areas.
class ResultsSnapshot {
  const ResultsSnapshot({required this.results, required this.awaitingDecision});

  /// Results awaiting a decision (oldest first), then the latest others.
  final List<ElectionResultSubmission> results;

  /// Every result awaiting a decision; more than were loaded when the areas
  /// are very busy.
  final int awaitingDecision;
}

/// One area in a collation breakdown.
class CollationArea {
  const CollationArea({
    required this.level,
    required this.code,
    required this.name,
    required this.expectedPollingUnits,
    required this.reportedPollingUnits,
    required this.verifiedPollingUnits,
    required this.completionPercent,
    required this.partyVotes,
    this.leadingParty,
  });

  final GeographyLevel level;
  final String code;
  final String name;
  final int expectedPollingUnits;
  final int reportedPollingUnits;
  final int verifiedPollingUnits;
  final double completionPercent;
  final Map<String, int> partyVotes;

  /// Null before any verified result, and on a tie.
  final String? leadingParty;

  factory CollationArea.fromJson(Map<String, dynamic> json) => CollationArea(
        level: GeographyLevel.values.byName(json['level'] as String),
        code: json['code'] as String,
        name: json['name'] as String,
        expectedPollingUnits: json['expected_polling_units'] as int,
        reportedPollingUnits: json['reported_polling_units'] as int,
        verifiedPollingUnits: json['verified_polling_units'] as int,
        completionPercent: (json['completion_percent'] as num).toDouble(),
        partyVotes: _votes(json['party_votes']),
        leadingParty: _text(json['leading_party']),
      );
}

/// The server's unofficial collation of verified results for one area of one
/// election (`/collation/`). It never replaces INEC's declaration.
class ServerCollation {
  const ServerCollation({
    required this.election,
    required this.scope,
    required this.expectedPollingUnits,
    required this.reportedPollingUnits,
    required this.verifiedPollingUnits,
    required this.underReview,
    required this.disputed,
    required this.missingPollingUnits,
    required this.completionPercent,
    required this.accreditedVoters,
    required this.totalValidVotes,
    required this.rejectedVotes,
    required this.partyVotes,
    required this.children,
    this.leadingParty,
  });

  final String election;
  final GeographicScope scope;
  final int expectedPollingUnits;
  final int reportedPollingUnits;
  final int verifiedPollingUnits;
  final int underReview;
  final int disputed;
  final int missingPollingUnits;
  final double completionPercent;
  final int accreditedVoters;
  final int totalValidVotes;
  final int rejectedVotes;

  /// Verified votes by party, most votes first.
  final Map<String, int> partyVotes;

  /// Null before any verified result, and on a tie.
  final String? leadingParty;

  /// The next level down (none below a polling unit).
  final List<CollationArea> children;

  factory ServerCollation.fromJson(Map<String, dynamic> json) => ServerCollation(
        election: json['election'] as String,
        scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
        expectedPollingUnits: json['expected_polling_units'] as int,
        reportedPollingUnits: json['reported_polling_units'] as int,
        verifiedPollingUnits: json['verified_polling_units'] as int,
        underReview: json['under_review'] as int,
        disputed: json['disputed'] as int,
        missingPollingUnits: json['missing_polling_units'] as int,
        completionPercent: (json['completion_percent'] as num).toDouble(),
        accreditedVoters: json['accredited_voters'] as int,
        totalValidVotes: json['total_valid_votes'] as int,
        rejectedVotes: json['rejected_votes'] as int,
        partyVotes: _votes(json['party_votes']),
        leadingParty: _text(json['leading_party']),
        children: [
          for (final item in json['children'] as List<dynamic>? ?? const [])
            CollationArea.fromJson(item as Map<String, dynamic>),
        ],
      );
}

/// Polling-unit results and collation (`/results/`, `/elections/`,
/// `/collation/`). The server decides what each account sees, and checks
/// every review decision in the result's area.
class ResultsRepository {
  ResultsRepository(this.client);
  final ApiClient client;

  static const awaitingStatuses = [
    RecordStatus.underReview,
    RecordStatus.disputed,
    RecordStatus.submitted,
  ];

  /// Results awaiting a decision (up to [awaiting] of each status, oldest
  /// first) and the [latest] results whatever their status.
  Future<ResultsSnapshot> load({int awaiting = 300, int latest = 100}) async {
    final pages = await Future.wait([
      for (final status in awaitingStatuses)
        client.get('results/', query: {
          'status': status.name,
          'ordering': 'submitted_at',
          'limit': '$awaiting',
        }),
      client.get('results/', query: {'ordering': '-submitted_at', 'limit': '$latest'}),
    ]);
    final seen = <String>{};
    final results = <ElectionResultSubmission>[];
    for (final page in pages) {
      for (final item in (page as Map<String, dynamic>)['results'] as List<dynamic>) {
        final result = resultFromJson(item as Map<String, dynamic>);
        if (seen.add(result.id)) results.add(result);
      }
    }
    return ResultsSnapshot(
      results: results,
      awaitingDecision: [
        for (final page in pages.take(awaitingStatuses.length))
          (page as Map<String, dynamic>)['count'] as int? ?? 0,
      ].fold(0, (sum, count) => sum + count),
    );
  }

  /// Confirms a result; only verified results count in collation.
  Future<ElectionResultSubmission> verify(String reference, {String note = ''}) async =>
      resultFromJson(
        await client.post('results/$reference/verify/', body: {'note': note.trim()})
            as Map<String, dynamic>,
      );

  /// Flags a result as contested.
  Future<ElectionResultSubmission> dispute(String reference, {required String reason}) async =>
      resultFromJson(
        await client.post('results/$reference/dispute/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  /// Refuses a result; the agent resubmits a corrected one.
  Future<ElectionResultSubmission> reject(String reference, {required String reason}) async =>
      resultFromJson(
        await client.post('results/$reference/reject/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  /// Every decision on the result, oldest first.
  Future<List<ResultHistoryEntry>> history(String reference) async {
    final body = await client.get('results/$reference/events/') as List<dynamic>;
    return [for (final item in body) ResultHistoryEntry.fromJson(item as Map<String, dynamic>)];
  }

  /// Every election, newest first.
  Future<List<ServerElection>> elections() async {
    final body = await client.get('elections/') as List<dynamic>;
    return [for (final item in body) ServerElection.fromJson(item as Map<String, dynamic>)];
  }

  /// The collation of [election] in an area: [level] and [code], or your own.
  Future<ServerCollation> collation(
    String election, {
    GeographyLevel? level,
    String? code,
  }) async =>
      ServerCollation.fromJson(
        await client.get('collation/', query: {
          'election': election,
          if (level != null) 'level': level.name,
          'code': ?code,
        }) as Map<String, dynamic>,
      );
}
