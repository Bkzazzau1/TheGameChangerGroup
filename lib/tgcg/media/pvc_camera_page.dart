import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/tgcg_design.dart';
import 'card_scan_guide.dart';
import 'device_media.dart';
import 'unmirror.dart';

/// What a PVC's photo is called, whatever the camera named it: a browser's
/// camera gives it no name, and the server ignores an upload without one.
const voterCardPhotoName = 'voter-card.jpg';

/// The camera for the front of a PVC, as identity checks do it: the
/// picture fills the screen, the card's frame shows where the card goes,
/// and the photo is checked before it is used. Pops with the photo, or null
/// when the person cancels.
class PvcCameraPage extends StatefulWidget {
  const PvcCameraPage({super.key, this.otherCamera});

  /// Another way to take the photo (the phone's camera app), offered when
  /// this camera cannot start.
  final Future<XFile?> Function()? otherCamera;

  /// Every PVC camera page's camera work starts afresh (tests only).
  @visibleForTesting
  static void forgetCameraWork() => _PvcCameraPageState._work = Future.value();

  @override
  State<PvcCameraPage> createState() => _PvcCameraPageState();
}

class _PvcCameraPageState extends State<PvcCameraPage>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  // Each opening of a camera; only the latest may keep its camera.
  int _opening = 0;
  // Camera work in turn, an opening or a letting go each after the last, for
  // every PVC camera page: on Android letting any camera go stops the one in
  // use, even a page's opened after it.
  static Future<void> _work = Future.value();
  // Let go in the background, to open again on return (or on Retake, when a
  // photo is being checked). A permission prompt only makes the app
  // inactive, and the opening goes on.
  bool _released = false;
  bool _busy = false;
  bool _torch = false;
  String? _error;
  XFile? _taken;
  Uint8List? _takenBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _letGo();
    super.dispose();
  }

  /// Lets the camera go now the page is closing, without waiting for it to
  /// slide away: the scan may be opened again meanwhile. The caller redraws.
  void _letGo() {
    _opening++; // an opening under way lets its own go when done
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    _torch = false;
    _queue(() => _quietly(controller.dispose()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Out of sight, the system takes the camera back: let it go (an
      // opening under way lets its own go when done), and open it again on
      // return.
      final controller = _controller;
      final opening =
          controller == null && _error == null && _cameras.isNotEmpty;
      if (_released || (controller == null && !opening)) return;
      _released = true;
      _opening++;
      if (controller != null) {
        setState(() {
          _controller = null;
          _torch = false;
        });
        _queue(() => _quietly(controller.dispose()));
      }
    } else if (state == AppLifecycleState.resumed &&
        _released &&
        _takenBytes == null) {
      _reopen();
    }
  }

  void _reopen() {
    _released = false;
    if (_error == null && _cameras.isNotEmpty) _open(_cameraIndex);
  }

  Future<void> _queue(Future<void> Function() job) {
    // A camera that never answers does not hold up the next for ever.
    final before = _quietly(
      _work,
    ).timeout(const Duration(seconds: 12), onTimeout: () {});
    final next = before.then((_) => job());
    _work = _quietly(next);
    return next;
  }

  /// A camera's clean-up may fail when it never started; that is not news.
  static Future<void> _quietly(Future<void>? done) async {
    try {
      await done;
    } catch (_) {}
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera was found on this device.');
        return;
      }
      final back = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameras = cameras;
      await _open(back < 0 ? 0 : back);
    } catch (error) {
      if (mounted) setState(() => _error = describeDeviceError(error));
    }
  }

  Future<void> _open(int index) {
    final opening = ++_opening;
    final previous = _controller;
    setState(() {
      _controller = null;
      _cameraIndex = index;
      _error = null;
      _torch = false;
    });
    bool current() => mounted && opening == _opening;
    return _queue(() async {
      await _quietly(previous?.dispose());
      if (!current()) return;
      // A card's small print needs detail; 4K stays well under the server's
      // 8 MB for a card photo, where a phone's full sensor may not.
      final controller = CameraController(
        _cameras[index],
        ResolutionPreset.ultraHigh,
        enableAudio: false,
      );
      try {
        await controller.initialize();
      } catch (error) {
        await _quietly(controller.dispose());
        if (current()) setState(() => _error = describeDeviceError(error));
        return;
      }
      if (!current()) return _quietly(controller.dispose());
      try {
        await controller.setFlashMode(
          FlashMode.off,
        ); // a flash glares on the card
      } catch (_) {
        // A camera without a flash, or a browser's: nothing to turn off.
      }
      if (!current()) return _quietly(controller.dispose());
      setState(() => _controller = controller);
    });
  }

  /// A browser mirrors any camera that is not a back camera, as for a selfie.
  bool _mirrored(CameraController controller) =>
      kIsWeb &&
      controller.description.lensDirection != CameraLensDirection.back;

  /// A light for reading a card in poor light: the back camera's, in the
  /// phone apps.
  bool _canTorch(CameraController? controller) =>
      controller != null &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      controller.description.lensDirection == CameraLensDirection.back;

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    try {
      await controller.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torch = !_torch);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _shutter() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      var photo = await controller.takePicture();
      if (_mirrored(controller)) {
        photo = await unmirrored(photo, name: voterCardPhotoName);
      }
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        // Its own path kept (the phone reads the card from the file).
        _taken = XFile.fromData(
          bytes,
          path: photo.path,
          name: voterCardPhotoName,
          mimeType: 'image/jpeg',
        );
        _takenBytes = bytes;
        _busy = false;
      });
    } catch (error) {
      _fail(error);
    }
  }

  void _retake() {
    setState(() {
      _taken = null;
      _takenBytes = null;
    });
    // Let go in the background while the photo was checked: open it now.
    if (_released) _reopen();
  }

  Future<void> _useOtherCamera() async {
    final other = widget.otherCamera;
    if (other == null) return;
    try {
      final photo = await other();
      if (photo == null || !mounted) return;
      Navigator.pop(
        context,
        photo.name.isEmpty
            ? XFile(
                photo.path,
                name: voterCardPhotoName,
                mimeType: 'image/jpeg',
              )
            : photo,
      );
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

  /// The picture's shape on screen. Phone cameras give the sensor's size,
  /// lying on its side, and the preview stands it up; browsers and desktop
  /// cameras give the picture as it is shown.
  static double _shape(CameraValue value) {
    final size = value.previewSize;
    if (size == null || size.width <= 0 || size.height <= 0) return 3 / 4;
    final ratio = size.width / size.height;
    if (isDesktopPlatform) return ratio;
    final turned = value.lockedCaptureOrientation ?? value.deviceOrientation;
    final flat =
        turned == DeviceOrientation.landscapeLeft ||
        turned == DeviceOrientation.landscapeRight;
    return flat ? ratio : 1 / ratio;
  }

  /// The camera's picture filling [size], cut at the edges as needed: the
  /// photo still holds everything inside the frame.
  Widget _preview(CameraController controller, Size size) {
    Widget picture;
    if (kIsWeb) {
      // A browser fills the box with the picture and cuts it to fit, as it
      // turns with the phone; the size it first reported would go stale.
      picture = SizedBox.fromSize(size: size, child: CameraPreview(controller));
    } else {
      // Rebuilt as the camera reports the phone turning, which comes a
      // moment after the screen turns.
      picture = ValueListenableBuilder<CameraValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final shape = _shape(value);
          var width = size.width;
          var height = width / shape;
          if (height < size.height) {
            height = size.height;
            width = height * shape;
          }
          return OverflowBox(
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: SizedBox(
              width: width,
              height: height,
              child: CameraPreview(controller),
            ),
          );
        },
      );
    }
    // Shown as the card is, so its text reads the right way.
    if (_mirrored(controller)) {
      picture = Transform.flip(flipX: true, child: picture);
    }
    return ClipRect(child: picture);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final taken = _takenBytes;
    final pad = MediaQuery.paddingOf(context);
    return PopScope(
      // However the page closes (Cancel, Use photo, the back button).
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) setState(_letGo);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            // A phone lying flat keeps its shutter at the side.
            final flat = size.width > size.height;
            final top = pad.top + (flat ? 84 : 64);
            final margin = flat
                ? EdgeInsets.fromLTRB(
                    pad.left + 16,
                    top,
                    pad.right + 128,
                    pad.bottom + 16,
                  )
                : EdgeInsets.fromLTRB(
                    pad.left + 16,
                    top,
                    pad.right + 16,
                    pad.bottom + 196,
                  );
            return Stack(
              children: [
                // Kept while the photo is checked, so a browser's camera keeps
                // running for a retake.
                if (controller != null)
                  Positioned.fill(child: _preview(controller, size)),
                if (controller != null && taken == null)
                  Positioned.fill(child: CardScanFrame(margin: margin)),
                if (taken != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black,
                      child: Padding(
                        // Beside the buttons when the phone lies flat, for the
                        // photo's full height.
                        padding: EdgeInsets.fromLTRB(
                          pad.left + 12,
                          pad.top + 64,
                          pad.right + (flat ? 232 : 12),
                          pad.bottom + (flat ? 16 : 150),
                        ),
                        child: Image.memory(
                          taken,
                          fit: BoxFit.contain,
                          semanticLabel: 'The photo of your PVC',
                        ),
                      ),
                    ),
                  ),
                if (_error != null && taken == null)
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: pad.top + 56,
                        bottom: pad.bottom,
                      ),
                      child: Center(child: _errorView()),
                    ),
                  ),
                if (controller == null && _error == null && taken == null)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _topBar(controller, flat),
                ),
                if (taken != null && flat)
                  Positioned(
                    top: pad.top + 64,
                    bottom: 0,
                    right: 0,
                    child: _reviewPanel(side: true),
                  )
                else if (taken != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _reviewPanel(),
                  )
                else if (_error == null && flat)
                  // Under the title bar and its hint, clear of both.
                  Positioned(
                    top: top,
                    bottom: 0,
                    right: 0,
                    child: _sideControls(controller),
                  )
                else if (_error == null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _bottomControls(controller),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(CameraController? controller, bool flat) {
    final reviewing = _takenBytes != null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      reviewing ? 'Check the photo' : 'Scan your PVC',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_cameras.length > 1 && !reviewing)
                    IconButton(
                      tooltip: 'Switch camera',
                      // Not while a camera is still opening.
                      onPressed: _busy || (controller == null && _error == null)
                          ? null
                          : () => _open((_cameraIndex + 1) % _cameras.length),
                      icon: const Icon(
                        Icons.cameraswitch_rounded,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              if (flat && !reviewing && _error == null) _hint(short: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint({bool short = false}) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Place the front of your PVC inside the frame',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
            height: 1.3,
          ),
        ),
        if (!short) ...[
          const SizedBox(height: 6),
          const Text(
            'Lay it flat in good light, away from glare, with all four corners '
            'inside the frame.',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ],
    ),
  );

  Widget _bottomControls(CameraController? controller) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _hint(),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Balanced either side of the shutter.
              SizedBox(
                width: 56,
                child: _canTorch(controller) ? _torchButton(controller) : null,
              ),
              const SizedBox(width: 20),
              _shutterButton(controller),
              const SizedBox(width: 20),
              const SizedBox(width: 56),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _sideControls(CameraController? controller) => SafeArea(
    left: false,
    child: SizedBox(
      width: 112,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 56,
            child: _canTorch(controller) ? _torchButton(controller) : null,
          ),
          const SizedBox(height: 16),
          _shutterButton(controller),
        ],
      ),
    ),
  );

  Widget _errorView() => SingleChildScrollView(
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
          style: const TextStyle(color: Colors.white, height: 1.4),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
        ),
        if (widget.otherCamera != null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _useOtherCamera,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Use the camera app'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ],
    ),
  );

  /// Below the photo, or beside it ([side]) when the phone lies flat.
  Widget _reviewPanel({bool side = false}) {
    final retake = OutlinedButton.icon(
      onPressed: _retake,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Retake'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white70),
      ),
    );
    final use = FilledButton.icon(
      onPressed: () => Navigator.pop(context, _taken),
      icon: const Icon(Icons.check_rounded),
      label: const Text('Use photo'),
    );
    final panel = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: const Text(
              'Make sure the card is sharp and every word on it can be read.',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          if (side) ...[
            use,
            const SizedBox(height: 10),
            retake,
          ] else
            Row(
              children: [
                Expanded(child: retake),
                const SizedBox(width: 12),
                Expanded(child: use),
              ],
            ),
        ],
      ),
    );
    // Large text kept in bounds; beside the photo it scrolls rather than
    // running off a short screen.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SafeArea(
        top: false,
        left: !side,
        child: side
            ? SizedBox(
                width: 220,
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Center(child: panel),
                    ),
                  ),
                ),
              )
            : panel,
      ),
    );
  }

  Widget _torchButton(CameraController? controller) => IconButton(
    tooltip: _torch ? 'Turn the light off' : 'Turn the light on',
    onPressed: controller == null || _busy ? null : _toggleTorch,
    icon: Icon(
      _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
      color: _torch ? TgcgColors.accentBright : Colors.white,
    ),
  );

  Widget _shutterButton(CameraController? controller) {
    final ready = controller != null && !_busy;
    return Semantics(
      button: true,
      label: 'Take photo',
      child: GestureDetector(
        onTap: ready ? _shutter : null,
        child: Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ready ? Colors.white : Colors.white30,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
