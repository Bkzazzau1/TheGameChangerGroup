import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/app.dart';
import 'package:tgcg_emcop/tgcg/member/forgot_pin_page.dart';
import 'package:tgcg_emcop/tgcg/member/member_registration_page.dart';
import 'package:tgcg_emcop/tgcg/member/member_shell.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// A valid 1x1 PNG, so photo previews decode.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const _unit = {
  'code': '18-23-01-014',
  'name': 'UNG. ASKA I/ L.E.A. ANGUWAN KAHU',
  'location': '',
  'ward': 'KWARBAI "A"',
  'ward_code': '18-23-01',
  'lga': 'Zaria',
  'state': 'Kaduna',
  'navigation': {
    'latitude': 11.0539,
    'longitude': 7.712955,
    'confirmed': false,
    'accuracy_m': 5.6,
    'source': 'inec',
  },
};

Map<String, dynamic> _card() => {
      'membership_number': 'TGCG-000123',
      'full_name': 'Musa Bello',
      'phone_number': '+2348031234567',
      'email': '',
      'vin': '90F5***********7263',
      'has_pvc': true,
      'gender': 'male',
      'date_of_birth': '1990-05-14',
      'occupation': 'Teacher',
      'status': 'verified',
      'polling_unit': _unit,
      'member_since': '2026-10-11T08:00:00Z',
      'photo_url': null,
      'qr_token': 'TGCG-000123:signed-token',
    };

Map<String, dynamic> _session() => {'access': 'A', 'refresh': 'R', 'member': _card()};

/// A fake TGCG server. Records every request; [respond] answers by path.
class _Server {
  _Server(this.respond);
  final http.Response? Function(http.Request request) respond;
  final requests = <http.BaseRequest>[];
  final bodies = <String, String>{};

  BackendServices connect() => BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient.streaming((request, body) async {
          requests.add(request);
          final bytes = await body.toBytes();
          final plain = http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..bodyBytes = bytes;
          bodies['${request.method} ${request.url.path}'] = utf8.decode(bytes, allowMalformed: true);
          final response = respond(plain) ?? _json({'detail': 'Not found.'}, 404);
          return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode,
              headers: response.headers);
        }),
      );
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

String _path(http.Request request) => request.url.path.replaceFirst('/api/v1/', '');

Future<TgcgSessionController> _pump(
  WidgetTester tester,
  BackendServices backend,
  Widget home, {
  bool member = false,
}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController();
  if (member) session.signInMember(fullName: 'Musa Bello', membershipNumber: 'TGCG-000123');
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: backend,
      child: TgcgSession(controller: session, child: MaterialApp(home: home)),
    ),
  );
  return session;
}

