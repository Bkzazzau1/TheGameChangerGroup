import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';
import 'device_media.dart';

enum CameraCaptureMode { photo, video }

/// Full-screen in-app camera. Pops with the captured [XFile], or null when
/// the operator cancels.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    required this.mode,
    this.maxDuration,
    this.preferFront = false,
  });

  final CameraCaptureMode mode;
  final Duration? maxDuration;
  final bool preferFront;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _busy = false;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _error;

  bool get _video => widget.mode == CameraCaptureMode.video;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera was found on this device.');
        return;
      }
      final wanted = widget.preferFront
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final preferred = cameras.indexWhere((c) => c.lensDirection == wanted);
      _cameras = cameras;
      await _open(preferred < 0 ? 0 : preferred);
    } catch (error) {
      if (mounted) setState(() => _error = describeDeviceError(error));
    }
  }

  Future<void> _open(int index) async {
    final previous = _controller;
    setState(() {
      _controller = null;
      _cameraIndex = index;
      _error = null;
    });
    await previous?.dispose();
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: _video,
    );
    try {
      await controller.initialize();
    } catch (error) {
      await controller.dispose();
      if (mounted) setState(() => _error = describeDeviceError(error));
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  Future<void> _shutter() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    if (!_video) {
      setState(() => _busy = true);
      try {
        final file = await controller.takePicture();
        if (mounted) Navigator.pop(context, file);
      } catch (error) {
        _fail(error);
      }
      return;
    }
    if (_recording) {
      await _stopRecording();
      return;
    }
    setState(() => _busy = true);
    try {
      await controller.startVideoRecording();
      _elapsed = Duration.zero;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        final limit = widget.maxDuration;
        if (limit != null && _elapsed >= limit) _stopRecording();
      });
      setState(() {
        _recording = true;
        _busy = false;
      });
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null || !_recording) return;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final file = await controller.stopVideoRecording();
      if (mounted) Navigator.pop(context, file);
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(describeDeviceError(error))));
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final limit = widget.maxDuration;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: _recording ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _video ? 'Record video evidence' : 'Take photo evidence',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (_recording)
                    TgcgStatusPill(
                      label: limit == null
                          ? _format(_elapsed)
                          : '${_format(_elapsed)} / ${_format(limit)}',
                      color: TgcgColors.danger,
                      icon: Icons.fiber_manual_record_rounded,
                      compact: true,
                    ),
                  if (_cameras.length > 1)
                    IconButton(
                      tooltip: 'Switch camera',
                      onPressed: _recording || _busy
                          ? null
                          : () => _open((_cameraIndex + 1) % _cameras.length),
                      icon: const Icon(
                        Icons.cameraswitch_rounded,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.no_photography_outlined,
                              color: Colors.white70,
                              size: 48,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _start,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Try again'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : controller == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: CameraPreview(controller),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
              child: Semantics(
                button: true,
                label: _video
                    ? (_recording ? 'Stop recording' : 'Start recording')
                    : 'Take photo',
                child: GestureDetector(
                  onTap: controller == null || _busy ? null : _shutter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 76,
                    height: 76,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: controller == null || _busy
                            ? Colors.white30
                            : _video
                            ? TgcgColors.danger
                            : Colors.white,
                        borderRadius: BorderRadius.circular(
                          _recording ? 8 : 40,
                        ),
                      ),
                      margin: EdgeInsets.all(_recording ? 12 : 0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
