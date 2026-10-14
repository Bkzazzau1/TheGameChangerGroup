import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/media/device_media.dart';

void main() {
  test('release builds keep the constructors ML Kit creates by name', () {
    // Without them ML Kit cannot start in a release APK, and reading a PVC
    // or a face crashes. Debug builds are not shrunk, so only this rule
    // catches it before a phone does.
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();
    expect(
      rules.replaceAll(RegExp(r'\s+'), ' '),
      contains(
        '-keep class * implements com.google.firebase.components.ComponentRegistrar '
        '{ <init>(); }',
      ),
    );
  });

  test('a phone error shows its message, not the Android stack trace', () {
    final text = describeDeviceError(
      PlatformException(
        code: 'error',
        message: "Attempt to invoke virtual method 'java.lang.Class "
            "java.lang.Object.getClass()' on a null object reference",
        stacktrace: 'java.lang.NullPointerException\n at na3.<init>(r8-map-id-e07a:62)',
      ),
    );
    expect(text, startsWith('The phone could not complete this. Try again.'));
    expect(text, contains('on a null object reference'));
    expect(text, isNot(contains('r8-map-id')));
    expect(text, isNot(contains('PlatformException')));
  });

  test('a refused camera or photo library says how to allow it', () {
    expect(
      describeDeviceError(
        PlatformException(code: 'camera_access_denied', message: 'Camera access denied.'),
      ),
      'Camera or photo access is blocked. Allow it in system settings.',
    );
  });
}
