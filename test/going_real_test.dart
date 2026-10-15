import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/app.dart';
import 'package:tgcg_emcop/tgcg/dashboard_page.dart';
import 'package:tgcg_emcop/tgcg/domain/permissions.dart';
import 'package:tgcg_emcop/tgcg/field/field_agent_shell.dart';
import 'package:tgcg_emcop/tgcg/field/field_operations_store.dart';
import 'package:tgcg_emcop/tgcg/login_page.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/results/result_operations_store.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_design.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _page(int count) =>
    {'count': count, 'next': null, 'previous': null, 'results': <Object>[]};

const _kaduna = {
  'level': 'state',
  'country': 'Nigeria',
  'zoneId': 'NW',
  'zoneName': 'North West',
  'stateId': 'KD',
  'stateName': 'Kaduna',
};

Map<String, dynamic> _tally(int agents, int checkedIn) => {
      'agents': agents,
      'checked_in': checkedIn,
      'not_checked_in': agents - checkedIn,
      'on_site': checkedIn,
      'away': 0,
      'unverified': 0,
      'suspect': 0,
      'on_duty_now': 2,
    };

BackendServices _server(http.Response? Function(String key, Map<String, String> query) answer) =>
    BackendServices.connect(
      'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
        return answer(key, request.url.queryParameters) ?? _json({'detail': 'Not found.'}, 404);
      }),
    );

