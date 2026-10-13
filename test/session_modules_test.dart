import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

void main() {
  group('TGCG role-aware modules', () {
    const M = TgcgModule.values;
    TgcgModule m(String name) => M.byName(name);
    Set<TgcgModule> modules(String names) => {for (final name in names.split(' ')) m(name)};

    // The role grid agreed on 10 October 2026 ("Proposed"), plus screens built
    // since: Unit Mapping for coordinators who pin units, and Agents on the
    // Ground for whoever sees live operations. Role Assignment for zonal and
    // state coordinators and Technical Support waits for cascading appointments.
    final grid = <TgcgRole, Set<TgcgModule>>{
      TgcgRole.nationalCollationOfficer: modules(
        'overview liveOperations agentTracking alertCenter situationRoom evidenceCapture '
        'resultCapture aiVerification collation communications discussionRoom meetingRoom reports',
      ),
      TgcgRole.situationRoomDirector: modules(
        'overview liveOperations agentTracking aiAnalytics alertCenter situationRoom '
        'securityResponse mediaIntelligence fieldMonitoring evidenceCapture resultCapture '
        'aiVerification collation communications bulkCommunications discussionRoom meetingRoom '
        'reports',
      ),
      TgcgRole.zonalCoordinator: modules(
        'overview liveOperations agentTracking aiAnalytics alertCenter situationRoom '
        'securityResponse mediaIntelligence accreditation unitMapping aiVerification '
        'fieldMonitoring evidenceCapture resultCapture collation communications '
        'bulkCommunications discussionRoom meetingRoom reports',
      ),
      TgcgRole.stateCoordinator: modules(
        'overview liveOperations agentTracking aiAnalytics alertCenter situationRoom '
        'securityResponse mediaIntelligence accreditation unitMapping aiVerification '
        'fieldMonitoring evidenceCapture resultCapture collation communications '
        'bulkCommunications discussionRoom meetingRoom reports',
      ),
      TgcgRole.lgaCoordinator: modules(
        'overview liveOperations agentTracking alertCenter situationRoom securityResponse '
        'accreditation unitMapping aiVerification fieldMonitoring evidenceCapture resultCapture '
        'collation communications discussionRoom meetingRoom',
      ),
      TgcgRole.wardCoordinator: modules(
        'overview liveOperations agentTracking situationRoom accreditation unitMapping '
        'fieldMonitoring evidenceCapture resultCapture collation communications discussionRoom '
        'meetingRoom',
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
        'overview liveOperations agentTracking aiAnalytics situationRoom mediaIntelligence '
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
