import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart'
    show ConnectToServerNotice, failureMessage, formatMoment, promptText, showDone;
import '../api/backend.dart';
import '../api/security_repository.dart';
import '../field/incident_report.dart' show incidentSeverityColor;
import '../location/directions.dart';
import '../ui/tgcg_design.dart';

Color securityStepColor(String step) => switch (step) {
  'sent' => TgcgColors.warning,
  'accepted' || 'onTheWay' || 'arrived' => TgcgColors.info,
  'resolved' => TgcgColors.success,
  _ => TgcgColors.muted,
};

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

/// "Sent Fri 17 Oct, 10:02 · Accepted 10:03 · On the way 10:05".
String securityTimeline({
  required String status,
  required DateTime sentAt,
  DateTime? acceptedAt,
  DateTime? onTheWayAt,
  DateTime? arrivedAt,
  DateTime? finishedAt,
}) => [
  'Sent ${formatMoment(sentAt)}',
  if (acceptedAt != null) 'Accepted ${_clock(acceptedAt)}',
  if (onTheWayAt != null) 'On the way ${_clock(onTheWayAt)}',
  if (arrivedAt != null) 'Arrived ${_clock(arrivedAt)}',
  if (finishedAt != null) '${securityStepLabel(status)} ${_clock(finishedAt)}',
].join(' · ');

/// Opens the phone app to call [phone], saying so when none could open.
Future<void> callPhone(BuildContext context, String phone, {LaunchDirections launch = launchDirections}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await launch(Uri(scheme: 'tel', path: phone))) {
    messenger.showSnackBar(const SnackBar(content: Text('No phone app could be opened on this device.')));
  }
}

String _stepAction(String step) => switch (step) {
  'accepted' => 'Accept',
  'declined' => 'Decline',
  'onTheWay' => 'On the way',
  'arrived' => 'Arrived',
  'resolved' => 'Resolved',
  _ => step,
};

IconData _stepIcon(String step) => switch (step) {
  'accepted' => Icons.check_rounded,
  'declined' => Icons.close_rounded,
  'onTheWay' => Icons.directions_run_rounded,
  'arrived' => Icons.place_outlined,
  'resolved' => Icons.task_alt_rounded,
  _ => Icons.flag_outlined,
};

/// The incidents the Situation Room sent to this security officer: where to
/// go, whom to call, and each step of their answer.
class SecurityOfficerPage extends StatefulWidget {
  const SecurityOfficerPage({
    super.key,
    this.refreshEvery = const Duration(seconds: 30),
    this.launch = launchDirections,
  });

  final Duration refreshEvery;
  final LaunchDirections launch;

  @override
  State<SecurityOfficerPage> createState() => _SecurityOfficerPageState();
}

