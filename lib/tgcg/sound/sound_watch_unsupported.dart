import 'sound_watch.dart';

/// Browsers cannot run the sound model or listen with the screen locked.
SoundWatch deviceSoundWatch() => _Unsupported();

class _Unsupported implements SoundWatch {
  @override
  bool get supported => false;

  @override
  Future<bool> start({
    required void Function(SoundHeard heard) onHeard,
    required void Function(AlertAction action) onAction,
  }) async =>
      false;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> notify(String title, String text, {bool alerting = false}) async {}
}
