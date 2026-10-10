import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/models.dart';
import '../offline/offline_persistence.dart';

/// Why a GPS reading could not be taken.
enum GpsProblem { serviceOff, denied, deniedForever, timeout, unsupported }

class GpsUnavailable implements Exception {
  const GpsUnavailable(this.problem);
  final GpsProblem problem;

  String get message => switch (problem) {
        GpsProblem.serviceOff =>
          'Location is switched off on this phone. Turn it on to continue.',
        GpsProblem.denied =>
          'TGCG needs permission to use your location. Allow it to continue.',
        GpsProblem.deniedForever =>
          'Location permission is blocked for TGCG. Open the app settings and allow location.',
        GpsProblem.timeout =>
          'No GPS signal yet. Move outdoors or near a window and try again.',
        GpsProblem.unsupported => 'This device cannot provide a GPS location.',
      };

  @override
  String toString() => message;
}

GpsFix _toFix(Position position) => GpsFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      capturedAt: position.timestamp.toUtc(),
      isMocked: position.isMocked,
    );

/// Takes GPS readings for check-ins, incidents, results and evidence.
class GpsService {
  const GpsService();

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Ensures location services are on and permission is granted.
  Future<void> ensureAccess() async {
    if (!supported) throw const GpsUnavailable(GpsProblem.unsupported);
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const GpsUnavailable(GpsProblem.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const GpsUnavailable(GpsProblem.deniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const GpsUnavailable(GpsProblem.denied);
    }
  }

  /// A fresh, high-accuracy reading. Throws [GpsUnavailable].
  Future<GpsFix> currentFix({Duration timeout = const Duration(seconds: 20)}) async {
    await ensureAccess();
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: timeout,
        ),
      );
      return _toFix(position);
    } on TimeoutException {
      throw const GpsUnavailable(GpsProblem.timeout);
    }
  }

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

/// Shares live location while an agent is on duty.
///
/// On Android this runs as a foreground service with a visible
/// "TGCG on duty" notification, so the agent always knows they are sharing.
/// Readings are queued in the offline outbox and uploaded when online.
class DutyTracker extends ChangeNotifier {
  DutyTracker({GpsService gps = const GpsService()}) : _gps = gps;

  static final instance = DutyTracker();

  final GpsService _gps;
  StreamSubscription<Position>? _subscription;
  DateTime? _since;
  GpsFix? _lastFix;
  int _queued = 0;
  String? _ownerId;
  OfflinePersistenceController? _persistence;

  bool get onDuty => _subscription != null;
  DateTime? get since => _since;
  GpsFix? get lastFix => _lastFix;
  int get queuedReadings => _queued;

  Future<void> start({
    required String ownerId,
    OfflinePersistenceController? persistence,
  }) async {
    if (onDuty) return;
    await _gps.ensureAccess();
    _ownerId = ownerId;
    _persistence = persistence;
    _since = DateTime.now().toUtc();
    await _record(
      'duty_start',
      {'on_duty': true, 'started_at': _since!.toIso8601String()},
    );

    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 50,
            intervalDuration: const Duration(minutes: 3),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'TGCG on duty',
              notificationText:
                  'Sharing your location with your coordinator. Switch duty off in the app to stop.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 50,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
            pauseLocationUpdatesAutomatically: false,
          );
    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _lastFix = _toFix(position);
        _record('location_ping', _lastFix!.toJson());
        notifyListeners();
      },
      onError: (_) {},
    );
    notifyListeners();
  }

  Future<void> stop() async {
    if (!onDuty) return;
    await _subscription?.cancel();
    _subscription = null;
    await _record('duty_stop', {
      'on_duty': false,
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    });
    _since = null;
    notifyListeners();
  }

  Future<void> _record(String type, Map<String, Object?> payload) async {
    _queued++;
    await _persistence?.persistMutation(
      entityType: type,
      entityId: '$type-${DateTime.now().microsecondsSinceEpoch}',
      mutationType: SyncMutationType.create,
      payload: payload,
      ownerId: _ownerId,
    );
  }
}
