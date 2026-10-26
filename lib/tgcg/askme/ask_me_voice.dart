import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import '../evidence/voice_note.dart';
import '../media/playable_media.dart';

/// The longest spoken question.
const askMeVoiceLimit = Duration(seconds: 60);

/// Ask Me records WAV everywhere: every voice service reads it.
VoiceRecorder askMeRecorder() => deviceVoiceRecorder(wav: true);

/// Plays sound fetched with the session's token (replaced in tests).
abstract class AskMeSpeaker {
  Future<void> play(Uint8List audio, {required String id});
  Future<void> stop();
}

/// What kind of sound [bytes] are, from their first bytes.
String audioType(Uint8List bytes) {
  bool starts(List<int> prefix) =>
      bytes.length >= prefix.length && [for (var i = 0; i < prefix.length; i++) bytes[i]].join(',') == prefix.join(',');
  if (starts('RIFF'.codeUnits)) return 'audio/wav';
  if (starts('ID3'.codeUnits) || starts([0xff, 0xfb]) || starts([0xff, 0xf3])) return 'audio/mpeg';
  if (starts('OggS'.codeUnits)) return 'audio/ogg';
  return 'audio/mp4';
}

class DeviceSpeaker implements AskMeSpeaker {
  VideoPlayerController? _controller;
  Future<void> Function()? _release;

  @override
  Future<void> play(Uint8List audio, {required String id}) async {
    await stop();
    final (controller, release) = await playableMedia(audio, id: id, mimeType: audioType(audio));
    _controller = controller;
    _release = release;
    await controller.initialize();
    await controller.play();
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    final release = _release;
    _controller = null;
    _release = null;
    if (controller != null) {
      await controller.pause();
      await controller.dispose();
    }
    if (release != null) await release();
  }
}
