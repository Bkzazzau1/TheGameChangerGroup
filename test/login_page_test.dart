import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/login_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_theme.dart';

import 'support/redesign_fixtures.dart';

Future<TgcgSessionController> _pump(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  useScreen(tester, size);
  final session = TgcgSessionController();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: fakeBackend((path) => jsonResponse({'detail': 'Wrong.'}, 401)),
      child: TgcgSession(
        controller: session,
        child: MaterialApp(theme: tgcgTheme(), home: const TgcgLoginPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index));

void main() {
  testWidgets('the ways in stay on screen on the smallest phones', (tester) async {
    await _pump(tester, size: const Size(320, 568));
    final bottom = tester.getBottomLeft(find.text('New member? Register with your PVC')).dy;
    expect(bottom, lessThan(568));
    expect(tester.getBottomLeft(find.text('Sign in')).dy, lessThan(bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('members sign in with a phone number and PIN', (tester) async {
    await _pump(tester);
    await _openForm(tester);

    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);
    expect(_field(tester, 0).keyboardType, TextInputType.phone);
    expect(_field(tester, 1).keyboardType, TextInputType.number);
    expect(_field(tester, 1).obscureText, isTrue);
  });

  testWidgets('agents and coordinators sign in with an access ID and password', (tester) async {
    await _pump(tester);
    await _openForm(tester);
    await tester.tap(find.text('Agent or coordinator'));
    await tester.pumpAndSettle();

    expect(find.text('Access ID or phone number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Phone number'), findsNothing);
    expect(_field(tester, 0).keyboardType, TextInputType.text);
    expect(_field(tester, 1).keyboardType, TextInputType.text);
    expect(_field(tester, 1).obscureText, isTrue);
  });

  testWidgets('what was typed stays when the choice changes', (tester) async {
    await _pump(tester);
    await _openForm(tester);
    await tester.enterText(find.byType(TextField).at(0), 'TGCG-KD-0001');
    await tester.tap(find.text('Agent or coordinator'));
    await tester.pumpAndSettle();
    expect(find.text('TGCG-KD-0001'), findsOneWidget);
  });

  testWidgets('an empty form says what is missing, for each choice', (tester) async {
    await _pump(tester);
    await _openForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your phone number and PIN.'), findsOneWidget);

    await tester.tap(find.text('Agent or coordinator'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-error')), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your access ID or phone number and password.'), findsOneWidget);
  });

  testWidgets('the password can be shown and hidden', (tester) async {
    await _pump(tester);
    await _openForm(tester);
    await tester.tap(find.byTooltip('Show'));
    await tester.pump();
    expect(_field(tester, 1).obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide'));
    await tester.pump();
    expect(_field(tester, 1).obscureText, isTrue);
  });

  for (final width in screenWidths) {
    testWidgets('holds at $width wide', (tester) async {
      await _pump(tester, size: Size(width, 700));
      expect(tester.takeException(), isNull);
      if (width < 980) await _openForm(tester);
      await tester.tap(find.text('Agent or coordinator'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
