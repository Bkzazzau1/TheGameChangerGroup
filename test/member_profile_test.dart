import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/membership/member_profile.dart';
import 'package:tgcg_emcop/tgcg/membership/member_search.dart' show MemberCard;
import 'package:tgcg_emcop/tgcg/membership/membership_store.dart';
import 'package:tgcg_emcop/tgcg/membership/polling_unit_members_page.dart';
import 'package:tgcg_emcop/tgcg/api/access_repository.dart' show RoleDefinition;
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/api/member_admin_repository.dart' show StaffMember;
import 'package:tgcg_emcop/tgcg/session.dart';

import 'support/redesign_fixtures.dart';
import 'support/review_fixtures.dart';

// A member's profile looks the same wherever it is opened, and a member under
// review can be decided from it, by whoever the server says may decide.
void main() {
  const review = {'verifyMemberIdentity'};
  const key = ValueKey('open');

  Future<void> open(
    WidgetTester tester,
    ReviewServer server, {
    Set<String> powers = review,
    Size size = const Size(1200, 1000),
    bool reviewAny = false,
    VoidCallback? onChanged,
  }) async {
    useScreen(tester, size);
    final session = reviewerSession(powers);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      memberApp(
        server.connect(),
        session,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: key,
              onPressed: () => showMemberDetails(
                context,
                reviewedNumber,
                reviewAny: reviewAny,
                onChanged: onChanged,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> decide(WidgetTester tester, String button, String words) async {
    await tester.tap(
      find.widgetWithText(button == 'Approve' ? FilledButton : OutlinedButton, button),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, words);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, button).last);
    await tester.pumpAndSettle();
  }

  group('deciding', () {
    testWidgets('a reviewer approves a member under review', (tester) async {
      final server = ReviewServer();
      var changes = 0;
      await open(tester, server, onChanged: () => changes++);

      expect(find.text('Identity checks'), findsOneWidget);
      expect(find.text('PVC details captured'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);

      await decide(tester, 'Approve', 'Compared the PVC with Bala in person.');

      expect(server.bodies['POST members/$reviewedNumber/verification/approve/'], {
        'notes': 'Compared the PVC with Bala in person.',
      });
      expect(find.text('Identity approved.'), findsOneWidget);
      expect(find.text('Verified'), findsWidgets);
      // Decided: nothing left to press, and the list behind was told.
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(changes, 1);
    });

    testWidgets('a reviewer rejects a member under review, saying why', (tester) async {
      final server = ReviewServer();
      await open(tester, server);

      await decide(tester, 'Reject', 'The face does not match the card.');

      expect(server.bodies['POST members/$reviewedNumber/verification/reject/'], {
        'reason': 'The face does not match the card.',
      });
      expect(find.text('Identity rejected.'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('a refused decision says so and changes nothing', (tester) async {
      final server = ReviewServer(refuseApproval: true);
      var changes = 0;
      await open(tester, server, onChanged: () => changes++);

      await decide(tester, 'Approve', 'Checked in person.');

      expect(find.text('Resolve the failed checks first: card match.'), findsOneWidget);
      expect(find.text('Identity approved.'), findsNothing);
      expect(find.text('Approve'), findsOneWidget); // it can be tried again
      expect(changes, 0);
    });

    testWidgets('cancelling sends nothing', (tester) async {
      final server = ReviewServer();
      await open(tester, server);

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(server.asked('verification/approve/'), isFalse);
      expect(server.status, 'pendingReview');
    });
  });

  group('who is offered the decision', () {
    testWidgets('nobody without the power, and the server is not even asked', (tester) async {
      final server = ReviewServer();
      await open(tester, server, powers: const {'viewMemberSensitiveData'});

      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(server.asked('verification/'), isFalse);
      expect(server.asked('card-photo/'), isFalse);
    });

    testWidgets('nobody the server refuses, even with the power', (tester) async {
      final server = ReviewServer(mayDecide: false);
      await open(tester, server);

      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Identity checks'), findsNothing);
      expect(server.asked('card-photo/'), isFalse);
      expect(find.textContaining('could not be loaded'), findsNothing);
    });

    for (final status in ['verified', 'rejected', 'unverified']) {
      testWidgets('nobody for a member who is $status', (tester) async {
        await open(tester, ReviewServer(status: status));
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Reject'), findsNothing);
      });
    }

    testWidgets('Member Review may still reverse a decision', (tester) async {
      await open(tester, ReviewServer(status: 'verified'), reviewAny: true);
      expect(find.text('Approve'), findsNothing); // already verified
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('and approve someone rejected', (tester) async {
      await open(tester, ReviewServer(status: 'rejected'), reviewAny: true);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsNothing); // already rejected
    });
  });

  group('the photos', () {
    testWidgets('a reviewer sees the selfie and the voter card, large', (tester) async {
      final server = ReviewServer();
      await open(tester, server);

      expect(server.asked('/photo/'), isTrue);
      expect(server.asked('card-photo/'), isTrue);
      expect(find.byKey(const ValueKey('member-card-photo')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('member-photo'))).width, 300);
    });

    testWidgets('a reviewer without personal access still sees what they judge', (tester) async {
      final server = ReviewServer(seesPersonal: false);
      await open(tester, server);

      expect(server.asked('/photo/'), isTrue);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Hidden for your role'), findsOneWidget); // the phone stays hidden
    });

    testWidgets('personal access alone shows the selfie, never the card', (tester) async {
      final server = ReviewServer(status: 'verified');
      await open(tester, server, powers: const {'viewMemberSensitiveData'});

      expect(server.asked('/photo/'), isTrue);
      expect(find.byKey(const ValueKey('member-card-photo')), findsNothing);
    });

    testWidgets('neither access shows no photo and says why', (tester) async {
      final server = ReviewServer(seesPersonal: false, status: 'verified');
      await open(tester, server, powers: const {'registerMembers'});

      expect(server.asked('/photo/'), isFalse);
      expect(find.text('Photo hidden for your role'), findsOneWidget);
    });

    testWidgets('a member with no photos says so', (tester) async {
      final server = ReviewServer(gaps: const ['selfie', 'cardPhoto']);
      await open(tester, server);

      expect(find.text('No photo on record'), findsOneWidget);
      expect(find.byKey(const ValueKey('member-card-photo')), findsNothing);
      expect(find.text('Approve'), findsOneWidget); // the decision does not depend on them
    });

    testWidgets('tapping a photo opens it full screen', (tester) async {
      await open(tester, ReviewServer());

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('member-photo')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('Approve'), findsOneWidget); // back on the profile
    });
  });

  group('assigning a position', () {
    const appoints = {'assignRoles'};

    testWidgets('anyone who appoints can start from the profile', (tester) async {
      await open(tester, ReviewServer(status: 'verified'), powers: appoints);

      await tester.tap(find.text('Assign position'));
      await tester.pumpAndSettle();

      expect(find.text('Appoint a member'), findsOneWidget);
      // This member is already chosen.
      final chosen = tester.widget<TextField>(find.byType(TextField).first);
      expect(chosen.controller!.text, reviewedNumber);
      expect(find.text('Bala Musa'), findsWidgets);
    });

    testWidgets('and the new position shows on the profile', (tester) async {
      useScreen(tester, const Size(1200, 1000));
      final server = ReviewServer(status: 'verified');
      final session = reviewerSession(appoints);
      addTearDown(session.dispose);
      var changes = 0;
      await tester.pumpWidget(
        TgcgBackend(
          services: server.connect(),
          child: TgcgSession(
            controller: session,
            // The area picker reads Nigeria's places from here.
            child: MembershipOperations(
              controller: MembershipOperationsController.prototypeSeed(
                GeographyRegistry.prototypeSeed(),
              ),
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      key: key,
                      onPressed: () =>
                          showMemberDetails(context, reviewedNumber, onChanged: () => changes++),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(find.text('An ordinary member'), findsOneWidget);

      await tester.tap(find.text('Assign position'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<RoleDefinition>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('State Secretary').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add area'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and appoint'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Appoint'));
      await tester.pumpAndSettle();

      expect(server.bodies['POST access/assignments/']!['member'], reviewedNumber);
      expect(find.text('Bala Musa appointed State Secretary.'), findsOneWidget);
      expect(find.text('An ordinary member'), findsNothing);
      expect(find.text('State Secretary'), findsOneWidget);
      expect(changes, 1);
    });

    testWidgets('nobody who does not appoint is offered it', (tester) async {
      await open(tester, ReviewServer(status: 'verified'));
      expect(find.text('Assign position'), findsNothing);
    });

    testWidgets('nobody is offered it on their own profile', (tester) async {
      useScreen(tester, const Size(1200, 1000));
      final server = ReviewServer(status: 'verified');
      final session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Bala Musa',
          accessId: reviewedNumber,
          scope: GeographicScope.nigeria,
          capabilities: appoints,
          membershipNumber: reviewedNumber,
        );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        memberApp(
          server.connect(),
          session,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: key,
                onPressed: () => showMemberDetails(context, reviewedNumber),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(find.text('Assign position'), findsNothing);
    });

    testWidgets('a member not yet verified is told why, not sent to the form', (tester) async {
      final server = ReviewServer();
      await open(tester, server, powers: appoints);

      await tester.tap(find.text('Assign position'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Only a member with a verified identity'), findsOneWidget);
      expect(find.text('Appoint a member'), findsNothing);
      expect(server.bodies.containsKey('POST access/assignments/'), isFalse);
    });

    testWidgets('once approved, the same person can be given a position', (tester) async {
      await open(tester, ReviewServer(), powers: const {'verifyMemberIdentity', 'assignRoles'});

      await decide(tester, 'Approve', 'Checked in person.');
      await tester.ensureVisible(find.text('Assign position'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign position'));
      await tester.pumpAndSettle();

      expect(find.text('Appoint a member'), findsOneWidget);
    });
  });

  group('managing the member from the profile', () {
    const manages = {'assignRoles', 'manageAssignments', 'suspendMembers'};

    Future<void> confirm(WidgetTester tester, String button, String reason) async {
      await tester.tap(find.widgetWithText(OutlinedButton, button));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, reason);
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
    }

    testWidgets('everything is offered at the top, without scrolling', (tester) async {
      await open(tester, ReviewServer(status: 'verified'), powers: manages);
      for (final button in ['Assign position', 'Suspend membership', 'End membership']) {
        expect(tester.getBottomLeft(find.text(button)).dy, lessThan(1000), reason: button);
      }
      expect(tester.getTopLeft(find.text('Assign position')).dy, lessThan(300));
    });

    testWidgets('a membership is suspended, then restored', (tester) async {
      final server = ReviewServer(status: 'verified');
      var changes = 0;
      await open(tester, server, powers: manages, onChanged: () => changes++);

      await confirm(tester, 'Suspend membership', 'Under investigation.');

      expect(server.bodies['POST members/$reviewedNumber/suspend/'], {
        'reason': 'Under investigation.',
      });
      expect(find.text('Membership suspended.'), findsOneWidget);
      expect(find.text('Suspend membership'), findsNothing);
      expect(changes, 1);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Restore membership'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      expect(server.standing, 'active');
      expect(find.text('Membership restored.'), findsOneWidget);
    });

    testWidgets('a membership is ended, with a reason', (tester) async {
      final server = ReviewServer(status: 'verified');
      await open(tester, server, powers: manages);

      await confirm(tester, 'End membership', 'Left the group.');

      expect(server.standing, 'deactivated');
      expect(find.text('Membership ended.'), findsOneWidget);
      expect(find.text('End membership'), findsNothing);
      expect(find.text('Restore membership'), findsOneWidget);
    });

    testWidgets('changing your mind does nothing', (tester) async {
      final server = ReviewServer(status: 'verified');
      await open(tester, server, powers: manages);

      await tester.tap(find.widgetWithText(OutlinedButton, 'End membership'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(server.standing, 'active');
      expect(server.asked('deactivate/'), isFalse);
    });

    testWidgets('a position can be managed and ended here', (tester) async {
      final server = ReviewServer(status: 'verified')
        ..posts.add({'role': 'state-secretary', 'role_name': 'State Secretary', 'state': 'active'});
      await open(tester, server, powers: manages);

      expect(find.text('State Secretary'), findsOneWidget);
      expect(find.text('Assign another position'), findsOneWidget);

      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Term over.');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Close').last);
      await tester.pumpAndSettle();

      expect(server.asked('access/assignments/a1/revoke/'), isTrue);
      expect(find.text('State Secretary'), findsNothing);
      expect(find.text('An ordinary member'), findsOneWidget);
      expect(find.text('Assign position'), findsOneWidget);
    });

    testWidgets('a position still shows to someone who cannot manage it', (tester) async {
      final server = ReviewServer(status: 'verified')
        ..posts.add({'role': 'state-secretary', 'role_name': 'State Secretary', 'state': 'active'});
      await open(tester, server);

      expect(find.text('State Secretary'), findsOneWidget);
      expect(find.text('Manage'), findsNothing);
      expect(server.asked('access/assignments/'), isFalse);
    });

    testWidgets('nothing is offered without the powers', (tester) async {
      await open(tester, ReviewServer(status: 'verified'));
      for (final button in ['Assign position', 'Suspend membership', 'End membership']) {
        expect(find.text(button), findsNothing, reason: button);
      }
    });

    testWidgets('each power brings only its own buttons', (tester) async {
      await open(tester, ReviewServer(status: 'verified'), powers: const {'suspendMembers'});
      expect(find.text('Suspend membership'), findsOneWidget);
      expect(find.text('Assign position'), findsNothing);
    });

    testWidgets('a suspended member cannot be given a position, and is told', (tester) async {
      final server = ReviewServer(status: 'verified', standing: 'suspended');
      await open(tester, server, powers: manages);

      await tester.tap(find.text('Assign position'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Only a member with a verified identity'), findsOneWidget);
      expect(find.text('Appoint a member'), findsNothing);
    });
  });

  for (final width in screenWidths) {
    testWidgets('managing fits at $width wide', (tester) async {
      await open(
        tester,
        ReviewServer(),
        size: Size(width, 700),
        powers: const {'verifyMemberIdentity', 'assignRoles', 'suspendMembers'},
      );
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Assign position'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the decision stays in reach at $width wide', (tester) async {
      final size = Size(width, 640);
      await open(tester, ReviewServer(), size: size);

      final approve = find.widgetWithText(FilledButton, 'Approve');
      final reject = find.widgetWithText(OutlinedButton, 'Reject');
      // The record is far longer than the screen: the buttons do not scroll away.
      expect(tester.getBottomRight(approve).dy, lessThanOrEqualTo(size.height));
      expect(tester.getBottomRight(reject).dy, lessThanOrEqualTo(size.height));
      expect(tester.getBottomRight(approve).dx, lessThanOrEqualTo(size.width));
    });
  }

  group('wherever a member is opened', () {
    Future<void> pumpPage(WidgetTester tester, ReviewServer server, Widget page) async {
      useScreen(tester, const Size(1200, 1000));
      final session = reviewerSession(review);
      addTearDown(session.dispose);
      await tester.pumpWidget(memberApp(server.connect(), session, page));
      await tester.pumpAndSettle();
    }

    testWidgets('from a search result', (tester) async {
      final server = ReviewServer();
      var changes = 0;
      await pumpPage(
        tester,
        server,
        Scaffold(
          body: MemberCard(member: StaffMember.fromJson(server.person), onChanged: () => changes++),
        ),
      );

      await tester.tap(find.text('Bala Musa'));
      await tester.pumpAndSettle();
      await decide(tester, 'Approve', 'Checked in person.');

      expect(server.status, 'verified');
      expect(changes, 1);
    });

    testWidgets('from a polling unit, whose list then shows the decision', (tester) async {
      final server = ReviewServer();
      await pumpPage(
        tester,
        server,
        const PollingUnitMembersPage(code: '18-23-01-001', name: 'KWARBAI I'),
      );
      expect(find.textContaining('Awaiting review'), findsWidgets);

      await tester.tap(find.text('Bala Musa'));
      await tester.pumpAndSettle();
      await decide(tester, 'Approve', 'Checked in person.');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Awaiting review'), findsNothing);
      expect(find.text('Bala Musa'), findsOneWidget); // once, not doubled by the reload
    });
  });
}
