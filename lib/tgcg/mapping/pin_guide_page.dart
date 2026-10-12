import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/mapping_repository.dart';
import '../domain/models.dart';
import '../location/directions.dart';
import '../location/gps_service.dart';
import '../ui/tgcg_design.dart';
import 'unit_mapping_page.dart' show mappingUnitLabel;

/// GPS accuracy a pin must reach (matches the server's PIN_MAX_ACCURACY_M).
const pinTargetAccuracyMeters = 30.0;

/// Step-by-step guide for pinning one polling unit on site.
class PinGuidePage extends StatefulWidget {
  const PinGuidePage({
    super.key,
    required this.unit,
    this.gps = const GpsService(),
    this.pickPhoto,
    this.launch = launchDirections,
  });

  final MappingUnit unit;
  final GpsService gps;

  /// Opens the maps app (replaced in tests).
  final LaunchDirections launch;

  /// Replaces the camera (tests). Returns the photo bytes and file name.
  final Future<(Uint8List, String)?> Function()? pickPhoto;

  @override
  State<PinGuidePage> createState() => _PinGuidePageState();
}

enum _Step { arrive, signboard, gps, photo, review }

class _PinGuidePageState extends State<PinGuidePage> {
  _Step _step = _Step.arrive;
  bool _atEntrance = false;
  bool? _nameMatches;

  // Problem report (when the signboard does not match).
  MappingProblem _problem = MappingProblem.notFound;
  final _problemNote = TextEditingController();

  // GPS.
  StreamSubscription<GpsFix>? _gpsSub;
  GpsFix? _latest;
  GpsFix? _best;
  String? _gpsError;
  DateTime? _gpsStarted;
  Timer? _ticker;

  // Photo and submission.
  Uint8List? _photo;
  String _photoName = 'unit.jpg';
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  PinOutcome? _outcome;

  @override
  void dispose() {
    _stopGps();
    _problemNote.dispose();
    _note.dispose();
    super.dispose();
  }

  // --- GPS ----------------------------------------------------------------

  Future<void> _startGps() async {
    _stopGps();
    setState(() {
      _gpsError = null;
      _latest = null;
      _best = null;
      _gpsStarted = DateTime.now();
    });
    try {
      await widget.gps.ensureAccess();
    } on GpsUnavailable catch (error) {
      if (mounted) setState(() => _gpsError = error.message);
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _gpsSub = widget.gps.watch().listen(
      (fix) {
        if (!mounted) return;
        setState(() {
          _latest = fix;
          if (!fix.isMocked && (_best == null || fix.accuracyMeters < _best!.accuracyMeters)) {
            _best = fix;
          }
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _gpsError = '$error');
      },
    );
  }

  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _ticker?.cancel();
    _ticker = null;
  }

  bool get _fixGoodEnough =>
      _best != null && _best!.accuracyMeters <= pinTargetAccuracyMeters && !(_latest?.isMocked ?? false);

  // --- photo -----------------------------------------------------------------

  Future<void> _takePhoto() async {
    final override = widget.pickPhoto;
    if (override != null) {
      final picked = await override();
      if (picked != null && mounted) {
        setState(() {
          _photo = picked.$1;
          _photoName = picked.$2;
        });
      }
      return;
    }
    final picker = ImagePicker();
    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final image = await picker.pickImage(
      source: mobile ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photo = bytes;
      _photoName = image.name.isEmpty ? 'unit.jpg' : image.name;
    });
  }

  // --- submit ----------------------------------------------------------------

