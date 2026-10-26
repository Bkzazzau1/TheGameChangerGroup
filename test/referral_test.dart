import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/member/referral.dart';

// The code and link here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('the referral code comes from the link the app was opened with', () {
    expect(referralFromLink(Uri.parse('https://app.tgcg.online/?ref=4827155')), '4827155');
    expect(referralFromLink(Uri.parse('https://app.tgcg.online/?ref=482-7155')), '4827155');
    expect(referralFromLink(Uri.parse('https://app.tgcg.online/?ref=48')), isNull);
    expect(referralFromLink(Uri.parse('https://app.tgcg.online/')), isNull);
  });

  testWidgets('a member shares or copies their code and link', (tester) async {
    final shared = <String>[];
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = BackendServices.connect(
      'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient(
        (request) async => request.url.path.endsWith('/me/referral/')
            ? _json({
                'code': '4827155',
                'link': 'https://app.tgcg.online/?ref=4827155',
                'joined': 3,
                'signed_in': 3,
                'credited': 2,
              })
            : _json({'detail': 'Not found.'}, 404),
      ),
    );
    await tester.pumpWidget(
      TgcgBackend(
        services: services,
        child: MaterialApp(
          home: Scaffold(
            body: ReferralCard(share: (text) async => shared.add(text)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4827155'), findsOneWidget);
    expect(find.text('https://app.tgcg.online/?ref=4827155'), findsOneWidget);
    expect(find.text('3 joined with your code · 2 rewarded'), findsOneWidget);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared.single, contains('4827155'));
    expect(shared.single, contains('https://app.tgcg.online/?ref=4827155'));

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, ['https://app.tgcg.online/?ref=4827155']);
    expect(find.text('Link copied.'), findsOneWidget);
  });
}
