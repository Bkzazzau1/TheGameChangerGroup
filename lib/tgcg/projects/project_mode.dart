import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../access/access_widgets.dart' show areaLabel, formatMoment, showFailure;
import '../api/backend.dart';
import '../api/projects_repository.dart';
import '../location/gps_service.dart';
import '../offline/offline_persistence.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'projects_page.dart' show ProjectDetailPage;

String hourMinute(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'am' : 'pm'}';
}

/// Where a project stands now: the server's word, moved on by the clock.
String statusNow(TgcgProject project, [DateTime? now]) {
  if (project.status == 'cancelled') return 'cancelled';
  final at = now ?? DateTime.now();
  if (at.isBefore(project.startsAt)) return 'scheduled';
  if (at.isBefore(project.endsAt)) return 'active';
  return 'ended';
}

/// Sharing location for a project: the phone's GPS and the duty service.
abstract class ProjectSharing {
  bool get on;

  /// Starts sharing, with [notice] in the phone's ongoing notification.
  /// Throws [GpsUnavailable] when location is off or not allowed.
  Future<void> start(String notice);
  Future<void> stop();

  /// What stops sharing now, without asking for permission.
  Future<GpsProblem?> problem();
}

class DeviceProjectSharing implements ProjectSharing {
  DeviceProjectSharing({required this.ownerId, this.persistence});

  final String ownerId;
  final OfflinePersistenceController? persistence;
  DutyTracker get _tracker => DutyTracker.instance;

  @override
  bool get on => _tracker.onDuty;

  @override
  Future<void> start(String notice) =>
      _tracker.start(ownerId: ownerId, persistence: persistence, notice: notice);

  @override
  Future<void> stop() => _tracker.stop();

  @override
  Future<GpsProblem?> problem() async {
    if (!const GpsService().supported) return GpsProblem.unsupported;
    if (!await Geolocator.isLocationServiceEnabled()) return GpsProblem.serviceOff;
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.denied => GpsProblem.denied,
      LocationPermission.deniedForever => GpsProblem.deniedForever,
      _ => null,
    };
  }
}

/// The projects this account sees and takes part in, kept fresh while the
/// app is open. While a project it accepted runs, location is shared without
/// a switch; when the project ends, sharing stops.
///
/// The list is fetched about every [refreshEvery] (each phone at a random
/// point between three quarters and one and a quarter of it, so a million
/// phones on election day do not ask together) and whenever the app comes
/// back to the screen. Projects start and end by the clock in between.
class ProjectModeController extends ChangeNotifier {
  ProjectModeController({
    required this.repository,
    required this.sharing,
    this.refreshEvery = const Duration(minutes: 10),
    this.tickEvery = const Duration(seconds: 30),
    math.Random? random,
  }) : _random = random ?? math.Random();

  final ProjectsRepository repository;
  final ProjectSharing sharing;
  final Duration refreshEvery;
  final Duration tickEvery;
  final math.Random _random;
  Duration _refreshIn = Duration.zero;

  List<TgcgProject> _projects = const [];
  GpsProblem? _gpsProblem;
  bool _sharingForProject = false;
  DateTime? _refreshedAt;
  Timer? _timer;
  bool _disposed = false;

  List<TgcgProject> get projects => _projects;

  /// Projects on now in this account's areas.
  List<TgcgProject> get running => [
    for (final project in _projects)
      if (statusNow(project) == 'active') project,
  ];

  /// The running project this account takes part in.
  TgcgProject? get myWork {
    for (final project in running) {
      if (project.myParticipation?.accepted ?? false) return project;
    }
    return null;
  }

  /// Projects this account is asked to take part in, not yet answered.
  List<TgcgProject> get invitations => [
    for (final project in _projects)
      if ((project.myParticipation?.invited ?? false) &&
          const {'scheduled', 'active'}.contains(statusNow(project)))
        project,
  ];

  /// Why location cannot be shared for [myWork]; the app waits until it can.
  GpsProblem? get gpsProblem => myWork == null ? null : _gpsProblem;