  Future<void> _submitPin() async {
    final mapping = TgcgBackend.of(context)!.mapping;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await mapping.pin(
        unitCode: widget.unit.code,
        gps: _best!,
        photoBytes: _photo!,
        photoName: _photoName,
        note: _note.text.trim(),
      );
      if (mounted) setState(() => _outcome = outcome);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitProblem() async {
    final note = _problemNote.text.trim();
    if (note.isEmpty) {
      setState(() => _error = 'Describe what you found, e.g. where the unit moved to.');
      return;
    }
    final mapping = TgcgBackend.of(context)!.mapping;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await mapping.reportProblem(unitCode: widget.unit.code, problem: _problem, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Problem reported for ${widget.unit.code}. Your LGA coordinator will follow up.')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _go(_Step step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (step == _Step.gps && _best == null) {
      _startGps();
    } else if (step != _Step.gps) {
      _stopGps();
    }
  }

  // --- UI ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final (label, color) = mappingUnitLabel(unit);
    return Scaffold(
      appBar: AppBar(title: Text('Pin ${unit.code}')),
      body: _outcome != null
          ? _OutcomeView(unit: unit, outcome: _outcome!)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(unit.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  [unit.code, unit.wardName, if (unit.location.isNotEmpty) unit.location].join(' · '),
                  style: const TextStyle(color: TgcgColors.muted),
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: TgcgStatusPill(label: label, color: color, compact: true)),
                if (unit.status == MappingStatus.pinned || unit.status == MappingStatus.confirmed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      unit.locatedByInec
                          ? "INEC's polling unit locator places this unit on the map. Pin it from "
                              "the entrance: a pin close to INEC's point confirms it, and one "
                              'further away flags it for review.'
                          : 'This unit already has a location. Pinning it again from the same spot confirms it.',
                      style: const TextStyle(fontSize: 12.5, color: TgcgColors.muted),
                    ),
                  ),
                if (unit.locationNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      unit.locationNote,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: TgcgColors.warning),
                    ),
                  ),
                const SizedBox(height: 12),
                Stepper(
                  physics: const NeverScrollableScrollPhysics(),
                  currentStep: _step.index,
                  controlsBuilder: (_, _) => const SizedBox.shrink(),
                  steps: [
                    Step(
                      title: const Text('Go to the unit'),
                      isActive: _step.index >= 0,
                      state: _step.index > 0 ? StepState.complete : StepState.indexed,
                      content: _only(_Step.arrive, _arriveStep),
                    ),
                    Step(
                      title: const Text('Check the signboard'),
                      isActive: _step.index >= 1,
                      state: _step.index > 1 ? StepState.complete : StepState.indexed,
                      content: _only(_Step.signboard, _signboardStep),
                    ),
                    Step(
                      title: const Text('Get a precise GPS fix'),
                      isActive: _step.index >= 2,
                      state: _step.index > 2 ? StepState.complete : StepState.indexed,
                      content: _only(_Step.gps, _gpsStep),
                    ),
                    Step(
                      title: const Text('Photograph the unit'),
                      isActive: _step.index >= 3,
                      state: _step.index > 3 ? StepState.complete : StepState.indexed,
                      content: _only(_Step.photo, _photoStep),
                    ),
                    Step(
                      title: const Text('Review and submit'),
                      isActive: _step.index >= 4,
                      content: _only(_Step.review, _reviewStep),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Builds only the current step: hidden steps would otherwise keep live
  /// widgets (and GPS animations) running in the background.
  Widget _only(_Step step, Widget Function() build) =>
      _step == step ? build() : const SizedBox.shrink();

  Widget _arriveStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Tips([
            'Travel to the polling unit listed above.',
            'Stand at its main entrance, or where voting takes place (the classroom, shed or open space).',
            'Do not pin from the road, a car or a nearby building.',
          ]),
          if (widget.unit.hasLocation) ...[
            OutlinedButton.icon(
              onPressed: () => openDirections(
                context,
                widget.unit.latitude!,
                widget.unit.longitude!,
                launch: widget.launch,
              ),
              icon: const Icon(Icons.directions_rounded),
              label: Text(
                widget.unit.locatedByInec ? "Directions to INEC's location" : 'Directions to the pinned location',
              ),
            ),
            const SizedBox(height: 4),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _atEntrance,
            onChanged: (value) => setState(() => _atEntrance = value ?? false),
            title: const Text('I am standing at the main entrance or voting point of this unit'),
          ),
          FilledButton(
            onPressed: _atEntrance ? () => _go(_Step.signboard) : null,
            child: const Text('Next'),
          ),
        ],
      );

  Widget _signboardStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Does the signboard or building match "${widget.unit.name}"?',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () {
                  setState(() => _nameMatches = true);
                  _go(_Step.gps);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Yes, it matches'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _nameMatches = false),
                icon: const Icon(Icons.report_outlined),
                label: const Text('No / cannot find it'),
              ),
            ],
          ),
          if (_nameMatches == false) ...[
            const SizedBox(height: 14),
            const Text(
              'Do not pin. Report what you found instead, so the unit is checked.',
              style: TextStyle(color: TgcgColors.warning, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<MappingProblem>(
              initialValue: _problem,
              decoration: const InputDecoration(labelText: 'What is wrong?'),
              items: [
                for (final p in MappingProblem.values) DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (value) => setState(() => _problem = value ?? _problem),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _problemNote,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What did you find?',
                hintText: 'e.g. The unit moved to the new primary school by the market.',
              ),
            ),
            _ErrorText(_error),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : _submitProblem,
              child: Text(_busy ? 'Sending…' : 'Report problem'),
            ),
          ],
        ],
      );

  Widget _gpsStep() {
    if (_gpsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_gpsError!, style: const TextStyle(color: TgcgColors.danger)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: widget.gps.openLocationSettings, child: const Text('Location settings')),
              FilledButton(onPressed: _startGps, child: const Text('Try again')),
            ],
          ),
        ],
      );
    }
    final best = _best;
    final latest = _latest;
    final accuracy = best?.accuracyMeters;
    final good = _fixGoodEnough;
    final waited = _gpsStarted == null ? 0 : DateTime.now().difference(_gpsStarted!).inSeconds;
    final color = accuracy == null
        ? TgcgColors.muted
        : accuracy <= pinTargetAccuracyMeters
            ? TgcgColors.success
            : accuracy <= 60
                ? TgcgColors.warning
                : TgcgColors.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              accuracy == null ? '…' : '±${accuracy.round()} m',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  accuracy == null
                      ? 'Waiting for satellites…'
                      : good
                          ? 'Precise enough. You can use this location.'
                          : 'Target: ${pinTargetAccuracyMeters.round()} m or better. Keep still.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            minHeight: 8,
            color: color,
            // 100 m or worse shows empty; the target fills it.
            value: accuracy == null ? null : ((100 - accuracy) / (100 - pinTargetAccuracyMeters)).clamp(0.0, 1.0),
          ),
        ),
        if (latest?.isMocked ?? false)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'A fake-location app is active on this phone. Turn it off: pins from fake locations are refused.',
              style: TextStyle(color: TgcgColors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        if (!good && waited >= 20)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: _Tips([
              'Step outside, away from walls, roofs and trees.',
              'Hold the phone up, screen facing the sky, and keep still.',
              'Turn on high-accuracy location (Wi-Fi and mobile data help the first fix).',
              'Wait: a precise fix can take up to a minute.',
            ]),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: good
              ? () {
                  _stopGps();
                  _go(_Step.photo);
                }
              : null,
          icon: const Icon(Icons.my_location_rounded),
          label: Text(good ? 'Use this location (±${accuracy!.round()} m)' : 'Waiting for a precise fix'),
        ),
      ],
    );
  }

  Widget _photoStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Tips([
            'Photograph the signboard with the unit name, or the building where voting happens.',
            'Make sure the photo is clear and not blurred.',
          ]),
          if (_photo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_photo!, height: 200, fit: BoxFit.cover),
              ),
            ),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_photo == null ? 'Take photo' : 'Retake'),
              ),
              FilledButton(
                onPressed: _photo == null ? null : () => _go(_Step.review),
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      );

  Widget _reviewStep() {
    final best = _best;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Line(Icons.door_front_door_outlined, 'Standing at the entrance or voting point'),
        _Line(Icons.check_rounded, 'Signboard matches "${widget.unit.name}"'),
        if (best != null) _Line(Icons.my_location_rounded, best.label),
        if (_photo != null) const _Line(Icons.photo_outlined, 'Photo attached'),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Entrance faces the main road'),
        ),
        _ErrorText(_error),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: [
            OutlinedButton(onPressed: _busy ? null : () => _go(_Step.gps), child: const Text('Redo GPS')),
            FilledButton.icon(
              onPressed: _busy || best == null || _photo == null ? null : _submitPin,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.push_pin_rounded),
              label: Text(_busy ? 'Saving…' : 'Pin this unit'),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.unit, required this.outcome});
  final MappingUnit unit;
  final PinOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, detail) = switch (outcome.status) {
      'pinned' => (
          Icons.push_pin_rounded,
          TgcgColors.primary,
          'Location set',
          'This is the first pin for ${unit.code}. A second coordinator pinning from the same spot will confirm it.',
        ),
      'confirmed' => (
          Icons.verified_rounded,
          TgcgColors.success,
          'Location confirmed',
          'Your pin agrees with the unit\'s location${outcome.distanceMeters == null ? '' : ' (${outcome.distanceMeters} m apart)'}.',
        ),
      _ => (
          Icons.call_split_rounded,
          TgcgColors.danger,
          'Pins disagree',
          'Your pin is ${outcome.distanceMeters ?? 'over 50'} m from the unit\'s current location. '
              'Another coordinator will review both pins and accept the right one.',
        ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 56),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Back to the list'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips(this.tips);
  final List<String> tips;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final tip in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.lightbulb_outline_rounded, size: 15, color: TgcgColors.accentDeep),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tip, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: TgcgColors.success),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.error);
  final String? error;

  @override
  Widget build(BuildContext context) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!, style: const TextStyle(color: TgcgColors.danger, fontWeight: FontWeight.w600)),
        );
}
