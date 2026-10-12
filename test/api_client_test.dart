import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/auth_repository.dart';
import 'package:tgcg_emcop/tgcg/api/member_repository.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';

const _user = {
  'access_id': 'TGCG-KD-0001',
  'full_name': 'Amina Kaduna',
  'phone_number': '+2348031234567',
  'email': '',
  'role': 'lgaCoordinator',
  'scope': {
    'level': 'lga',
    'country': 'Nigeria',
    'zoneId': 'NW',
    'zoneName': 'North West',
    'stateId': 'KD',
    'stateName': 'Kaduna',
    'senatorialDistrictId': 'SD/031/KD',
    'senatorialDistrictName': 'Kaduna Central',
    'lgaId': 'KD-KADUNA-NORTH',
    'lgaName': 'Kaduna North',
    'wardId': null,
    'wardName': null,
    'pollingUnitId': null,
    'pollingUnitName': null,
  },
  'capabilities': ['viewIncidents', 'verifyElectionResult'],
};

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

({ApiClient client, AuthRepository auth, MemoryTokenStore tokens, List<http.BaseRequest> log})
    _setup(Future<http.Response> Function(http.Request request) handler) {
  final log = <http.BaseRequest>[];
  final tokens = MemoryTokenStore();
  final client = ApiClient(
    baseUrl: 'https://api.tgcg.test',
    tokens: tokens,
    httpClient: MockClient((request) {
      log.add(request);
      return handler(request);
    }),
  );
  return (client: client, auth: AuthRepository(client), tokens: tokens, log: log);
}

