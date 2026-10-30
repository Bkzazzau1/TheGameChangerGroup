import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/sync/server_records.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_worker.dart';

import 'support/redesign_fixtures.dart';

Future<AgentPhone> _start(
  WidgetTester tester, {
  Set<String> capabilities = agentCapabilities,
  String? membershipNumber = 'TGCG-000001',
  SyncPushResult Function()? upload,
  Size size = const Size(390, 844),
}) async {
  useScreen(tester, size);
  final phone = (await tester.runAsync(
    () => AgentPhone.start(
      capabilities: capabilities,
      membershipNumber: membershipNumber,
      upload: upload,
    ),
  ))!;
  addTearDown(() {
    phone.field.dispose();
    phone.results.dispose();
    phone.session.dispose();
  });
  return phone;
}

Future<void> _show(WidgetTester tester, AgentPhone phone) async {
  await tester.pumpWidget(phone.app());
  await tester.pumpAndSettle();
}

Future<void> _reach(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);

/// An incident made on this phone, saved to the outbox.
Future<String> _report(WidgetTester tester, AgentPhone phone) async {
  final incident = await tester.runAsync(
    () => phone.field.createIncident(
      title: 'Materials arrived late',
      category: 'Logistics',
      severity: IncidentSeverity.medium,
      scope: phone.session.scope,
      reporterId: phone.session.accessId,
      summary: 'No ballot boxes yet.',
    ),
  );
  await tester.pump();
  return incident!.id;
}

