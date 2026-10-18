import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'sound_detector.dart';
import 'sound_watch.dart';
import 'wav.dart';

/// YAMNet hears 0.975 s of 16 kHz mono sound at a time; this listens every
/// half second, and keeps the last five seconds for the alert's clip.
const _rate = 16000;
const _window = 15600;
const _hop = _rate ~/ 2;
const _clipBytes = 5 * _rate * 2;

const _alertButtons = [
  NotificationButton(id: 'falseAlarm', text: 'False alarm'),
  NotificationButton(id: 'sendNow', text: 'Send now'),
];

SoundWatch deviceSoundWatch() => _DeviceSoundWatch();

/// Runs in the listening service, so the alert's buttons work from the lock
/// screen; it passes each press to the app.
@pragma('vm:entry-point')
void soundAlertButtons() => FlutterForegroundTask.setTaskHandler(_ButtonRelay());

class _ButtonRelay extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) => FlutterForegroundTask.sendDataToMain(id);
}

class _DeviceSoundWatch implements SoundWatch {
  // Made on first use: only phones that can listen need one.
  late final _recorder = AudioRecorder();
  final _detector = SoundDetector();
  Interpreter? _model;
  IsolateInterpreter? _runner;
  var _inputRank = 1;
  var _outputShape = const [1, 521];
  void Function(SoundHeard heard)? _onHeard;
  void Function(AlertAction action)? _onAction;
  StreamSubscription<Uint8List>? _audio;
  final _samples = Float32List(_window);
  var _filled = 0;
  var _sinceLast = 0;
  var _busy = false;
  final _clip = <Uint8List>[];
  var _clipLength = 0;

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<bool> start({
    required void Function(SoundHeard heard) onHeard,
    required void Function(AlertAction action) onAction,
  }) async {
    if (!supported) return false;
    if (_onHeard != null) return true;
    if (!await _recorder.hasPermission()) return false;
    final model = _model ??= await Interpreter.fromAsset('assets/models/yamnet.tflite');
    _inputRank = model.getInputTensor(0).shape.length;
    _outputShape = model.getOutputTensor(0).shape;
    _runner ??= await IsolateInterpreter.create(address: model.address);
    if (!await _startService()) return false;
    _onHeard = onHeard;
    _onAction = onAction;
    FlutterForegroundTask.addTaskDataCallback(_pressed);
    await _listen();
    return true;
  }

  void _pressed(Object data) {
    final action = switch (data) {
      'sendNow' => AlertAction.sendNow,
      'falseAlarm' => AlertAction.falseAlarm,
      _ => null,
    };
    if (action != null) _onAction?.call(action);
  }

  Future<void> _listen() async {
    if (_audio != null) return;
    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _rate, numChannels: 1),
    );
    _audio = stream.listen(_take, onError: (_) {});
  }

  Future<void> _quiet() async {
    await _audio?.cancel();
    _audio = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    _filled = 0;
    _sinceLast = 0;
    _clip.clear();
    _clipLength = 0;
  }

  void _take(Uint8List chunk) {
    _keepForClip(chunk);
    final pcm = ByteData.sublistView(chunk);
    final count = chunk.length ~/ 2;
    // Slide the window along and add the new samples, scaled to [-1, 1].
    final keep = _window - count;
    if (keep > 0) _samples.setRange(0, keep, _samples, count);
    for (var i = 0; i < count && i < _window; i++) {
      _samples[_window - 1 - i] = pcm.getInt16((count - 1 - i) * 2, Endian.little) / 32768.0;
    }
    _filled = (_filled + count).clamp(0, _window);
    _sinceLast += count;
    if (_filled < _window || _sinceLast < _hop || _busy) return;
    _sinceLast = 0;
    unawaited(_classify());
  }

  void _keepForClip(Uint8List chunk) {
    _clip.add(Uint8List.fromList(chunk));
    _clipLength += chunk.length;
    while (_clipLength - _clip.first.length >= _clipBytes) {
      _clipLength -= _clip.removeAt(0).length;
    }
  }

  Future<void> _classify() async {
    final runner = _runner;
    if (runner == null) return;
    _busy = true;
    try {
      final window = Float32List.fromList(_samples);
      final Object input = _inputRank == 1 ? window : [window];
      final scores = List<double>.filled(_outputShape.last, 0);
      final Object output = _outputShape.length == 1 ? scores : [scores];
      await runner.run(input, output);
      final heard = _detector.listen(scores, DateTime.now());
      final onHeard = _onHeard;
      if (heard != null && onHeard != null && _audio != null) {
        final clip = BytesBuilder(copy: false);
        for (final chunk in _clip) {
          clip.add(chunk);
        }
        onHeard(SoundHeard(heard, wavFromPcm16(clip.takeBytes(), sampleRate: _rate)));
      }
    } catch (_) {
      // A window the model could not take is skipped; listening goes on.
    } finally {
      _busy = false;
    }
  }

  Future<bool> _startService() async {
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      // Vibration, not sound: an agent near danger may need to stay quiet.
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tgcg_sound_alerts',
        channelName: 'Sound alerts',
        channelDescription: 'Danger sounds heard while on duty',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        enableVibration: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      // Listening lives in the app: if the app is closed or killed, the
      // service must not come back on its own and claim to be listening.
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowAutoRestart: false,
      ),
    );
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    final started = await FlutterForegroundTask.startService(
      serviceId: 4242,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: 'Sound alerts on',
      notificationText: 'Listening for gunshots, screaming, a loud crowd or breaking glass.',
      // The status-bar icon named in AndroidManifest.xml.
      notificationIcon: const NotificationIcon(
        metaDataName: 'ng.tgcg.notification_icon',
        backgroundColor: Color(0xFF0A2463),
      ),
      callback: soundAlertButtons,
    );
    return started is ServiceRequestSuccess;
  }

  @override
  Future<void> pause() => _quiet();

  @override
  Future<void> resume() async {
    if (_onHeard != null) await _listen();
  }

  @override
  Future<void> stop() async {
    _onHeard = null;
    _onAction = null;
    FlutterForegroundTask.removeTaskDataCallback(_pressed);
    await _quiet();
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> notify(String title, String text, {bool alerting = false}) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
      notificationButtons: alerting ? _alertButtons : const [],
    );
  }
}
