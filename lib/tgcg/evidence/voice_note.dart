import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../domain/models.dart';
import '../sound/microphone.dart';
import '../ui/tgcg_design.dart';
import 'evidence_upload.dart';

/// The longest voice note: time to explain, small enough for a weak network.
const voiceNoteLimit = Duration(minutes: 3);

/// Records one voice note on this device.
abstract class VoiceRecorder {
  /// Starts recording; false when the microphone is not allowed.
  Future<bool> start();

  /// The recorded note, or null when nothing was recorded.
  Future<PendingEvidence?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  Future<void> dispose();
}

VoiceRecorder deviceVoiceRecorder() => _DeviceVoiceRecorder();

class _DeviceVoiceRecorder implements VoiceRecorder {
  final _recorder = AudioRecorder();
  var _extension = '.m4a';
  var _mime = 'audio/mp4';

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    // Sound alerts give the microphone up while the note records.
    await Microphone.instance.take(this);
    // Phones record AAC (.m4a); a browser records WAV, which all of them can.
    final aac = !kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.aacLc);
    _extension = aac ? '.m4a' : '.wav';
    _mime = aac ? 'audio/mp4' : 'audio/wav';
    final path = kIsWeb
        ? ''
        : '${(await getTemporaryDirectory()).path}/voice-'
              '${DateTime.now().millisecondsSinceEpoch}$_extension';
    await _recorder.start(
      RecordConfig(
        encoder: aac ? AudioEncoder.aacLc : AudioEncoder.wav,
        numChannels: 1,
        sampleRate: aac ? 44100 : 16000,
        bitRate: 64000,
      ),
      path: path,
    );
    return true;
  }

  @override
  Future<PendingEvidence?> stop() async {
    final path = await _recorder.stop();
    await Microphone.instance.release(this);
    if (path == null) return null;
    final bytes = await XFile(path).readAsBytes();
    if (bytes.isEmpty) return null;
    return evidenceFromBytes(
      type: EvidenceType.audio,
      name: 'voice-note$_extension',
      bytes: bytes,
      mimeType: _mime,
    );
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    await Microphone.instance.release(this);
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
    await Microphone.instance.release(this);
  }
}

String _clock(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

/// A report's voice note: record it, stop, remove it to record again.
class VoiceNoteField extends StatefulWidget {
  const VoiceNoteField({
    super.key,
    required this.note,
    required this.onChanged,
    this.newRecorder = deviceVoiceRecorder,
  });

  final PendingEvidence? note;
  final ValueChanged<PendingEvidence?> onChanged;
  final VoiceRecorder Function() newRecorder;

  @override
  State<VoiceNoteField> createState() => _VoiceNoteFieldState();
}

class _VoiceNoteFieldState extends State<VoiceNoteField> {
  VoiceRecorder? _recorder;
  Timer? _ticker;
  var _elapsed = Duration.zero;
  Duration? _length;
  var _busy = false;

  bool get _recording => _recorder != null;

  @override
  void dispose() {
    _ticker?.cancel();
    final recorder = _recorder;
    if (recorder != null) recorder.cancel().whenComplete(recorder.dispose);
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final recorder = widget.newRecorder();
    try {
      if (!await recorder.start()) {
        await recorder.dispose();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow the microphone to record a voice note.')),
          );
        }
        return;
      }
    } catch (error) {
      await recorder.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The voice note could not be recorded: $error')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) {
      await recorder.cancel();
      await recorder.dispose();
      return;
    }
    setState(() {
      _recorder = recorder;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= voiceNoteLimit) _stop();
    });
  }

  Future<void> _stop() async {
    final recorder = _recorder;
    if (recorder == null) return;
    _ticker?.cancel();
    setState(() {
      _recorder = null;
      _busy = true;
    });
    try {
      final note = await recorder.stop();
      _length = _elapsed;
      widget.onChanged(note);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The voice note could not be saved: $error')),
        );
      }
    } finally {
      await recorder.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Voice note (optional)',
          style: TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (_recording)
          Row(
            children: [
              const Icon(Icons.fiber_manual_record, color: TgcgColors.danger, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_clock(_elapsed)} / ${_clock(voiceNoteLimit)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
              ),
            ],
          )
        else if (note != null)
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, color: TgcgColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Voice note${_length == null ? '' : ' · ${_clock(_length!)}'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Remove the voice note',
                onPressed: () => widget.onChanged(null),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.mic_none_rounded, size: 18),
            label: const Text('Record a voice note'),
          ),
      ],
    );
  }
}