void main() {
  group('the agent dashboard', () {
    testWidgets('lays out identity, check-in, actions, duty and the countdown', (tester) async {
      final phone = await _start(tester);
      await _show(tester, phone);

      expect(find.text('Musa Bello'), findsOneWidget);
      expect(find.text('AG-00001 · Polling Unit Agent'), findsOneWidget);
      expect(find.text('KWARBAI I'), findsWidgets);
      expect(find.text('KWARBAI "A" · Zaria · Kaduna'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Check in'), findsOneWidget);
      // The urgent actions are on the first screen, with nothing to scroll.
      final bottomBar = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(tester.getBottomLeft(find.text('Report an incident')).dy, lessThan(bottomBar));
      expect(tester.getBottomLeft(find.text('Submit the result')).dy, lessThan(bottomBar));
      for (final tab in ['Home', 'Report', 'Result', 'Meetings', 'Social']) {
        expect(find.widgetWithText(NavigationDestination, tab), findsOneWidget, reason: tab);
      }
      await _reach(tester, find.text('No project now'));
      await _reach(tester, find.textContaining('to the presidential election'));
      expect(find.textContaining("INEC's election calendar"), findsOneWidget);
      await _reach(tester, find.textContaining('Nothing yet.'));
      phone.stop();
    });

    testWidgets('the urgent actions open the right pages', (tester) async {
      final phone = await _start(tester);
      await _show(tester, phone);
      await tester.tap(find.text('Report an incident'));
      await tester.pumpAndSettle();
      expect(find.text('Field Reporting'), findsOneWidget);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit the result'));
      await tester.pumpAndSettle();
      expect(find.text('Result Submission'), findsOneWidget);
      phone.stop();
    });

    testWidgets('once checked in, the button gives way to the time', (tester) async {
      final phone = await _start(tester);
      await tester.runAsync(
        () => phone.field.submitFieldReport(
          category: 'Agent check-in',
          summary: 'Agent checked in for field duty.',
          scope: phone.session.scope,
          reporterId: phone.session.accessId,
        ),
      );
      await _show(tester, phone);
      expect(find.textContaining('Checked in today at'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Check in'), findsNothing);
      phone.stop();
    });
  });

  group('what the server allows', () {
    testWidgets('an agent who may not submit results does not see the button', (tester) async {
      final phone = await _start(tester, capabilities: {'createIncident', 'submitFieldReport'});
      await _show(tester, phone);
      expect(find.text('Report an incident'), findsOneWidget);
      expect(find.text('Submit the result'), findsNothing);
      expect(find.widgetWithText(NavigationDestination, 'Result'), findsNothing);
      expect(find.widgetWithText(NavigationDestination, 'Meetings'), findsNothing);
      await _reach(tester, find.textContaining('Nothing yet.'));
      expect(find.text('Meetings'), findsNothing);
      phone.stop();
    });

    testWidgets('identity checks appear only with the power to do them', (tester) async {
      final phone = await _start(
        tester,
        capabilities: {...agentCapabilities, 'verifyMemberIdentity'},
      );
      await _show(tester, phone);
      await _reach(tester, find.text('Identity checks'));
      expect(find.text('Identity checks'), findsOneWidget);
      phone.stop();
    });

    testWidgets('without the power they stay hidden', (tester) async {
      final phone = await _start(tester);
      await _show(tester, phone);
      await _reach(tester, find.text('My wallet'));
      expect(find.text('Identity checks'), findsNothing);
      phone.stop();
    });

    testWidgets('an account with no membership has no card or wallet', (tester) async {
      final phone = await _start(tester, membershipNumber: null);
      await _show(tester, phone);
      await _reach(tester, find.text('Social Forum'));
      expect(find.text('My membership card'), findsNothing);
      expect(find.text('My wallet'), findsNothing);
      phone.stop();
    });
  });

  group('where a record stands, from the outbox', () {
    testWidgets('never says uploaded before the server has confirmed it', (tester) async {
      final phone = await _start(tester);
      final id = await _report(tester, phone);
      final outbox = phone.offline.outbox.single.id;

      expect(phone.field.uploadState(id), RecordUpload.waiting);
      await _show(tester, phone);
      await _reach(tester, find.text('Materials arrived late'));
      expect(find.text('Waiting to upload'), findsOneWidget);
      expect(find.text('Uploaded'), findsNothing);

      await tester.runAsync(() => phone.offline.markSyncing(outbox));
      await tester.pump();
      expect(phone.field.uploadState(id), RecordUpload.uploading);
      expect(find.text('Uploading'), findsOneWidget);
      expect(find.text('Uploaded'), findsNothing);

      await tester.runAsync(
        () => phone.offline.acknowledge(outboxId: outbox, serverVersion: 1, serverReference: 'S-1'),
      );
      await tester.pump();
      expect(phone.field.uploadState(id), RecordUpload.uploaded);
      expect(find.text('Uploaded'), findsOneWidget);
      phone.stop();
    });

    testWidgets('a record that cannot be sent yet is saved on the phone', (tester) async {
      final phone = await _start(tester);
      await _report(tester, phone);
      phone.sync.setEnabled(true);
      await tester.runAsync(() => phone.sync.syncNow(manual: true));
      await _show(tester, phone);

      // The sync card says why, and the record stays on the phone.
      expect(find.text('1 waiting to upload'), findsOneWidget);
      expect(find.textContaining('No connection.'), findsOneWidget);
      await _reach(tester, find.text('Materials arrived late'));
      expect(find.text('Saved on phone'), findsOneWidget);
      phone.stop();
    });

    testWidgets('a refused record says so, with the reason', (tester) async {
      final phone = await _start(
        tester,
        upload: () =>
            const SyncPushResult.failed(message: 'The polling unit is outside your area.'),
      );
      final id = await _report(tester, phone);
      phone.sync.setEnabled(true);
      await tester.runAsync(() => phone.sync.syncNow(manual: true));
      await _show(tester, phone);

      expect(phone.field.uploadState(id), RecordUpload.refused);
      expect(find.text('1 record was refused by the server.'), findsOneWidget);
      await _reach(tester, find.text('Materials arrived late'));
      expect(find.text('Not accepted'), findsOneWidget);
      expect(find.textContaining('The polling unit is outside your area.'), findsWidgets);
      expect(find.text('Uploaded'), findsNothing);
      phone.stop();
    });
  });

  group('the layout', () {
    for (final width in screenWidths) {
      testWidgets('holds at $width wide', (tester) async {
        final phone = await _start(tester, size: Size(width, 800));
        await _report(tester, phone);
        await _show(tester, phone);
        expect(tester.takeException(), isNull);
        phone.stop();
      });
    }

    testWidgets('wide screens use two columns', (tester) async {
      final phone = await _start(tester, size: const Size(1200, 900));
      await _show(tester, phone);
      final action = tester.getCenter(find.text('Report an incident'));
      final sent = tester.getCenter(find.text('What you have sent'));
      expect(sent.dx, greaterThan(action.dx));
      phone.stop();
    });
  });
}
