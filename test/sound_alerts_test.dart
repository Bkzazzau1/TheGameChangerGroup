import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/field/field_agent_shell.dart';
import 'package:tgcg_emcop/tgcg/field/field_operations_store.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/results/result_operations_store.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/sound/microphone.dart';
import 'package:tgcg_emcop/tgcg/sound/sound_alerts.dart';
import 'package:tgcg_emcop/tgcg/sound/sound_detector.dart';
import 'package:tgcg_emcop/tgcg/sound/sound_watch.dart';
import 'package:tgcg_emcop/tgcg/sound/wav.dart';

/// One window's scores: [hits] (class index to score), nothing else heard.
List<double> _scores([Map<int, double> hits = const {}]) =>
    [for (var i = 0; i < 521; i++) hits[i] ?? 0];

/// The phone's listening, without a microphone or the model.
class _FakeWatch implements SoundWatch {
  void Function(SoundHeard heard)? _onHeard;
  void Function(AlertAction action)? onAction;
  var allowed = true;
  var listening = false;
  var paused = false;
  final notes = <(String, String, bool)>[];

  @override
  bool get supported => true;

  @override
  Future<bool> start({
    required void Function(SoundHeard heard) onHeard,
    required void Function(AlertAction action) onAction,
  }) async {
    if (!allowed) return false;
    _onHeard = onHeard;
    this.onAction = onAction;
    listening = true;
    return true;
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<void> stop() async {
    listening = false;
    _onHeard = null;
    onAction = null;
  }

  @override
  Future<void> notify(String title, String text, {bool alerting = false}) async {
    notes.add((title, text, alerting));
  }

  void hear(DangerSound kind, {double confidence = .8}) => _onHeard!(
        SoundHeard(
          DangerHeard(kind, confidence, DateTime.now()),
          wavFromPcm16(Uint8List(3200)),
        ),
      );
}

final _fix = GpsFix(
  latitude: 11.0855,
  longitude: 7.7199,
  accuracyMeters: 8,
  capturedAt: DateTime.utc(2027, 2, 25, 10),
);

void main() {
  group('the detector', () {
    final at = DateTime.utc(2027, 2, 25, 10);

    test('one window of gunshots is enough, and one event raises one alert', () {
      final detector = SoundDetector();
      final heard = detector.listen(_scores({421: .7}), at);
      expect(heard?.kind, DangerSound.gunfire);
      expect(heard?.confidence, closeTo(.7, 1e-9));
      // Still shooting a second later: the same event, no second alert.
      expect(detector.listen(_scores({421: .9}), at.add(const Duration(seconds: 1))), isNull);
      final later = at.add(const Duration(minutes: 3, seconds: 1));
      expect(detector.listen(_scores({421: .9}), later)?.kind, DangerSound.gunfire);
    });

    test('screaming must go on for two windows, a crowd for four', () {
      final detector = SoundDetector();
      expect(detector.listen(_scores({11: .8}), at), isNull);
      expect(detector.listen(_scores({11: .8}), at)?.kind, DangerSound.screaming);
      for (var i = 0; i < 3; i++) {
        expect(detector.listen(_scores({64: .9}), at), isNull);
      }
      expect(detector.listen(_scores({64: .9}), at)?.kind, DangerSound.crowd);
    });

    test('a quiet window starts the count again', () {
      final detector = SoundDetector();
      for (final crowd in [true, true, false, true, true, true]) {
        expect(detector.listen(_scores({if (crowd) 64: .9}), at), isNull);
      }
      expect(detector.listen(_scores({64: .9}), at)?.kind, DangerSound.crowd);
    });

    test('breaking glass is heard, faint sounds and celebrations are not', () {
      final detector = SoundDetector();
      expect(detector.listen(_scores({421: .39, 437: .39, 11: .49}), at), isNull);
      // Fireworks, firecrackers, cap guns, cheering, applause and children
      // shouting are common near polling units.
      for (var i = 0; i < 6; i++) {
        final party = _scores({426: .9, 427: .9, 425: .9, 61: .9, 62: .9, 10: .9});
        expect(detector.listen(party, at), isNull);
      }
      expect(detector.listen(_scores({464: .6}), at)?.kind, DangerSound.glass);
    });
  });

  test('the recording is a 16 kHz mono 16-bit WAV file', () {
    final wav = wavFromPcm16(Uint8List.fromList([1, 0, 2, 0]));
    final header = ByteData.sublistView(wav);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(header.getUint32(4, Endian.little), 36 + 4);
    expect(ascii.decode(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(header.getUint16(20, Endian.little), 1); // PCM
    expect(header.getUint16(22, Endian.little), 1); // mono
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(ascii.decode(wav.sublist(36, 40)), 'data');
    expect(header.getUint32(40, Endian.little), 4);
    expect(wav.sublist(44), [1, 0, 2, 0]);
  });

  group('sound alerts', () {
    late _FakeWatch watch;
    late SoundAlerts alerts;
    late List<SoundAlert> sent;
    late int located;

    setUp(() {
      watch = _FakeWatch();
      sent = [];
      located = 0;
      alerts = SoundAlerts(
        watch: watch,
        locate: () async {
          located++;
          return _fix;
        },
      )..attach((alert) async => sent.add(alert));
    });

    tearDown(() async {
      await alerts.switchOff();
      alerts.dispose();
    });

    testWidgets('a danger counts down, then goes with the GPS and the recording', (tester) async {
      expect(await alerts.switchOn(), isTrue);
      expect(alerts.state, SoundAlertsState.listening);

      watch.hear(DangerSound.gunfire);
      expect(alerts.state, SoundAlertsState.counting);
      expect(alerts.alert?.kind, DangerSound.gunfire);
      // The phone starts finding its position at once, and the notification
      // gets the alert's buttons.
      expect(located, 1);
      expect(watch.notes.last.$1, 'Gunshots or an explosion heard');
      expect(watch.notes.last.$3, isTrue);

      await tester.pump(const Duration(seconds: 14));
      expect(sent, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      final alert = sent.single;
      expect(alert.danger.kind, DangerSound.gunfire);
      expect(alert.gps, same(_fix));
      expect(alert.clip.sublist(0, 4), ascii.encode('RIFF'));
      expect(alert.sentByAgent, isFalse);
      expect(alert.summary, contains('Nobody called it off within 15 seconds.'));
      expect(alert.summary, contains('(score 80%)'));
      expect(alerts.state, SoundAlertsState.listening);
      expect(alerts.lastSent?.kind, DangerSound.gunfire);
      expect(watch.notes.last.$1, 'Alert sent: Gunshots or an explosion');
      expect(watch.notes.last.$3, isFalse);
    });

    testWidgets("the notification's False alarm calls it off and Send now sends at once",
        (tester) async {
      await alerts.switchOn();
      watch.hear(DangerSound.glass);
      watch.onAction!(AlertAction.falseAlarm);
      expect(alerts.state, SoundAlertsState.listening);
      expect(watch.notes.last.$3, isFalse);
      await tester.pump(const Duration(seconds: 20));
      expect(sent, isEmpty);

      watch.hear(DangerSound.screaming);
      watch.onAction!(AlertAction.sendNow);
      await tester.pump();
      expect(sent.single.danger.kind, DangerSound.screaming);
      expect(sent.single.sentByAgent, isTrue);
      expect(sent.single.summary, contains('The agent sent it at once.'));
      await tester.pump(const Duration(seconds: 20));
      expect(sent, hasLength(1));
    });

    testWidgets('a danger heard during a countdown does not start another', (tester) async {
      await alerts.switchOn();
      watch.hear(DangerSound.crowd);
      watch.hear(DangerSound.gunfire);
      expect(alerts.alert?.kind, DangerSound.crowd);
      alerts.sendNow();
      await tester.pump();
      expect(sent.single.danger.kind, DangerSound.crowd);
    });

    testWidgets('an alert that cannot be saved says so, and listening goes on', (tester) async {
      alerts.attach((_) async => throw Exception('the phone is full'));
      await alerts.switchOn();
      watch.hear(DangerSound.gunfire);
      alerts.sendNow();
      await tester.pump();
      expect(alerts.problem, contains('the phone is full'));
      expect(alerts.state, SoundAlertsState.listening);
      expect(watch.notes.last.$1, 'The alert was not saved');
    });

    testWidgets('an alert still goes when the phone cannot find its position', (tester) async {
      final lost = SoundAlerts(watch: watch, locate: () async => throw Exception('no signal'))
        ..attach((alert) async => sent.add(alert));
      addTearDown(lost.dispose);
      await lost.switchOn();
      watch.hear(DangerSound.gunfire);
      lost.sendNow();
      await tester.pump();
      expect(sent.single.gps, isNull);
      expect(lost.problem, isNull);
      await lost.switchOff();
    });

    testWidgets('without the microphone it stays off', (tester) async {
      watch.allowed = false;
      expect(await alerts.switchOn(), isFalse);
      expect(alerts.state, SoundAlertsState.off);
      expect(watch.listening, isFalse);
    });

    testWidgets('a voice note, live video or call takes the microphone, then listening resumes',
        (tester) async {
      await alerts.switchOn();
      final note = Object();
      final call = Object();
      await Microphone.instance.take(note);
      await Microphone.instance.take(call);
      expect(watch.paused, isTrue);
      await Microphone.instance.release(note);
      expect(watch.paused, isTrue);
      await Microphone.instance.release(call);
      expect(watch.paused, isFalse);

      await alerts.switchOff();
      expect(watch.listening, isFalse);
      await Microphone.instance.take(note);
      expect(watch.paused, isFalse);
      await Microphone.instance.release(note);
    });
  });

  testWidgets("on the agent's phone the alert covers the screen and becomes an incident",
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = TgcgSessionController()
      ..signInFromServer(
        role: TgcgRole.pollingUnitAgent,
        fullName: 'Musa Bello',
        accessId: 'AG-00001',
        scope: const GeographicScope(
          level: GeographyLevel.pollingUnit,
          country: 'Nigeria',
          stateId: 'KD',
          lgaId: 'KD-ZARIA',
          wardId: '18-23-01',
          pollingUnitId: '18-23-01-001',
          pollingUnitName: 'KWARBAI I',
        ),
        capabilities: {'createIncident', 'submitFieldReport', 'submitElectionResult'},
      );
    final field = FieldOperationsController.prototypeSeed();
    final results = ResultOperationsController.prototypeSeed();
    final watch = _FakeWatch();
    final alerts = SoundAlerts(watch: watch, locate: () async => _fix);
    addTearDown(() {
      alerts.dispose();
      field.dispose();
      results.dispose();
      session.dispose();
    });
    final before = field.incidents.length;
    await alerts.switchOn();

    await tester.pumpWidget(
      TgcgSession(
        controller: session,
        child: OfflinePersistence(
          controller: OfflinePersistenceController(),
          child: FieldOperations(
            controller: field,
            child: ResultOperations(
              controller: results,
              child: MaterialApp(home: FieldAgentShell(soundAlerts: alerts)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sound alerts on'), findsOneWidget);
    expect(find.text('Listening, also with the screen locked'), findsOneWidget);

    watch.hear(DangerSound.gunfire, confidence: .91);
    await tester.pump();
    expect(find.text('Gunshots or an explosion heard'), findsOneWidget);
    expect(find.text('Sending an alert in 15 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Sending an alert in 12 s'), findsOneWidget);

    await tester.tap(find.text('Send now'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Gunshots or an explosion heard'), findsNothing);

    expect(field.incidents, hasLength(before + 1));
    final incident = field.incidents.first;
    expect(incident.title, 'Sound alert: Gunshots or an explosion');
    expect(incident.category, 'Violence / threat');
    expect(incident.severity, IncidentSeverity.critical);
    expect(incident.origin, RecordOrigin.systemDerived);
    expect(incident.reporterId, 'AG-00001');
    expect(incident.scope.pollingUnitId, '18-23-01-001');
    expect(incident.gps, same(_fix));
    expect(incident.summary, contains('(score 91%)'));
    expect(incident.evidence.single.type, EvidenceType.audio);
    expect(incident.evidence.single.fileName, 'sound-alert.wav');
    expect(find.textContaining('Last alert'), findsOneWidget);

    // A false alarm sends nothing.
    watch.hear(DangerSound.glass);
    await tester.pump();
    await tester.tap(find.text('False alarm'));
    await tester.pumpAndSettle();
    expect(find.text('Breaking glass heard'), findsNothing);
    expect(field.incidents, hasLength(before + 1));

    // Off duty, switched off: the switch waits for duty.
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(watch.listening, isFalse);
    expect(find.text('Works while you are on duty'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).last).onChanged, isNull);
  });
}
