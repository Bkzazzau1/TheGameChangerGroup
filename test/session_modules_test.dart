import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

void main() {
  group('TGCG role-aware modules', () {
    const M = TgcgModule.values;
    TgcgModule m(String name) => M.byName(name);
    Set<TgcgModule> modules(String names) => {for (final name in names.split(' ')) m(name)};

    // The role grid agreed on 10 October 2026 ("Proposed"), plus screens built
    // since: Unit Mapping for coordinators who pin units, and Agents on the
    // Ground for whoever sees live operations, and Member Review for the state,
    // LGA and ward coordinators who verify identities (13 October 2026). Role
    // Assignment for zonal and state coordinators and Technical Support waits for
    // cascading appointments. Since 15 October 2026 the Situation Room is national,
    // so no coordinator has it, nor Security Response, which needs it. Projects
    // (17 October 2026) for whoever watches live operations or assigns people.
    final grid = <TgcgRole, Set<TgcgModule>>{
      TgcgRole.nationalCollationOfficer: modules(
        'overview projects liveOperations agentTracking alertCenter situationRoom evidenceCapture '
        'resultCapture aiVerification collation communications discussionRoom meetingRoom reports',
      ),
      TgcgRole.situationRoomDirector: modules(
        'overview projects liveOperations agentTracking aiAnalytics alertCenter situationRoom '
        'securityResponse mediaIntelligence fieldMonitoring evidenceCapture resultCapture '
        'aiVerification collation communications bulkCommunications discussionRoom meetingRoom '
        'reports',
      ),
      TgcgRole.zonalCoordinator: modules(
        'overview projects liveOperations agentTracking aiAnalytics alertCenter '
        'mediaIntelligence accreditation unitMapping aiVerification '
        'fieldMonitoring evidenceCapture resultCapture collation communications '
        'bulkCommunications discussionRoom meetingRoom reports',
      ),
      TgcgRole.stateCoordinator: modules(
        'overview projects liveOperations agentTracking aiAnalytics alertCenter '
        'mediaIntelligence accreditation memberReview unitMapping aiVerification '
        'fieldMonitoring evidenceCapture resultCapture collation communications '
        'bulkCommunications discussionRoom meetingRoom reports',
      ),
      TgcgRole.lgaCoordinator: modules(
        'overview projects liveOperations agentTracking alertCenter '
        'accreditation memberReview unitMapping aiVerification fieldMonitoring evidenceCapture '
        'resultCapture collation communications discussionRoom meetingRoom',
      ),
      TgcgRole.wardCoordinator: modules(
        'overview projects liveOperations agentTracking accreditation memberReview '
        'unitMapping fieldMonitoring evidenceCapture resultCapture collation communications '
        'discussionRoom meetingRoom',
      ),
      TgcgRole.pollingUnitAgent: modules(
        'overview fieldMonitoring evidenceCapture resultCapture communications discussionRoom '
        'meetingRoom',
      ),
      TgcgRole.observer: modules(
        'overview fieldMonitoring evidenceCapture communications discussionRoom meetingRoom',
      ),
      TgcgRole.legalOfficer: modules(
        'overview situationRoom mediaIntelligence fieldMonitoring evidenceCapture resultCapture '
        'collation communications discussionRoom meetingRoom reports governance',
      ),
      TgcgRole.technicalSupport: modules(
        'overview communications discussionRoom meetingRoom systemMonitoring governance',
      ),
      TgcgRole.readOnlyExecutive: modules(
        'overview projects liveOperations agentTracking aiAnalytics situationRoom mediaIntelligence '
        'collation meetingRoom reports',
      ),
    };

    for (final MapEntry(key: role, value: expected) in grid.entries) {
      test('${role.name} sees what the role grid gives it', () {
        expect(allowedModules(role), expected);
      });
    }

    test('national administrator sees every application module', () {
      expect(allowedModules(TgcgRole.nationalAdministrator), containsAll(TgcgModule.values));
    });

    test('only the national administrator opens geography master data and member records', () {
      for (final role in TgcgRole.values.where((r) => r != TgcgRole.nationalAdministrator)) {
        final seen = allowedModules(role);
        expect(seen, isNot(contains(TgcgModule.geography)), reason: role.name);
        expect(seen, isNot(contains(TgcgModule.membershipNetwork)), reason: role.name);
      }
    });
  });
}
