/// The phone's microphone, shared between sound alerts, which listen in the
/// background while on duty, and recordings made on purpose (a voice note,
/// live video, a call), which take it over until they finish.
class Microphone {
  Microphone._();

  static final instance = Microphone._();

  final _users = <Object>{};
  Future<void> Function()? _pause;
  Future<void> Function()? _resume;

  /// Whether a recording has the microphone now.
  bool get taken => _users.isNotEmpty;

  /// Background listening gives the microphone up through [pause] when a
  /// recording takes it, and gets it back through [resume].
  void lend({required Future<void> Function() pause, required Future<void> Function() resume}) {
    _pause = pause;
    _resume = resume;
  }

  void stopLending() {
    _pause = null;
    _resume = null;
  }

  /// Takes the microphone for [user]; background listening pauses first.
  Future<void> take(Object user) async {
    final first = _users.isEmpty;
    _users.add(user);
    if (first) await _pause?.call();
  }

  /// Gives it back; background listening resumes when nobody else has it.
  Future<void> release(Object user) async {
    if (!_users.remove(user) || _users.isNotEmpty) return;
    await _resume?.call();
  }
}