Future<void> _pump(WidgetTester tester, Widget home, {Size size = const Size(400, 1600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(home);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a phone opens on the poster and the welcome, then signs in', (tester) async {
    final backend = _server((key, query) => null);
    await _pump(
      tester,
      TgcgBackend(
        services: backend,
        child: TgcgSession(
          controller: TgcgSessionController(),
          child: const MaterialApp(home: TgcgLoginPage()),
        ),
      ),
    );
    final poster = find.byWidgetPredicate(
      (widget) => widget is Image && '${widget.image}'.contains('assets/brand/login_poster.webp'),
    );
    expect(poster, findsOneWidget);
    // The poster keeps its own shape even before the picture has loaded, and
    // it comes first, above the welcome.
    expect(tester.getSize(poster).aspectRatio, closeTo(1086 / 1448, .01));
    expect(
      tester.getTopLeft(poster).dy,
      lessThan(tester.getTopLeft(find.text('Welcome to TGCG-EMCOP')).dy),
    );
    expect(find.text('Welcome to TGCG-EMCOP'), findsOneWidget);
    expect(find.text('TGCG-EMCOP'), findsOneWidget); // beside the logo
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Operational role'), findsNothing); // no presentation roles

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to TGCG-EMCOP'), findsOneWidget);
  });

  group("a phone's light top bar draws its buttons dark", () {
    const unit = {'level': 'pollingUnit', 'country': 'Nigeria', 'pollingUnitId': '18-23-05-001'};

    Future<void> signIn(WidgetTester tester, Map<String, dynamic> user) async {
      final backend = _server((key, query) => switch (key) {
            'POST auth/login/' => _json({'access': 'A', 'refresh': 'R', 'user': user}),
            'GET incidents/' || 'GET field-reports/' || 'GET results/' => _json(_page(0)),
            _ => null,
          });
      // The real app, with its theme: white icons there are for dark bars.
      await _pump(tester, TgcgApp(backend: backend), size: const Size(400, 900));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '08030000001');
      await tester.enterText(find.byType(TextField).at(1), '08030000001');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
    }

    Color? drawn(WidgetTester tester, String tooltip) => tester
        .widget<RichText>(
          find.descendant(of: find.byTooltip(tooltip), matching: find.byType(RichText)).first,
        )
        .text
        .style
        ?.color;

    testWidgets("the operations app's menu button", (tester) async {
      const permissions = [
        'createIncident',
        'submitFieldReport',
        'submitElectionResult',
        'viewIncidents',
        'viewSituationRoom',
        'verifyMemberIdentity',
        'viewMeetingRoom',
        'joinMeeting',
      ];
      await signIn(tester, {
        'access_id': 'TGCG-000200',
        'full_name': 'Musa Bello',
        'role': 'member',
        'scope': unit,
        'capabilities': permissions,
        'membership_number': 'TGCG-000200',
        'access': [
          {
            'source': 'assignment',
            'assignment': 'a1',
            'role': 'pu-organising-officer',
            'role_name': 'PU Organising Officer',
            'protected': false,
            'areas': [unit],
            'permissions': permissions,
          },
        ],
      });

      expect(drawn(tester, 'Open navigation menu'), TgcgColors.ink);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      for (final item in ['Result Capture', 'Field Monitoring', 'Situation Room', 'Meeting Room']) {
        expect(
          find.descendant(of: find.byType(Drawer), matching: find.text(item)),
          findsOneWidget,
          reason: item,
        );
      }
    });

    testWidgets("the polling agent's PIN and sign-out buttons", (tester) async {
      await signIn(tester, {
        'access_id': 'AG-00001',
        'full_name': 'Musa Bello',
        'role': 'pollingUnitAgent',
        'scope': unit,
        'capabilities': ['createIncident', 'submitFieldReport', 'submitElectionResult'],
      });

      for (final button in ['Change PIN', 'Sign out']) {
        expect(drawn(tester, button), TgcgColors.ink, reason: button);
      }
    });
  });

  test('a build made without TGCG_API_URL uses the live server', () {
    // Tests run without --dart-define, like Run in VS Code or `flutter run`.
    expect(tgcgApiUrl, 'https://api.tgcg.online');
  });

  test('menus offer only modules that work on server records', () {
    final everything = TgcgSessionController()
      ..signInFromServer(
        role: TgcgRole.nationalAdministrator,
        fullName: 'TGCG',
        accessId: 'TGCG',
        scope: GeographicScope.nigeria,
        capabilities: {for (final capability in TgcgCapability.values) capability.name},
      );
    expect(everything.modules, liveModules);
    for (final sample in [
      TgcgModule.membershipNetwork,
      TgcgModule.accreditation,
      TgcgModule.communications,
      TgcgModule.discussionRoom,
      TgcgModule.evidenceCapture,
      TgcgModule.reports,
    ]) {
      expect(everything.modules, isNot(contains(sample)), reason: sample.name);
    }
  });

  group('signed in to the server', () {
    late BackendServices backend;
    late FieldOperationsController field;
    late ResultOperationsController results;
    late TgcgSessionController session;
    late OfflinePersistenceController offline;

    Future<void> connect(http.Response? Function(String key, Map<String, String> query) answer) async {
      backend = _server(answer);
      field = FieldOperationsController.prototypeSeed();
      results = ResultOperationsController.prototypeSeed();
      field.connect(backend.field, account: session.accessId);
      results.connect(backend.results, account: session.accessId);
      await field.refreshIfOlderThan(const Duration(hours: 1));
      await results.refreshIfOlderThan(const Duration(hours: 1));
    }

    tearDown(() {
      field.dispose();
      results.dispose();
      session.dispose();
    });

    Widget app(Widget home) => TgcgBackend(
          services: backend,
          child: TgcgSession(
            controller: session,
            child: OfflinePersistence(
              controller: offline,
              child: FieldOperations(
                controller: field,
                child: ResultOperations(
                  controller: results,
                  child: MaterialApp(home: Scaffold(body: home)),
                ),
              ),
            ),
          ),
        );

    testWidgets("an agent's phone shows their own account, not sample profiles", (tester) async {
      offline = OfflinePersistenceController();
      session = TgcgSessionController()
        ..signInFromServer(
          role: TgcgRole.pollingUnitAgent,
          fullName: 'Musa Bello',
          accessId: 'AG-00001',
          scope: const GeographicScope(
            level: GeographyLevel.pollingUnit,
            country: 'Nigeria',
            stateId: 'KD',
            lgaId: 'KD-ZARIA',
            wardId: '18-23-01',
            wardName: 'KWARBAI "A"',
            pollingUnitId: '18-23-01-001',
            pollingUnitName: 'KWARBAI I',
          ),
          capabilities: {
            'createIncident',
            'submitFieldReport',
            'submitElectionResult',
            'viewMeetingRoom',
            'joinMeeting',
          },
        );
      final now = DateTime.now().toUtc();
      await tester.runAsync(
        () => connect((key, query) => switch (key) {
              'GET incidents/' || 'GET field-reports/' || 'GET results/' => _json(_page(0)),
              'GET tracking/check-ins/' => _json({
                  'count': 1,
                  'next': null,
                  'previous': null,
                  'results': [
                    {'agent': 'AG-00001', 'created_at': now.toIso8601String()},
                  ],
                }),
              _ => null,
            }),
      );
      await _pump(tester, app(const FieldAgentShell()));

      expect(find.text('Musa Bello'), findsOneWidget);
      expect(find.text('AG-00001 · Polling unit agent'), findsOneWidget);
      expect(find.textContaining('KWARBAI I'), findsWidgets);
      expect(find.textContaining('Checked in today at'), findsOneWidget);
      expect(find.text('Off duty'), findsOneWidget);
      for (final tab in ['Home', 'Report', 'Result', 'Meetings']) {
        expect(find.widgetWithText(NavigationDestination, tab), findsOneWidget, reason: tab);
      }
      for (final gone in ['Messages', 'Forum', 'Field Assignment Required']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('the dashboard shows only the server numbers the account may see', (tester) async {
      offline = OfflinePersistenceController();
      session = TgcgSessionController()
        ..signInFromServer(
          role: TgcgRole.stateCoordinator,
          fullName: 'Kaduna Coordinator',
          accessId: 'SC-KD',
          scope: const GeographicScope(
            level: GeographyLevel.state,
            country: 'Nigeria',
            stateId: 'KD',
            stateName: 'Kaduna',
          ),
          capabilities: {
            'viewIncidents',
            'viewLiveOperations',
            'viewSituationRoom',
            'verifyElectionResult',
            'viewCollation',
            'registerMembers',
          },
        );
      await tester.runAsync(
        () => connect((key, query) => switch (key) {
              'GET members/' => _json(_page(1234)),
              'GET tracking/coverage/' => _json({
                  'date': '2027-02-25',
                  'scope': _kaduna,
                  ..._tally(4, 3),
                  'children': [
                    {'level': 'senatorialDistrict', 'code': 'KD-N', 'name': 'Kaduna North', ..._tally(4, 3)},
                  ],
                }),
              'GET results/' when query['status'] == 'verified' => _json(_page(5)),
              'GET results/' => _json(_page(12)),
              'GET incidents/' when query['open'] == 'true' => _json(_page(2)),
              'GET incidents/' || 'GET field-reports/' => _json(_page(0)),
              _ => null,
            }),
      );
      await _pump(tester, app(TgcgDashboardPage(onOpenModule: (_) {})), size: const Size(1300, 2400));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Demo data'), findsNothing);
      expect(find.text('1234'), findsOneWidget);
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('Agent check-ins today'), findsOneWidget);
      expect(find.text('Kaduna North'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // open incidents on the server
      // No sample members, agents or readiness.
      for (final gone in ['Approved agents', 'Agent readiness', 'Operational readiness']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });
  });
}