void main() {
  test('login stores tokens and reads role, scope and capabilities', () async {
    final api = _setup((request) async {
      expect(request.url.toString(), 'https://api.tgcg.test/api/v1/auth/login/');
      expect(request.headers['Authorization'], isNull);
      expect(jsonDecode(request.body), {'username': 'TGCG-KD-0001', 'password': 'secret-pass'});
      return _json({'access': 'A1', 'refresh': 'R1', 'user': _user});
    });

    final user = await api.auth.login(identifier: ' TGCG-KD-0001 ', password: 'secret-pass');

    expect(user.role, TgcgRole.lgaCoordinator);
    expect(user.scope.level, GeographyLevel.lga);
    expect(user.scope.lgaId, 'KD-KADUNA-NORTH');
    expect(user.scope.senatorialDistrictId, 'SD/031/KD');
    expect(user.capabilities, {'viewIncidents', 'verifyElectionResult'});
    expect(await api.tokens.read(), (access: 'A1', refresh: 'R1'));
  });

  test('member accounts are recognised but have no operations role', () async {
    final api = _setup((_) async => _json({
          'access': 'A',
          'refresh': 'R',
          'user': {..._user, 'role': 'member', 'capabilities': <String>[]},
        }));
    final user = await api.auth.login(identifier: '08031234567', password: '482915');
    expect(user.role, isNull);
    expect(user.isMember, isTrue);
  });

  test('an expired access token is refreshed once and the call retried', () async {
    var refreshes = 0;
    final api = _setup((request) async {
      if (request.url.path.endsWith('/auth/refresh/')) {
        refreshes++;
        expect(jsonDecode(request.body), {'refresh': 'R1'});
        return _json({'access': 'A2', 'refresh': 'R2'});
      }
      return request.headers['Authorization'] == 'Bearer A2'
          ? _json(_user)
          : _json({'detail': 'Token expired'}, 401);
    });
    await api.tokens.write(access: 'A1', refresh: 'R1');

    // Two calls at once share a single refresh.
    final results = await Future.wait([api.auth.me(), api.auth.me()]);

    expect(results.map((u) => u.accessId), ['TGCG-KD-0001', 'TGCG-KD-0001']);
    expect(refreshes, 1);
    expect(await api.tokens.read(), (access: 'A2', refresh: 'R2'));
  });

  test('a refresh that fails signs the user out', () async {
    var expired = false;
    final api = _setup((request) async => request.url.path.endsWith('/auth/refresh/')
        ? _json({'detail': 'Token is blacklisted'}, 401)
        : _json({'detail': 'Token expired'}, 401));
    api.client.onSessionExpired = () => expired = true;
    await api.tokens.write(access: 'A1', refresh: 'R1');

    await expectLater(api.auth.me(), throwsA(isA<ApiException>()));
    expect(expired, isTrue);
    expect(await api.tokens.read(), isNull);
  });

  test('server validation errors become readable messages', () async {
    final api = _setup((_) async => _json(
          {
            'phone_number': ['This phone number is already registered.'],
            'vin': ['A VIN has 19 letters and digits.'],
          },
          400,
        ));
    try {
      await api.client.post('register/code/', body: {}, authenticated: false);
      fail('expected an ApiException');
    } on ApiException catch (error) {
      expect(error.statusCode, 400);
      expect(error.message, 'This phone number is already registered.');
      expect(error.fieldError('vin'), 'A VIN has 19 letters and digits.');
    }
  });

  test('no connection is reported as offline', () async {
    final api = _setup((_) async => throw http.ClientException('Connection refused'));
    try {
      await api.client.get('health/');
      fail('expected an ApiException');
    } on ApiException catch (error) {
      expect(error.isOffline, isTrue);
      expect(error.message, contains('No connection'));
    }
  });

  group('multipart response deadlines', () {
    testWidgets('the ordinary deadline still applies without an override', (tester) async {
      final client = ApiClient(
        baseUrl: 'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 60));
          return _json({'ok': true});
        }),
      );
      Object? failure;
      unawaited(client.postMultipart('register/', fields: const {}, authenticated: false).then<void>(
        (_) => fail('The ordinary request should time out.'),
        onError: (Object error) => failure = error,
      ));

      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      expect(failure, isA<ApiException>().having((e) => e.isOffline, 'offline', isTrue));
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('an override shares one budget across sending and the body', (tester) async {
      final client = ApiClient(
        baseUrl: 'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        timeout: const Duration(milliseconds: 100),
        httpClient: MockClient.streaming((_, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 6));
          return http.StreamedResponse(
            Stream.fromFuture(Future<List<int>>.delayed(
              const Duration(milliseconds: 6),
              () => utf8.encode('{"ok":true}'),
            )),
            200,
          );
        }),
      );
      Object? failure;
      unawaited(client.postMultipart(
        'register/',
        fields: const {},
        authenticated: false,
        requestTimeout: const Duration(milliseconds: 10),
      ).then<void>(
        (_) => fail('Sending plus reading must fit the same deadline.'),
        onError: (Object error) => failure = error,
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 6));
      await tester.pump(const Duration(milliseconds: 5));
      expect(
        failure,
        isA<ApiException>().having((e) => e.message, 'message', 'The TGCG server did not respond in time.'),
      );
      await tester.pump(const Duration(milliseconds: 6));
    });

    testWidgets('card reading can wait for fallback without extending other uploads', (tester) async {
      final tokens = MemoryTokenStore();
      await tokens.write(access: 'A', refresh: 'R');
      final client = ApiClient(
        baseUrl: 'https://api.tgcg.test',
        tokens: tokens,
        httpClient: MockClient.streaming((request, body) async {
          await body.toBytes();
          if (request.url.path.endsWith('/register/read-pvc/')) {
            expectSync(request.method, 'POST');
            expectSync(request.headers['Authorization'], isNull);
            final photo = (request as http.MultipartRequest).files.single;
            expectSync(photo.field, 'image');
            expectSync(photo.filename, 'card.png');
          }
          await Future<void>.delayed(const Duration(seconds: 60));
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"text":"CODE: 18-23-01-014"}')),
            200,
          );
        }),
      );
      String? text;
      Object? ordinaryFailure;
      unawaited(MemberRepository(client).readPvcText(
        (bytes: Uint8List.fromList([1, 2, 3]), name: 'card.png'),
      ).then<void>((value) => text = value));
      unawaited(client.postMultipart('register/', fields: const {}, authenticated: false).then<void>(
        (_) => fail('Other uploads keep the normal deadline.'),
        onError: (Object error) => ordinaryFailure = error,
      ));

      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      expect(text, isNull);
      expect(ordinaryFailure, isA<ApiException>().having((e) => e.isOffline, 'offline', isTrue));
      await tester.pump(const Duration(seconds: 29));
      expect(text, 'CODE: 18-23-01-014');
    });

    testWidgets('card reading times out at 90 seconds even with an unfinished body', (tester) async {
      final body = StreamController<List<int>>();
      final client = ApiClient(
        baseUrl: 'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient.streaming((_, _) async => http.StreamedResponse(body.stream, 200)),
      );
      Object? failure;
      unawaited(MemberRepository(client).readPvcText(
        (bytes: Uint8List.fromList([1, 2, 3]), name: 'card.png'),
      ).then<void>(
        (_) => fail('An unfinished card-reading response should time out.'),
        onError: (Object error) => failure = error,
      ));

      await tester.pump();
      body.add(utf8.encode('{"text":"'));
      await tester.pump(const Duration(seconds: 89));
      expect(failure, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(
        failure,
        isA<ApiException>()
            .having((e) => e.isOffline, 'offline', isTrue)
            .having((e) => e.message, 'message', 'The TGCG server did not respond in time.'),
      );
      body.add(utf8.encode('CODE: 18-23-01-014"}'));
      await body.close();
    });
  });

  test('restore returns the saved user, or null without a valid session', () async {
    final signedIn = _setup((_) async => _json(_user));
    expect(await signedIn.auth.restore(), isNull); // no saved tokens
    await signedIn.tokens.write(access: 'A', refresh: 'R');
    expect((await signedIn.auth.restore())!.fullName, 'Amina Kaduna');

    final expired = _setup((_) async => _json({'detail': 'expired'}, 401));
    await expired.tokens.write(access: 'A', refresh: 'R');
    expect(await expired.auth.restore(), isNull);
    expect(await expired.tokens.read(), isNull);
  });

  test('logout revokes the refresh token and always forgets it locally', () async {
    final api = _setup((request) async {
      expect(request.url.path, '/api/v1/auth/logout/');
      expect(jsonDecode(request.body), {'refresh': 'R1'});
      return http.Response('', 503);
    });
    await api.tokens.write(access: 'A1', refresh: 'R1');
    await api.auth.logout();
    expect(await api.tokens.read(), isNull);
    expect(api.log, hasLength(1));
  });
}