class _SecurityOfficerPageState extends State<SecurityOfficerPage> {
  List<OfficerDispatch>? _dispatches;
  Object? _error;
  Timer? _timer;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer == null && TgcgBackend.of(context) != null) {
      unawaited(_load());
      _timer = Timer.periodic(widget.refreshEvery, (_) => _load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final backend = TgcgBackend.of(context);
    if (backend == null) return;
    try {
      final dispatches = await backend.security.mine();
      if (!mounted) return;
      setState(() {
        _dispatches = dispatches;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _answer(OfficerDispatch dispatch, String step) async {
    final reference = dispatch.incident.reference;
    var note = '';
    if (step == 'declined' || step == 'resolved') {
      final declining = step == 'declined';
      final written = await promptText(
        context,
        title: declining ? 'Decline $reference' : 'Resolve $reference',
        label: declining ? 'Reason' : 'What was done',
        action: declining ? 'Decline' : 'Resolved',
        required: true,
        destructive: declining,
      );
      if (written == null || !mounted) return;
      note = written;
    }
    final backend = TgcgBackend.of(context)!;
    setState(() => _busy.add(dispatch.id));
    try {
      final answered = await backend.security.respond(dispatch.id, step, note: note);
      if (!mounted) return;
      setState(() {
        _dispatches = [
          for (final item in _dispatches ?? const <OfficerDispatch>[])
            item.id == answered.id ? answered : item,
        ];
      });
      showDone(context, '$reference: ${securityStepLabel(answered.status).toLowerCase()}.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage(error)), backgroundColor: TgcgColors.danger),
      );
      unawaited(_load());
    } finally {
      if (mounted) setState(() => _busy.remove(dispatch.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (TgcgBackend.of(context) == null) {
      return const ConnectToServerNotice(
        message: 'Incidents sent to you come from the server. Sign in with a server account to see them.',
      );
    }
    final dispatches = _dispatches;
    if (dispatches == null) {
      if (_error != null) {
        return Center(
          child: TgcgEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Incidents could not be loaded',
            message: failureMessage(_error!),
            action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final active = [for (final item in dispatches) if (item.active) item];
    final earlier = [for (final item in dispatches) if (!item.active) item];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  active.isEmpty ? 'Nothing with you now' : '${active.length} with you now',
                  style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                failureMessage(_error!),
                style: const TextStyle(color: TgcgColors.danger, fontSize: 12),
              ),
            ),
          if (dispatches.isEmpty)
            const TgcgEmptyState(
              icon: Icons.shield_outlined,
              title: 'No incidents sent to you',
              message: 'Incidents the Situation Room sends you appear here.',
            ),
          for (final item in active) ...[
            _DispatchCard(
              dispatch: item,
              busy: _busy.contains(item.id),
              onAnswer: (step) => _answer(item, step),
              launch: widget.launch,
            ),
            const SizedBox(height: 12),
          ],
          if (earlier.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 8, 2, 8),
              child: Text(
                'Earlier this week',
                style: TextStyle(color: TgcgColors.muted, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
            for (final item in earlier) ...[
              _DispatchCard(dispatch: item, launch: widget.launch),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _DispatchCard extends StatelessWidget {
  const _DispatchCard({required this.dispatch, required this.launch, this.busy = false, this.onAnswer});

  final OfficerDispatch dispatch;
  final LaunchDirections launch;
  final bool busy;
  final ValueChanged<String>? onAnswer;

  @override
  Widget build(BuildContext context) {
    final incident = dispatch.incident;
    final latitude = incident.latitude;
    final longitude = incident.longitude;
    final finished = !dispatch.active;
    const small = TextStyle(color: TgcgColors.muted, fontSize: 11.5, height: 1.4);
    return TgcgSectionCard(
      padding: const EdgeInsets.all(16),
      title: '${incident.reference} · ${incident.title}',
      subtitle: [incident.category, incident.place].where((part) => part.isNotEmpty).join(' · '),
      trailing: TgcgStatusPill(
        label: securityStepLabel(dispatch.status),
        color: securityStepColor(dispatch.status),
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TgcgStatusPill(
                label: incident.severity.name.toUpperCase(),
                color: incidentSeverityColor(incident.severity),
                compact: true,
              ),
              Text('Reported ${formatMoment(incident.reportedAt)}', style: small),
            ],
          ),
          if (incident.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(incident.summary, style: const TextStyle(color: TgcgColors.ink, height: 1.4)),
          ],
          if (dispatch.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Situation Room: ${dispatch.note}',
              style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w700, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            [
              'From ${dispatch.sentBy}',
              if (dispatch.distanceMeters != null)
                '${distanceLabel(dispatch.distanceMeters!)} away when sent',
            ].join(' · '),
            style: small,
          ),
          if (incident.reporterName.isNotEmpty || incident.reporterPhone.isNotEmpty)
            Text(
              'Reported by ${[incident.reporterName, incident.reporterPhone].where((part) => part.isNotEmpty).join(', ')}',
              style: small,
            ),
          Text(
            securityTimeline(
              status: dispatch.status,
              sentAt: dispatch.sentAt,
              acceptedAt: dispatch.acceptedAt,
              onTheWayAt: dispatch.onTheWayAt,
              arrivedAt: dispatch.arrivedAt,
              finishedAt: dispatch.finishedAt,
            ),
            style: small,
          ),
          if (dispatch.outcome.isNotEmpty) Text(dispatch.outcome, style: small),
          if (dispatch.cancelReason.isNotEmpty) Text(dispatch.cancelReason, style: small),
          if (!finished) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (latitude != null && longitude != null)
                  OutlinedButton.icon(
                    onPressed: () => openDirections(context, latitude, longitude, launch: launch),
                    icon: const Icon(Icons.directions_rounded, size: 17),
                    label: const Text('Directions'),
                  ),
                if (incident.reporterPhone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => callPhone(context, incident.reporterPhone, launch: launch),
                    icon: const Icon(Icons.call_outlined, size: 17),
                    label: const Text('Call reporter'),
                  ),
              ],
            ),
          ],
          if (dispatch.next.isNotEmpty && onAnswer != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (index, step) in dispatch.next.indexed)
                        index == 0
                            ? FilledButton.icon(
                                onPressed: busy ? null : () => onAnswer!(step),
                                icon: Icon(_stepIcon(step), size: 17),
                                label: Text(_stepAction(step)),
                              )
                            : OutlinedButton.icon(
                                onPressed: busy ? null : () => onAnswer!(step),
                                icon: Icon(_stepIcon(step), size: 17),
                                label: Text(_stepAction(step)),
                              ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
