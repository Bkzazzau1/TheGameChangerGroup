import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/member/member_shell.dart';
import 'package:tgcg_emcop/tgcg/member/registered_members_page.dart';

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Server {
  final requests = <String>[];
  final bodies = <String, Object?>{};
  http.Response? Function(String key, Object? body) answer = (_, _) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add(key);
      final text = utf8.decode(await body.toBytes());
      final decoded = text.isEmpty ? null : jsonDecode(text);
      bodies[key] = decoded;
      final response = answer(key, decoded) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}

Future<void> _pump(WidgetTester tester, _Server server, Widget page) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TgcgBackend(services: server.connect(), child: MaterialApp(home: page)),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _listed({bool verified = false}) => {
  'membership_number': 'TGCG-000123',
  'full_name': 'Sani Umar',
  'phone_number': '+2348051234567',
  'scope': {'level': 'country', 'country': 'Nigeria'},
  'verification_status': verified ? 'verified' : 'unverified',
  'membership_state': 'active',
  'registered_at': '2026-10-17T10:00:00Z',
  'missing': verified ? <String>[] : ['photo', 'pvc_photo', 'gender', 'date_of_birth'],
  'can_complete': !verified,
  'signed_in': false,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> members) =>
    {'count': members.length, 'next': null, 'previous': null, 'results': members};

Map<String, dynamic> _details() => {
  'membership_number': 'TGCG-000123',
  'full_name': 'Sani Umar',
  'phone_number': '+2348051234567',
  'whatsapp_number': '',
  'email': '',
  'vin': null,
  'has_pvc': false,
  'has_card_photo': false,
  'gender': '',
  'date_of_birth': null,
  'occupation': '',
  'status': 'active',
  'verification_status': 'unverified',
  'membership_state': 'active',
  'scope': {'level': 'country', 'country': 'Nigeria'},
  'polling_unit': null,
  'member_since': '2026-10-17T10:00:00Z',
  'photo_url': null,
  'disabilities': <String>[],
  'disability_other': '',
  'card_missing': ['photo', 'pvc_photo', 'gender', 'date_of_birth'],
  'can_change_phone': true,
};

/// The add or change button in a row of the details.
Finder _action(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.byType(TextButton),
);

void main() {
  testWidgets('anyone registers a member with a name and a phone number', (tester) async {
    final server = _Server();
    var registered = <Map<String, dynamic>>[];
    server.answer = (key, body) => switch (key) {
      'GET me/registered/' => _json(_page(registered)),
      'POST me/registered/' => _json((registered = [_listed()]).single, 201),
      _ => null,
    };
    await _pump(tester, server, const RegisteredMembersPage());
    expect(find.text('No one registered yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Register a member'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Sani Umar');
    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '0805 123 4567');
    await tester.pump();
    Finder register() => find.widgetWithText(FilledButton, 'Register');
    // Not without their agreement.
    expect(tester.widget<FilledButton>(register()).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(register());
    await tester.pumpAndSettle();
    expect(server.bodies['POST me/registered/'], {
      'full_name': 'Sani Umar',
      'phone_number': '0805 123 4567',
      'consent': true,
    });

    // How they sign in: the phone number is also the first password.
    expect(find.text('Sani Umar is registered'), findsOneWidget);
    expect(find.text('TGCG-000123'), findsOneWidget);
    expect(find.text('08051234567'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Sani Umar'), findsOneWidget);
    expect(find.text('Needs details'), findsOneWidget);
    expect(find.textContaining('TGCG-000123 · 08051234567'), findsOneWidget);
  });

  testWidgets('a member whose identity is checked is no longer theirs to complete', (tester) async {
    final server = _Server();
    server.answer = (key, body) => switch (key) {
      'GET me/registered/' => _json(_page([_listed(verified: true)])),
      _ => null,
    };
    await _pump(tester, server, const RegisteredMembersPage());
    expect(find.text('ID checked'), findsOneWidget);
    await tester.tap(find.text('Sani Umar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Their identity has been checked'), findsOneWidget);
    expect(server.requests, isNot(contains('GET me/registered/TGCG-000123/')));
  });

  testWidgets('the person who registered them completes the registration', (tester) async {
    final server = _Server();
    var details = _details();
    server.answer = (key, body) => switch (key) {
      'GET me/registered/TGCG-000123/' => _json(details),
      'GET me/registered/TGCG-000123/pvc-scan/' => _json({'can_scan': true, 'latest': null}),
      'PATCH me/registered/TGCG-000123/' => _json(
        details = {
          ...details,
          ...body! as Map<String, dynamic>,
          if ((body as Map<String, dynamic>)['phone_number'] != null)
            'phone_number': '+2348057654321',
        },
      ),
      _ => null,
    };
    await _pump(tester, server, const RegisteredMemberPage(membershipNumber: 'TGCG-000123'));
    expect(find.text('Their details'), findsOneWidget);
    expect(find.text('08051234567'), findsOneWidget);
    expect(find.text('Not scanned'), findsOneWidget);
    expect(_action('Place'), findsOneWidget);

    await tester.tap(_action('Occupation'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What they do for a living'), 'Trader');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(server.bodies['PATCH me/registered/TGCG-000123/'], {'occupation': 'Trader'});
    expect(find.text('Trader'), findsOneWidget);

    await tester.tap(_action('Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Full name, as on their PVC'), 'Sani Umar Bello');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(server.bodies['PATCH me/registered/TGCG-000123/'], {'full_name': 'Sani Umar Bello'});

    // The number is also the first password, so both change.
    await tester.tap(_action('Phone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Their phone number'), '0805 765 4321');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(server.bodies['PATCH me/registered/TGCG-000123/'], {'phone_number': '0805 765 4321'});
    expect(
      find.text('They now sign in with 08057654321, and 08057654321 is the password.'),
      findsOneWidget,
    );
  });
}
