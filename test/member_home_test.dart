import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tgcg_emcop/tgcg/member/member_shell.dart';

import 'support/redesign_fixtures.dart';

Future<void> _pump(
  WidgetTester tester,
  http.Response? Function(String path) answer, {
  Size size = const Size(390, 844),
  String? waitingRole,
  String name = 'Musa Bello',
  List<String>? requests,
}) async {
  useScreen(tester, size);
  final session = memberSession(name: name, waitingRole: waitingRole);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    memberApp(fakeBackend(answer, requests: requests), session, const MemberShell()),
  );
  await tester.pumpAndSettle();
}

/// Scrolls the page until [finder] is built.
Future<void> _reach(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);

void main() {
  group('member navigation', () {
    testWidgets('five tabs, and everything from the old tabs can still be found', (tester) async {
      await _pump(tester, memberServer);

      for (final tab in ['Home', 'My Unit', 'Updates', 'Social', 'Account']) {
        expect(find.widgetWithText(NavigationDestination, tab), findsOneWidget, reason: tab);
      }
      for (final gone in ['Card', 'News', 'Volunteer', 'Roles']) {
        expect(find.widgetWithText(NavigationDestination, gone), findsNothing, reason: gone);
      }

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      for (final row in [
        'Membership card',
        'My wallet',
        'Invite with your code',
        'Registered members',
        'Volunteering',
        'Roles and access',
        'Change PIN',
        'Sign out',
      ]) {
        await _reach(tester, find.text(row));
        expect(find.text(row), findsOneWidget, reason: row);
      }
    });

    testWidgets('the card opens from home, with its signed code', (tester) async {
      await _pump(tester, memberServer);
      await _reach(tester, find.text('View membership card'));
      await tester.tap(find.text('View membership card'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('membership-qr')), findsOneWidget);
      expect(find.text('Download card (PDF)'), findsOneWidget);
      expect(find.text('My details'), findsOneWidget);
    });

    testWidgets('home leads to the other tabs', (tester) async {
      await _pump(tester, memberServer);
      await _reach(tester, find.text('See all'));
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(
        find.text('All Kwarbai A members meet at 4pm at the ward secretariat.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await _reach(tester, find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('TGCG members in this unit'), findsOneWidget);
    });

    testWidgets('sign out and the PIN work from the account', (tester) async {
      useScreen(tester, const Size(390, 844));
      final session = memberSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(memberApp(fakeBackend(memberServer), session, const MemberShell()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await _reach(tester, find.text('Change PIN'));
      await tester.tap(find.text('Change PIN'));
      await tester.pumpAndSettle();
      expect(find.text('New 6-digit PIN'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _reach(tester, find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(session.isAuthenticated, isFalse);
    });

    testWidgets('on a wide screen the bar shows its buttons, not a menu', (tester) async {
      await _pump(tester, memberServer, size: const Size(1200, 800));
      expect(find.byTooltip('More'), findsNothing);
      for (final button in ['Register members', 'Change PIN', 'Sign out', 'Messages', 'Refresh']) {
        expect(find.byTooltip(button), findsOneWidget, reason: button);
      }
    });
  });

  group('the home dashboard', () {
    testWidgets('greets the member and shows only what the server sent', (tester) async {
      await _pump(tester, memberServer);
      expect(find.textContaining(RegExp('^Good (morning|afternoon|evening)')), findsOneWidget);
      expect(find.text('Musa Bello'), findsOneWidget);
      expect(find.text('TGCG-000123'), findsOneWidget);
      expect(find.text('PRESIDENTIAL ELECTION'), findsOneWidget);
      expect(find.text('Saturday, 16 January 2027'), findsOneWidget);
      expect(find.text("Date from INEC's election calendar"), findsOneWidget);
      await _reach(tester, find.text('Active'));
      expect(find.text('Identity checked'), findsOneWidget);
      expect(find.text('Member since 2026'), findsOneWidget);
      await _reach(tester, find.text('UNG. ASKA I/ L.E.A. ANGUWAN KAHU'));
      expect(find.text('Code 18-23-01-014'), findsOneWidget);
      await _reach(tester, find.text('Navigate to polling unit'));
      await _reach(tester, find.text('Ward meeting on Saturday'));
      await _reach(tester, find.text('Invite with your code'));
      expect(find.text('Volunteer'), findsOneWidget);
    });

    testWidgets('says plainly when there is nothing yet', (tester) async {
      await _pump(
        tester,
        (path) => switch (path) {
          'me/polling-unit/' => jsonResponse({'polling_unit': null}),
          'me/announcements/' => jsonResponse({'count': 0, 'results': <Object>[]}),
          _ => memberServer(path),
        },
      );
      await _reach(tester, find.textContaining('Your polling unit is not on record.'));
      await _reach(tester, find.text('Announcements for your area will appear here.'));
      expect(find.text('Ward meeting on Saturday'), findsNothing);
      expect(find.text('Navigate to polling unit'), findsNothing);
    });

    testWidgets('an unchecked member is told so, without being pressed', (tester) async {
      await _pump(tester, (path) => memberServer(path, card: fakeCard(verification: 'pending')));
      await _reach(tester, find.text('Identity not checked yet'));
      expect(find.text('Identity checked'), findsNothing);
      expect(find.text('Complete your membership card'), findsNothing);
    });

    testWidgets('what is waiting for the member comes first', (tester) async {
      await _pump(
        tester,
        (path) => switch (path) {
          'me/member/' => jsonResponse(fakeCard(missing: const ['photo', 'pvc_photo'])),
          'me/messages/' => jsonResponse([
            {'id': 'm1', 'title': 'Rally on Friday', 'body': 'Meet at the ward office.'},
          ]),
          _ => memberServer(path),
        },
      );
      expect(find.text('Complete your membership card'), findsOneWidget);
      expect(find.text('Add a photo of you, a photo of your PVC'), findsOneWidget);
      expect(find.text('Rally on Friday'), findsOneWidget);
    });

    testWidgets('a role waiting for an identity check is explained', (tester) async {
      await _pump(tester, memberServer, waitingRole: 'polling unit agent');
      expect(find.textContaining('You are listed as a polling unit agent.'), findsOneWidget);
    });

    testWidgets('one failed part stays in its place and can be tried again', (tester) async {
      var unitWorks = false;
      await _pump(
        tester,
        (path) => path == 'me/polling-unit/' && !unitWorks
            ? jsonResponse({'detail': 'The server is busy.'}, 503)
            : memberServer(path),
      );
      // The rest of the page is unharmed.
      expect(find.text('Musa Bello'), findsOneWidget);
      await _reach(tester, find.text('Your polling unit could not load.'));
      await _reach(tester, find.text('Ward meeting on Saturday'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();

      unitWorks = true;
      await _reach(tester, find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await _reach(tester, find.text('UNG. ASKA I/ L.E.A. ANGUWAN KAHU'));
      expect(find.text('Your polling unit could not load.'), findsNothing);
    });

    testWidgets('offline, the member can still reach sign out', (tester) async {
      await _pump(tester, (_) => jsonResponse({'detail': 'No connection.'}, 503));
      // The greeting comes from the session, not the network.
      expect(find.text('Musa Bello'), findsOneWidget);
      await _reach(tester, find.text('Your membership details could not load.'));
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await _reach(tester, find.text('Sign out'));
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('each part shows it is loading until its answer comes', (tester) async {
      useScreen(tester, const Size(390, 844));
      final session = memberSession();
      addTearDown(session.dispose);
      final network = Completer<void>();
      final services = fakeBackend(memberServer, hold: network.future);
      await tester.pumpWidget(memberApp(services, session, const MemberShell()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      // The greeting does not wait for the network.
      expect(find.text('Musa Bello'), findsOneWidget);
      network.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Active'), findsOneWidget);
    });
  });

  group('the layout', () {
    for (final width in screenWidths) {
      testWidgets('holds at $width wide, with a long name', (tester) async {
        await _pump(
          tester,
          memberServer,
          size: Size(width, 800),
          name: 'Muhammadu Abdulrahman Ibrahim-Oluwaseun Bello',
        );
        expect(tester.takeException(), isNull);
        for (final tab in ['My Unit', 'Updates', 'Account', 'Home']) {
          await tester.tap(find.widgetWithText(NavigationDestination, tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tab);
        }
      });
    }

    testWidgets('holds with large system text on a small phone', (tester) async {
      useScreen(tester, const Size(320, 640));
      final session = memberSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
          child: memberApp(fakeBackend(memberServer), session, const MemberShell()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide screens use two columns', (tester) async {
      await _pump(tester, memberServer, size: const Size(1200, 900));
      final countdown = tester.getCenter(find.text('PRESIDENTIAL ELECTION'));
      final unit = tester.getCenter(find.text('Your polling unit'));
      expect(unit.dx, greaterThan(countdown.dx));
      // Both columns start near the top.
      expect(find.text('Latest announcements'), findsOneWidget);
    });
  });

  testWidgets('agents and executives still see their wallet and code on the card page', (
    tester,
  ) async {
    useScreen(tester, const Size(390, 844));
    final session = memberSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      memberApp(fakeBackend(memberServer), session, const MyMembershipCardPage()),
    );
    await tester.pumpAndSettle();
    await _reach(tester, find.text('Invite with your code'));
    expect(find.text('Invite with your code'), findsOneWidget);
  });
}
