import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/app.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_figures.dart';

import 'support/command_fixtures.dart';
import 'support/redesign_fixtures.dart';

// The operations app as a National Administrator uses it, signed in through
// the real login page: what each screen says, and that it holds at each width.
void main() {
  setUpAll(loadMapOnce);

  Future<void> start(
    WidgetTester tester,
    double width, {
    BackendServices? services,
    double height = 4200,
  }) async {
    useScreen(tester, Size(width, height));
    await tester.pumpWidget(TgcgApp(backend: services ?? commandBackend()));
    await signInAsCoordinator(tester, width);
  }

  Future<void> finish(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  for (final width in screenWidths) {
    testWidgets('every command screen holds at $width wide', (tester) async {
      await start(tester, width);

      expect(find.text('Operations Command'), findsOneWidget);
      expect(find.text('NATIONAL COMMAND CENTRE'), findsOneWidget);
      expect(find.text('248,310'), findsOneWidget);
      expect(find.text('339 results awaiting a decision'), findsOneWidget);

      // Men as well as women, and what members do: six groups, then the rest.
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Men'), findsOneWidget);
      expect(find.text('131,000 · 53%'), findsOneWidget);
      expect(find.text('Women'), findsOneWidget);
      expect(find.text('Profession'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('41,200 · 17%'), findsOneWidget);
      expect(find.text('Artisans'), findsNothing);
      expect(find.text('20,510 · 8%'), findsOneWidget); // Other: 9,110 + 7,100 + 4,300
      expect(find.text('66,200 · 27%'), findsOneWidget); // Not given

      await openModule(tester, 'Situation Room', width);
      expect(find.text('LIVE FROM SERVER'), findsOneWidget);
      expect(find.text('Ballot box snatched'), findsWidgets);
      expect(find.text('Acknowledge'), findsOneWidget);

      await openModule(tester, 'Collation', width);
      expect(find.text('UNOFFICIAL: NOT INEC'), findsOneWidget);
      expect(find.text('UNOFFICIAL COUNT'), findsOneWidget);
      expect(find.text('4,218 of 176,846'), findsOneWidget);
      expect(find.textContaining('Unofficial. Verified votes only.'), findsOneWidget);
      expect(find.textContaining('INEC declares the official result'), findsOneWidget);

      await openModule(tester, 'Members & Exco', width);
      expect(find.text('Download list (PDF)'), findsOneWidget);
      expect(find.text('120,450'), findsOneWidget);
      expect(find.text('Positions held most'), findsOneWidget);
      expect(find.text('131,000'), findsOneWidget); // the men's tile
      expect(find.text('Profession'), findsOneWidget);
      expect(find.text('Artisans'), findsOneWidget); // all the groups here
      expect(find.textContaining('50% men · 40% women'), findsWidgets);

      await finish(tester);
    });
  }

  testWidgets('before anything has happened, the screens say so', (tester) async {
    const width = 390.0;
    await start(tester, width, services: commandBackend(quiet: true));
    expect(find.text('Nothing waiting'), findsOneWidget);

    await openModule(tester, 'Situation Room', width);
    expect(find.text('No active incidents'), findsOneWidget);
    expect(find.text('No open incidents in your areas'), findsOneWidget);
    expect(find.text('Nothing selected'), findsOneWidget);
    expect(find.text('No activity yet'), findsOneWidget);

    await openModule(tester, 'Collation', width);
    expect(find.text('NO VERIFIED RESULTS'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);
    expect(find.text('UNOFFICIAL: NOT INEC'), findsOneWidget);

    await openModule(tester, 'Members & Exco', width);
    expect(find.text('No exco here yet.'), findsOneWidget);
    expect(find.text('Profession'), findsNothing);

    await finish(tester);
  });

  testWidgets('with the server down, nothing reads as an all-clear', (tester) async {
    const width = 390.0;
    await start(tester, width, services: commandBackend(down: true));

    expect(find.textContaining('could not be loaded from the server:'), findsOneWidget);
    expect(find.text('Could not be checked'), findsOneWidget);
    expect(find.text('Nothing waiting'), findsNothing);
    expect(find.text('Open incidents'), findsNothing);

    await openModule(tester, 'Situation Room', width);
    expect(find.text('NOT UPDATED'), findsOneWidget);
    expect(find.text('Incidents could not be loaded'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    for (final allClear in ['No active incidents', 'No open incidents in your areas', 'Critical']) {
      expect(find.text(allClear), findsNothing, reason: allClear);
    }

    await openModule(tester, 'Collation', width);
    expect(find.textContaining('Elections could not be loaded'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await openModule(tester, 'Members & Exco', width);
    expect(find.text('The figures could not be loaded'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('an account that cannot see incidents is not told there are none', (tester) async {
    await start(
      tester,
      1200,
      services: commandBackend(capabilities: {'viewCommunications', 'viewCollation'}),
    );
    expect(find.text('Priority events'), findsNothing);
    expect(find.text('Nothing waiting'), findsNothing);
    expect(find.text('Open incidents'), findsNothing);
    await finish(tester);
  });

  testWidgets('a selected pin stays on its place on a narrow phone', (tester) async {
    const width = 320.0;
    await start(tester, width);
    await openModule(tester, 'Situation Room', width);

    Finder pinOf(String title) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is Tooltip && (widget.message ?? '').startsWith(title),
      ),
      matching: find.byIcon(Icons.location_on_rounded),
    );

    // The most severe incident, in Borno, opens selected, its label to the left.
    final selectedPin = tester.getCenter(pinOf('Ballot box snatched'));
    expect(find.text('Maiduguri'), findsOneWidget);

    await tester.tap(find.text('Agents turned away from the unit').first);
    await settleLoads(tester);
    final restingPin = tester.getCenter(pinOf('Ballot box snatched'));
    expect((selectedPin.dx - restingPin.dx).abs(), lessThan(10));

    // East stays east of west.
    expect(restingPin.dx, greaterThan(tester.getCenter(pinOf('Agents turned away')).dx + 100));
    await finish(tester);
  });

  testWidgets('on a phone, choosing from the queue brings the incident into view', (tester) async {
    const width = 360.0;
    const height = 740.0;
    await start(tester, width, height: height);
    await openModule(tester, 'Situation Room', width);

    final queued = find.text('Materials arrived late');
    await tester.dragUntilVisible(queued, find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(queued.first);
    await settleLoads(tester);

    final top = tester.getTopLeft(find.text('Incident inspector')).dy;
    expect(top, inInclusiveRange(0, height));
    await finish(tester);
  });

  group('a thin bar', () {
    Future<double?> fillWidth(WidgetTester tester, double value) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 200, child: TgcgBar(value: value)),
          ),
        ),
      );
      final fill = find.descendant(of: find.byType(TgcgBar), matching: find.byType(Container));
      final boxes = tester.widgetList<Container>(fill).toList();
      return boxes.length < 2 ? null : tester.getSize(fill.last).width;
    }

    testWidgets('shows nothing for nothing, and always shows something', (tester) async {
      expect(await fillWidth(tester, 0), isNull);
      expect(await fillWidth(tester, double.nan), isNull);
      expect(await fillWidth(tester, .0001), 6);
    });

    testWidgets('never runs past its track', (tester) async {
      expect(await fillWidth(tester, .5), 100);
      expect(await fillWidth(tester, 3), 200);
    });
  });
}
