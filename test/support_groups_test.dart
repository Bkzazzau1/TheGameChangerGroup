import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/support_groups_repository.dart';
import 'package:tgcg_emcop/tgcg/domain/permissions.dart';
import 'package:tgcg_emcop/tgcg/election/follow_ups.dart';
import 'package:tgcg_emcop/tgcg/groups/led_group_page.dart';
import 'package:tgcg_emcop/tgcg/groups/my_support_groups_page.dart';
import 'package:tgcg_emcop/tgcg/groups/support_groups_page.dart';
import 'package:tgcg_emcop/tgcg/member/referral.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

import 'support/redesign_fixtures.dart';

// Names here are made up.

const _name = 'Arewa Youth for Progress';

Map<String, dynamic> _group({
  String status = 'approved',
  String label = 'Approved',
  bool confirmed = true,
}) => {
  'id': 'g1',
  'serial_number': 'TGCG/0001/BAT/27',
  'name': _name,
  'coverage': 'state',
  'coverage_label': 'State',
  'zone': null,
  'state': 'Kaduna',
  'email': 'info@ayp.ng',
  'officials': [
    {'name': 'Bala Musa', 'position': 'Secretary', 'phone': '08035550009'},
  ],
  'leader': {
    'membership_number': 'TGCG-000123',
    'full_name': 'Halima Sani',
    'phone_number': '08035550001',
    'place': 'Zaria, Kaduna',
  },
  'leader_confirmed': confirmed,
  'status': status,
  'status_label': label,
  'decision_reason': status == 'rejected' ? 'Duplicate' : '',
  'decided_at': null,
  'created_at': '2026-11-03T09:00:00Z',
  'members': 3,
  'approved_members': 1,
  'waiting': 1,
  'registered_by': 'Halima Sani',
  'decided_by': '',
  'join_code': status == 'approved' ? '4827155' : null,
  'link': status == 'approved' ? 'https://app.tgcg.online/?ref=1234567&group=4827155' : null,
};

Map<String, dynamic> _person(String id, String name, {String status = 'active'}) => {
  'id': id,
  'full_name': name,
  'phone_number': '08035550001',
  'place': 'Zaria, Kaduna',
  'approved': status == 'active' ? true : null,
  'status': status,
  'status_label': status == 'active' ? 'Member' : 'Asked to confirm',
  'via': id == 'leader' ? 'leader' : 'registered',
  'via_label': 'Registered by the group',
  'membership_number': 'TGCG-000123',
  'created_at': '2026-11-03T09:00:00Z',
  'answered_at': null,
};

Map<String, dynamic> _page(List<Object> items) => {
  'count': items.length,
  'next': null,
  'previous': null,
  'results': items,
};

Map<String, dynamic> _invitation({bool leads = false}) => {
  'id': 'p1',
  'group': {
    'id': 'g1',
    'serial_number': 'TGCG/0001/BAT/27',
    'name': _name,
    'coverage_label': 'State',
    'leader': 'Halima Sani',
    'status': 'approved',
  },
  'status': 'invited',
  'status_label': 'Asked to confirm',
  'via': leads ? 'leader' : 'confirmed',
  'leads': leads,
  'created_at': '2026-11-03T09:00:00Z',
};

/// A server that keeps what it was sent: method, path and JSON body.
class _Api {
  _Api(this.answer);

  final http.Response? Function(String method, String path, Object? body) answer;
  final calls = <(String, String, Object?)>[];
  final urls = <Uri>[];

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1/', '');
      final json = (request.headers['content-type'] ?? '').contains('application/json');
      final body = json && request.body.isNotEmpty ? jsonDecode(request.body) : null;
      calls.add((request.method, path, body));
      urls.add(request.url);
      return answer(request.method, path, body) ?? jsonResponse({'detail': 'Not found.'}, 404);
    }),
  );

  List<Object?> sent(String method, String path) => [
    for (final call in calls)
      if (call.$1 == method && call.$2 == path) call.$3,
  ];
}

