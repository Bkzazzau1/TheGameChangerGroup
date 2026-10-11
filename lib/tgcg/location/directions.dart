import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/reference_repository.dart';
import '../ui/tgcg_design.dart';

/// A Google Maps directions link. On phones it opens the Maps app; elsewhere
/// it opens in the browser.
Uri directionsUri(UnitDirections to) => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${to.latitude},${to.longitude}',
    });

typedef LaunchDirections = Future<bool> Function(Uri uri);

Future<bool> _launch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// "Navigate to polling unit": fetches the unit's mapped location from the
/// server and hands it to the maps app. Says so plainly when the unit has
/// not been mapped yet.
class NavigateToUnitButton extends StatefulWidget {
  const NavigateToUnitButton({super.key, required this.unitCode, this.launch = _launch});

  final String unitCode;
  final LaunchDirections launch;

  @override
  State<NavigateToUnitButton> createState() => _NavigateToUnitButtonState();
}

class _NavigateToUnitButtonState extends State<NavigateToUnitButton> {
  Future<ServerPollingUnit>? _unit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = TgcgBackend.of(context);
    if (backend != null) _unit ??= backend.reference.pollingUnit(widget.unitCode);
  }

  void _retry() => setState(
        () => _unit = TgcgBackend.of(context)!.reference.pollingUnit(widget.unitCode),
      );

  Future<void> _go(UnitDirections to) async {
    final opened = await widget.launch(directionsUri(to));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No maps app could be opened on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unit == null) {
      return const _Note(
        icon: Icons.cloud_off_outlined,
        text: 'Directions need a connection to the TGCG server.',
      );
    }
    return FutureBuilder<ServerPollingUnit>(
      future: _unit,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Row(
            children: [
              Expanded(
                child: _Note(
                  icon: Icons.error_outline_rounded,
                  text: error is ApiException
                      ? 'Directions unavailable: ${error.message}'
                      : 'Directions unavailable right now.',
                ),
              ),
              TextButton(onPressed: _retry, child: const Text('Retry')),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const FilledButton(
            onPressed: null,
            child: Text('Finding polling unit location...'),
          );
        }
        final to = snapshot.data!.directions;
        if (to == null) {
          return const _Note(
            icon: Icons.location_off_outlined,
            text: 'This polling unit has not been mapped yet, so directions are not available. '
                'Coordinators pin each unit before election day.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => _go(to),
              icon: const Icon(Icons.directions_rounded),
              label: const Text('Navigate to polling unit'),
            ),
            if (!to.confirmed) ...[
              const SizedBox(height: 6),
              const Text(
                'Location pinned by one coordinator and not yet confirmed. Check the signboard on arrival.',
                style: TextStyle(fontSize: 11.5, color: TgcgColors.muted),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: TgcgColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: TgcgColors.muted)),
          ),
        ],
      );
}
