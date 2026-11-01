// Renders the redesigned screens to build/previews, with real fonts and
// shadows, to look at. Off by default:
//   flutter test --dart-define=TGCG_PREVIEWS=true test/previews_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/popups_repository.dart';
import 'package:tgcg_emcop/tgcg/app.dart';
import 'package:tgcg_emcop/tgcg/election/daily_reminder.dart';
import 'package:tgcg_emcop/tgcg/election/election_countdown.dart';
import 'package:tgcg_emcop/tgcg/login_page.dart';
import 'package:tgcg_emcop/tgcg/member/member_shell.dart';
import 'package:tgcg_emcop/tgcg/membership/member_profile.dart';
import 'package:tgcg_emcop/tgcg/messaging/popup_post_dialog.dart';
import 'package:tgcg_emcop/tgcg/messaging/popups_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_design.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_theme.dart';

import 'support/command_fixtures.dart';
import 'support/redesign_fixtures.dart';
import 'support/review_fixtures.dart';

const _enabled = bool.fromEnvironment('TGCG_PREVIEWS');
const _frame = ValueKey('preview-frame');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter';
  final folder = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('$folder/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final asset in ['assets/brand/tgcg_logo.png', 'assets/brand/login_poster.webp']) {
      await precacheImage(AssetImage(asset), tester.element(find.byKey(_frame)));
    }
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/previews/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget _framed(Widget app) => RepaintBoundary(key: _frame, child: app);

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    await _loadFonts();
    await loadMapOnce();
  });

  for (final width in screenWidths) {
    final size = Size(width, width > 900 ? 860 : 1500);
    final tag = width.round();

    testWidgets('login at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, Size(width, width > 900 ? 860 : 780));
      final session = TgcgSessionController();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        _framed(
          TgcgBackend(
            services: fakeBackend((_) => null),
            child: TgcgSession(
              controller: session,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: tgcgTheme(),
                home: const TgcgLoginPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, 'login-welcome-$tag');
      if (width < 980) {
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Agent or coordinator'));
      await tester.pumpAndSettle();
      await _shot(tester, 'login-agent-$tag');
      debugDisableShadows = true;
    }, skip: !_enabled);

    testWidgets('member at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, size);
      final session = memberSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        _framed(memberApp(fakeBackend(memberServer), session, const MemberShell())),
      );
      await tester.pumpAndSettle();
      await _shot(tester, 'member-home-$tag');
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await _shot(tester, 'member-account-$tag');
      await tester.tap(find.text('Membership card'));
      await tester.pumpAndSettle();
      await _shot(tester, 'member-card-$tag');
      debugDisableShadows = true;
    }, skip: !_enabled);

    testWidgets('agent at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, size);
      final phone = (await tester.runAsync(AgentPhone.start))!;
      addTearDown(() {
        phone.field.dispose();
        phone.results.dispose();
        phone.session.dispose();
      });
      await tester.pumpWidget(_framed(phone.app()));
      await tester.pumpAndSettle();
      await _shot(tester, 'agent-home-$tag');

      // A report that cannot be sent yet stays on the phone, and says so.
      await tester.runAsync(
        () => phone.field.createIncident(
          title: 'Materials arrived late',
          category: 'Logistics',
          severity: IncidentSeverity.medium,
          scope: phone.session.scope,
          reporterId: phone.session.accessId,
          summary: 'No ballot boxes yet.',
        ),
      );
      phone.sync.setEnabled(true);
      await tester.runAsync(() => phone.sync.syncNow(manual: true));
      await tester.pumpAndSettle();
      await _shot(tester, 'agent-offline-$tag');
      phone.stop();
      debugDisableShadows = true;
    }, skip: !_enabled);

  }

  for (final width in [...screenWidths, 1700.0]) {
    final tag = width.round();

    testWidgets('command screens at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, Size(width, width > 900 ? 3400 : 5600));
      await tester.pumpWidget(_framed(TgcgApp(backend: commandBackend())));
      await signInAsCoordinator(tester, width);
      await _shot(tester, 'command-dashboard-$tag');
      await openModule(tester, 'Situation Room', width);
      await _shot(tester, 'command-situation-$tag');
      await openModule(tester, 'Collation', width);
      await _shot(tester, 'command-collation-$tag');
      await openModule(tester, 'Members & Exco', width);
      await _shot(tester, 'command-members-$tag');
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    }, skip: !_enabled);
  }

  for (final size in const [Size(320, 640), Size(390, 844), Size(1200, 860)]) {
    final tag = size.width.round();

    testWidgets('daily reminder at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, size);
      const area = {'level': 'state', 'country': 'Nigeria', 'stateId': 'KD', 'stateName': 'Kaduna'};
      final session = memberSession();
      addTearDown(session.dispose);
      final services = fakeBackend(
        (path) => switch (path) {
          'me/assignments/' => jsonResponse([
            {
              'id': 'a1',
              'member': 'TGCG-000123',
              'member_name': 'Musa Bello',
              'role': 'ward-secretary',
              'role_name': 'Ward Secretary',
              'areas': [area],
              'permissions': <String>[],
              'starts_at': '2026-10-11T08:00:00Z',
              'state': 'active',
            },
          ]),
          'me/projects/' => jsonResponse([
            {
              'id': 'p1',
              'name': 'Ward mobilisation week',
              'starts_at': '2027-01-04T08:00:00Z',
              'ends_at': '2027-01-09T17:00:00Z',
              'status': 'scheduled',
              'my_participation': {
                'id': 'w1',
                'project': 'p1',
                'place': area,
                'status': 'invited',
              },
            },
          ]),
          'me/member/' => jsonResponse(fakeCard(missing: ['pvc_photo'])),
          _ => null,
        },
      );
      await tester.pumpWidget(
        _framed(
          memberApp(
            services,
            session,
            DailyReminder(
              log: MemoryReminderLog(),
              clock: () => DateTime.utc(2026, 11, 1, 9),
              child: const Scaffold(body: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, 'daily-reminder-$tag');
      debugDisableShadows = true;
    }, skip: !_enabled);

    testWidgets('pop-up messages at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, size);
      final picture = File('assets/brand/login_poster.webp').readAsBytesSync();
      const post = PopupPost(
        id: 'p1',
        title: 'Rally at Murtala Square on Saturday',
        body: 'All members are invited. Come with your membership card, and bring a neighbour.',
        frequency: 'daily',
        linkUrl: 'https://tgcg.online/rally',
        linkLabel: 'Read more',
      );
      await tester.pumpWidget(
        _framed(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: tgcgTheme(),
            home: Scaffold(
              backgroundColor: Colors.black54,
              body: Center(child: PopupPostDialog(post: post, picture: picture)),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(MemoryImage(picture), tester.element(find.byType(PopupPostDialog))),
      );
      await tester.pump();
      await _shot(tester, 'popup-post-$tag');

      await tester.pumpWidget(
        _framed(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: tgcgTheme(),
            home: const Scaffold(backgroundColor: Colors.black54, body: PopupFormDialog()),
          ),
        ),
      );
      await _shot(tester, 'popup-form-$tag');
      debugDisableShadows = true;
    }, skip: !_enabled);

    testWidgets('election watch at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, Size(size.width, 760));
      DateTime clock() => DateTime.utc(2026, 11, 1, 9, 14, 22);
      await tester.pumpWidget(
        _framed(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: tgcgTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElectionCountdown(clock: clock),
                    const SizedBox(height: 16),
                    TgcgNavyPanel(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ElectionCountdown(size: ElectionCountdownSize.band, clock: clock),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElectionCountdown(size: ElectionCountdownSize.compact, clock: clock),
                    const SizedBox(height: 16),
                    ElectionCountdown(clock: () => DateTime.utc(2027, 1, 16, 8, 40, 5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await _shot(tester, 'election-watch-$tag');
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    }, skip: !_enabled);
  }

  for (final size in const [Size(360, 740), Size(390, 844), Size(1200, 860)]) {
    final tag = size.width.round();

    testWidgets('member under review at $tag', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, size);
      // Placeholders with a person's and a card's proportions, not real people.
      final server = ReviewServer(
        selfie: File('assets/brand/login_poster.webp').readAsBytesSync(),
        card: File('assets/brand/tgcg_logo.png').readAsBytesSync(),
      )..posts.add({'role': 'state-secretary', 'role_name': 'State Secretary', 'state': 'active'});
      final session = reviewerSession(const {
        'verifyMemberIdentity',
        'viewMemberSensitiveData',
        'assignRoles',
        'manageAssignments',
        'suspendMembers',
      });
      addTearDown(session.dispose);
      await tester.pumpWidget(
        _framed(
          memberApp(
            server.connect(),
            session,
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showMemberDetails(context, reviewedNumber),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      for (var round = 0; round < 6; round++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _shot(tester, 'review-profile-$tag');
      debugDisableShadows = true;
    }, skip: !_enabled);
  }

  for (final (state, services) in [
    ('down', commandBackend(down: true)),
    ('quiet', commandBackend(quiet: true)),
  ]) {
    testWidgets('command screens with the server $state', (tester) async {
      debugDisableShadows = false;
      useScreen(tester, const Size(390, 1800));
      await tester.pumpWidget(_framed(TgcgApp(backend: services)));
      await signInAsCoordinator(tester, 390);
      await _shot(tester, 'command-$state-dashboard');
      await openModule(tester, 'Situation Room', 390);
      await _shot(tester, 'command-$state-situation');
      await openModule(tester, 'Collation', 390);
      await _shot(tester, 'command-$state-collation');
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    }, skip: !_enabled);
  }
}
