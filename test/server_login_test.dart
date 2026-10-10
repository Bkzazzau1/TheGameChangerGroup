import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/app.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  testWidgets('server mode signs in with the role and scope the server returns', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = BackendServices.connect(
      'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['password'] != 'Strong-Pass-2027!') {
          return _json({'detail': 'No active account found with the given credentials'}, 401);
        }
        return _json({
          'access': 'A',
          'refresh': 'R',
          'user': {
            'access_id': 'SC-KD',
            'full_name': 'Kaduna Coordinator',
            'role': 'stateCoordinator',
            'scope': {'level': 'state', 'country': 'Nigeria', 'zoneId': 'NW', 'zoneName': 'North West', 'stateId': 'KD', 'stateName': 'Kaduna'},
            'capabilities': ['accreditAgents'],
          },
        });
      }),
    );

    await tester.pumpWidget(TgcgApp(backend: backend));
    await tester.pumpAndSettle();

    // No presentation role picker when connected to a server.
    expect(find.text('Operational role'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'SC-KD');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    expect(find.textContaining('Wrong access ID'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'Strong-Pass-2027!');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNothing);
    expect(find.textContaining('Kaduna'), findsWidgets);
  });
}
