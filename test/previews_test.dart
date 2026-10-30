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
import 'package:tgcg_emcop/tgcg/login_page.dart';
import 'package:tgcg_emcop/tgcg/member/member_shell.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_theme.dart';

import 'support/redesign_fixtures.dart';

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
    if (_enabled) await _loadFonts();
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
}
