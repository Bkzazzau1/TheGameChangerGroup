import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/tracking_repository.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/geography/lga_wards.dart';
import 'package:tgcg_emcop/tgcg/membership/membership_store.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/tracking/agents_on_ground_page.dart';

const _zaria = {
  'level': 'lga',
  'country': 'Nigeria',
  'zoneId': 'NW',
  'stateId': 'KD',
  'stateName': 'Kaduna',
  'lgaId': 'KD-ZARIA',
  'lgaName': 'Zaria',
};

Map<String, dynamic> _agent(String id, String name, String? status, {bool stale = false}) => {
      'agent': id,
      'name': name,
      'role': 'pollingUnitAgent',
      'polling_unit': '18-23-01-014',
      'on_duty_since': '2026-10-11T07:00:00Z',
      'position': status == null
          ? null
          : {
              'latitude': '11.053900',
              'longitude': '7.712955',
              'accuracy_m': 8.0,
              'captured_at': DateTime.now().toUtc().toIso8601String(),
              'is_mocked': status == 'suspect',
              'distance_to_pu_m': status == 'away' ? 1400 : 12,
              'status': status,
            },
      'stale': stale,
    };

Map<String, dynamic> _tally(int agents, int checked, int onSite, int away, int suspect) => {
      'agents': agents,
      'checked_in': checked,
      'not_checked_in': agents - checked,
      'on_site': onSite,
      'away': away,
      'unverified': 0,
      'suspect': suspect,
      'on_duty_now': checked,
    };

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  test('live agents and coverage parse from the server', () {
    final live = LiveAgents.fromJson({
      'scope': _zaria,
      'count': 2,
      'agents': [_agent('AG-00001', 'Musa Bello', 'onSite'), _agent('AG-00002', 'Ada Obi', null, stale: true)],
    });
    expect(live.scope.lgaId, 'KD-ZARIA');
    expect(live.agents.first.position!.status, AgentLocationStatus.onSite);
    expect(live.agents.first.position!.latitude, 11.0539);
    expect(live.agents.last.position, isNull);
    expect(agentStatus(live.agents.last).$1, 'NO RECENT SIGNAL');

    final coverage = Coverage.fromJson({
      'date': '2026-10-11',
      'scope': _zaria,
      ..._tally(4, 3, 1, 1, 1),
      'children': [
        {'level': 'ward', 'code': '18-23-01', 'name': 'KWARBAI "A"', ..._tally(2, 2, 1, 0, 1)},
      ],
    });
    expect(coverage.total.checkedInShare, .75);
    expect(coverage.children.single.level, GeographyLevel.ward);
    expect(coverage.children.single.tally.suspect, 1);
  });

  testWidgets('shows coverage, agents by urgency on the map, and opens a ward', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LgaWards.load('KD-ZARIA'));

    final asked = <Uri>[];
    final backend = BackendServices.connect(
      'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        asked.add(request.url);
        final ward = request.url.queryParameters['level'] == 'ward';
        final scope = ward
            ? {..._zaria, 'level': 'ward', 'wardId': '18-23-01', 'wardName': 'KWARBAI "A"'}
            : _zaria;
        if (request.url.path.endsWith('tracking/live/')) {
          return _json({
            'scope': scope,
            'count': 4,
            'agents': [
              _agent('AG-00001', 'Musa Bello', 'onSite'),
              _agent('AG-00002', 'Ada Obi', 'away'),
              _agent('AG-00003', 'Sani Musa', 'suspect'),
              _agent('AG-00004', 'Bola Ade', null, stale: true),
            ],
          });
        }
        return _json({
          'date': '2026-10-11',
          'scope': scope,
          ..._tally(4, 3, 1, 1, 1),
          'children': ward
              ? []
              : [
                  {'level': 'ward', 'code': '18-23-01', 'name': 'KWARBAI "A"', ..._tally(4, 3, 1, 1, 1)},
                  {'level': 'ward', 'code': '18-23-02', 'name': 'KWARBAI "B"', ..._tally(0, 0, 0, 0, 0)},
                ],
        });
      }),
    );
    final session = TgcgSessionController()
      ..signIn(role: TgcgRole.lgaCoordinator, operatorName: 'LGA Coordinator', accessId: 'LC-1');
    addTearDown(session.dispose);
    final membership = MembershipOperationsController.prototypeSeed(GeographyRegistry.prototypeSeed());
    addTearDown(membership.dispose);

    await tester.pumpWidget(
      TgcgBackend(
        services: backend,
        child: TgcgSession(
          controller: session,
          child: MembershipOperations(
            controller: membership,
            child: const MaterialApp(
              home: Scaffold(body: AgentsOnGroundPage(refreshEvery: Duration(hours: 1))),
            ),
          ),
        ),
      ),
    );
    // The map resolves its outlines over a few frames before placing markers.
    for (var i = 0; i < 20 && find.byKey(const ValueKey('agent-AG-00001')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(find.text('3 of 4 polling-unit agents have checked in (75%).'), findsOneWidget);
    expect(find.text('1 SUSPECT GPS'), findsOneWidget);
    // Agents with a position get a map marker; the one without does not.
    expect(find.byKey(const ValueKey('agent-AG-00001')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-AG-00004')), findsNothing);
    // Problems come first in the list.
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => ((tile.title as Text).data))
        .toList();
    expect(names, ['Sani Musa', 'Ada Obi', 'Bola Ade', 'Musa Bello']);
    expect(find.textContaining('1.4 km from unit'), findsOneWidget);

    // Open a ward from the breakdown.
    await tester.tap(find.text('KWARBAI "A"'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump();
    expect(asked.last.queryParameters, {'level': 'ward', 'code': '18-23-01'});
    expect(find.widgetWithText(ActionChip, 'My area'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'KWARBAI "A"'), findsOneWidget);
  });
}
