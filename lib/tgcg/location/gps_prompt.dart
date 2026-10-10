import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../ui/tgcg_design.dart';
import 'gps_service.dart';

/// Takes a GPS reading, guiding the agent if location is off or refused.
///
/// When [required] is true the agent can only retry or cancel, and null
/// means "cancelled". When false, they may continue without GPS and null
/// means "no reading".
Future<GpsFix?> captureGps(
  BuildContext context, {
  required bool required,
  required String action,
  GpsService gps = const GpsService(),
}) async {
  while (true) {
    if (!context.mounted) return null;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Getting your GPS location…'),
        duration: Duration(seconds: 20),
      ),
    );
    try {
      final fix = await gps.currentFix();
      messenger.hideCurrentSnackBar();
      if (fix.isMocked && context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'A mock-location app is active. This report will be flagged for review.',
            ),
          ),
        );
      }
      return fix;
    } on GpsUnavailable catch (error) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return null;
      final choice = await showDialog<_GpsChoice>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.location_off_outlined, color: TgcgColors.danger),
          title: Text(required ? 'Location needed to $action' : 'No GPS location'),
          content: Text(
            required
                ? '${error.message}\n\nTGCG uses your location to confirm you are at your polling unit.'
                : '${error.message}\n\nYou can still send it; it will be marked "no location".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                required ? _GpsChoice.cancel : _GpsChoice.continueWithout,
              ),
              child: Text(required ? 'Cancel' : 'Send without GPS'),
            ),
            if (error.problem == GpsProblem.serviceOff)
              TextButton(
                onPressed: () => Navigator.pop(context, _GpsChoice.locationSettings),
                child: const Text('Turn on location'),
              ),
            if (error.problem == GpsProblem.deniedForever)
              TextButton(
                onPressed: () => Navigator.pop(context, _GpsChoice.appSettings),
                child: const Text('Open app settings'),
              ),
            if (error.problem != GpsProblem.unsupported)
              FilledButton(
                onPressed: () => Navigator.pop(context, _GpsChoice.retry),
                child: const Text('Try again'),
              ),
          ],
        ),
      );
      switch (choice) {
        case _GpsChoice.locationSettings:
          await gps.openLocationSettings();
        case _GpsChoice.appSettings:
          await gps.openAppSettings();
        case _GpsChoice.retry:
          break;
        case _GpsChoice.cancel:
        case _GpsChoice.continueWithout:
        case null:
          return null;
      }
    }
  }
}

enum _GpsChoice { retry, locationSettings, appSettings, cancel, continueWithout }

/// Compact chip describing a record's GPS.
class GpsChip extends StatelessWidget {
  const GpsChip({super.key, required this.fix});
  final GpsFix? fix;

  @override
  Widget build(BuildContext context) {
    final value = fix;
    final (icon, color, text) = value == null
        ? (Icons.location_off_outlined, TgcgColors.muted, 'No GPS')
        : value.isMocked
            ? (Icons.gpp_maybe_outlined, TgcgColors.danger, 'Mock location')
            : (Icons.my_location_rounded, TgcgColors.success, '±${value.accuracyMeters.round()} m');
    return TgcgStatusPill(label: text.toUpperCase(), color: color, icon: icon, compact: true);
  }
}
