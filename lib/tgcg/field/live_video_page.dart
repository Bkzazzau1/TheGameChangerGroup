import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../access/access_widgets.dart' show failureMessage;
import '../api/backend.dart';
import '../domain/models.dart';
import '../sound/microphone.dart';
import '../ui/tgcg_design.dart';

Room _createRoom() =>
    Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));

String _clock(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class _LivePill extends StatelessWidget {
  const _LivePill({this.since});

  final DateTime? since;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const TgcgStatusPill(label: 'LIVE', color: TgcgColors.danger, compact: true),
      if (since != null) ...[
        const SizedBox(width: 8),
        Text(
          _clock(DateTime.now().difference(since!)),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ],
    ],
  );
}

/// Broadcasting an incident live from this phone: its camera (the back one
/// first) and microphone go to LiveKit for those who can see the incident to
/// watch, and are recorded onto the incident when recording is set up.
/// Leaving the page ends the live video.
class LiveBroadcastPage extends StatefulWidget {
  const LiveBroadcastPage({super.key, required this.incident, this.createRoom = _createRoom});

  final FieldIncident incident;
  final Room Function() createRoom;

  @override
  State<LiveBroadcastPage> createState() => _LiveBroadcastPageState();
}

class _LiveBroadcastPageState extends State<LiveBroadcastPage> {
  late final Room _room = widget.createRoom();
  var _started = false;
  var _connecting = true;
  var _ending = false;
  var _back = true;
  String? _error;
  DateTime? _since;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _room.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final field = TgcgBackend.of(context)!.field;
    try {
      final pass = await field.goLive(widget.incident.id);
      if (!mounted) return;
      await Microphone.instance.take(this);
      await _room.connect(pass.url, pass.token);
      if (!mounted) return;
      final me = _room.localParticipant;
      await me?.setCameraEnabled(
        true,
        cameraCaptureOptions: const CameraCaptureOptions(cameraPosition: CameraPosition.back),
      );
      await me?.setMicrophoneEnabled(true);
      if (!mounted) return;
      setState(() => _since = DateTime.now());
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    } catch (error) {
      if (mounted) setState(() => _error = failureMessage(error));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _end() async {
    if (_ending) return;
    setState(() => _ending = true);
    _ticker?.cancel();
    final field = TgcgBackend.of(context)!.field;
    if (_since != null) {
      try {
        await field.endLive(widget.incident.id);
      } catch (_) {
        // The server ends it anyway once LiveKit closes the empty room.
      }
    }
    await _room.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _flip() async {
    final track = _camera;
    if (track is! LocalVideoTrack) return;
    _back = !_back;
    await track.setCameraPosition(_back ? CameraPosition.back : CameraPosition.front);
    _changed();
  }

  Future<void> _toggleMicrophone() async {
    final me = _room.localParticipant;
    if (me == null) return;
    await me.setMicrophoneEnabled(!me.isMicrophoneEnabled());
    _changed();
  }

  Track? get _camera => _room.localParticipant?.videoTrackPublications
      .where((item) => !item.isScreenShare && item.track != null)
      .firstOrNull
      ?.track;

  @override
  void dispose() {
    _ticker?.cancel();
    _room.removeListener(_changed);
    unawaited(
      _room
          .disconnect()
          .whenComplete(_room.dispose)
          .whenComplete(() => Microphone.instance.release(this)),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final microphoneOn = _room.localParticipant?.isMicrophoneEnabled() ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_end());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.incident.title, overflow: TextOverflow.ellipsis),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: camera is VideoTrack
                  ? VideoTrackRenderer(camera, fit: VideoViewFit.cover)
                  : Center(
                      child: _connecting
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error ?? 'Starting the camera…',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                    ),
            ),
            if (_since != null)
              Positioned(left: 16, top: 16, child: _LivePill(since: _since)),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (_since != null) ...[
                    IconButton.filledTonal(
                      tooltip: 'Switch camera',
                      onPressed: _flip,
                      icon: const Icon(Icons.cameraswitch_rounded),
                    ),
                    IconButton.filledTonal(
                      tooltip: microphoneOn ? 'Mute the microphone' : 'Unmute the microphone',
                      onPressed: _toggleMicrophone,
                      icon: Icon(microphoneOn ? Icons.mic_rounded : Icons.mic_off_rounded),
                    ),
                  ],
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: TgcgColors.danger),
                    onPressed: _ending ? null : _end,
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(_since == null ? 'Close' : 'End live video'),
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

/// Watching an incident's live video, unseen and without broadcasting.
class LiveWatchPage extends StatefulWidget {
  const LiveWatchPage({super.key, required this.incident, this.createRoom = _createRoom});

  final FieldIncident incident;
  final Room Function() createRoom;

  @override
  State<LiveWatchPage> createState() => _LiveWatchPageState();
}

class _LiveWatchPageState extends State<LiveWatchPage> {
  late final Room _room = widget.createRoom();
  late final EventsListener<RoomEvent> _events = _room.createListener();
  var _started = false;
  var _connecting = true;
  var _ended = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _room.addListener(_changed);
    _events.on<RoomDisconnectedEvent>((_) {
      if (mounted) setState(() => _ended = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final field = TgcgBackend.of(context)!.field;
    try {
      final pass = await field.watchLive(widget.incident.id);
      if (!mounted) return;
      await _room.connect(pass.url, pass.token);
      if (kIsWeb) {
        // A browser plays sound only after a tap; this page opened from one.
        try {
          await _room.startAudio();
        } catch (_) {
          // The video still plays; the sound starts when the page is tapped.
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = failureMessage(error));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  void dispose() {
    _room.removeListener(_changed);
    unawaited(_events.dispose());
    unawaited(_room.disconnect().whenComplete(_room.dispose));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = [
      for (final participant in _room.remoteParticipants.values)
        ...participant.videoTrackPublications.where(
          (item) => !item.isScreenShare && !item.muted && item.track != null,
        ),
    ].firstOrNull?.track;
    final message = _error ??
        (_ended
            ? 'The live video has ended.'
            : _connecting
            ? null
            : 'Waiting for the video…');
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.incident.title, overflow: TextOverflow.ellipsis),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: camera != null && !_ended
                ? VideoTrackRenderer(camera, fit: VideoViewFit.contain)
                : Center(
                    child: message == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                  ),
          ),
          if (!_ended && _error == null)
            const Positioned(left: 16, top: 16, child: _LivePill()),
        ],
      ),
    );
  }
}
