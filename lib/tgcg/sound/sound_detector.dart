import 'dart:math' as math;

import '../domain/models.dart';

/// Dangerous sounds the phone listens for while on duty: the YAMNet classes
/// that make each (google's AudioSet model, 521 classes), how sure the model
/// must be, and for how many half-second windows in a row.
///
/// Fireworks, firecrackers, cap guns and children shouting are left out on
/// purpose: they are common near polling units and are not danger.
enum DangerSound {
  gunfire(
    label: 'Gunshots or an explosion',
    classes: [420, 421, 422, 423, 424], // explosion, gunshot, machine gun, fusillade, artillery
    threshold: .4,
    windows: 1,
    severity: IncidentSeverity.critical,
    category: 'Violence / threat',
  ),
  screaming(
    label: 'Screaming or shouting',
    classes: [6, 9, 11], // shout, yell, screaming
    threshold: .5,
    windows: 2,
    severity: IncidentSeverity.high,
    category: 'Violence / threat',
  ),
  crowd(
    label: 'A loud crowd',
    classes: [64], // crowd
    threshold: .6,
    windows: 4,
    severity: IncidentSeverity.medium,
    category: 'Security',
  ),
  glass(
    label: 'Breaking glass',
    classes: [437, 463, 464], // shatter, smash/crash, breaking
    threshold: .4,
    windows: 1,
    severity: IncidentSeverity.high,
    category: 'Security',
  );

  const DangerSound({
    required this.label,
    required this.classes,
    required this.threshold,
    required this.windows,
    required this.severity,
    required this.category,
  });

  final String label;
  final List<int> classes;
  final double threshold;
  final int windows;
  final IncidentSeverity severity;

  /// One of the incident categories the server accepts.
  final String category;
}

/// A danger heard, and how sure the model was (0 to 1).
class DangerHeard {
  const DangerHeard(this.kind, this.confidence, this.at);

  final DangerSound kind;
  final double confidence;
  final DateTime at;
}

/// Decides, window by window, when a danger has been heard long and surely
/// enough. After an alert, the same kind stays quiet for [cooldown], so one
/// event raises one alert.
class SoundDetector {
  SoundDetector({this.cooldown = const Duration(minutes: 3)});

  final Duration cooldown;
  final _streak = <DangerSound, int>{};
  final _best = <DangerSound, double>{};
  final _quietUntil = <DangerSound, DateTime>{};

  /// The scores of one window (YAMNet's 521 classes); the danger heard, if any.
  DangerHeard? listen(List<double> scores, DateTime at) {
    DangerHeard? heard;
    for (final kind in DangerSound.values) {
      final score = kind.classes
          .map((index) => index < scores.length ? scores[index] : 0.0)
          .reduce(math.max);
      if (score >= kind.threshold) {
        _streak[kind] = (_streak[kind] ?? 0) + 1;
        _best[kind] = math.max(_best[kind] ?? 0, score);
      } else {
        _streak[kind] = 0;
        _best[kind] = 0;
      }
      final quietUntil = _quietUntil[kind];
      final quiet = quietUntil != null && at.isBefore(quietUntil);
      if (heard == null && !quiet && (_streak[kind] ?? 0) >= kind.windows) {
        heard = DangerHeard(kind, _best[kind]!, at);
      }
    }
    if (heard != null) {
      _quietUntil[heard.kind] = at.add(cooldown);
      _streak[heard.kind] = 0;
      _best[heard.kind] = 0;
    }
    return heard;
  }
}
