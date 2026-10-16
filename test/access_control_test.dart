import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/access/access_page.dart';
import 'package:tgcg_emcop/tgcg/access/my_access_page.dart';
import 'package:tgcg_emcop/tgcg/api/access_repository.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/auth_repository.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/domain/permissions.dart';
import 'package:tgcg_emcop/tgcg/membership/member_review_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

String _path(http.Request request) => request.url.path.replaceFirst('/api/v1/', '');

/// A fake TGCG server that records the body of every request by method and path.
class _Server {
  _Server(this.respond);
  final http.Response? Function(http.Request request) respond;
  final bodies = <String, String>{};

  BackendServices connect() => BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          bodies['${request.method} ${_path(request)}'] = request.body;
          return respond(request) ?? _json({'detail': 'Not found.'}, 404);
        }),
      );
}

const _kaduna = {'level': 'state', 'country': 'Nigeria', 'stateId': 'KD', 'stateName': 'Kaduna'};

// A valid 1x1 PNG, so a card photo decodes.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

final _permissions = [
  {'code': 'sendBroadcast', 'module': 'communications', 'action': 'publish', 'label': 'Publish announcements and broadcasts', 'protected': false, 'sensitive': false},
  {'code': 'viewRoles', 'module': 'roleManagement', 'action': 'view', 'label': 'View roles and appointments', 'protected': false, 'sensitive': false},
];

Map<String, dynamic> _appointment({String state = 'active', String? acceptedAt}) => {
      'id': 'a1',
      'member': 'TGCG-000200',
      'member_name': 'Ada Obi',
      'role': 'kaduna-media-officer',
      'role_name': 'Kaduna Media Officer',
      'supervising_role': null,
      'areas': [_kaduna],
      'restricted_permissions': null,
      'permissions': ['sendBroadcast'],
      'starts_at': '2026-10-11T08:00:00Z',
      'ends_at': null,
      'state': state,
      'status': state == 'scheduled' ? 'active' : state,
      'status_reason': '',
      'status_changed_at': null,
      'accepted_at': acceptedAt,
      'granted_by': 'NA-1',
      'authority': 'nationalAdministrator',
      'created_at': '2026-10-11T08:00:00Z',
    };

