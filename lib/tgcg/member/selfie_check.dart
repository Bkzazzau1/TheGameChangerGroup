import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

/// What the phone found in a selfie before it is sent. It checks the photo,
/// not the person: the server does not rely on it, and a coordinator still
/// reviews every new member.
class SelfieCheck {
  const SelfieCheck.passed()
      : problem = null,
        ran = true;
  const SelfieCheck.failed(String this.problem) : ran = true;
  const SelfieCheck.notAvailable()
      : problem = null,
        ran = false;

  /// What to change, in words for the member; null when the photo will do.
  final String? problem;

  /// False where the phone could not look for faces (a browser or desktop).
  final bool ran;

  bool get passed => problem == null;
}

typedef CheckSelfie = Future<SelfieCheck> Function(XFile selfie);

/// Face detection runs in the Android and iPhone apps only.
bool get canCheckFaces =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Looks for one face, turned to the camera with eyes open, on the phone.
Future<SelfieCheck> checkSelfieOnDevice(XFile selfie) async {
  if (!canCheckFaces || selfie.path.isEmpty) return const SelfieCheck.notAvailable();
  final detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // eyes open or closed
      minFaceSize: 0.15, // faces far in the background do not count
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  try {
    return judgeSelfie(await detector.processImage(InputImage.fromFilePath(selfie.path)));
  } finally {
    await detector.close();
  }
}

/// The verdict on the faces found in a selfie: a passport-style photo has
/// exactly one, looking straight at the camera, with eyes open.
SelfieCheck judgeSelfie(List<Face> faces) {
  if (faces.isEmpty) {
    return const SelfieCheck.failed(
      "No face found. Hold the phone at arm's length, face the camera in good light and try again.",
    );
  }
  if (faces.length > 1) {
    return const SelfieCheck.failed(
      'More than one face in the photo. Take it with only you in the picture.',
    );
  }
  final face = faces.single;
  if ((face.headEulerAngleY ?? 0).abs() > 25 || (face.headEulerAngleX ?? 0).abs() > 25) {
    return const SelfieCheck.failed('Look straight at the camera.');
  }
  if ((face.headEulerAngleZ ?? 0).abs() > 20) {
    return const SelfieCheck.failed('Hold your head straight.');
  }
  final left = face.leftEyeOpenProbability;
  final right = face.rightEyeOpenProbability;
  if (left != null && right != null && left < 0.2 && right < 0.2) {
    return const SelfieCheck.failed('Keep your eyes open.');
  }
  return const SelfieCheck.passed();
}
