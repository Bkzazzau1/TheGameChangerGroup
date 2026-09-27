import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'device_media.dart';

/// Live self-view from this device's camera (front camera when available).
/// Opens the camera when shown and releases it when removed.
class LocalCameraView extends StatefulWidget {
  const LocalCameraView({super.key});

  @override
  State<LocalCameraView> createState() => _LocalCameraViewState();
}

class _LocalCameraViewState extends State<LocalCameraView> {
  CameraController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found');
        return;
      }
      final front = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final controller = CameraController(
        cameras[front < 0 ? 0 : front],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = describeDeviceError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Color(0xFF9CB3AB)),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFA7BBB5), fontSize: 10),
            ),
          ],
        ),
      );
    }
    if (controller == null) {
      return const SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      );
    }
    // CameraPreview flips the ratio for portrait phones; mirror that here so
    // the cover crop does not stretch the image.
    final portrait =
        !isDesktopPlatform &&
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final ratio = portrait
        ? 1 / controller.value.aspectRatio
        : controller.value.aspectRatio;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: 480 * ratio,
          height: 480,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
