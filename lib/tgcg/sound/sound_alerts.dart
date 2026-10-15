import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../location/gps_service.dart';
import 'microphone.dart';
import 'sound_detector.dart';
import 'sound_watch.dart';

/// An alert to send: what was heard, the recording, and where the phone was.
class SoundAlert {
  const SoundAlert({
    required this.danger,
    required this.clip,
    required this.gps,
    required this.sentByAgent,
    required this.countdown,
  });

  final DangerHeard danger;

  /// The last seconds of sound before the alert, as WAV.
  final Uint8List clip;
  final GpsFix? gps;

  /// True when the agent pressed Send now; false when nobody called it off.
  final bool sentByAgent;
  final Duration countdown;

  /// The incident's account of how it was raised: by the phone's sound
  /// model, which can be wrong, so the recording goes with it.
  String get summary {
    final at = danger.at.toLocal();
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final how = sentByAgent
        ? 'The agent sent it at once.'
        : 'Nobody called it off within ${countdown.inSeconds} seconds.';
    return "Raised by the phone's sound alert at $time "
        '(score ${(danger.confidence * 100).round()}%). $how '
        'The recording is the last seconds before the alert.';
  }
}

enum SoundAlertsState { off, starting, listening, counting, sending }

typedef AlertSender = Future<void> Function(SoundAlert alert);

Future<GpsFix?> _deviceFix() async {
  try {
    return await const GpsService().currentFix(timeout: const Duration(seconds: 20));
  } catch (_) {
    // On duty the phone shares its position every few minutes.
    return DutyTracker.instance.lastFix;
  }
}

const _listeningTitle = 'Sound alerts on';
const _listeningText = 'Listening for gunshots, screaming, a loud crowd or breaking glass.';

/// Sound alerts while on duty: when the phone hears a danger, it counts down
/// so the agent can call off a false alarm, then sends an incident with the
/// recording and the phone's GPS.
class SoundAlerts extends ChangeNotifier {
  SoundAlerts({
    SoundWatch? watch,
    Future<GpsFix?> Function()? locate,
    this.countdown = const Duration(seconds: 15),
  })  : _watch = watch ?? deviceSoundWatch(),
        _locate = locate ?? _deviceFix;

  static final instance = SoundAlerts();

  final SoundWatch _watch;
  final Future<GpsFix?> Function() _locate;
  final Duration countdown;
  AlertSender? _sender;
  var _state = SoundAlertsState.off;
  SoundHeard? _heard;
  Future<GpsFix?>? _where;
  var _secondsLeft = 0;
  Timer? _timer;
  DangerHeard? _lastSent;
  String? _problem;

  bool get supported => _watch.supported;
  SoundAlertsState get state => _state;
  bool get on => _state != SoundAlertsState.off;

  /// The danger counting down or being sent.
  DangerHeard? get alert => _heard?.danger;

  /// Seconds until the alert counting down is sent.
  int get secondsLeft => _secondsLeft;

  /// The last alert sent from this phone.
  DangerHeard? get lastSent => _lastSent;

  /// Why the last alert could not be saved, until the next one.
  String? get problem => _problem;

  /// The app part that turns an alert into an incident.
  void attach(AlertSender sender) => _sender = sender;

  void detach(AlertSender sender) {
    if (_sender == sender) _sender = null;
  }

  /// False when the phone would not let it listen (no microphone permission).
  Future<bool> switchOn() async {
    if (_state != SoundAlertsState.off) return true;
    _set(SoundAlertsState.starting);
    var started = false;
    try {
      started = await _watch.start(onHeard: _heardDanger, onAction: _pressed);
    } catch (_) {
      started = false;
    }
    if (_state != SoundAlertsState.starting) {
      // Switched off while starting.
      if (started) await _watch.stop();
      return false;
    }
    if (!started) {
      _set(SoundAlertsState.off);
      return false;
    }
    Microphone.instance.lend(pause: _watch.pause, resume: _watch.resume);
    if (Microphone.instance.taken) await _watch.pause();
    _set(SoundAlertsState.listening);
    return true;
  }

  Future<void> switchOff() async {
    if (_state == SoundAlertsState.off) return;
    final wasStarting = _state == SoundAlertsState.starting;
    _clearAlert();
    Microphone.instance.stopLending();
    _set(SoundAlertsState.off);
    if (!wasStarting) await _watch.stop();
  }

  void _heardDanger(SoundHeard heard) {
    if (_state != SoundAlertsState.listening) return;
    _heard = heard;
    _problem = null;
    // Finding the phone's position starts now, so it is ready to send. An
    // alert without it still goes.
    _where = Future<GpsFix?>.sync(_locate)
        .then<GpsFix?>((fix) => fix, onError: (Object _) => null);
    _secondsLeft = countdown.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _set(SoundAlertsState.counting);
    unawaited(
      _watch.notify(
        '${heard.danger.kind.label} heard',
        'An alert goes to your coordinators in ${countdown.inSeconds} seconds.',
        alerting: true,
      ),
    );
  }

  void _tick() {
    if (_state != SoundAlertsState.counting) return;
    _secondsLeft--;
    if (_secondsLeft > 0) {
      notifyListeners();
    } else {
      unawaited(_send(byAgent: false));
    }
  }

  void _pressed(AlertAction action) => switch (action) {
        AlertAction.sendNow => sendNow(),
        AlertAction.falseAlarm => falseAlarm(),
      };

  /// Sends the alert without waiting for the countdown.
  void sendNow() {
    if (_state == SoundAlertsState.counting) unawaited(_send(byAgent: true));
  }

  /// Calls the alert off: nothing is sent.
  void falseAlarm() {
    if (_state != SoundAlertsState.counting) return;
    _clearAlert();
    _set(SoundAlertsState.listening);
    unawaited(_watch.notify(_listeningTitle, _listeningText));
  }

  Future<void> _send({required bool byAgent}) async {
    final heard = _heard;
    if (_state != SoundAlertsState.counting || heard == null) return;
    _timer?.cancel();
    _set(SoundAlertsState.sending);
    try {
      final gps = await _where?.timeout(const Duration(seconds: 30), onTimeout: () => null);
      final sender = _sender;
      if (sender == null) {
        _problem = 'The alert was not saved. Report it from the Report tab.';
      } else {
        await sender(
          SoundAlert(
            danger: heard.danger,
            clip: heard.clip,
            gps: gps,
            sentByAgent: byAgent,
            countdown: countdown,
          ),
        );
        _lastSent = heard.danger;
      }
    } catch (error) {
      _problem = 'The alert was not saved: $error';
    }
    _clearAlert();
    if (_state == SoundAlertsState.sending) {
      _set(SoundAlertsState.listening);
      final title = _problem == null
          ? 'Alert sent: ${heard.danger.kind.label}'
          : 'The alert was not saved';
      unawaited(_watch.notify(title, _listeningText));
    } else {
      notifyListeners();
    }
  }

  void _clearAlert() {
    _timer?.cancel();
    _timer = null;
    _heard = null;
    _where = null;
    _secondsLeft = 0;
  }

  void _set(SoundAlertsState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
