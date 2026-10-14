import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/auth_repository.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/app.dart';
import 'package:tgcg_emcop/tgcg/member/forgot_pin_page.dart';
import 'package:tgcg_emcop/tgcg/member/member_registration_page.dart';
import 'package:tgcg_emcop/tgcg/member/member_shell.dart';
import 'package:tgcg_emcop/tgcg/member/selfie_check.dart';
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

Map<String, dynamic> _card({String verification = 'verified'}) => {
      'membership_number': 'TGCG-000123',
      'full_name': 'Musa Bello',
      'phone_number': '+2348031234567',
      'email': '',
      'vin': '90F5***********7263',
      'has_pvc': true,
      'gender': 'male',
      'date_of_birth': '1990-05-14',
      'occupation': 'Teacher',
      'status': 'submitted',
      'membership_state': 'active',
      'verification_status': verification,
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

  group('joining in the app', () {
    /// A server answering registration. [smsCodes]: whether joining needs an
    /// SMS code (null: a server from before that question, which always did).
    _Server server({bool? smsCodes = false, http.Response? Function(String path)? extra}) =>
        _Server((request) => switch (_path(request)) {
              'register/options/' when smsCodes != null => _json({'phone_code_required': smsCodes}),
              'register/polling-unit/' => _json({
                  ..._unit,
                  'code': '18-23-01-001',
                  'name': 'KWARBAI I/ PRI. SCH. MADARKACI',
                  'navigation': null,
                }),
              final path => extra?.call(path),
            });

    Future<TgcgSessionController> open(
      WidgetTester tester,
      _Server server, {
      ScanPvc? scanPvc,
      CheckSelfie? checkSelfie,
      ReadPvcText? readPvcText,
    }) =>
        _pump(
          tester,
          server.connect(),
          MemberRegistrationPage(
            scanPvc: scanPvc ?? ({required camera}) async => null,
            takeSelfie: () async => XFile.fromData(_pixel),
            checkSelfie: checkSelfie ?? (_) async => const SelfieCheck.passed(),
            readPvcText: readPvcText,
          ),
        );

    Future<PvcScan?> scanned({required bool camera}) async => PvcScan(
          photo: (bytes: _pixel, name: 'pvc.png'),
          fullName: 'Musa Bello',
          vin: '90F5B0E8D0295847263',
          delim: '18-23-01-001',
        );

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    Future<void> enterPhone(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '0803 123 4567');
      await next(tester);
    }

    Future<void> typeCard(WidgetTester tester, {String vin = '90F5B0E8D0295847263'}) async {
      await tester.enterText(find.widgetWithText(TextField, 'Full name, as on the PVC'), 'Musa Bello');
      await tester.enterText(find.widgetWithText(TextField, 'VIN (Voter Identification Number)'), vin);
      await tester.enterText(
        find.widgetWithText(TextField, 'Polling unit code (marked CODE on the PVC)'),
        '18/23/01/001',
      );
      await next(tester);
    }

    Future<void> choosePin(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextField, 'PIN'), '482915');
      await tester.enterText(find.widgetWithText(TextField, 'PIN again'), '482915');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Create my membership'));
      await tester.pumpAndSettle();
    }

    testWidgets('without SMS asks what USSD asks: phone, PVC details, then a PIN', (tester) async {
      final api = server(extra: (path) => path == 'register/' ? _json(_session(), 201) : null);
      final session = await open(tester, api);

      // The phone comes first, with no code while the server cannot send SMS.
      expect(find.text('Your phone number'), findsOneWidget);
      await enterPhone(tester);
      expect(api.bodies.keys, isNot(contains('POST /api/v1/register/code/')));

      // Typed from the card: no scan or photo needed. Next finds the unit.
      expect(find.text('Your PVC details'), findsOneWidget);
      await typeCard(tester, vin: '90f5 b0e8 d029 5847 263');
      final lookup = api.requests.firstWhere((r) => r.url.path.endsWith('register/polling-unit/'));
      expect(lookup.url.queryParameters['delim'], '18/23/01/001');

      // Everything about the member is optional.
      expect(find.text('About you (optional)'), findsOneWidget);
      await next(tester);
      await choosePin(tester);

      expect(session.isMember, isTrue);
      expect(session.accessId, 'TGCG-000123');
      final upload = api.requests.last as http.MultipartRequest;
      expect(upload.url.path, '/api/v1/register/');
      expect(upload.fields, {
        'phone_number': '+2348031234567',
        'vin': '90F5B0E8D0295847263',
        'delim': '18-23-01-001',
        'full_name': 'Musa Bello',
        'occupation': '',
        'email': '',
        'pin': '482915',
        'consent': 'true',
      });
      expect(upload.files, isEmpty);
    });

    testWidgets('while SMS works the code comes first; a scan and a selfie go with the rest',
        (tester) async {
      final api = server(
        smsCodes: true,
        extra: (path) => switch (path) {
          'register/code/' => _json({'expires_in': 600}),
          'register/' => _json(_session(), 201),
          _ => null,
        },
      );
      final session = await open(tester, api, scanPvc: scanned);

      await enterPhone(tester);
      expect(jsonDecode(api.bodies['POST /api/v1/register/code/']!), {'phone_number': '+2348031234567'});
      expect(find.text('We sent a 6-digit code to +2348031234567. Enter it below.'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Enter the 6-digit code from the SMS.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Code from the SMS'), '123456');
      await next(tester);

      await tester.tap(find.text('Scan PVC'));
      await tester.pumpAndSettle();
      expect(
        find.text('Read from your card: name, VIN, polling unit code. Check each one against the card.'),
        findsOneWidget,
      );
      expect(find.textContaining('Your polling unit: KWARBAI I/ PRI. SCH. MADARKACI'), findsOneWidget);
      await next(tester);

      await tester.tap(find.text('Male'));
      await tester.tap(find.text('Take selfie'));
      await tester.pumpAndSettle();
      await next(tester);
      await choosePin(tester);

      expect(session.isMember, isTrue);
      final upload = api.requests.last as http.MultipartRequest;
      expect(upload.fields['code'], '123456');
      expect(upload.fields['gender'], 'male');
      expect(upload.files.map((f) => f.field), unorderedEquals(['photo', 'pvc_image']));
    });

    testWidgets('a wrong SMS code sends the member back to the phone step', (tester) async {
      // A server from before the question always wants a code.
      final api = server(
        smsCodes: null,
        extra: (path) => switch (path) {
          'register/code/' => _json({'expires_in': 600}),
          'register/' => _json({
              'code': ['The code is wrong or has expired. Request a new one.'],
            }, 400),
          _ => null,
        },
      );
      final session = await open(tester, api);
      await enterPhone(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Code from the SMS'), '000000');
      await next(tester);
      await typeCard(tester);
      await next(tester);
      await choosePin(tester);

      expect(session.isMember, isFalse);
      expect(find.text('Your phone number'), findsOneWidget);
      expect(find.text('The code is wrong or has expired. Request a new one.'), findsOneWidget);
    });

    testWidgets('Next says what is missing instead of staying grey', (tester) async {
      await open(tester, server());
      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '12345');
      await next(tester);
      expect(find.text('Enter a Nigerian mobile number, e.g. 0803 123 4567.'), findsOneWidget);
      await enterPhone(tester);

      await next(tester);
      expect(find.text('Enter your full name, as on the PVC.'), findsOneWidget);
      expect(find.text('A VIN has 19 letters and digits.'), findsOneWidget);
      expect(find.text('Enter the polling unit code from your PVC.'), findsOneWidget);

      // A VIN one character short is caught here, not at the very end.
      await typeCard(tester, vin: '90F5B0E8D029584726');
      expect(find.text('Your PVC details'), findsOneWidget);
      expect(find.text('A VIN has 19 letters and digits.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'VIN (Voter Identification Number)'),
        '90F5B0E8D0295847263',
      );
      await next(tester);
      expect(find.text('About you (optional)'), findsOneWidget);

      await next(tester);
      await tester.tap(find.text('Create my membership'));
      await tester.pump();
      expect(find.text('Choose 6 digits.'), findsOneWidget);
      expect(find.text('Tick the box to agree.'), findsOneWidget);
    });

    testWidgets('a scan says what it read, what to type, and fills in the details', (tester) async {
      await open(
        tester,
        server(),
        scanPvc: ({required camera}) async => PvcScan(
          photo: (bytes: _pixel, name: 'pvc.png'),
          fullName: 'Musa Bello',
          delim: '18/23/01/014',
          dateOfBirth: DateTime(1990, 5, 14),
          gender: 'male',
          occupation: 'Teacher',
        ),
      );
      await enterPhone(tester);
      await tester.tap(find.text('Scan PVC'));
      await tester.pumpAndSettle();
      expect(
        find.text('Read from your card: name, polling unit code, date of birth, gender, occupation. '
            'Check each one against the card.'),
        findsOneWidget,
      );
      expect(find.text('Not found on the photo: VIN. Type it from the card.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'VIN (Voter Identification Number)'),
        '90F5B0E8D0295847263',
      );
      await next(tester);
      expect(tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>)).selected, {'male'});
      expect(find.text('Born 14/5/1990'), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);
    });

    group('with a card photo added in a browser', () {
      // A browser cannot read text itself, so the server reads the photo.
      Future<PvcScan?> photoOnly({required bool camera}) async =>
          PvcScan(photo: (bytes: _pixel, name: 'pvc.png'), textRead: false);

      testWidgets('reads it on the server and fills the form', (tester) async {
        final sent = <String>[];
        await open(
          tester,
          server(),
          scanPvc: photoOnly,
          readPvcText: (photo) async {
            sent.add(photo.name);
            // Made-up details in a PVC's layout.
            return [
              'CODE: 18-23-01-014 VIN 90F5 B0E8 D029 5847 263',
              'DELIM: KADUNA | ZARIA',
              'BELLO, MUSA IBRAHIM',
              'DATE OF BIRTH GENDER',
              '14-05-1990 Male',
              'OCCUPATION',
              'TRADER',
            ].join('\n');
          },
        );
        await enterPhone(tester);
        await tester.tap(find.text('Choose photo'));
        await tester.pumpAndSettle();
        expect(sent, ['pvc.png']);
        expect(find.text('Bello Musa Ibrahim'), findsOneWidget);
        expect(find.text('90F5B0E8D0295847263'), findsOneWidget);
        expect(
          find.text('Read from your card: name, VIN, polling unit code, date of birth, gender, '
              'occupation. Check each one against the card.'),
          findsOneWidget,
        );
        expect(find.textContaining('Your polling unit: '), findsOneWidget);

        await next(tester);
        expect(find.text('Born 14/5/1990'), findsOneWidget);
        expect(find.text('Trader'), findsOneWidget);
      });

      testWidgets('that cannot be read asks for the details to be typed', (tester) async {
        await open(
          tester,
          server(),
          scanPvc: photoOnly,
          readPvcText: (photo) async => throw const ApiException(
            503,
            'Reading cards is not set up on this server. Type the details from the card.',
          ),
        );
        await enterPhone(tester);
        await tester.tap(find.text('Choose photo'));
        await tester.pumpAndSettle();
        expect(find.text('Scan again'), findsOneWidget); // the photo is attached
        expect(find.textContaining('Type the details from the card.'), findsOneWidget);
        expect(find.textContaining('Read from your card'), findsNothing);
      });

      testWidgets('gets a plain message from a server that cannot read cards yet', (tester) async {
        await open(
          tester,
          server(),
          scanPvc: photoOnly,
          readPvcText: (photo) async => throw const ApiException(404, 'Not found.'),
        );
        await enterPhone(tester);
        await tester.tap(find.text('Choose photo'));
        await tester.pumpAndSettle();
        expect(
          find.text('Your card could not be read just now. Type the details from the card.'),
          findsOneWidget,
        );
        expect(find.textContaining('Not found'), findsNothing);
      });
    });

    group('the selfie', () {
      Future<void> toSelfie(WidgetTester tester, CheckSelfie checkSelfie) async {
        await open(tester, server(), scanPvc: scanned, checkSelfie: checkSelfie);
        await enterPhone(tester);
        await tester.tap(find.text('Scan PVC'));
        await tester.pumpAndSettle();
        await next(tester);
        expect(find.text('About you (optional)'), findsOneWidget);
      }

      testWidgets('that fails the face check must be taken again or removed', (tester) async {
        final results = [
          const SelfieCheck.failed('More than one face in the photo. Take it with only you in the picture.'),
          const SelfieCheck.passed(),
        ];
        await toSelfie(tester, (_) async => results.removeAt(0));

        await tester.tap(find.text('Take selfie'));
        await tester.pumpAndSettle();
        expect(find.textContaining('More than one face'), findsOneWidget);
        expect(find.text('Use this photo anyway'), findsNothing);
        await next(tester);
        expect(find.text('Take the photo again, or remove it.'), findsOneWidget);
        expect(find.text('About you (optional)'), findsOneWidget);

        await tester.tap(find.text('Take again'));
        await tester.pumpAndSettle();
        expect(find.text('Clear photo: one face, looking at the camera.'), findsOneWidget);
        await next(tester);
        expect(find.text('Choose your PIN'), findsOneWidget);
      });

      testWidgets('can be kept after failing twice, since the check can be wrong', (tester) async {
        await toSelfie(tester, (_) async => const SelfieCheck.failed('No face found.'));
        await tester.tap(find.text('Take selfie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Take again'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this photo anyway'));
        await tester.pump();
        await next(tester);
        expect(find.text('Choose your PIN'), findsOneWidget);
      });

      testWidgets('goes through when the phone cannot check faces', (tester) async {
        await toSelfie(tester, (_) async => const SelfieCheck.notAvailable());
        await tester.tap(find.text('Take selfie'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Clear photo'), findsNothing);
        await next(tester);
        expect(find.text('Choose your PIN'), findsOneWidget);
      });

      testWidgets('is optional, and a failed one can be removed', (tester) async {
        await toSelfie(tester, (_) async => const SelfieCheck.failed('No face found.'));
        await tester.tap(find.text('Take selfie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove photo'));
        await tester.pump();
        expect(find.text('Take selfie'), findsOneWidget);
        await next(tester);
        expect(find.text('Choose your PIN'), findsOneWidget);
      });
    });
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
    // The first page welcomes; signing in opens the form.
    expect(find.text('Welcome to TGCG-EMCOP'), findsOneWidget);
    expect(find.text('New member? Register with your PVC'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot PIN?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '0803 123 4567');
    await tester.enterText(find.byType(TextField).at(1), '482915');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('TGCG Member'), findsOneWidget);
    expect(find.text('TGCG-000123'), findsOneWidget);
  });

  group('who needs an identity check', () {
    Map<String, dynamic> user({String? membershipNumber, bool verified = false, List<String> can = const []}) => {
          'access_id': membershipNumber ?? 'AG-1',
          'full_name': 'Musa Bello',
          'role': 'pollingUnitAgent',
          'scope': {'level': 'pollingUnit', 'country': 'Nigeria', 'pollingUnitId': '18-23-01-014'},
          'capabilities': can,
          'membership_number': membershipNumber,
          'identity_verified': verified,
        };

    test('agents wait for it; members never do', () {
      final waiting = ServerUser.fromJson(user(membershipNumber: 'TGCG-000123'));
      expect(waiting.usesMemberApp, isTrue);
      expect(waiting.roleAwaitingVerification, 'polling unit agent');

      final unlinked = ServerUser.fromJson(user());
      expect(unlinked.usesMemberApp, isFalse);
      expect(unlinked.roleAwaitingVerification, 'polling unit agent');

      final working = ServerUser.fromJson(
        user(membershipNumber: 'TGCG-000123', verified: true, can: ['submitElectionResult']),
      );
      expect(working.usesMemberApp, isFalse);
      expect(working.roleAwaitingVerification, isNull);

      final member = ServerUser.fromJson({...user(membershipNumber: 'TGCG-000124'), 'role': 'member'});
      expect(member.usesMemberApp, isTrue);
      expect(member.roleAwaitingVerification, isNull);
    });

    Future<void> signIn(WidgetTester tester, Map<String, dynamic> account) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server((request) => switch (_path(request)) {
            'auth/login/' => _json({'access': 'A', 'refresh': 'R', 'user': account}),
            'auth/logout/' => _json(<String, Object>{}),
            'me/member/' => _json(_card(verification: 'pendingReview')),
            'me/polling-unit/' => _json({'polling_unit': _unit, 'members_in_unit': 1, 'members_in_ward': 1}),
            'me/announcements/' => _json({'count': 0, 'results': <Object>[]}),
            'me/volunteer/' => _json(<Object>[]),
            _ => null,
          });
      await tester.pumpWidget(TgcgApp(backend: server.connect()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '0803 123 4567');
      await tester.enterText(find.byType(TextField).at(1), '482915');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
    }

    testWidgets('an agent not checked yet gets the member app and is told why', (tester) async {
      await signIn(tester, user(membershipNumber: 'TGCG-000123'));
      expect(find.text('TGCG Member'), findsOneWidget);
      expect(find.textContaining('You are listed as a polling unit agent.'), findsOneWidget);
      expect(find.text('Membership'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('ID check'), findsNothing);
    });

    testWidgets('an agent account that belongs to no member cannot sign in', (tester) async {
      await signIn(tester, user());
      expect(find.textContaining('This polling unit agent account cannot work yet.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  testWidgets('a member asks to move polling unit with their updated card', (tester) async {
    var changes = <Map<String, dynamic>>[];
    final server = _Server((request) => switch (_path(request)) {
          'me/member/' => _json(_card()),
          'me/polling-unit/' => _json({'polling_unit': _unit, 'members_in_unit': 12, 'members_in_ward': 140}),
          'me/announcements/' => _json({'count': 0, 'results': <Object>[]}),
          'me/volunteer/' => _json(<Object>[]),
          'me/polling-unit/changes/' when request.method == 'POST' => () {
              changes = [
                {
                  'id': 'c1',
                  'member': 'TGCG-000123',
                  'member_name': 'Musa Bello',
                  'from_polling_unit': '18-23-01-014',
                  'to_polling_unit': '18-23-01-020',
                  'to_polling_unit_name': 'KOFAR DOKA',
                  'status': 'pending',
                  'reason': '',
                  'decided_by': null,
                  'decided_at': null,
                  'decision_reason': '',
                  'created_at': '2026-10-11T09:00:00Z',
                },
              ];
              return _json(changes.first, 201);
            }(),
          'me/polling-unit/changes/' => _json(changes),
          _ => null,
        });
    await _pump(
      tester,
      server.connect(),
      MemberShell(
        launch: (_) async => true,
        scanPvc: ({required bool camera}) async => PvcScan(
          photo: (bytes: _pixel, name: 'card.png'),
          delim: '18/23/01/020',
        ),
      ),
      member: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('My unit'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Ask to change my polling unit'), 200);
    await tester.tap(find.text('Ask to change my polling unit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan card'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '18/23/01/020'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    final sent = server.bodies['POST /api/v1/me/polling-unit/changes/']!;
    expect(sent, contains('name="delim"'));
    expect(sent, contains('18/23/01/020'));
    expect(sent, contains('name="pvc_image"'));
    expect(find.textContaining('Waiting for review: move to 18-23-01-020'), findsOneWidget);
  });

  testWidgets('a member holding appointments signs in to the operations app', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
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
                'capabilities': ['sendBroadcast', 'viewCommunications'],
                'membership_number': 'TGCG-000123',
                'access': [
                  {
                    'source': 'assignment',
                    'assignment': 'a1',
                    'role': 'kaduna-media-director',
                    'role_name': 'Kaduna Media Director',
                    'protected': false,
                    'areas': [
                      {'level': 'state', 'country': 'Nigeria', 'stateId': 'KD', 'stateName': 'Kaduna'},
                    ],
                    'permissions': ['sendBroadcast', 'viewCommunications'],
                  },
                ],
              },
            }),
          _ => null,
        });
    await tester.pumpWidget(TgcgApp(backend: server.connect()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '0803 123 4567');
    await tester.enterText(find.byType(TextField).at(1), '482915');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // The operations app, with what the appointment allows and nothing else:
    // broadcasting is not built on the server yet, so it is not offered.
    expect(find.text('TGCG Member'), findsNothing);
    expect(find.text('Bulk Communications'), findsNothing);
    expect(find.text('Roles & Access'), findsNothing);
    expect(find.text('Your access'), findsOneWidget);
    expect(find.text('Kaduna Media Director'), findsWidgets);
    // Still a member: the card and the rest of the member app are one tap away.
    expect(find.byTooltip('My membership'), findsOneWidget);
  });
}