void main() {
  test('Nigerian phone numbers are normalised like the server does', () {
    expect(normalizeNigerianPhone('0803 123 4567'), '+2348031234567');
    expect(normalizeNigerianPhone('+234 803 123 4567'), '+2348031234567');
    expect(normalizeNigerianPhone('8031234567'), '+2348031234567');
    expect(normalizeNigerianPhone('0603 123 4567'), isNull);
    expect(normalizeNigerianPhone('12345'), isNull);
  });

  test('a member session has no operations role', () {
    final session = TgcgSessionController();
    session.signInMember(fullName: 'Musa Bello', membershipNumber: 'TGCG-000123');
    expect(session.isAuthenticated, isTrue);
    expect(session.isMember, isTrue);
    expect(session.role, isNull);
    expect(session.accessId, 'TGCG-000123');
    session.signOut();
    expect(session.isAuthenticated, isFalse);
    expect(session.isMember, isFalse);
  });

  testWidgets('registration goes from a PVC scan to a signed-in member', (tester) async {
    final server = _Server((request) => switch (_path(request)) {
          'register/polling-unit/' => _json({
              ..._unit,
              'code': '18-23-01-001',
              'name': 'KWARBAI I/ PRI. SCH. MADARKACI',
              'navigation': null,
            }),
          'register/code/' => _json({'expires_in': 600}),
          'register/' => _json(_session(), 201),
          _ => null,
        });
    final session = await _pump(
      tester,
      server.connect(),
      MemberRegistrationPage(
        scanPvc: ({required camera}) async => PvcScan(
          photo: (bytes: _pixel, name: 'pvc.png'),
          fullName: 'Musa Bello',
          vin: '90F5B0E8D0295847263',
          delim: '18-23-01-001',
        ),
        takeSelfie: () async => (bytes: _pixel, name: 'selfie.png'),
      ),
    );

    // Step 1: the scan fills the form and finds the polling unit.
    await tester.tap(find.text('Scan PVC'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your polling unit: KWARBAI I/ PRI. SCH. MADARKACI'), findsOneWidget);
    expect(server.requests.first.url.queryParameters['delim'], '18-23-01-001');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: gender and phone are required.
    expect(find.text('Your details'), findsOneWidget);
    await tester.tap(find.text('Male'));
    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '0803 123 4567');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3: the code is texted, then typed in.
    await tester.tap(find.text('Send code'));
    await tester.pump();
    await tester.pump();
    expect(jsonDecode(server.bodies['POST /api/v1/register/code/']!), {
      'phone_number': '+2348031234567',
      'vin': '90F5B0E8D0295847263',
    });
    expect(find.textContaining('We sent a 6-digit code to +2348031234567'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Code from the SMS'), '123456');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();

    // Step 4: selfie.
    await tester.tap(find.text('Take selfie'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();

    // Step 5: PIN and consent.
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '482915');
    await tester.enterText(find.widgetWithText(TextField, 'PIN again'), '482915');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create my membership'));
    await tester.pump();
    await tester.pump();

    expect(session.isMember, isTrue);
    expect(session.accessId, 'TGCG-000123');
    final upload = server.requests.last as http.MultipartRequest;
    expect(upload.url.path, '/api/v1/register/');
    expect(upload.fields['phone_number'], '+2348031234567');
    expect(upload.fields['vin'], '90F5B0E8D0295847263');
    expect(upload.fields['delim'], '18-23-01-001');
    expect(upload.fields['gender'], 'male');
    expect(upload.fields['pin'], '482915');
    expect(upload.fields['consent'], 'true');
    expect(upload.files.map((f) => f.field), containsAll(['photo', 'pvc_image']));
  });

  testWidgets('a wrong SMS code sends the member back to the code step', (tester) async {
    final server = _Server((request) => switch (_path(request)) {
          'register/polling-unit/' => _json({..._unit, 'navigation': null}),
          'register/code/' => _json({'expires_in': 600}),
          'register/' => _json({
              'code': ['The code is wrong or has expired. Request a new one.'],
            }, 400),
          _ => null,
        });
    final session = await _pump(
      tester,
      server.connect(),
      MemberRegistrationPage(
        scanPvc: ({required camera}) async => PvcScan(
          photo: (bytes: _pixel, name: 'pvc.png'),
          fullName: 'Musa Bello',
          vin: '90F5B0E8D0295847263',
          delim: '18/23/01/014',
        ),
        takeSelfie: () async => (bytes: _pixel, name: 'selfie.png'),
      ),
    );
    await tester.tap(find.text('Scan PVC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female'));
    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '08031234567');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send code'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Code from the SMS'), '000000');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Take selfie'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '482915');
    await tester.enterText(find.widgetWithText(TextField, 'PIN again'), '482915');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create my membership'));
    await tester.pump();
    await tester.pump();

    expect(session.isMember, isFalse);
    expect(find.text('Confirm your phone'), findsOneWidget);
    expect(find.text('The code is wrong or has expired. Request a new one.'), findsOneWidget);
  });

  testWidgets('a forgotten PIN is reset by SMS code and signs the member in', (tester) async {
    final server = _Server((request) => switch (_path(request)) {
          'register/pin-code/' => _json({'expires_in': 600}),
          'register/pin/' => _json(_session()),
          _ => null,
        });
    final session = await _pump(tester, server.connect(), const ForgotPinPage());
    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '0803 123 4567');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Code from the SMS'), '123456');
    await tester.enterText(find.widgetWithText(TextField, 'New PIN'), '482915');
    await tester.enterText(find.widgetWithText(TextField, 'New PIN again'), '482915');
    await tester.pump();
    await tester.tap(find.text('Save PIN and sign in'));
    await tester.pumpAndSettle();

    expect(session.isMember, isTrue);
    expect(jsonDecode(server.bodies['POST /api/v1/register/pin/']!), {
      'phone_number': '+2348031234567',
      'code': '123456',
      'pin': '482915',
    });
  });

  testWidgets('the member home shows the card, directions, news and volunteering', (tester) async {
    var offers = <Map<String, dynamic>>[];
    final server = _Server((request) => switch (_path(request)) {
          'me/member/' => _json(_card()),
          'me/polling-unit/' => _json({'polling_unit': _unit, 'members_in_unit': 12, 'members_in_ward': 140}),
          'me/announcements/' => _json({
              'count': 1,
              'results': [
                {
                  'id': 'a1',
                  'title': 'Ward meeting on Saturday',
                  'body': 'All Kwarbai A members meet at 4pm.',
                  'author': 'Ward Coordinator',
                  'published_at': '2026-10-10T16:00:00Z',
                },
              ],
            }),
          'me/volunteer/' when request.method == 'POST' => () {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              offers = [
                {
                  'id': 'v1',
                  'interests': body['interests'],
                  'status': 'pending',
                  'message': body['message'],
                  'decision_reason': '',
                  'created_at': '2026-10-11T09:00:00Z',
                },
              ];
              return _json(offers.first, 201);
            }(),
          'me/volunteer/' => _json(offers),
          'me/volunteer/v1/withdraw/' => () {
              offers = [
                {...offers.first, 'status': 'withdrawn'},
              ];
              return _json(offers.first);
            }(),
          _ => null,
        });
    final launched = <Uri>[];
    await _pump(
      tester,
      server.connect(),
      MemberShell(launch: (uri) async {
        launched.add(uri);
        return true;
      }),
      member: true,
    );
    await tester.pumpAndSettle();

    // Card.
    expect(find.text('Musa Bello'), findsOneWidget);
    expect(find.text('TGCG-000123'), findsOneWidget);
    expect(find.byKey(const ValueKey('membership-qr')), findsOneWidget);
    expect(find.text('PVC on record'), findsOneWidget);

    // My polling unit, with directions from INEC's location.
    await tester.tap(find.text('My unit'));
    await tester.pumpAndSettle();
    expect(find.text('UNG. ASKA I/ L.E.A. ANGUWAN KAHU'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining("from INEC's polling unit locator"), findsOneWidget);
    await tester.tap(find.text('Navigate to polling unit'));
    await tester.pump();
    expect(launched.single.queryParameters['destination'], '11.0539,7.712955');

    // News.
    await tester.tap(find.text('News'));
    await tester.pumpAndSettle();
    expect(find.text('Ward meeting on Saturday'), findsOneWidget);

    // Volunteering is for party work; nothing here is about becoming an agent.
    await tester.tap(find.text('Volunteer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('agent'), findsNothing);
    await tester.tap(find.text('Offer to help'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull);
    await tester.tap(find.text('Mobilisation and door-to-door'));
    await tester.tap(find.text('Election-day support'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Free on weekends.');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST /api/v1/me/volunteer/']!), {
      'interests': ['mobilisation', 'electionDay'],
      'message': 'Free on weekends.',
    });
    expect(find.text('WITH COORDINATORS'), findsOneWidget);
    expect(find.text('Offer to help'), findsNothing);

    // An unanswered offer can be withdrawn, and a new one sent.
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(server.bodies.containsKey('POST /api/v1/me/volunteer/v1/withdraw/'), isTrue);
    expect(find.text('WITHDRAWN'), findsOneWidget);
    expect(find.text('Offer to help'), findsOneWidget);
  });

  testWidgets('a member signing in on the server opens the member app', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server((request) => switch (_path(request)) {
          'auth/login/' => _json({
              'access': 'A',
              'refresh': 'R',
              'user': {
                'access_id': 'TGCG-000123',
                'full_name': 'Musa Bello',
                'role': 'member',
                'scope': {'level': 'pollingUnit', 'country': 'Nigeria', 'pollingUnitId': '18-23-01-014'},
                'capabilities': <String>[],
              },
            }),
          'me/member/' => _json(_card()),
          'me/polling-unit/' => _json({'polling_unit': _unit, 'members_in_unit': 1, 'members_in_ward': 1}),
          'me/announcements/' => _json({'count': 0, 'results': <Object>[]}),
          'me/volunteer/' => _json(<Object>[]),
          _ => null,
        });
    await tester.pumpWidget(TgcgApp(backend: server.connect()));
    await tester.pumpAndSettle();
    expect(find.text('New member? Register with your PVC'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '0803 123 4567');
    await tester.enterText(find.byType(TextField).at(1), '482915');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('TGCG Member'), findsOneWidget);
    expect(find.text('TGCG-000123'), findsOneWidget);
  });
}
