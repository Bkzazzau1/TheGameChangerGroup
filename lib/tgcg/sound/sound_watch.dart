import 'dart:typed_data';

import 'sound_detector.dart';
import 'sound_watch_unsupported.dart'
    if (dart.library.io) 'sound_watch_device.dart' as platform;

/// A danger heard, with the last seconds of sound as a WAV clip.
class SoundHeard {
  const SoundHeard(this.danger, this.clip);

  final DangerHeard danger;
  final Uint8List clip;
}

/// The buttons on the listening notification while an alert counts down.
enum AlertAction { sendNow, falseAlarm }

/// Listens to the microphone and runs the sound model on the phone. On
/// Android it keeps listening with the screen locked, as a foreground
/// service with its own notification.
abstract class SoundWatch {
  /// False where the phone cannot listen this way (for example a browser).
  bool get supported;

  /// Starts listening; false when the microphone is not allowed or the
  /// phone would not let it listen in the background.
  Future<bool> start({
    required void Function(SoundHeard heard) onHeard,
    required void Function(AlertAction action) onAction,
  });

  /// Lets another recording use the microphone, keeping the notification.
  Future<void> pause();

  /// Listens again after [pause].
  Future<void> resume();

  Future<void> stop();

  /// Changes the notification shown while listening; while [alerting] it
  /// carries the alert's buttons.
  Future<void> notify(String title, String text, {bool alerting = false});
}

SoundWatch deviceSoundWatch() => platform.deviceSoundWatch();