  void start() {
    unawaited(refresh());
    _timer = Timer.periodic(tickEvery, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    final last = _refreshedAt;
    if (last == null || DateTime.now().difference(last) >= _refreshIn) {
      await refresh();
    } else {
      await _applySharing();
    }
  }

  Future<void> refresh() async {
    final byId = <String, TgcgProject>{};
    try {
      for (final project in await repository.projects()) {
        byId[project.id] = project;
      }
    } catch (_) {
      // Offline: keep what was loaded, and the clock moves it on.
      for (final project in _projects) {
        byId[project.id] = project;
      }
    }
    try {
      // Their own place may be in a project outside their role's areas.
      for (final project in await repository.mine()) {
        byId[project.id] = project;
      }
    } catch (_) {
      // Not a member account, or offline.
    }
    _projects = byId.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    _refreshedAt = DateTime.now();
    _refreshIn = refreshEvery * (0.75 + _random.nextDouble() / 2);
    await _applySharing();
  }

  Future<void> _applySharing() async {
    final work = myWork;
    if (work == null) {
      if (_sharingForProject) {
        await sharing.stop();
        _sharingForProject = false;
      }
      _gpsProblem = null;
    } else {
      final problem = await sharing.problem();
      // A computer that cannot share location still works; a phone waits.
      _gpsProblem = problem == GpsProblem.unsupported ? null : problem;
      if (problem == null && !sharing.on) {
        try {
          await sharing.start('Sharing your location for ${work.name} until ${hourMinute(work.endsAt)}.');
          _sharingForProject = true;
        } on GpsUnavailable catch (error) {
          _gpsProblem = error.problem;
        }
      } else if (sharing.on) {
        _sharingForProject = true;
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// After the person turns location on.
  Future<void> retryGps() => _applySharing();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    // Signing out stops sharing.
    if (_sharingForProject) unawaited(sharing.stop());
    super.dispose();
  }
}

/// Provides the [ProjectModeController] to the operations and field apps.
class ProjectMode extends StatefulWidget {
  const ProjectMode({super.key, required this.child, this.sharing});

  final Widget child;

  /// Replaced in tests.
  final ProjectSharing? sharing;

  static ProjectModeController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ProjectModeScope>()?.notifier;

  @override
  State<ProjectMode> createState() => _ProjectModeState();
}

class _ProjectModeState extends State<ProjectMode> with WidgetsBindingObserver {
  ProjectModeController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final services = TgcgBackend.of(context);
    if (services == null) return;
    final session = TgcgSession.of(context, listen: false);
    _controller = ProjectModeController(
      repository: services.projects,
      sharing: widget.sharing ??
          DeviceProjectSharing(
            ownerId: session.accessId,
            persistence: OfflinePersistence.of(context, listen: false),
          ),
    )..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app, e.g. from the phone's location settings.
    if (state == AppLifecycleState.resumed) unawaited(_controller?.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return _ProjectModeScope(notifier: controller, child: widget.child);
  }
}

class _ProjectModeScope extends InheritedNotifier<ProjectModeController> {
  const _ProjectModeScope({required super.notifier, required super.child});
}

/// While someone takes part in a running project, the app waits for their
/// location to be on.
class ProjectGpsGate extends StatelessWidget {
  const ProjectGpsGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mode = ProjectMode.of(context);
    final problem = mode?.gpsProblem;
    final work = mode?.myWork;
    if (mode == null || problem == null || work == null) return child;
    const gps = GpsService();
    return ColoredBox(
      color: TgcgColors.canvas,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_off_outlined, size: 56, color: TgcgColors.danger),
                const SizedBox(height: 14),
                const Text(
                  'Turn on your location',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  '${work.name} is on until ${hourMinute(work.endsAt)}. '
                  '${GpsUnavailable(problem).message}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TgcgColors.muted, height: 1.4),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (problem == GpsProblem.serviceOff)
                      FilledButton.icon(
                        onPressed: () => unawaited(gps.openLocationSettings()),
                        icon: const Icon(Icons.location_on_outlined),
                        label: const Text('Turn on location'),
                      ),
                    if (problem == GpsProblem.deniedForever)
                      FilledButton.icon(
                        onPressed: () => unawaited(gps.openAppSettings()),
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Open app settings'),
                      ),
                    if (problem == GpsProblem.denied)
                      FilledButton.icon(
                        onPressed: () async {
                          await Geolocator.requestPermission();
                          await mode.retryGps();
                        },
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Allow location'),
                      ),
                    OutlinedButton(onPressed: mode.retryGps, child: const Text('Try again')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The projects on now and the invitations to answer, at the top of the app.
class ProjectStrip extends StatelessWidget {
  const ProjectStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = ProjectMode.of(context);
    if (mode == null) return const SizedBox.shrink();
    final work = mode.myWork;
    final rows = <Widget>[
      for (final project in mode.invitations)
        _StripRow(
          color: TgcgColors.accentDeep,
          icon: Icons.mark_email_unread_outlined,
          text: 'You are asked to take part in ${project.name}',
          action: 'Answer',
          onTap: () => answerInvitation(context, project),
        ),
      for (final project in mode.running)
        _StripRow(
          color: project == work ? TgcgColors.success : TgcgColors.primary,
          icon: project == work ? Icons.share_location_rounded : Icons.flag_outlined,
          text: project == work
              ? '${project.name} · until ${hourMinute(project.endsAt)} · sharing your location'
              : '${project.name} · until ${hourMinute(project.endsAt)}',
          onTap: () => openProject(context, project),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _StripRow extends StatelessWidget {
  const _StripRow({
    required this.color,
    required this.icon,
    required this.text,
    required this.onTap,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
            if (action != null)
              Text(
                action!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

void openProject(BuildContext context, TgcgProject project) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: project.id)),
);

/// The person agrees to take part (and to their location being shared while
/// the project runs) or declines.
Future<void> answerInvitation(BuildContext context, TgcgProject project) async {
  final mode = ProjectMode.of(context);
  final participation = project.myParticipation;
  final services = TgcgBackend.of(context);
  if (participation == null || services == null) return;
  final answer = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Take part in ${project.name}?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (project.description.isNotEmpty) ...[
              Text(project.description),
              const SizedBox(height: 10),
            ],
            Text('From ${formatMoment(project.startsAt)} to ${formatMoment(project.endsAt)}'),
            Text('At ${areaLabel(participation.place)}'),
            const SizedBox(height: 10),
            const Text(
              'While it runs, your location is shared with your coordinators.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'decline'),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'accept'),
          child: const Text('Accept'),
        ),
      ],
    ),
  );
  if (answer == null) return;
  try {
    await services.projects.answer(participation.id, answer);
    await mode?.refresh();
  } catch (error) {
    if (context.mounted) showFailure(context, error);
  }
}
