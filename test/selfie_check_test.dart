import 'dart:typed_data';
import 'dart:ui';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tgcg_emcop/tgcg/member/selfie_check.dart';

Face _face({double? turn, double? nod, double? tilt, double? leftEye, double? rightEye}) => Face(
      boundingBox: const Rect.fromLTWH(200, 300, 500, 600),
      landmarks: const {},
      contours: const {},
      headEulerAngleX: nod,
      headEulerAngleY: turn,
      headEulerAngleZ: tilt,
      leftEyeOpenProbability: leftEye,
      rightEyeOpenProbability: rightEye,
    );

void main() {
  test('a selfie needs exactly one face', () {
    expect(judgeSelfie([]).problem, startsWith('No face found.'));
    expect(judgeSelfie([_face(), _face()]).problem, startsWith('More than one face'));
    expect(judgeSelfie([_face(turn: 3, tilt: -2, leftEye: .9, rightEye: .8)]).passed, isTrue);
  });

  test('the face must look at the camera with eyes open', () {
    expect(judgeSelfie([_face(turn: 40)]).problem, 'Look straight at the camera.');
    expect(judgeSelfie([_face(nod: -35)]).problem, 'Look straight at the camera.');
    expect(judgeSelfie([_face(tilt: 30)]).problem, 'Hold your head straight.');
    expect(judgeSelfie([_face(leftEye: .05, rightEye: .1)]).problem, 'Keep your eyes open.');
    // A wink is fine, and so is a phone that cannot tell.
    expect(judgeSelfie([_face(leftEye: .05, rightEye: .9)]).passed, isTrue);
    expect(judgeSelfie([_face()]).passed, isTrue);
  });

  test('a photo with no file to read is not judged', () async {
    final check = await checkSelfieOnDevice(XFile.fromData(Uint8List(0)));
    expect(check.ran, isFalse);
    expect(check.passed, isTrue);
  });
}
