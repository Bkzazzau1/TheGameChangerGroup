import 'dart:async';
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

Map<String, dynamic> _rate({int credits = 1, String naira = '100.00', String minimum = '1000.00'}) => {
  'credits_per_registration': credits,
  'naira_per_credit': naira,
  'min_withdrawal': minimum,
  'reason': '',
  'set_by': null,
  'created_at': null,
};

const _paid = {
  'id': 'e1',
  'kind': 'credit',
  'amount': '5000.50',
  'balance_after': '5000.50',
  'credits': 0,
  'credits_after': 0,
  'purpose': 'PU agent pay',
  'created_at': '2026-10-16T10:00:00Z',
};

const _earned = {
  'id': 'e2',
  'kind': 'reward',
  'amount': '0.00',
  'balance_after': '0.00',
  'credits': 3,
  'credits_after': 3,
  'purpose': 'Registered Bala Musa',
  'created_at': '2026-10-17T10:00:00Z',
};

const _gtbank = {
  'bank': 'gtbank',
  'bank_name': 'Guaranty Trust Bank (GTBank)',
  'account_number': '0123456789',
  'payable': true,
};

Map<String, dynamic> _wallet({
  Map<String, dynamic>? account,
  bool hasWallet = true,
  String balance = '5000.50',
  int credits = 0,
  List<Object> entries = const [_paid],
}) => {
  'membership_number': 'TGCG-000300',
  'has_wallet': hasWallet,
  'account_name': 'Hauwa Sani',
  'balance': balance,
  'credits': credits,
  'credits_worth': '${credits * 100}.00',
  'rate': _rate(),
  'bank_account': account,
  'entries': entries,
};

