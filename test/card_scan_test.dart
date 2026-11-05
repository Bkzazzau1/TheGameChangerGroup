import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/media/card_scan_guide.dart';
import 'package:tgcg_emcop/tgcg/media/pvc_camera_page.dart';
import 'package:tgcg_emcop/tgcg/membership/pvc_recognition_service.dart';

import 'support/redesign_fixtures.dart' show screenWidths;

/// A 1 by 1 PNG, as a photo the camera took.
final shot = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A device's cameras: they start, show a picture and take [shot], which,
/// as a browser's camera does, comes without a name.
class FakeCameras extends CameraPlatform {
  FakeCameras({this.back = true, this.front = false, this.none = false});

  final bool back;
  final bool front;
  final bool none;
  final flash = <FlashMode>[];
  final disposed = <int>{};
  /// What happened, in order: 'create 1', 'dispose 1', ...
  final events = <String>[];
  ResolutionPreset? preset;
  var created = 0;
  var pictures = 0;

  /// While set, a camera does not finish starting.
  Completer<void>? hold;

  /// The phone turning, as the camera reports it.
  final turns = StreamController<DeviceOrientationChangedEvent>.broadcast();

  final _started = <int, StreamController<CameraInitializedEvent>>{};
  final _errors = StreamController<CameraErrorEvent>.broadcast();

  StreamController<CameraInitializedEvent> _startedOf(int id) =>
      _started.putIfAbsent(id, StreamController<CameraInitializedEvent>.broadcast);

  @override
  Future<List<CameraDescription>> availableCameras() async => [
    if (back && !none)
      const CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    if (front && !none)
      const CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? settings,
  ) async {
    preset = settings?.resolutionPreset;
    events.add('create ${created + 1}');
    return ++created;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => turns.stream;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) => _startedOf(cameraId).stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await hold?.future;
    _startedOf(cameraId).add(
      CameraInitializedEvent(cameraId, 1280, 960, ExposureMode.auto, true, FocusMode.auto, true),
    );
  }

  @override
  Widget buildPreview(int cameraId) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF6B5B4B), Color(0xFF3A3A44)]),
    ),
  );

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async => flash.add(mode);

  @override
  Future<XFile> takePicture(int cameraId) async {
    pictures++;
    return XFile.fromData(shot, mimeType: 'image/jpeg');
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposed.add(cameraId);
    events.add('dispose $cameraId');
  }
}

/// The PVC camera opened from a button, as the app opens it; [result] is
/// what it gave back once closed.
class _Opened {
  XFile? result;
  var closed = false;
}

Future<_Opened> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Future<XFile?> Function()? otherCamera,
  bool settle = true,
}) async {
  // The camera work queue is every page's: each test starts with its own,
  // made on the test's clock.
  PvcCameraPage.forgetCameraWork();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = _Opened();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            opened.result = await Navigator.of(context).push<XFile>(
              MaterialPageRoute(builder: (_) => PvcCameraPage(otherCamera: otherCamera)),
            );
            opened.closed = true;
          },
          child: const Text('Scan PVC'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Scan PVC'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A camera still opening spins for ever: a few frames only.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return opened;
}

