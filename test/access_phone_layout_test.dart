import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/access/access_page.dart';
import 'package:tgcg_emcop/tgcg/access/my_access_page.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/membership/member_review_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _kaduna = {'level': 'state', 'country': 'Nigeria', 'stateId': 'KD', 'stateName': 'Kaduna'};

final _appointment = {
  'id': 'a1',
  'member': 'TGCG-000200',
  'member_name': 'Adaeze Oluwaseun-Abubakar',
  'role': 'kaduna-media-officer',
  'role_name': 'Kaduna State Media and Publicity Officer',
  'supervising_role': 'state-media-director',
  'areas': [_kaduna, _kaduna],
  'restricted_permissions': ['sendBroadcast'],
  'permissions': ['sendBroadcast'],
  'starts_at': '2026-10-11T08:00:00Z',
  'ends_at': '2027-03-01T08:00:00Z',
  'state': 'active',
  'status': 'active',
  'status_reason': '',
  'status_changed_at': null,
  'accepted_at': null,
  'granted_by': 'NA-1',
  'authority': 'nationalAdministrator',
  'created_at': '2026-10-11T08:00:00Z',
};

final _role = {
  'code': 'kaduna-media-officer',
  'name': 'Kaduna State Media and Publicity Officer',
  'description': 'Announcements and publicity for Kaduna State.',
  'category': 'communications',
  'permitted_levels': ['state', 'lga', 'ward'],
  'permissions': ['sendBroadcast', 'viewCommunications'],
  'supervising_role': 'state-media-director',
  'is_system': false,
  'is_protected': false,
  'status': 'active',
  'archived_at': null,
  'archive_reason': '',
  'created_by': 'NA-1',
  'active_assignments': 12,
};

BackendServices _backend() => BackendServices.connect(
      'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1/', '');
        return switch (path) {
          'access/permissions/' => _json([
              {'code': 'sendBroadcast', 'module': 'communications', 'action': 'publish', 'label': 'Publish announcements and broadcasts'},
              {'code': 'viewCommunications', 'module': 'communications', 'action': 'view', 'label': 'View communications'},
              {'code': 'assignRoles', 'module': 'assignments', 'action': 'assign', 'label': 'Appoint members to roles'},
            ]),
          'access/roles/' => _json({'count': 1, 'next': null, 'results': [_role]}),
          'access/roles/kaduna-media-officer/' => _json(_role),
          'access/assignments/' => _json({'count': 1, 'next': null, 'results': [_appointment]}),
          'access/assignments/a1/history/' => _json(<Object>[]),
          'access/delegations/' => _json({'count': 0, 'next': null, 'results': <Object>[]}),
          'me/assignments/' => _json([_appointment]),
          'members/' => _json({
              'count': 1,
              'next': null,
              'results': [
                {
                  'membership_number': 'TGCG-000300',
                  'full_name': 'Oluwaseun Adebayo-Mohammed',
                  'verification_status': 'pendingReview',
                  'membership_state': 'suspended',
                  'scope': _kaduna,
                  'sensitive_visible': false,
                  'roles': [
                    {'role': 'x', 'role_name': 'Ward Mobilisation Lead', 'state': 'active'},
                  ],
                },
              ],
            }),
          'members/TGCG-000300/verification/' => _json({
              'membership_number': 'TGCG-000300',
              'verification_status': 'pendingReview',
              'verified_at': null,
              'reviewed_by': null,
              'checks': [
                {'kind': 'pvcValidated', 'result': 'unsupported', 'detail': 'No authoritative INEC source is connected; only the VIN format and the polling unit code were checked.'},
                {'kind': 'pvcCaptured', 'result': 'failed', 'detail': 'Registered without a PVC.'},
              ],
            }),
          _ => _json({'detail': 'Not found.'}, 404),
        };
      }),
    );

Future<void> _phone(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController()
    ..signInFromServer(
      fullName: 'Kaduna Lead',
      accessId: 'TGCG-000100',
      scope: GeographicScope.nigeria,
      capabilities: {
        'viewRoles',
        'manageRoles',
        'assignRoles',
        'manageAssignments',
        'delegateAuthority',
        'verifyMemberIdentity',
        'reviewPollingUnitChanges',
        'suspendMembers',
        'viewAudit',
      },
      membershipNumber: 'TGCG-000100',
    );
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: _backend(),
      child: TgcgSession(
        controller: session,
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('roles and appointments fit a phone', (tester) async {
    await _phone(tester, const AccessControlPage());
    expect(find.text('Kaduna State Media and Publicity Officer'), findsOneWidget);
    final card = find.ancestor(
      of: find.text('Kaduna State Media and Publicity Officer'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(card.first).height, lessThan(320)); // wrapped, not squeezed
    await tester.tap(find.text('Kaduna State Media and Publicity Officer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appointments'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Adaeze Oluwaseun-Abubakar'));
    await tester.pumpAndSettle();
    expect(find.text('Permissions (restricted)'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appoint a member'));
    await tester.pumpAndSettle();
    expect(find.text('Review and appoint'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Delegations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delegations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delegate authority'));
    await tester.pumpAndSettle();
    expect(find.text('Review and delegate'), findsOneWidget);
  });

  testWidgets('member review fits a phone', (tester) async {
    await _phone(tester, const MemberReviewPage());
    expect(find.text('Oluwaseun Adebayo-Mohammed'), findsOneWidget);
    final row = find.ancestor(
      of: find.text('Oluwaseun Adebayo-Mohammed'),
      matching: find.byType(ListTile),
    );
    // A row stays a row on a phone (the text is not squeezed letter by letter).
    expect(tester.getSize(row).height, lessThan(320));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('PVC confirmed with INEC'), findsOneWidget);
  });

  testWidgets('my access fits a phone', (tester) async {
    await _phone(tester, const MyAccessPage());
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });
}