Map<String, dynamic> _withdrawal({
  String status = 'pending',
  bool canDecide = false,
  bool canCancel = false,
  String failure = '',
}) => {
  'id': 'w1',
  'member': 'TGCG-000300',
  'member_name': 'Hauwa Sani',
  'amount': '1500.00',
  'bank': 'gtbank',
  'bank_name': 'Guaranty Trust Bank (GTBank)',
  'account_number': canDecide ? '******6789' : '0123456789',
  'status': status,
  'created_at': '2026-10-23T10:00:00Z',
  'decided_by': status == 'pending' ? null : 'TGCG-000102',
  'decided_at': null,
  'decision_reason': '',
  'bank_account_name': status == 'pending' ? '' : 'SANI HAUWA',
  'failure_reason': failure,
  'finished_at': null,
  'can_decide': canDecide,
  'can_cancel': canCancel,
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
  FutureOr<http.Response?> Function(String key) answer = (_) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add('$key ${request.url.query}');
      bodies[key] = utf8.decode(await body.toBytes());
      final response = await answer(key) ?? _json({'detail': 'Not found.'}, 404);
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

Future<({_Server server, Completer<http.Response> pending, Finder submit})> _pendingWalletDialog(
  WidgetTester tester,
  String operation,
) async {
  final pending = Completer<http.Response>();
  final server = _Server();
  server.answer = (key) => switch (key) {
    'GET me/wallet/' => _json(_wallet(account: _gtbank, credits: 3)),
    'GET me/wallet/withdrawals/' => _json(_page([])),
    'GET wallets/credit-rates/' => _json({'current': _rate(), 'history': []}),
    'POST me/wallet/convert/' ||
    'POST me/wallet/withdrawals/' ||
    'POST wallets/credit-rates/' => pending.future,
    _ => null,
  };
  if (operation == 'rates') {
    await _pump(tester, server, const WalletPaymentsPage(), can: {'manageCreditRates'});
    await tester.tap(find.text('Change rates'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Synthetic rate correction');
  } else {
    await _pump(tester, server, const MyWalletPage());
    final label = operation == 'convert' ? 'Convert to naira' : 'Withdraw';
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }
  await tester.pump();
  final label = switch (operation) {
    'convert' => 'Convert',
    'withdraw' => 'Send for approval',
    _ => 'Save rates',
  };
  return (server: server, pending: pending, submit: find.widgetWithText(FilledButton, label));
}

void main() {
  for (final operation in ['convert', 'withdraw', 'rates']) {
    testWidgets('$operation submits once and a dismissed response leaves the page open', (
      tester,
    ) async {
      final state = await _pendingWalletDialog(tester, operation);
      final submit = tester.widget<FilledButton>(state.submit).onPressed!;
      submit();
      submit(); // The previous frame's callback must not submit a second time.
      await tester.pump();
      expect(state.server.requests.where((request) => request.startsWith('POST ')), hasLength(1));
      final dialog = tester.element(find.byType(AlertDialog));
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      expect(dialog.mounted, isTrue); // The dismissal animation has not finished.
      expect(ModalRoute.of(dialog)?.isCurrent, isFalse);
      state.pending.complete(
        _json(switch (operation) {
          'convert' => _wallet(account: _gtbank, balance: '5300.50'),
          'withdraw' => _withdrawal(),
          _ => _rate(),
        }),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(operation == 'rates' ? WalletPaymentsPage : MyWalletPage), findsOneWidget);
    });

    testWidgets('$operation ignores a server error after its dialog is disposed', (tester) async {
      final state = await _pendingWalletDialog(tester, operation);
      await tester.tap(state.submit);
      await tester.pump();
      final dialog = tester.element(find.byType(AlertDialog));
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(dialog.mounted, isFalse);
      state.pending.complete(_json({'detail': 'Synthetic request failed.'}, 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(operation == 'rates' ? WalletPaymentsPage : MyWalletPage), findsOneWidget);
    });
  }
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
      'GET me/wallet/withdrawals/' => _json(_page([])),
      'GET wallets/banks/' => _json([
        {'code': 'access', 'name': 'Access Bank', 'payable': true},
        {'code': 'gtbank', 'name': 'Guaranty Trust Bank (GTBank)', 'payable': true},
        {'code': 'lapo', 'name': 'LAPO Microfinance Bank', 'payable': false},
      ]),
      'PUT me/wallet/bank-account/' => _json(_wallet(account: _gtbank)),
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
    // A bank Paystack does not pay is listed, but cannot be chosen.
    final lapo = tester.widget<DropdownMenuItem<String>>(
      find.ancestor(
        of: find.text('LAPO Microfinance Bank (cannot receive withdrawals)').last,
        matching: find.byType(DropdownMenuItem<String>),
      ),
    );
    expect(lapo.enabled, isFalse);
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
    server.answer = (key) => key == 'GET me/wallet/'
        ? _json(_wallet(hasWallet: false, balance: '0.00', entries: const []))
        : null;
    await _pump(tester, server, const MyWalletPage());
    expect(find.text('No wallet yet'), findsOneWidget);
    expect(find.text('Payout account'), findsNothing);
  });

  testWidgets('TGC tokens for registering are kept until the identity is checked', (tester) async {
    final server = _Server();
    server.answer = (key) => key == 'GET me/wallet/'
        ? _json(_wallet(hasWallet: false, balance: '0.00', credits: 3, entries: const [_earned]))
        : null;
    await _pump(tester, server, const MyWalletPage());
    expect(find.text('3 TGC tokens'), findsOneWidget);
    expect(find.text('Worth ₦300.00 today · ₦100.00 each'), findsOneWidget);
    expect(find.text('Registered Bala Musa'), findsOneWidget);
    expect(find.text('+3 TGC tokens'), findsOneWidget);
    expect(find.text('Your wallet opens once your identity is checked.'), findsOneWidget);
    // Converting and withdrawing wait for the identity check.
    expect(find.text('Convert to naira'), findsNothing);
    expect(find.text('Withdraw'), findsNothing);
    expect(find.text('Payout account'), findsNothing);
    expect(server.requests.where((r) => r.startsWith('GET me/wallet/withdrawals/')), isEmpty);
  });

  testWidgets('a verified member converts TGC tokens to naira', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET me/wallet/' => _json(_wallet(account: _gtbank, credits: 3, entries: const [_earned, _paid])),
      'GET me/wallet/withdrawals/' => _json(_page([])),
      'POST me/wallet/convert/' => _json(
        _wallet(
          account: _gtbank,
          balance: '5300.50',
          entries: const [
            {
              'id': 'e3',
              'kind': 'conversion',
              'amount': '300.00',
              'balance_after': '5300.50',
              'credits': -3,
              'credits_after': 0,
              'purpose': 'Converted 3 TGC tokens',
              'created_at': '2026-10-23T10:00:00Z',
            },
            _earned,
            _paid,
          ],
        ),
      ),
      _ => null,
    };
    await _pump(tester, server, const MyWalletPage());
    await tester.ensureVisible(find.text('Convert to naira'));
    await tester.tap(find.text('Convert to naira'));
    await tester.pumpAndSettle();
    expect(find.text('₦300.00'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'TGC tokens'), '2');
    await tester.pump();
    expect(find.text('₦200.00'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'TGC tokens'), '3');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Convert'));
    await tester.pumpAndSettle();

    expect(jsonDecode(server.bodies['POST me/wallet/convert/']!), {'credits': 3});
    expect(find.text('TGC tokens converted. Your balance is ₦5,300.50.'), findsOneWidget);
    expect(find.text('₦5,300.50'), findsWidgets);
    expect(find.text('0 TGC tokens'), findsOneWidget);
    expect(find.text('Converted 3 TGC tokens'), findsOneWidget);
  });

  testWidgets('a member withdraws to the payout account, then cancels', (tester) async {
    var withdrawals = <Object>[];
    var balance = '5000.50';
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET me/wallet/' => _json(_wallet(account: _gtbank, balance: balance)),
      'GET me/wallet/withdrawals/' => _json(_page(withdrawals)),
      'POST me/wallet/withdrawals/' => () {
        balance = '3500.50';
        withdrawals = [_withdrawal(canCancel: true)];
        return _json(_withdrawal(canCancel: true), 201);
      }(),
      'POST me/wallet/withdrawals/w1/cancel/' => () {
        balance = '5000.50';
        withdrawals = [_withdrawal(status: 'cancelled')];
        return _json(_withdrawal(status: 'cancelled'));
      }(),
      _ => null,
    };
    await _pump(tester, server, const MyWalletPage());
    await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
    await tester.pumpAndSettle();
    expect(find.text('Guaranty Trust Bank (GTBank) 0123456789\nHauwa Sani'), findsOneWidget);
    // Below the smallest withdrawal, it cannot be sent.
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '500');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send for approval')).onPressed,
      isNull,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1,500');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send for approval'));
    await tester.pumpAndSettle();

    expect(jsonDecode(server.bodies['POST me/wallet/withdrawals/']!), {'amount': '1500'});
    expect(find.text('Withdrawal of ₦1,500.00 sent for approval.'), findsOneWidget);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('A withdrawal of yours is still being handled.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Withdraw')).onPressed,
      isNull,
    );

    await tester.pump(const Duration(seconds: 5)); // the first message goes
    await tester.ensureVisible(find.text('Cancel withdrawal'));
    await tester.tap(find.text('Cancel withdrawal'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel withdrawal'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST me/wallet/withdrawals/w1/cancel/ '));
    expect(find.text('Withdrawal cancelled.'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('an account at a bank Paystack does not pay cannot be withdrawn to', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET me/wallet/' => _json(
        _wallet(
          account: {
            'bank': 'lapo',
            'bank_name': 'LAPO Microfinance Bank',
            'account_number': '0123456789',
            'payable': false,
          },
        ),
      ),
      'GET me/wallet/withdrawals/' => _json(_page([])),
      _ => null,
    };
    await _pump(tester, server, const MyWalletPage());
    expect(
      find.text('Withdrawals cannot be paid into LAPO Microfinance Bank. Choose another bank.'),
      findsOneWidget,
    );
    expect(find.text('Withdrawals cannot be paid into this bank. Choose another bank.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Withdraw')).onPressed,
      isNull,
    );
  });

  testWidgets('a second person approves or rejects withdrawals', (tester) async {
    var approval = _json(_withdrawal(status: 'processing'));
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET withdrawals/' => _json(_page([_withdrawal(canDecide: true)])),
      'POST withdrawals/w1/approve/' => approval,
      'POST withdrawals/w1/reject/' => _json(_withdrawal(status: 'rejected')),
      _ => null,
    };
    await _pump(tester, server, const WalletPaymentsPage(), can: {'approveWithdrawals'});
    // Withdrawals first, and registrars: no payments are asked for.
    expect(server.requests, contains('GET withdrawals/ status=pending'));
    expect(server.requests.where((r) => r.startsWith('GET wallet-payments/')), isEmpty);
    expect(find.text('Payments'), findsNothing);
    expect(find.text('Registrars'), findsOneWidget);
    expect(find.text('Hauwa Sani (TGCG-000300)'), findsOneWidget);
    expect(find.text('Guaranty Trust Bank (GTBank) ******6789'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Approve and pay this withdrawal?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve and pay'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST withdrawals/w1/approve/ '));
    expect(find.text('Withdrawal approved; the payment is on its way.'), findsOneWidget);

    // Without Paystack on the server, the approval is refused and says why.
    approval = _json({
      'detail': 'Withdrawals cannot be paid yet: Paystack is not set up on the server.',
    }, 503);
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve and pay'));
    await tester.pumpAndSettle();
    expect(
      find.text('Withdrawals cannot be paid yet: Paystack is not set up on the server.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Wrong account');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST withdrawals/w1/reject/']!), {'reason': 'Wrong account'});
    expect(find.text("Withdrawal rejected; the money is back in the member's wallet."), findsOneWidget);
  });

  testWidgets('a National Administrator sets the TGC token rates', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET wallets/credit-rates/' => _json({
        'current': _rate(),
        'history': [
          {
            ..._rate(credits: 2, naira: '50.00'),
            'reason': 'Launch',
            'set_by': 'NA-0001',
            'created_at': '2026-10-20T10:00:00Z',
          },
        ],
      }),
      'POST wallets/credit-rates/' => _json(_rate(credits: 2, naira: '150.00'), 201),
      _ => null,
    };
    await _pump(tester, server, const WalletPaymentsPage(), can: {'manageCreditRates'});
    expect(find.text('Starting rates'), findsOneWidget);
    expect(find.text('₦100.00'), findsOneWidget);
    expect(find.text('₦1,000.00'), findsOneWidget);
    expect(
      find.text('2 TGC tokens a member registered · ₦50.00 a TGC token · withdrawals from ₦1,000.00'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Change rates'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'TGC tokens a member registered'), '2');
    await tester.enterText(find.widgetWithText(TextField, 'Naira a TGC token'), '150');
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'More for registering');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save rates'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST wallets/credit-rates/']!), {
      'credits_per_registration': 2,
      'naira_per_credit': '150',
      'min_withdrawal': '1000.00',
      'reason': 'More for registering',
    });
    expect(find.text('New rates saved.'), findsOneWidget);
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
    for (final power in ['approveWithdrawals', 'manageCreditRates']) {
      final finance = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Finance',
          accessId: 'TGCG-000103',
          scope: GeographicScope.nigeria,
          capabilities: {power},
        );
      addTearDown(finance.dispose);
      expect(finance.modules, contains(TgcgModule.wallets), reason: power);
    }
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
  testWidgets('a registrar sees how many they registered and how many are still to sign in', (
    tester,
  ) async {
    final server = _Server();
    server.answer = (key) => key == 'GET me/wallet/'
        ? _json({
            ..._wallet(hasWallet: false, balance: '0.00', entries: const []),
            'registrations': {'registered': 15, 'signed_in': 3, 'waiting': 12, 'credited': 3},
          })
        : null;
    await _pump(tester, server, const MyWalletPage());
    // Not "No wallet yet": their people are on the way to earning credits.
    expect(find.text('No wallet yet'), findsNothing);
    expect(find.text('You registered 15 people'), findsOneWidget);
    expect(find.text('3 signed in · 12 not signed in yet · 3 rewarded'), findsOneWidget);
  });

  testWidgets('finance staff see who registered how many, and open one registrar', (tester) async {
    Map<String, dynamic> registrar(String id, String name, int registered, int signedIn) => {
      'access_id': id,
      'full_name': name,
      'membership_number': id,
      'scope': {'level': 'lga', 'country': 'Nigeria', 'stateId': 'KD', 'lgaId': 'KD-ZARIA'},
      'identity_verified': id == 'TGCG-000401',
      'registered': registered,
      'signed_in': signedIn,
      'waiting': registered - signedIn,
      'credited': signedIn,
      'credits_earned': signedIn,
      'credits': signedIn,
      'last_registered_at': '2026-10-24T09:00:00Z',
    };
    Map<String, dynamic> person(String number, {bool signedIn = false}) => {
      'membership_number': number,
      'full_name': 'Person $number',
      'scope': {'level': 'country', 'country': 'Nigeria'},
      'registered_at': '2026-10-20T09:00:00Z',
      'signed_in': signedIn,
      'last_sign_in': signedIn ? '2026-10-24T08:00:00Z' : null,
      'credited': signedIn,
      'verification_status': 'unverified',
      'membership_state': 'active',
    };
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET wallet-payments/' => _json(_page([])),
      'GET wallets/registrars/' => _json(
        _page([
          registrar('TGCG-000401', 'Ada Obi', 12, 2),
          registrar('TGCG-000402', 'Bala Umar', 3, 0),
        ]),
      ),
      'GET wallets/registrars/summary/' => _json({
        'registrars': 2,
        'registered': 15,
        'signed_in': 2,
        'waiting': 13,
        'credited': 2,
      }),
      'GET wallets/registrars/TGCG-000401/registered/' => _json(
        server.requests.last.contains('signed_in=false')
            ? _page([person('TGCG-000501')])
            : _page([person('TGCG-000501'), person('TGCG-000502', signedIn: true)]),
      ),
      _ => null,
    };
    await _pump(tester, server, const WalletPaymentsPage(), can: {'viewWallets'});

    // The last section: on a phone the switch scrolls to it.
    await tester.ensureVisible(find.text('Registrars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrars'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('GET wallets/registrars/ ordering=-registered'));
    expect(find.text('13'), findsOneWidget); // not signed in yet, of all
    expect(find.text('Ada Obi'), findsOneWidget);
    expect(find.text('10 not signed in yet'), findsOneWidget);
    expect(find.text('ID not checked'), findsOneWidget); // Bala Umar

    await tester.tap(find.text('Most not signed in yet'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('GET wallets/registrars/ ordering=-waiting'));

    await tester.tap(find.text('Ada Obi'));
    await tester.pumpAndSettle();
    expect(find.text('Person TGCG-000502 (TGCG-000502)'), findsOneWidget);
    expect(find.text('Rewarded'), findsWidgets);
    // Twelve registered, two listed: the rest were placed in other areas.
    expect(find.text('10 registered in other areas are not listed here.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Not signed in yet'));
    await tester.pumpAndSettle();
    expect(
      server.requests,
      contains('GET wallets/registrars/TGCG-000401/registered/ signed_in=false'),
    );
    expect(find.text('Person TGCG-000502 (TGCG-000502)'), findsNothing);
    expect(find.text('Person TGCG-000501 (TGCG-000501)'), findsOneWidget);
  });
}
