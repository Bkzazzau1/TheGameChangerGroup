import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'camera_capture_page.dart';

/// Root navigator, so device services without a BuildContext (such as the
/// image_picker camera delegate) can present the in-app camera.
final tgcgNavigatorKey = GlobalKey<NavigatorState>();

bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// On desktop, image_picker can only open files; ImageSource.camera needs a
/// delegate. Route it to the in-app camera so evidence capture works the same
/// on Windows as on phones.
void registerDesktopCameraDelegate() {
  if (!isDesktopPlatform) return;
  final platform = ImagePickerPlatform.instance;
  if (platform is CameraDelegatingImagePickerPlatform) {
    platform.cameraDelegate = TgcgCameraDelegate();
  }
}

class TgcgCameraDelegate extends ImagePickerCameraDelegate {
  @override
  Future<XFile?> takePhoto({
    ImagePickerCameraDelegateOptions options =
        const ImagePickerCameraDelegateOptions(),
  }) => _open(CameraCaptureMode.photo, options);

  @override
  Future<XFile?> takeVideo({
    ImagePickerCameraDelegateOptions options =
        const ImagePickerCameraDelegateOptions(),
  }) => _open(CameraCaptureMode.video, options);

  Future<XFile?> _open(
    CameraCaptureMode mode,
    ImagePickerCameraDelegateOptions options,
  ) async {
    final navigator = tgcgNavigatorKey.currentState;
    if (navigator == null) {
      throw StateError('Camera is not available until the app has started.');
    }
    return navigator.push<XFile>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraCapturePage(
          mode: mode,
          maxDuration: options.maxVideoDuration,
          preferFront: options.preferredCameraDevice == CameraDevice.front,
        ),
      ),
    );
  }
}

/// Turns plugin and OS errors into guidance an operator can act on.
String describeDeviceError(Object error) {
  final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  if (error is MissingPluginException) {
    return 'This device feature was added after the app started. Fully close '
        'and relaunch the app (hot reload is not enough).';
  }
  if (error is CameraException) {
    final code = error.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return windows
          ? 'Camera access is blocked. Enable it in Windows Settings > Privacy '
                '& security > Camera, including "Let desktop apps access your camera".'
          : 'Camera permission is required. Allow camera access in system settings.';
    }
    return 'Camera error: ${error.description ?? error.code}';
  }
  if (error is LocationServiceDisabledException) {
    return windows
        ? 'Location services are off. Turn on Windows Settings > Privacy & '
              'security > Location, including "Let desktop apps access your location".'
        : 'Location services are off. Turn on location in system settings.';
  }
  if (error is PermissionDeniedException) {
    return 'Location permission was denied. Allow location access in system settings.';
  }
  final message = error.toString();
  if (message.contains('Microphone permission')) {
    return windows
        ? 'Microphone access is blocked. Enable it in Windows Settings > Privacy '
              '& security > Microphone, including "Let desktop apps access your microphone".'
        : 'Microphone permission is required. Allow microphone access in system settings.';
  }
  if (message.contains('Location permission')) {
    return windows
        ? 'Location access is blocked. Enable it in Windows Settings > Privacy '
              '& security > Location.'
        : 'Location permission is required. Allow location access in system settings.';
  }
  return message.replaceFirst(RegExp(r'^(Bad state|Exception): '), '');
}
