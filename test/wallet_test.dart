import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/wallet_repository.dart';
import 'package:tgcg_emcop/tgcg/member/wallet_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/wallets/wallet_payments_page.dart';

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _page(List<Object> results) =>
    {'count': results.length, 'next': null, 'previous': null, 'results': results};

Map<String, dynamic> _wallet({Map<String, dynamic>? account, bool hasWallet = true}) => {
  'membership_number': 'TGCG-000300',
  'has_wallet': hasWallet,
  'account_name': 'Hauwa Sani',
  'balance': '5000.50',
  'bank_account': account,
  'entries': [
    {
      'id': 'e1',
      'kind': 'credit',
      'amount': '5000.50',
      'balance_after': '5000.50',
      'purpose': 'PU agent pay',
      'created_at': '2026-10-16T10:00:00Z',
    },
  ],
};

Map<String, dynamic> _payment({String status = 'pending', bool canDecide = false}) => {
  'id': 'p1',
  'member': 'TGCG-000300',
  'member_name': 'Hauwa Sani',
  'amount': '1500.00',
  'purpose': 'Transport',
  'status': status,
  'requested_by': 'TGCG-000101',
  'created_at': '2026-10-16T10:00:00Z',
  'decided_by': status == 'pending' ? null : 'TGCG-000102',
  'decided_at': null,
  'decision_reason': '',
  'can_decide': canDecide,
  'can_cancel': false,
};

class _Server {
  final requests = <String>[];
  final bodies = <String, String>{};
  http.Response? Function(String key) answer = (_) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add('$key ${request.url.query}');
      bodies[key] = utf8.decode(await body.toBytes());
      final response = answer(key) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}

Future<void> _pump(WidgetTester tester, _Server server, Widget page, {Set<String>? can}) async {
  tester.view.physicalSize = const Size(360, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController();
  if (can != null) {
    session.signInFromServer(
      fullName: 'Kaduna Finance',
      accessId: 'TGCG-000102',
      scope: const GeographicScope(level: GeographyLevel.state, country: 'Nigeria', stateId: 'KD'),
      capabilities: can,
    );
  }
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: TgcgSession(
        controller: session,
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('amounts show in naira with thousands grouped', () {
    expect(formatNaira('5000.50'), '₦5,000.50');
    expect(formatNaira('1000000.00'), '₦1,000,000.00');
    expect(formatNaira('250'), '₦250.00');
    expect(formatNaira('0.00'), '₦0.00');
  });

  testWidgets('a member adds the payout account; its name is theirs and fixed', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET me/wallet/' => _json(_wallet()),
      'GET wallets/banks/' => _json([
        {'code': 'access', 'name': 'Access Bank'},
        {'code': 'gtbank', 'name': 'Guaranty Trust Bank (GTBank)'},
      ]),
      'PUT me/wallet/bank-account/' => _json(
        _wallet(
          account: {
            'bank': 'gtbank',
            'bank_name': 'Guaranty Trust Bank (GTBank)',
            'account_number': '0123456789',
          },
        ),
      ),
      _ => null,
    };
    await _pump(tester, server, const MyWalletPage());

    expect(find.text('₦5,000.50'), findsWidgets);
    expect(find.text('PU agent pay'), findsOneWidget);
    expect(find.text('Hauwa Sani'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    final name = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(name.enabled, isFalse);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Hauwa Sani')), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guaranty Trust Bank (GTBank)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Account number'), '0123456789');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(jsonDecode(server.bodies['PUT me/wallet/bank-account/']!), {
      'bank': 'gtbank',
      'account_number': '0123456789',
    });
    expect(find.text('Guaranty Trust Bank (GTBank)'), findsOneWidget);
    expect(find.text('0123456789'), findsOneWidget);
  });

  testWidgets('a member whose identity is not checked has no wallet yet', (tester) async {
    final server = _Server();
    server.answer = (key) => key == 'GET me/wallet/' ? _json(_wallet(hasWallet: false)) : null;
    await _pump(tester, server, const MyWalletPage());
    expect(find.text('No wallet yet'), findsOneWidget);
    expect(find.text('Payout account'), findsNothing);
  });

  testWidgets('finance staff request payments and a second person approves', (tester) async {
    var status = 'pending';
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET wallet-payments/' => _json(_page([_payment(status: status, canDecide: true)])),
      'POST wallet-payments/' => _json(_payment(), 201),
      'POST wallet-payments/p1/approve/' => () {
        status = 'approved';
        return _json(_payment(status: status));
      }(),
      _ => null,
    };
    await _pump(
      tester,
      server,
      const WalletPaymentsPage(),
      can: {'viewWallets', 'creditWallets', 'approveWalletCredits'},
    );
    expect(server.requests, contains('GET wallet-payments/ status=pending'));
    expect(find.text('Hauwa Sani (TGCG-000300)'), findsOneWidget);
    expect(find.text('₦1,500.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Approve this payment?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST wallet-payments/p1/approve/ '));
    expect(find.text('Payment approved.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'New payment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Membership number'), 'TGCG-000300');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1,500');
    await tester.enterText(find.widgetWithText(TextField, 'What it is for'), 'Transport');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send for approval'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST wallet-payments/']!), {
      'member': 'TGCG-000300',
      'amount': '1500',
      'purpose': 'Transport',
    });
  });

  test('wallet permissions open the Wallets page', () {
    final session = TgcgSessionController()
      ..signInFromServer(
        fullName: 'Kaduna Finance',
        accessId: 'TGCG-000102',
        scope: GeographicScope.nigeria,
        capabilities: {'approveWalletCredits'},
      );
    addTearDown(session.dispose);
    expect(session.modules, contains(TgcgModule.wallets));
    final member = TgcgSessionController()
      ..signInFromServer(
        fullName: 'Hauwa Sani',
        accessId: 'TGCG-000300',
        scope: GeographicScope.nigeria,
        capabilities: const {},
      );
    addTearDown(member.dispose);
    expect(member.modules, isNot(contains(TgcgModule.wallets)));
  });
}