Future<void> _show(WidgetTester tester, _Api api, Widget home) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(memberApp(api.connect(), memberSession(), home));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test("a support group's link carries its code", () {
    final link = Uri.parse('https://app.tgcg.online/?ref=1234567&group=4827155');
    expect(groupFromLink(link), '4827155');
    expect(referralFromLink(link), '1234567');
    expect(groupFromLink(Uri.parse('https://app.tgcg.online/?group=12')), isNull);
  });

  test('only those who vet support groups get the page', () {
    expect(
      allowedModulesFor((c) => c == TgcgCapability.manageSupportGroups),
      contains(TgcgModule.supportGroups),
    );
    expect(allowedModulesFor((c) => false), isNot(contains(TgcgModule.supportGroups)));
    expect(liveModules, contains(TgcgModule.supportGroups));
  });

  testWidgets('a member says yes to a group that lists them, and joins one with its code', (
    tester,
  ) async {
    var answered = false;
    final api = _Api(
      (method, path, body) => switch ((method, path)) {
        ('GET', 'me/support-groups/') => jsonResponse({
          'invitations': answered ? <Object>[] : [_invitation()],
          'groups': <Object>[],
          'leading': <Object>[],
          'vets': false,
        }),
        ('POST', 'me/support-groups/p1/answer/') => () {
          answered = true;
          return jsonResponse({..._invitation(), 'status': 'active'});
        }(),
        ('POST', 'me/support-groups/join/') => jsonResponse({
          'group_code': ["That group code was not found. Check it with the group's leader."],
        }, 400),
        _ => null,
      },
    );
    await _show(tester, api, const MySupportGroupsPage());

    expect(find.text('$_name lists you as a member'), findsOneWidget);
    expect(
      find.textContaining('The group sees your name and place only after you say yes'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Yes, I am a member'));
    expect(api.sent('POST', 'me/support-groups/p1/answer/'), [
      {'yes': true},
    ]);
    expect(find.text('$_name lists you as a member'), findsNothing);
    expect(find.text('You are not in a support group'), findsOneWidget);

    await _tap(tester, find.text("Join with a group's code"));
    await tester.enterText(find.byType(TextField), '48');
    await _tap(tester, find.text('Join'));
    expect(find.text('The code has 7 digits.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '7654321');
    await _tap(tester, find.text('Join'));
    expect(api.sent('POST', 'me/support-groups/join/'), [
      {'code': '7654321'},
    ]);
    expect(find.textContaining('That group code was not found'), findsOneWidget);
  });

  testWidgets('a member named as leader is asked whether they lead it', (tester) async {
    final api = _Api(
      (method, path, body) => path == 'me/support-groups/'
          ? jsonResponse({
              'invitations': [_invitation(leads: true)],
              'groups': <Object>[],
              'leading': <Object>[],
              'vets': false,
            })
          : null,
    );
    await _show(tester, api, const MySupportGroupsPage());
    expect(find.text('$_name names you as its leader'), findsOneWidget);
    expect(find.text('Yes, I lead it'), findsOneWidget);
  });

  testWidgets('the leader shares the code, and adds a checked list in batches', (tester) async {
    String? shared;
    final listed = [
      for (var line = 1; line <= 30; line++)
        {
          'line': line,
          'full_name': 'Person Number $line',
          'phone_number': '0803556${line.toString().padLeft(4, '0')}',
          'gender': '',
          'place': line == 1 ? 'Zaria, Kaduna' : '',
          'scope': line == 1 ? {'level': 'lga', 'lgaId': 'KD-ZARIA'} : null,
          'problem': '',
        },
      {
        'line': 31,
        'full_name': '',
        'phone_number': '08035560031',
        'gender': '',
        'place': '',
        'scope': null,
        'problem': 'No name was found next to this number.',
      },
    ];
    final api = _Api((method, path, body) {
      switch ((method, path)) {
        case ('GET', 'my-groups/g1/'):
          return jsonResponse(_group());
        case ('GET', 'my-groups/g1/members/'):
          return jsonResponse(_page([_person('leader', 'Halima Sani')]));
        case ('POST', 'my-groups/g1/read-list/'):
          return jsonResponse({'kind': 'excel', 'people': listed, 'notes': <Object>[]});
        case ('POST', 'my-groups/g1/add/'):
          final people = (body! as Map)['people'] as List;
          return jsonResponse({
            'results': [
              for (final person in people)
                {
                  'line': (person as Map)['line'],
                  'outcome': person['line'] == 2 ? 'asked' : 'registered',
                  'detail': '',
                },
            ],
          });
      }
      return null;
    });
    await _show(
      tester,
      api,
      LedGroupPage(
        groupId: 'g1',
        pickFile: () async => (bytes: Uint8List.fromList([1, 2, 3]), name: 'members.xlsx'),
        share: (text) async => shared = text,
      ),
    );

    expect(find.text('4827155'), findsOneWidget);
    await _tap(tester, find.text('Share'));
    expect(shared, contains('https://app.tgcg.online/?ref=1234567&group=4827155'));

    await _tap(tester, find.text('Upload a list'));
    expect(find.text('members.xlsx'), findsOneWidget);
    expect(find.textContaining('31 people found, 1 with a problem'), findsOneWidget);
    expect(find.text('No name was found next to this number.'), findsOneWidget);
    await _tap(tester, find.text('Add 30 people'));
    expect(find.text('Tick the box to confirm.'), findsOneWidget);
    expect(api.sent('POST', 'my-groups/g1/add/'), isEmpty);

    await _tap(tester, find.byType(CheckboxListTile));
    await _tap(tester, find.text('Add 30 people'));
    final batches = api.sent('POST', 'my-groups/g1/add/');
    expect([for (final batch in batches) ((batch! as Map)['people'] as List).length], [10, 10, 10]);
    final first = ((batches.first! as Map)['people'] as List).first as Map;
    expect(first['scope'], {'level': 'lga', 'lgaId': 'KD-ZARIA'});
    expect((batches.first! as Map)['consent'], isTrue);
    expect(find.text('29 registered with TGCG and added'), findsOneWidget);
    expect(find.text('1 already members, asked in the app to say yes'), findsOneWidget);
  });

  testWidgets('a group waiting for vetting cannot add anyone yet', (tester) async {
    final api = _Api(
      (method, path, body) => switch (path) {
        'my-groups/g1/' => jsonResponse(_group(status: 'pending', label: 'Waiting for vetting')),
        'my-groups/g1/members/' => jsonResponse(_page([_person('leader', 'Halima Sani')])),
        _ => null,
      },
    );
    await _show(tester, api, const LedGroupPage(groupId: 'g1'));
    expect(find.text('Waiting for vetting'), findsOneWidget);
    expect(find.textContaining('TGCG is vetting the organization'), findsOneWidget);
    expect(find.text('Upload a list'), findsNothing);
    expect(find.text('Add a person'), findsNothing);
  });

  testWidgets('those who vet groups approve one, and give a reason to turn one down', (
    tester,
  ) async {
    final api = _Api((method, path, body) {
      switch ((method, path)) {
        case ('GET', 'support-groups/totals/'):
          return jsonResponse({
            'groups': {'pending': 1, 'approved': 4, 'rejected': 0, 'suspended': 0},
            'people': 1250,
            'approved_people': 310,
          });
        case ('GET', 'support-groups/'):
          return jsonResponse(_page([_group(status: 'pending', label: 'Waiting for vetting')]));
        case ('GET', 'support-groups/g1/members/'):
          return jsonResponse(_page([_person('leader', 'Halima Sani')]));
        case ('POST', 'support-groups/g1/reject/'):
          return jsonResponse(_group(status: 'rejected', label: 'Not approved'));
      }
      return null;
    });
    await _show(tester, api, const Scaffold(body: SupportGroupsPage()));

    // Every group at first, whatever its state.
    final listed = api.urls.firstWhere((url) => url.path.endsWith('/support-groups/'));
    expect(listed.queryParameters, isEmpty);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All groups')).selected,
      isTrue,
    );
    expect(find.text('1250'), findsOneWidget);
    expect(find.text('Each person counted once'), findsOneWidget);
    await _tap(tester, find.text(_name));
    expect(find.text('TGCG/0001/BAT/27'), findsWidgets);
    expect(find.text('Bala Musa · 08035550009'), findsOneWidget);
    expect(
      find.text('TGCG-000123 · 08035550001 · Zaria, Kaduna · Registered by the group'),
      findsOneWidget,
    );

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Turn down'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Turn down'));
    expect(find.text('Say why.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Duplicate');
    await _tap(tester, find.widgetWithText(FilledButton, 'Turn down'));
    expect(api.sent('POST', 'support-groups/g1/reject/'), [
      {'reason': 'Duplicate'},
    ]);
    expect(find.text('Not approved'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('types of group open their groups; a type is added and a group moved', (
    tester,
  ) async {
    Map<String, dynamic> kind(String code, String name, {int approved = 0, bool offered = true}) =>
        {
          'code': code,
          'name': name,
          'offered': offered,
          'groups': {'pending': 0, 'approved': approved, 'rejected': 0, 'suspended': 0},
          'people': approved * 40,
        };
    var kinds = [
      {'code': 'support', 'name': 'Support Groups', 'position': 1, 'offered': true},
      {'code': 'women', 'name': 'Women Groups', 'position': 2, 'offered': true},
      {'code': 'youth', 'name': 'Youth Groups', 'position': 3, 'offered': true},
    ];
    final api = _Api((method, path, body) {
      switch ((method, path)) {
        case ('GET', 'support-groups/totals/'):
          return jsonResponse({
            'groups': {'pending': 0, 'approved': 3, 'rejected': 0, 'suspended': 0},
            'people': 120,
            'approved_people': 30,
            'kinds': [
              kind('support', 'Support Groups', approved: 1),
              kind('women', 'Women Groups', approved: 2),
              kind('pwd', 'People With Disability (PWD) Groups'),
            ],
          });
        case ('GET', 'support-groups/'):
          return jsonResponse(_page([_group()..['kind_name'] = 'Youth Groups']));
        case ('GET', 'support-groups/kinds/'):
          return jsonResponse(kinds);
        case ('POST', 'support-groups/kinds/'):
          kinds = [
            ...kinds,
            {'code': 'traders-groups', 'name': 'Traders Groups', 'position': 4, 'offered': true},
          ];
          return jsonResponse(kinds.last, 201);
        case ('PATCH', 'support-groups/kinds/women/'):
          kinds = [
            for (final row in kinds) row['code'] == 'women' ? {...row, 'offered': false} : row,
          ];
          return jsonResponse(kinds[1]);
        case ('GET', 'support-groups/g1/members/'):
          return jsonResponse(_page(<Object>[]));
        case ('POST', 'support-groups/g1/kind/'):
          return jsonResponse({..._group(), 'kind': 'women', 'kind_name': 'Women Groups'});
      }
      return null;
    });
    await _show(tester, api, const Scaffold(body: SupportGroupsPage()));

    expect(find.text('Types of group'), findsOneWidget);
    expect(find.text('2 approved · 80 people'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('kind-women')));
    expect(api.urls.last.queryParameters, {'kind': 'women'});
    await _tap(tester, find.byKey(const ValueKey('kind-women')));
    expect(api.urls.last.queryParameters, isEmpty);

    await _tap(tester, find.text('Manage types'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Name, e.g. Traders Groups'),
      'Traders Groups',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(api.sent('POST', 'support-groups/kinds/'), [
      {'name': 'Traders Groups'},
    ]);
    expect(find.text('Traders Groups'), findsOneWidget);
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('manage-kind-women')),
        matching: find.byType(Switch),
      ),
    );
    expect(api.sent('PATCH', 'support-groups/kinds/women/'), [
      {'offered': false},
    ]);
    expect(find.text('Not offered to new groups'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _tap(tester, find.text(_name));
    expect(find.text('Youth Groups'), findsOneWidget);
    await _tap(tester, find.text('Change type'));
    // Only types offered to groups, and its own.
    expect(find.text('Women Groups'), findsNothing);
    await _tap(tester, find.text('Traders Groups'));
    expect(api.sent('POST', 'support-groups/g1/kind/'), [
      {'kind': 'traders-groups'},
    ]);
    expect(find.text('Women Groups'), findsOneWidget);
  });

  testWidgets("a group's analytics show, its people are found, and one opens their profile", (
    tester,
  ) async {
    final api = _Api((method, path, body) {
      switch ((method, path)) {
        case ('GET', 'support-groups/g1/analysis/'):
          return jsonResponse({
            'members': {
              'total': 120,
              'new_7_days': 30,
              'new_30_days': 120,
              'verification': {'unverified': 118, 'verified': 2},
              'gender': {'male': 70, 'female': 20, '': 30},
              'age': {'18-24': 40, 'unknown': 80},
              'channel': {'import': 117, 'self': 3},
              'profile': {'signedIn': 25},
            },
            'via': {'leader': 1, 'list': 119},
            'waiting': 2,
            'states': [
              {'code': 'BO', 'name': 'Borno', 'count': 80},
              {'code': '', 'name': '', 'count': 40},
            ],
            'sign_in': {'phone': 80, 'vin_only': 30, 'nin_only': 10, 'pin_to_choose': 28},
          });
        case ('GET', 'support-groups/g1/members/'):
          return jsonResponse(_page([_person('p1', 'Musa Bello')]));
        case ('GET', 'members/TGCG-000123/'):
          return jsonResponse({
            'membership_number': 'TGCG-000123',
            'full_name': 'Musa Bello',
            'verification_status': 'unverified',
            'membership_state': 'active',
            'scope': {'level': 'state', 'country': 'Nigeria', 'stateId': 'BO', 'stateName': 'Borno'},
            'roles': <Object>[],
            'gaps': ['vin'],
          });
      }
      return null;
    });
    await _show(tester, api, VettedGroupPage(group: SupportGroup.fromJson(_group())));

    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('120'), findsWidgets);
    expect(find.text('Where they are'), findsOneWidget);
    expect(find.text('Borno'), findsOneWidget);
    expect(find.text('No place given'), findsOneWidget);
    expect(find.text("From the group's list, placed by TGCG"), findsOneWidget);
    expect(find.text('With their VIN'), findsOneWidget);
    expect(find.text('With their NIN'), findsOneWidget);
    expect(find.text('28 with a VIN or NIN have not chosen their own PIN yet.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Find by name, membership number, phone or VIN'),
      'musa',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final searched = api.urls.lastWhere((url) => url.path.endsWith('/support-groups/g1/members/'));
    expect(searched.queryParameters, {'q': 'musa'});

    await _tap(tester, find.byKey(const ValueKey('group-person-p1')));
    expect(api.urls.any((url) => url.path.endsWith('/members/TGCG-000123/')), isTrue);
    expect(find.text('Musa Bello'), findsWidgets);
  });

  testWidgets('people added between pages are not shown twice', (tester) async {
    var pages = 0;
    final api = _Api((method, path, body) {
      if (path != 'support-groups/g1/members/') return null;
      final more = pages++ > 0;
      return jsonResponse({
        'count': 3,
        // Someone joined at the top meanwhile: the second page repeats Musa.
        'next': more ? null : 'https://api.tgcg.test/api/v1/support-groups/g1/members/?offset=1',
        'previous': null,
        'results': more
            ? [_person('p1', 'Musa Bello'), _person('p2', 'Aisha Sani')]
            : [_person('p1', 'Musa Bello')],
      });
    });
    await _show(tester, api, VettedGroupPage(group: SupportGroup.fromJson(_group())));
    await _tap(tester, find.text('Show more'));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('group-person-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-person-p2')), findsOneWidget);
  });

  testWidgets('a group page from a server without analytics shows its people', (tester) async {
    final api = _Api(
      (method, path, body) => path == 'support-groups/g1/members/'
          ? jsonResponse(_page([_person('p1', 'Musa Bello')]))
          : null,
    );
    await _show(tester, api, VettedGroupPage(group: SupportGroup.fromJson(_group())));
    expect(find.text('Analytics'), findsNothing);
    expect(find.text('Musa Bello'), findsOneWidget);
  });

  testWidgets('a group whose named leader has not said yes cannot be approved', (tester) async {
    final api = _Api(
      (method, path, body) =>
          path == 'support-groups/g1/members/' ? jsonResponse(_page(<Object>[])) : null,
    );
    await _show(
      tester,
      api,
      VettedGroupPage(
        group: SupportGroup.fromJson(
          _group(status: 'pending', label: 'Waiting for vetting', confirmed: false),
        ),
      ),
    );
    expect(find.text('Waiting for the leader'), findsOneWidget);
    expect(find.textContaining('has not said yes in the app yet'), findsOneWidget);
    final approve = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'));
    expect(approve.onPressed, isNull);
  });

  test('a group asking to confirm is something to follow up', () async {
    final api = _Api(
      (method, path, body) => path == 'me/support-groups/'
          ? jsonResponse({
              'invitations': [_invitation()],
              'groups': <Object>[],
              'leading': <Object>[],
              'vets': false,
            })
          : path == 'me/member/'
          ? jsonResponse(fakeCard())
          : null,
    );
    final followUps = await loadFollowUps(api.connect(), memberSession(), DateTime(2026, 11, 3));
    expect(followUps.items.map((item) => item.title), contains('$_name asks you to confirm'));
  });
}