void main() {
  tearDown(() => CameraPlatform.instance = FakeCameras());

  test("the card's frame keeps a voter card's shape, clear of the bars", () {
    for (final size in const [Size(390, 520), Size(320, 427), Size(1200, 675), Size(400, 200)]) {
      final frame = cardFrameIn(size);
      expect(frame.width / frame.height, closeTo(voterCardAspectRatio, 0.001));
      expect((Offset.zero & size).contains(frame.topLeft), isTrue);
      expect((Offset.zero & size).contains(frame.bottomRight), isTrue);
      expect(frame.center.dx, closeTo(size.width / 2, 0.001));
      expect(frame.center.dy, closeTo(size.height / 2, 0.001));
    }
    // A phone held upright: the card spans most of the width.
    expect(cardFrameIn(const Size(390, 520)).width, closeTo(390 * 0.86, 0.001));
    const margin = EdgeInsets.fromLTRB(16, 64, 16, 196);
    final within = cardFrameWithin(const Size(390, 844), margin);
    expect(within.top, greaterThan(64));
    expect(within.bottom, lessThan(844 - 196));
  });

  for (final width in screenWidths) {
    testWidgets('the frame draws at $width wide', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: CardScanFrame())),
      );
      expect(find.bySemanticsLabel('Frame for the front of your PVC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a PVC is taken inside its frame, without the flash, and checked before use', (
    tester,
  ) async {
    final camera = CameraPlatform.instance = FakeCameras();
    final opened = await _open(tester, otherCamera: () async => null);

    expect(find.text('Scan your PVC'), findsOneWidget);
    expect(find.byType(CardScanFrame), findsOneWidget);
    expect(find.text('Place the front of your PVC inside the frame'), findsOneWidget);
    // The sharpest pictures, and no flash to glare on the card.
    expect(camera.preset, ResolutionPreset.ultraHigh);
    expect(camera.flash, [FlashMode.off]);
    // The picture fills the screen, upright as the phone is held, and the
    // card goes between the title bar and the shutter.
    final screen = tester.getRect(find.byType(PvcCameraPage));
    final picture = tester.getRect(find.byType(CameraPreview));
    expect(picture.width / picture.height, closeTo(960 / 1280, 0.01));
    expect(picture.contains(screen.topLeft) && picture.contains(screen.bottomRight - const Offset(1, 1)), isTrue);
    final frame = cardFrameWithin(screen.size, const EdgeInsets.fromLTRB(16, 64, 16, 196));
    expect(frame.width, greaterThan(300));
    expect(frame.bottom, lessThan(tester.getRect(find.bySemanticsLabel('Take photo')).top));

    await tester.tap(find.byTooltip('Turn the light on'));
    await tester.pump();
    expect(camera.flash.last, FlashMode.torch);
    expect(find.byTooltip('Turn the light off'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pumpAndSettle();
    expect(find.text('Check the photo'), findsOneWidget);
    expect(find.byType(CardScanFrame), findsNothing);
    // The camera keeps running under the photo, for a retake.
    expect(find.byType(CameraPreview), findsOneWidget);
    await tester.tap(find.text('Retake'));
    await tester.pumpAndSettle();
    expect(find.byType(CardScanFrame), findsOneWidget);
    expect(opened.closed, isFalse);

    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use photo'));
    await tester.pumpAndSettle();
    expect(camera.pictures, 2);
    expect(opened.closed, isTrue);
    // (Off the web a file's name is its path's; naming is tested below.)
    expect(opened.result!.mimeType, 'image/jpeg');
    expect(await opened.result!.readAsBytes(), shot);
    expect(camera.disposed, {1});
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a camera, a PVC can still be taken with the camera app', (tester) async {
    CameraPlatform.instance = FakeCameras(none: true);
    final photo = XFile.fromData(Uint8List.fromList(const [1, 2, 3]), path: 'IMG_0042.jpg');
    var asked = 0;
    final opened = await _open(
      tester,
      size: const Size(360, 740),
      otherCamera: () async {
        asked++;
        return photo;
      },
    );
    expect(find.text('Scan your PVC'), findsOneWidget);
    expect(find.text('No camera was found on this device.'), findsOneWidget);
    expect(find.text('Place the front of your PVC inside the frame'), findsNothing);
    await tester.tap(find.text('Use the camera app'));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(opened.result, same(photo));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the light is only offered with a back camera', (tester) async {
    CameraPlatform.instance = FakeCameras(back: false, front: true);
    await _open(tester);
    expect(find.byType(CardScanFrame), findsOneWidget);
    expect(find.byTooltip('Turn the light on'), findsNothing);
  });

  testWidgets('the camera is let go in the background and opened again on return', (
    tester,
  ) async {
    final camera = CameraPlatform.instance = FakeCameras();
    await _open(tester);
    expect(find.byType(CameraPreview), findsOneWidget);
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    // (No frames are drawn in the background, so only the camera is checked.)
    await tester.pump();
    expect(camera.disposed, {1});
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(camera.created, 2);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a permission prompt while the camera opens does not open a second one', (
    tester,
  ) async {
    final camera = CameraPlatform.instance = FakeCameras()..hold = Completer<void>();
    await _open(tester, settle: false);
    // Asking for the camera makes the app inactive, then resumed: no more.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    camera.hold!.complete();
    await tester.pumpAndSettle();
    expect(camera.events, ['create 1']);
    expect(find.byType(CameraPreview), findsOneWidget);
  });

  testWidgets('sent to the background while opening, the first camera goes before the next', (
    tester,
  ) async {
    final camera = CameraPlatform.instance = FakeCameras()..hold = Completer<void>();
    await _open(tester, settle: false);
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    camera.hold!.complete();
    await tester.pumpAndSettle();
    // On Android letting a camera go stops the one in use: never after it.
    expect(camera.events, ['create 1', 'dispose 1', 'create 2']);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed and opened again at once, the first camera goes before the next', (
    tester,
  ) async {
    final camera = CameraPlatform.instance = FakeCameras()..hold = Completer<void>();
    await _open(tester, settle: false);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Scan PVC'));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    camera.hold!.complete();
    await tester.pumpAndSettle();
    expect(camera.events, ['create 1', 'dispose 1', 'create 2']);
    expect(find.byType(CameraPreview), findsOneWidget);
  });

  testWidgets('the camera is let go as the page closes, not after', (tester) async {
    final camera = CameraPlatform.instance = FakeCameras();
    await _open(tester);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(camera.disposed, {1});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from the background while a photo is checked, the photo stays', (
    tester,
  ) async {
    final camera = CameraPlatform.instance = FakeCameras();
    await _open(tester);
    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pumpAndSettle();
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('Check the photo'), findsOneWidget);
    expect(camera.created, 1); // opened again only for a retake
    await tester.tap(find.text('Retake'));
    await tester.pumpAndSettle();
    expect(camera.created, 2);
    expect(find.byType(CardScanFrame), findsOneWidget);
  });

  testWidgets('the picture keeps its shape when the phone is turned', (tester) async {
    final camera = CameraPlatform.instance = FakeCameras();
    await _open(tester);
    var picture = tester.getRect(find.byType(CameraPreview));
    expect(picture.width / picture.height, closeTo(960 / 1280, 0.01));
    // The screen turns first; the camera says so a moment later.
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    camera.turns.add(const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft));
    await tester.pumpAndSettle();
    picture = tester.getRect(find.byType(CameraPreview));
    expect(picture.width / picture.height, closeTo(1280 / 960, 0.01));
    expect(picture.width, greaterThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lying flat, the photo is checked at full height beside its buttons', (
    tester,
  ) async {
    CameraPlatform.instance = FakeCameras();
    await _open(tester, size: const Size(800, 360));
    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pumpAndSettle();
    final photo = tester.getRect(find.byType(Image));
    expect(photo.height, greaterThan(250));
    expect(tester.getRect(find.text('Use photo')).left, greaterThan(photo.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a short flat screen the controls stay under the title bar', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    CameraPlatform.instance = FakeCameras(front: true);
    await _open(tester, size: const Size(568, 320));
    final title = tester.getRect(find.byIcon(Icons.cameraswitch_rounded));
    final light = tester.getRect(find.byTooltip('Turn the light on'));
    expect(light.top, greaterThan(title.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the camera cannot be switched while one is still opening', (tester) async {
    final camera = CameraPlatform.instance = FakeCameras(front: true)..hold = Completer<void>();
    await _open(tester, settle: false);
    final switching = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.cameraswitch_rounded), matching: find.byType(IconButton)),
    );
    expect(switching.onPressed, isNull);
    camera.hold!.complete();
    await tester.pumpAndSettle();
    expect(camera.created, 1);
    await tester.tap(find.byIcon(Icons.cameraswitch_rounded));
    await tester.pumpAndSettle();
    expect(camera.created, 2);
    expect(camera.disposed, {1});
    expect(find.byTooltip('Turn the light on'), findsNothing); // the front camera
  });

  for (final (size, scale) in const [
    (Size(800, 360), 1.0),
    (Size(640, 360), 1.3),
    (Size(640, 360), 2.0),
    (Size(568, 320), 2.0),
    (Size(320, 568), 2.0),
    (Size(1200, 800), 1.0),
  ]) {
    testWidgets('holds at ${size.width.toInt()}x${size.height.toInt()}, text x$scale', (
      tester,
    ) async {
      CameraPlatform.instance = FakeCameras();
      await _open(tester, size: size, textScale: scale);
      expect(find.byType(CardScanFrame), findsOneWidget);
      expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();
      expect(find.text('Use photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('scanning a PVC opens the camera with the frame, the camera app as the other way', () async {
    Future<XFile?> Function()? offered;
    final service = PvcRecognitionService(
      takePhoto: ({required otherCamera}) async {
        offered = otherCamera;
        return null;
      },
    );
    expect(await service.captureAndRecognize(), isNull);
    expect(offered, isNotNull);
  });

  test('a card photo without a name is given one, as the server needs', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows; // nothing read on the device
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final result = await PvcRecognitionService(
      takePhoto: ({required otherCamera}) async => null,
    ).recognizeImage(XFile.fromData(shot));
    expect(result.imageName, voterCardPhotoName);
  });
}
