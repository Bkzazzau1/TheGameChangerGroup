import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show failureMessage, promptText, showDone;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/security_repository.dart';
import '../domain/permissions.dart';
import '../location/directions.dart' show LaunchDirections, launchDirections;
import '../session.dart';
import '../ui/app_on_screen.dart';
import '../ui/tgcg_design.dart';
import 'security_officer_page.dart' show callPhone, securityStepColor, securityTimeline;

/// The security officer an incident was sent to and each step they took; for
/// the Situation Room, sending it to one of the nearest officers, or taking
/// it back.
class IncidentSecurityPanel extends StatefulWidget {
  const IncidentSecurityPanel({
    super.key,
    required this.incident,
    this.refreshEvery = const Duration(seconds: 30),
    this.launch = launchDirections,
  });

  final FieldIncident incident;
  final Duration refreshEvery;
  final LaunchDirections launch;

  @override
  State<IncidentSecurityPanel> createState() => _IncidentSecurityPanelState();
}

class _IncidentSecurityPanelState extends State<IncidentSecurityPanel> {
  IncidentSecurity? _security;
  Object? _error;
  Timer? _timer;
  bool _busy = false;

  bool get _follows => TgcgSession.of(context, listen: false).can(TgcgCapability.viewIncidents);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer == null && TgcgBackend.of(context) != null && _follows) {
      unawaited(_load());
      _timer = Timer.periodic(widget.refreshEvery, (_) {
        if (appOnScreen) _load();
      });
    }
  }

  @override
  void didUpdateWidget(IncidentSecurityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.incident;
    final now = widget.incident;
    if (before.id != now.id) _security = null;
    if (_timer != null && (before.id != now.id || before.status != now.status)) {
      unawaited(_load());
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
    final reference = widget.incident.id;
    try {
      final security = await backend.security.forIncident(reference);
      if (!mounted || reference != widget.incident.id) return;
      setState(() {
        _security = security;
        _error = null;
      });
    } on ApiException catch (error) {
      // Refused (no right to follow this incident): nothing to show.
      if (error.statusCode == 403 || error.statusCode == 404) {
        _timer?.cancel();
        return;
      }
      if (mounted) setState(() => _error = error);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _send() async {
    final reference = widget.incident.id;
    final backend = TgcgBackend.of(context)!;
    final sent = await showDialog<SecurityDispatch>(
      context: context,
      builder: (_) => _SendDialog(reference: reference, backend: backend),
    );
    if (sent == null || !mounted) return;
    showDone(context, '$reference sent to ${sent.officerName}.');
    await _load();
  }

  Future<void> _cancel(SecurityDispatch dispatch) async {
    final reason = await promptText(
      context,
      title: 'Take back ${dispatch.incident}',
      label: 'Reason',
      action: 'Take back',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final backend = TgcgBackend.of(context)!;
    setState(() => _busy = true);
    try {
      await backend.security.cancel(dispatch.id, reason);
      if (mounted) showDone(context, '${dispatch.officerName} no longer has ${dispatch.incident}.');
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failureMessage(error)), backgroundColor: TgcgColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = _security;
    if (security == null) {
      if (_error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Security officers could not be loaded. ${failureMessage(_error!)}',
                style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final current = security.current;
    final open =
        widget.incident.status != IncidentStatus.resolved && widget.incident.status != IncidentStatus.closed;
    final canSend = security.canSend && current == null && open;
    final canTakeBack = security.canSend && current != null;
    if (security.dispatches.isEmpty && !canSend) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Security officer',
                style: TextStyle(color: TgcgColors.ink, fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
              if (_busy) ...[
                const SizedBox(width: 10),
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (final dispatch in security.dispatches)
            _DispatchLine(dispatch: dispatch, launch: widget.launch),
          if (canSend || canTakeBack)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canSend)
                  FilledButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.local_police_outlined, size: 17),
                    label: const Text('Send to security'),
                  ),
                if (canTakeBack)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _cancel(current),
                    icon: const Icon(Icons.undo_rounded, size: 17),
                    label: const Text('Take back'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DispatchLine extends StatelessWidget {
  const _DispatchLine({required this.dispatch, required this.launch});

  final SecurityDispatch dispatch;
  final LaunchDirections launch;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(color: TgcgColors.muted, fontSize: 9.5, height: 1.35);
    final phone = dispatch.officerPhone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      dispatch.officerName,
                      style: const TextStyle(color: TgcgColors.ink, fontSize: 10.5, fontWeight: FontWeight.w900),
                    ),
                    TgcgStatusPill(
                      label: securityStepLabel(dispatch.status),
                      color: securityStepColor(dispatch.status),
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
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
                Text(
                  [
                    'By ${dispatch.sentBy}',
                    if (dispatch.distanceMeters != null)
                      '${distanceLabel(dispatch.distanceMeters!)} away'
                          '${dispatch.locatedBy == 'live' ? ' (live)' : ''}',
                    if (dispatch.notified.isNotEmpty)
                      'Told by ${dispatch.notified.map((channel) => channel == 'push' ? 'app' : 'SMS').join(' and ')}',
                  ].join(' · '),
                  style: small,
                ),
                if (dispatch.outcome.isNotEmpty) Text(dispatch.outcome, style: small),
                if (dispatch.cancelReason.isNotEmpty) Text(dispatch.cancelReason, style: small),
              ],
            ),
          ),
          if (phone != null && phone.isNotEmpty && dispatch.active)
            IconButton(
              tooltip: 'Call ${dispatch.officerName}',
              onPressed: () => callPhone(context, phone, launch: launch),
              icon: const Icon(Icons.call_outlined, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Picks one of the officers nearest to the incident and sends it to them.
class _SendDialog extends StatefulWidget {
  const _SendDialog({required this.reference, required this.backend});

  final String reference;
  final BackendServices backend;

  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  late Future<SecurityNearest> _nearest = widget.backend.security.nearest(widget.reference);
  String? _chosen;
  bool _sending = false;
  String? _problem;

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  void _find() => setState(() {
    _chosen = null;
    _nearest = widget.backend.security.nearest(widget.reference, search: _search.text);
  });

  Future<void> _sendTo(String officer) async {
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      final sent = await widget.backend.security.send(widget.reference, officer, note: _note.text);
      if (mounted) Navigator.pop(context, sent);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _problem = failureMessage(error);
        });
      }
    }
  }

  String _details(SecurityCandidate officer) => [
    officer.distanceMeters == null ? 'Distance unknown' : distanceLabel(officer.distanceMeters!),
    if (officer.locatedBy == 'live') 'live location' else if (officer.area != null) officer.area!,
    ...officer.roles,
  ].join(' · ');

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('Send ${widget.reference} to security'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
            decoration: InputDecoration(
              labelText: 'Name or ID',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _find,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<SecurityNearest>(
            future: _nearest,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    failureMessage(snapshot.error!),
                    style: const TextStyle(color: TgcgColors.danger),
                  ),
                );
              }
              final nearest = snapshot.data;
              if (nearest == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              if (nearest.officers.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No security officers found.', style: TextStyle(color: TgcgColors.muted)),
                );
              }
              return Column(
                children: [
                  for (final officer in nearest.officers)
                    ListTile(
                      key: ValueKey('officer-${officer.accessId}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      selected: _chosen == officer.accessId,
                      leading: Icon(
                        _chosen == officer.accessId
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                      ),
                      title: Text(officer.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_details(officer)),
                      trailing: officer.busy
                          ? const TgcgStatusPill(label: 'BUSY', color: TgcgColors.warning, compact: true)
                          : null,
                      onTap: _sending ? null : () => setState(() => _chosen = officer.accessId),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Note to the officer (optional)'),
          ),
          if (_problem != null)
            Text(_problem!, style: const TextStyle(color: TgcgColors.danger)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(
        onPressed: _chosen == null || _sending ? null : () => _sendTo(_chosen!),
        child: Text(_sending ? 'Sending...' : 'Send'),
      ),
    ],
  );
}
