import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/election/election_calendar.dart';
import 'package:tgcg_emcop/tgcg/election/election_countdown.dart';

const _election = nextPresidentialElection;

Future<void> _pump(
  WidgetTester tester,
  DateTime Function() clock, {
  ElectionCountdownSize size = ElectionCountdownSize.full,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ElectionCountdown(size: size, clock: clock),
      ),
    ),
  );
}

void main() {
  group('the election date', () {
    test('is the one INEC published, and comes from one place', () {
      expect(_election.date, DateTime.utc(2027, 1, 16));
      expect(_election.fullDate, 'Saturday, 16 January 2027');
      expect(_election.source, contains('INEC'));
      expect(_election.sourceUrl, 'https://www.inecnigeria.org/elections/calendar');
    });
  });

  group('the count, in Nigerian calendar days', () {
    ElectionStatus at(String moment) => ElectionStatus.of(_election, DateTime.parse(moment));

    test('counts whole days ahead', () {
      expect(at('2026-10-30T12:00:00Z').daysLeft, 78);
      expect(at('2026-10-30T12:00:00Z').phase, ElectionPhase.upcoming);
      expect(at('2026-12-31T12:00:00Z').daysLeft, 16);
    });

    test('the day before is one day', () {
      final status = at('2027-01-15T12:00:00Z');
      expect(status.phase, ElectionPhase.upcoming);
      expect(status.daysLeft, 1);
    });

    test('the date changes at midnight in Nigeria, not at midnight UTC', () {
      // 23:59:59 on the 15th in Nigeria.
      expect(at('2027-01-15T22:59:59Z').phase, ElectionPhase.upcoming);
      expect(at('2027-01-15T22:59:59Z').daysLeft, 1);
      // 00:00 on the 16th in Nigeria, while it is still the 15th in UTC.
      expect(at('2027-01-15T23:00:00Z').phase, ElectionPhase.electionDay);
      expect(at('2027-01-15T23:00:00Z').daysLeft, 0);
    });

    test('a phone set to another time zone gets the same answer', () {
      // The same moment written in New York (UTC-5) and Tokyo (UTC+9).
      expect(at('2027-01-15T17:59:59-05:00').daysLeft, 1);
      expect(at('2027-01-16T07:59:59+09:00').daysLeft, 1);
      expect(at('2027-01-15T18:00:00-05:00').phase, ElectionPhase.electionDay);
      expect(at('2027-01-16T08:00:00+09:00').phase, ElectionPhase.electionDay);
    });

    test('election day lasts until midnight in Nigeria', () {
      expect(at('2027-01-16T22:59:59Z').phase, ElectionPhase.electionDay);
      expect(at('2027-01-16T23:00:00Z').phase, ElectionPhase.completed);
    });

    test('never goes below zero', () {
      expect(at('2027-01-17T12:00:00Z').daysLeft, 0);
      expect(at('2030-06-01T12:00:00Z').daysLeft, 0);
      expect(at('2030-06-01T12:00:00Z').phase, ElectionPhase.completed);
    });

    test('next midnight is in Nigeria', () {
      expect(
        nextLagosMidnight(DateTime.parse('2027-01-15T12:00:00Z')),
        DateTime.parse('2027-01-15T23:00:00Z'),
      );
      // Just after midnight in Nigeria: the next one is a day away.
      expect(
        nextLagosMidnight(DateTime.parse('2027-01-15T23:00:01Z')),
        DateTime.parse('2027-01-16T23:00:00Z'),
      );
    });

    test('the hour is the hour in Nigeria', () {
      expect(lagosHour(DateTime.parse('2026-10-30T22:30:00Z')), 23);
      expect(lagosHour(DateTime.parse('2026-10-30T23:30:00Z')), 0);
    });
  });

  group('the countdown', () {
    testWidgets('shows the days, the full date and INEC as the source', (tester) async {
      await _pump(tester, () => DateTime.parse('2026-10-30T12:00:00Z'));
      expect(find.text('78'), findsOneWidget);
      expect(find.text('days to go'), findsOneWidget);
      expect(find.text('Saturday, 16 January 2027'), findsOneWidget);
      expect(find.text("Date from INEC's election calendar"), findsOneWidget);
      expect(find.text('PRESIDENTIAL ELECTION'), findsOneWidget);
    });

    testWidgets('says one day, not one days', (tester) async {
      await _pump(tester, () => DateTime.parse('2027-01-15T12:00:00Z'));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('day to go'), findsOneWidget);
    });

    testWidgets('becomes Election Day, with no count', (tester) async {
      await _pump(tester, () => DateTime.parse('2027-01-16T09:00:00Z'));
      expect(find.text('Election Day'), findsOneWidget);
      expect(find.textContaining('to go'), findsNothing);
      expect(find.text('Saturday, 16 January 2027'), findsOneWidget);
    });

    testWidgets('afterwards says it was held, and never a negative number', (tester) async {
      await _pump(tester, () => DateTime.parse('2027-02-01T09:00:00Z'));
      expect(find.text('Held'), findsOneWidget);
      expect(find.text('Held on Saturday, 16 January 2027'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
      expect(find.textContaining('to go'), findsNothing);
    });

    testWidgets('the compact form says the same in one row', (tester) async {
      await _pump(
        tester,
        () => DateTime.parse('2026-10-30T12:00:00Z'),
        size: ElectionCountdownSize.compact,
      );
      expect(find.text('78 days to the presidential election'), findsOneWidget);
      expect(find.text("Saturday, 16 January 2027 · INEC's election calendar"), findsOneWidget);
    });

    testWidgets('the compact form on election day and after', (tester) async {
      var now = DateTime.parse('2027-01-16T09:00:00Z');
      await _pump(tester, () => now, size: ElectionCountdownSize.compact);
      expect(find.text('Presidential election today'), findsOneWidget);

      now = DateTime.parse('2027-01-20T09:00:00Z');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Presidential election held'), findsOneWidget);
      expect(find.textContaining('Held on Saturday, 16 January 2027'), findsOneWidget);
    });

    testWidgets('the command band says the same, without the words on a card', (tester) async {
      var now = DateTime.parse('2026-10-30T12:00:00Z');
      await _pump(tester, () => now, size: ElectionCountdownSize.band);
      expect(find.text('78'), findsOneWidget);
      expect(find.text('days to the presidential election'), findsOneWidget);
      expect(find.text('Saturday, 16 January 2027'), findsOneWidget);

      now = DateTime.parse('2027-01-15T09:00:00Z');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('day to the presidential election'), findsOneWidget);

      now = DateTime.parse('2027-01-16T09:00:00Z');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Election Day'), findsOneWidget);
      expect(find.text('Presidential election'), findsOneWidget);

      now = DateTime.parse('2027-01-20T09:00:00Z');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Held'), findsOneWidget);
      expect(find.text('Held on Saturday, 16 January 2027'), findsOneWidget);
    });

    testWidgets('moves on by itself at midnight in Nigeria', (tester) async {
      var now = DateTime.parse('2027-01-15T22:59:00Z');
      await _pump(tester, () => now);
      expect(find.text('1'), findsOneWidget);

      // A minute later the phone's clock passes midnight in Nigeria.
      now = DateTime.parse('2027-01-15T23:00:00Z');
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Election Day'), findsOneWidget);
    });

    testWidgets('catches up when the app comes back after days away', (tester) async {
      var now = DateTime.parse('2026-10-30T12:00:00Z');
      await _pump(tester, () => now);
      expect(find.text('78'), findsOneWidget);

      now = DateTime.parse('2026-11-02T12:00:00Z');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('78'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('75'), findsOneWidget);
    });

    testWidgets('fits the narrowest phones, also with large system text', (tester) async {
      for (final moment in [
        '2026-10-30T12:00:00Z',
        '2027-01-16T09:00:00Z',
        '2027-02-01T09:00:00Z',
      ]) {
        for (final size in ElectionCountdownSize.values) {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 700),
                  textScaler: TextScaler.linear(1.3),
                ),
                child: Scaffold(
                  body: ElectionCountdown(size: size, clock: () => DateTime.parse(moment)),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: '$moment $size');
        }
      }
    });
  });
}
