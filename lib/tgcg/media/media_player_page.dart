import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../access/access_widgets.dart' show failureMessage;
import 'playable_media.dart';

/// Plays a video or a voice note, downloaded with the session's token.
class MediaPlayerPage extends StatefulWidget {
  const MediaPlayerPage({
    super.key,
    required this.title,
    required this.id,
    required this.mimeType,
    required this.load,
    this.cover,
  });

  final String title;

  /// The file's id on the server, which names its copy on this device.
  final String id;
  final String mimeType;
  final Future<Uint8List> Function() load;

  /// A video's picture, shown while it downloads.
  final Uint8List? cover;

  @override
  State<MediaPlayerPage> createState() => _MediaPlayerPageState();
}

class _MediaPlayerPageState extends State<MediaPlayerPage> {
  VideoPlayerController? _controller;
  Future<void> Function()? _release;
  Object? _error;

  bool get _sound => widget.mimeType.startsWith('audio/');

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final bytes = await widget.load();
      final (controller, release) = await playableMedia(
        bytes,
        id: widget.id,
        mimeType: widget.mimeType,
      );
      _release = release;
      if (!mounted) {
        await release();
        return;
      }
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        await release();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    final release = _release;
    if (controller == null) {
      release?.call();
    } else {
      controller.dispose().then((_) => release?.call());
    }
    super.dispose();
  }

  String _clock(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'It could not be played. ${failureMessage(_error!)}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              )
            : controller == null
            ? Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.cover case final cover?)
                    Opacity(opacity: 0.45, child: Image.memory(cover, fit: BoxFit.contain)),
                  const CircularProgressIndicator(),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: _sound
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 96),
                          )
                        : AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                  ),
                  VideoProgressIndicator(controller, allowScrubbing: true),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          color: Colors.white,
                          iconSize: 40,
                          onPressed: value.isPlaying ? controller.pause : controller.play,
                          icon: Icon(
                            value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          ),
                        ),
                        Text(
                          '${_clock(value.position)} / ${_clock(value.duration)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