Future<TgcgSessionController> _pump(
  WidgetTester tester,
  BackendServices backend,
  Widget page,
  void Function(TgcgSessionController session) signIn,
) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController();
  signIn(session);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: backend,
      child: TgcgSession(
        controller: session,
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

void main() {
  group('server-driven access', () {
    test('a server session can do exactly what the server granted', () {
      final session = TgcgSessionController()
        ..signInFromServer(
          role: TgcgRole.stateCoordinator,
          fullName: 'Kaduna Coordinator',
          accessId: 'SC-KD',
          scope: GeographicScope.nigeria,
          capabilities: {'viewSituationRoom'},
        );
      // The built-in matrix would allow accreditation; the server did not.
      expect(TgcgPermissionPolicy.allows(TgcgRole.stateCoordinator, TgcgCapability.accreditAgents),
          isTrue);
      expect(session.can(TgcgCapability.accreditAgents), isFalse);
      expect(session.can(TgcgCapability.viewSituationRoom), isTrue);
      expect(session.modules, contains(TgcgModule.situationRoom));
      expect(session.modules, isNot(contains(TgcgModule.accreditation)));
    });

    test('a member with appointments gets the modules their appointments allow', () {
      final session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Ada Obi',
          accessId: 'TGCG-000200',
          scope: GeographicScope.nigeria,
          capabilities: {'sendBroadcast', 'viewRoles', 'verifyMemberIdentity'},
          grants: [
            AccessGrant.fromJson({
              'source': 'assignment',
              'assignment': 'a1',
              'role': 'kaduna-media-director',
              'role_name': 'Kaduna Media Director',
              'areas': [_kaduna],
              'permissions': ['sendBroadcast', 'viewRoles', 'verifyMemberIdentity'],
            }),
          ],
          membershipNumber: 'TGCG-000200',
        );
      expect(session.role, isNull);
      expect(session.isOperator, isTrue);
      expect(session.roleTitle, 'Kaduna Media Director');
      expect(
        session.modules,
        containsAll([
          TgcgModule.overview,
          TgcgModule.roleAssignment,
          TgcgModule.memberReview,
        ]),
      );
      expect(session.modules, isNot(contains(TgcgModule.governance)));
      expect(session.modules, isNot(contains(TgcgModule.collation)));
      // The role grid gives broadcasting its page, but it is not built on the
      // server yet, so it stays out of the menu.
      expect(
        allowedModulesFor(session.can, supervises: session.supervises),
        contains(TgcgModule.bulkCommunications),
      );
      expect(session.modules, isNot(contains(TgcgModule.bulkCommunications)));
    });

    test('signing out forgets the grants', () {
      final session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Ada Obi',
          accessId: 'TGCG-000200',
          scope: GeographicScope.nigeria,
          capabilities: {'sendBroadcast'},
          membershipNumber: 'TGCG-000200',
        )
        ..signOut();
      expect(session.can(TgcgCapability.sendBroadcast), isFalse);
      expect(session.grants, isEmpty);
      expect(session.membershipNumber, isNull);
    });
  });

  testWidgets('a manager suspends an appointment with a reason', (tester) async {
    var appointment = _appointment();
    final server = _Server((request) => switch (_path(request)) {
          'access/permissions/' => _json(_permissions),
          'access/roles/' => _json({'count': 0, 'next': null, 'results': <Object>[]}),
          'access/assignments/' => _json({'count': 1, 'next': null, 'results': [appointment]}),
          'access/assignments/a1/history/' => _json(<Object>[]),
          'access/assignments/a1/suspend/' => () {
              appointment = {...appointment, 'state': 'suspended', 'status': 'suspended'};
              return _json(appointment);
            }(),
          _ => null,
        });
    await _pump(
      tester,
      server.connect(),
      const AccessControlPage(),
      (session) => session.signInFromServer(
        fullName: 'State Lead',
        accessId: 'TGCG-000100',
        scope: GeographicScope.nigeria,
        capabilities: {'viewRoles', 'manageAssignments'},
        membershipNumber: 'TGCG-000100',
      ),
    );

    expect(find.text('Roles & Access'), findsOneWidget);
    expect(find.text('New role'), findsNothing); // no manageRoles
    await tester.tap(find.text('Appointments'));
    await tester.pumpAndSettle();
    expect(find.text('Appoint a member'), findsNothing); // no assignRoles
    await tester.tap(find.text('Ada Obi · Kaduna Media Officer'));
    await tester.pumpAndSettle();
    expect(find.text('Publish announcements and broadcasts'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Suspend'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Suspend');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull); // a reason is required
    await tester.enterText(find.byType(TextField).last, 'Absent on election day');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(jsonDecode(server.bodies['POST access/assignments/a1/suspend/']!), {
      'reason': 'Absent on election day',
    });
    expect(find.text('Suspended'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'Reactivate'), findsOneWidget);
  });

  testWidgets('a member accepts an appointment of their own', (tester) async {
    var mine = _appointment(state: 'scheduled');
    final server = _Server((request) => switch (_path(request)) {
          'me/assignments/' => _json([mine]),
          'me/assignments/a1/accept/' => () {
              mine = {...mine, 'accepted_at': '2026-10-11T09:00:00Z'};
              return _json(mine);
            }(),
          'auth/me/' => _json({
              'access_id': 'TGCG-000200',
              'full_name': 'Ada Obi',
              'role': 'member',
              'scope': {'level': 'country', 'country': 'Nigeria'},
              'capabilities': <String>[],
              'access': <Object>[],
              'membership_number': 'TGCG-000200',
            }),
          _ => null,
        });
    final session = await _pump(
      tester,
      server.connect(),
      const MyAccessPage(),
      (session) => session.signInMember(fullName: 'Ada Obi', membershipNumber: 'TGCG-000200'),
    );

    expect(find.text('Kaduna Media Officer'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(server.bodies.containsKey('POST me/assignments/a1/accept/'), isTrue);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Resign'), findsOneWidget);
    // Not active yet, so the member stays in the member app.
    expect(session.isMember, isTrue);
  });

  testWidgets('a reviewer confirms an identity after seeing what was not checked', (tester) async {
    var status = 'pendingReview';
    Map<String, dynamic> verification() => {
          'membership_number': 'TGCG-000300',
          'verification_status': status,
          'verified_at': null,
          'reviewed_by': status == 'verified' ? 'TGCG-000100' : null,
          'checks': [
            {'kind': 'pvcCaptured', 'result': 'passed', 'detail': 'VIN and polling unit code read from the card.', 'checked_at': null, 'checked_by': null},
            {'kind': 'pvcValidated', 'result': 'unsupported', 'detail': 'No authoritative INEC source is connected.', 'checked_at': null, 'checked_by': null},
            {'kind': 'liveness', 'result': 'unsupported', 'detail': 'Liveness detection is not available.', 'checked_at': null, 'checked_by': null},
          ],
        };
    final server = _Server((request) => switch (_path(request)) {
          'members/' => _json({
              'count': 1,
              'next': null,
              'results': [
                {
                  'membership_number': 'TGCG-000300',
                  'full_name': 'Bala Musa',
                  'verification_status': status,
                  'membership_state': 'active',
                  'scope': _kaduna,
                  'phone_number': null,
                  'sensitive_visible': false,
                  'roles': <Object>[],
                },
              ],
            }),
          'members/TGCG-000300/verification/' => _json(verification()),
          'members/TGCG-000300/verification/approve/' => () {
              status = 'verified';
              return _json(verification());
            }(),
          _ => null,
        });
    await _pump(
      tester,
      server.connect(),
      const MemberReviewPage(),
      (session) => session.signInFromServer(
        fullName: 'Kaduna Reviewer',
        accessId: 'TGCG-000100',
        scope: GeographicScope.nigeria,
        capabilities: {'verifyMemberIdentity'},
        membershipNumber: 'TGCG-000100',
      ),
    );

    expect(find.text('Identity review'), findsOneWidget);
    expect(find.text('Polling unit changes'), findsNothing);
    await tester.tap(find.text('Bala Musa'));
    await tester.pumpAndSettle();
    expect(find.text('PVC confirmed with INEC'), findsOneWidget);
    expect(find.text('No authoritative INEC source is connected.'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsNWidgets(2)); // not available

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm identity'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Compared the PVC with Bala in person.');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm identity').last);
    await tester.pumpAndSettle();

    expect(jsonDecode(server.bodies['POST members/TGCG-000300/verification/approve/']!), {
      'notes': 'Compared the PVC with Bala in person.',
    });
    expect(find.text('Verified'), findsWidgets);
  });

  testWidgets('an identity verified under the policy shows that no person decided', (tester) async {
    final server = _Server((request) => switch (_path(request)) {
          'members/' => _json({
              'count': 1,
              'next': null,
              'results': [
                {
                  'membership_number': 'TGCG-000301',
                  'full_name': 'Hauwa Sani',
                  'verification_status': 'verified',
                  'membership_state': 'active',
                  'scope': _kaduna,
                  'phone_number': null,
                  'sensitive_visible': false,
                  'roles': <Object>[],
                },
              ],
            }),
          'members/TGCG-000301/verification/' => _json({
              'membership_number': 'TGCG-000301',
              'verification_status': 'verified',
              'verified_at': '2026-10-16T15:00:00Z',
              'reviewed_by': null,
              'verified_automatically': true,
              'checks': [
                {'kind': 'cardMatch', 'result': 'passed', 'detail': 'The name and VIN given match the text read from the card photo.', 'checked_at': null, 'checked_by': null},
                {'kind': 'faceMatch', 'result': 'unsupported', 'detail': 'No trusted reference photo is available to compare the selfie with.', 'checked_at': null, 'checked_by': null},
              ],
            }),
          _ => null,
        });
    await _pump(
      tester,
      server.connect(),
      const MemberReviewPage(),
      (session) => session.signInFromServer(
        fullName: 'Kaduna Reviewer',
        accessId: 'TGCG-000100',
        scope: GeographicScope.nigeria,
        capabilities: {'verifyMemberIdentity'},
        membershipNumber: 'TGCG-000100',
      ),
    );

    await tester.tap(find.text('Hauwa Sani'));
    await tester.pumpAndSettle();
    expect(find.text('Verified automatically'), findsOneWidget);
    expect(find.textContaining('Last decision by'), findsNothing);
    expect(find.text('Name and VIN match the card photo'), findsOneWidget);
  });

  testWidgets("a reviewer gives a checked member's PVC scan its second check", (tester) async {
    var status = 'pending';
    Map<String, dynamic> update() => {
          'id': 'p1',
          'member': 'TGCG-000300',
          'member_name': 'Bala Musa',
          'status': status,
          'changes': [
            {
              'field': 'full_name',
              'label': 'Name',
              'from': status == 'pending' ? 'Bala Musa' : null,
              'to': 'Bala Musa Ibrahim',
            },
            {
              'field': 'vin',
              'label': 'VIN',
              'from': status == 'pending' ? '***************7263' : null,
              'to': '***************7264',
            },
          ],
          'decided_by': null,
          'decided_at': null,
          'decision_reason': '',
          'created_at': '2026-10-14T09:00:00Z',
        };
    final server = _Server((request) => switch (_path(request)) {
          'members/' => _json({'count': 0, 'next': null, 'results': <Object>[]}),
          'pvc-updates/' => _json({'count': 1, 'next': null, 'results': [update()]}),
          'pvc-updates/p1/card/' =>
            http.Response.bytes(_pixel, 200, headers: {'content-type': 'image/png'}),
          'pvc-updates/p1/approve/' => () {
              status = 'approved';
              return _json(update());
            }(),
          _ => null,
        });
    await _pump(
      tester,
      server.connect(),
      const MemberReviewPage(),
      (session) => session.signInFromServer(
        fullName: 'Kaduna Reviewer',
        accessId: 'TGCG-000100',
        scope: GeographicScope.nigeria,
        capabilities: {'verifyMemberIdentity'},
        membershipNumber: 'TGCG-000100',
      ),
    );

    await tester.tap(find.text('PVC updates'));
    await tester.pumpAndSettle();
    expect(find.text('Name, VIN · 14 Oct 2026'), findsOneWidget);
    await tester.tap(find.text('Bala Musa (TGCG-000300)'));
    await tester.pumpAndSettle();
    // What changes, set against the card photo; the VIN stays masked.
    expect(find.text('Name: Bala Musa → Bala Musa Ibrahim'), findsOneWidget);
    expect(find.text('VIN: ***************7263 → ***************7264'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST pvc-updates/p1/approve/']!), {'reason': ''});
  });

  group('the working area', () {
    const kadunaNorth = GeographicScope(
      level: GeographyLevel.lga,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/033/KD',
      senatorialDistrictName: 'Kaduna Central',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
    );
    const zaria = GeographicScope(
      level: GeographyLevel.lga,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/032/KD',
      senatorialDistrictName: 'Kaduna North',
      lgaId: 'KD-ZARIA',
      lgaName: 'Zaria',
    );
    const kano = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KN',
      stateName: 'Kano',
    );
    const lagos = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'SW',
      zoneName: 'South West',
      stateId: 'LA',
      stateName: 'Lagos',
    );

    test('is the smallest area holding every appointment', () {
      expect(commonScope([kadunaNorth]).lgaId, 'KD-KADUNA-NORTH');
      final kaduna = commonScope([kadunaNorth, zaria]);
      expect(kaduna.level, GeographyLevel.state);
      expect(kaduna.stateId, 'KD');
      expect(kaduna.lgaId, isNull);
      expect(commonScope([kadunaNorth, kano]).level, GeographyLevel.geopoliticalZone);
      expect(commonScope([kano, lagos]).level, GeographyLevel.country);
      expect(commonScope([kano, GeographicScope.nigeria]).level, GeographyLevel.country);
    });

    test('comes from appointments, not where a member registered', () {
      final appointed = ServerUser.fromJson({
        'access_id': 'TGCG-000200',
        'full_name': 'Ada Obi',
        'role': 'member',
        'scope': {'level': 'pollingUnit', 'country': 'Nigeria', 'pollingUnitId': 'KN-001'},
        'capabilities': ['sendBroadcast'],
        'access': [
          {
            'source': 'assignment',
            'assignment': 'a1',
            'role': 'lga-coordinator',
            'role_name': 'LGA Coordinator',
            'areas': [
              {'level': 'lga', 'country': 'Nigeria', 'zoneId': 'NW', 'stateId': 'KD', 'lgaId': 'KD-KADUNA-NORTH', 'lgaName': 'Kaduna North'},
            ],
            'permissions': ['sendBroadcast'],
          },
        ],
      });
      expect(appointed.workingScope.lgaId, 'KD-KADUNA-NORTH');
      expect(appointed.usesMemberApp, isFalse);
    });
  });

  test('supervisors get the appointments they supervise, and nothing else', () {
    final session = TgcgSessionController()
      ..signInFromServer(
        role: TgcgRole.lgaCoordinator,
        fullName: 'LGA Coordinator',
        accessId: 'LC-KD',
        scope: GeographicScope.nigeria,
        capabilities: {'viewSituationRoom'},
        supervises: true,
      );
    expect(session.modules, contains(TgcgModule.roleAssignment));
    expect(session.can(TgcgCapability.manageAssignments), isFalse);
  });

  testWidgets('supervisors see only the appointments tab', (tester) async {
    final server = _Server((request) => switch (_path(request)) {
          'access/permissions/' => _json(_permissions),
          'access/assignments/' => _json({'count': 0, 'next': null, 'results': <Object>[]}),
          _ => null,
        });
    await _pump(
      tester,
      server.connect(),
      const AccessControlPage(),
      (session) => session.signInFromServer(
        role: TgcgRole.lgaCoordinator,
        fullName: 'LGA Coordinator',
        accessId: 'LC-KD',
        scope: GeographicScope.nigeria,
        capabilities: {'viewSituationRoom'},
        supervises: true,
      ),
    );
    expect(find.text('Appointments'), findsOneWidget);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Delegations'), findsNothing);
    expect(find.text('Appoint a member'), findsNothing);
  });

  testWidgets('the audit log asks for the next events by offset', (tester) async {
    final offsets = <String?>[];
    final server = _Server((request) {
      if (_path(request) != 'access/audit/') return null;
      final offset = request.url.queryParameters['offset'];
      offsets.add(offset);
      final start = int.parse(offset ?? '0');
      return _json({
        'count': 150,
        'next': start == 0 ? 'https://api.tgcg.test/api/v1/access/audit/?limit=100&offset=100' : null,
        'results': [
          for (var i = start; i < (start == 0 ? 100 : 150); i++)
            {
              'id': 150 - i,
              'created_at': '2026-10-11T08:00:00Z',
              'actor': 'NA-1',
              'action': 'role.created',
              'target_type': 'role',
              'target_id': 'r$i',
              'target_label': 'Role $i',
              'reason': '',
            },
        ],
      });
    });
    await _pump(
      tester,
      server.connect(),
      const AccessControlPage(),
      (session) => session.signInFromServer(
        fullName: 'Auditor',
        accessId: 'TGCG-000100',
        scope: GeographicScope.nigeria,
        capabilities: {'viewAudit'},
      ),
    );
    await tester.scrollUntilVisible(find.text('Load more'), 600, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(offsets, [null, '100']);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('a list reloads when its dialog is dismissed by tapping outside', (tester) async {
    var loads = 0;
    final server = _Server((request) => switch (_path(request)) {
          'access/permissions/' => _json(_permissions),
          'access/roles/' => _json({'count': 0, 'next': null, 'results': <Object>[]}),
          'access/assignments/' => () {
              loads++;
              return _json({'count': 1, 'next': null, 'results': [_appointment()]});
            }(),
          'access/assignments/a1/history/' => _json(<Object>[]),
          _ => null,
        });
    await _pump(
      tester,
      server.connect(),
      const AccessControlPage(),
      (session) => session.signInFromServer(
        fullName: 'State Lead',
        accessId: 'TGCG-000100',
        scope: GeographicScope.nigeria,
        capabilities: {'viewRoles', 'manageAssignments'},
      ),
    );
    await tester.tap(find.text('Appointments'));
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.tap(find.text('Ada Obi · Kaduna Media Officer'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); // outside the dialog
    await tester.pumpAndSettle();
    expect(loads, 2);
  });
}
