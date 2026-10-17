import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show formatMoment;
import '../api/backend.dart';
import '../api/projects_repository.dart';
import '../domain/permissions.dart';
import '../location/gps_prompt.dart';
import '../location/gps_service.dart';
import '../member/member_shell.dart';
import '../member/wallet_page.dart';
import '../membership/member_review_page.dart';
import '../projects/project_mode.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../sound/sound_alerts.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

/// An agent's home on the phone: who and where they are (from their server
/// account), check-in, on-duty location sharing, and the work of the day.
class AgentHomePage extends StatefulWidget {
  const AgentHomePage({super.key, required this.onOpenModule, this.soundAlerts});

  final ValueChanged<TgcgModule> onOpenModule;
  final SoundAlerts? soundAlerts;

  @override
  State<AgentHomePage> createState() => _AgentHomePageState();
}

class _AgentHomePageState extends State<AgentHomePage> {
  DateTime? _lastCheckIn;
  bool _checkingIn = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_loadCheckIn());
    }
  }

  Future<void> _loadCheckIn() async {
    final services = TgcgBackend.of(context);
    final accessId = TgcgSession.of(context, listen: false).accessId;
    if (services == null) return;
    try {
      final last = await services.tracking.lastCheckIn(accessId);
      if (mounted) setState(() => _lastCheckIn = last);
    } catch (_) {
      // Offline: the check-in made on this device still shows below.
    }
  }

  Future<void> _checkIn() async {
    final session = TgcgSession.of(context, listen: false);
    final field = FieldOperations.of(context, listen: false);
    final gps = await captureGps(context, required: true, action: 'check in');
    if (gps == null || !mounted) return;
    setState(() => _checkingIn = true);
    try {
      await field.submitFieldReport(
        category: 'Agent check-in',
        summary: 'Agent checked in for field duty.',
        scope: session.scope,
        reporterId: session.accessId,
        gps: gps,
      );
      if (!mounted) return;
      setState(() => _lastCheckIn = DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checked in. It uploads automatically.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The check-in was not saved: $error')),
      );
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final alerts = widget.soundAlerts ?? SoundAlerts.instance;
    final me = session.accessId;
    bool mine(String reporter) => reporter == me;

    final incidents = field.incidents.where((item) => mine(item.reporterId)).toList()
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final reports = field.reports
        .where((item) => mine(item.reporterId) && item.category != 'Agent check-in')
        .toList()
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final submissions = results.submissions.where((item) => mine(item.submittedBy)).toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    // A check-in made here today counts at once; otherwise the server's.
    final today = DateTime.now();
    final made = field.reports
        .where((item) => mine(item.reporterId) && item.category == 'Agent check-in')
        .map((item) => item.reportedAt.toLocal());
    final last = [?_lastCheckIn?.toLocal(), ...made].fold<DateTime?>(
      null,
      (latest, at) => latest == null || at.isAfter(latest) ? at : latest,
    );
    final checkedInToday = last != null &&
        last.year == today.year &&
        last.month == today.month &&
        last.day == today.day;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _AgentCard(
          name: session.operatorName,
          accessId: me,
          role: session.roleTitle,
          scope: session.scope,
        ),
        const SizedBox(height: 14),
        _CheckInCard(
          checkedInAt: checkedInToday ? last : null,
          busy: _checkingIn,
          onCheckIn: _checkIn,
        ),
        const SizedBox(height: 10),
        const _ProjectDutyCard(),
        if (alerts.supported) ...[
          const SizedBox(height: 10),
          _SoundAlertsCard(alerts: alerts),
        ],
        const SizedBox(height: 18),
        const Text(
          'Your work today',
          style: TextStyle(color: TgcgColors.ink, fontSize: 15, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        _Action(
          icon: Icons.report_problem_outlined,
          title: 'Report an incident',
          detail: 'Violence, missing materials, anything wrong at your unit',
          onTap: () => widget.onOpenModule(TgcgModule.fieldMonitoring),
        ),
        _Action(
          icon: Icons.ballot_outlined,
          title: 'Submit the result',
          detail: 'Figures from the signed sheet, with its photo',
          onTap: () => widget.onOpenModule(TgcgModule.resultCapture),
        ),
        _Action(
          icon: Icons.call_rounded,
          title: 'Meetings',
          detail: 'Calls from your coordinators',
          onTap: () => widget.onOpenModule(TgcgModule.meetingRoom),
        ),
        if (session.membershipNumber != null)
          _Action(
            icon: Icons.badge_outlined,
            title: 'My membership card',
            detail: 'Your details and photos, and the card to download',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyMembershipCardPage()),
            ),
          ),
        if (session.membershipNumber != null)
          _Action(
            icon: Icons.account_balance_wallet_outlined,
            title: 'My wallet',
            detail: 'Payments from TGCG, and the account they go to',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyWalletPage()),
            ),
          ),
        if (session.can(TgcgCapability.verifyMemberIdentity))
          _Action(
            icon: Icons.verified_user_outlined,
            title: 'Identity checks',
            detail: 'Confirm the members of your polling unit',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  backgroundColor: TgcgColors.canvas,
                  appBar: AppBar(title: const Text('Identity checks')),
                  body: const MemberReviewPage(),
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          'What you have sent',
          style: TextStyle(color: TgcgColors.ink, fontSize: 15, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (incidents.isEmpty && reports.isEmpty && submissions.isEmpty)
          const Text(
            'Nothing yet. Incidents, reports and results you send appear here.',
            style: TextStyle(color: TgcgColors.muted),
          )
        else ...[
          for (final item in submissions.take(3))
            _Sent(
              icon: Icons.ballot_outlined,
              title: 'Result ${item.pollingUnitScope.pollingUnitId ?? ''}',
              detail: '${item.status.name} · ${formatMoment(item.submittedAt.toLocal())}',
              onDevice: results.isOnDevice(item.id),
            ),
          for (final item in incidents.take(3))
            _Sent(
              icon: Icons.warning_amber_rounded,
              title: item.title,
              detail: '${item.status.name} · ${formatMoment(item.reportedAt.toLocal())}',
              onDevice: field.isOnDevice(item.id),
            ),
          for (final item in reports.take(3))
            _Sent(
              icon: Icons.feed_outlined,
              title: item.category,
              detail: '${item.status.name} · ${formatMoment(item.reportedAt.toLocal())}',
              onDevice: field.isOnDevice(item.id),
            ),
        ],
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.name,
    required this.accessId,
    required this.role,
    required this.scope,
  });

  final String name;
  final String accessId;

  /// "Polling Unit Agent", or the roles they were appointed to.
  final String role;
  final GeographicScope scope;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TgcgColors.primaryDark,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const TgcgLogo(size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '$accessId · $role',
                    style: const TextStyle(color: Color(0xFFC9D4F0), fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    scope.level == GeographyLevel.pollingUnit
                        ? '${scope.pollingUnitName ?? scope.pollingUnitId} · '
                            '${scope.wardName ?? scope.wardId ?? ''}'
                        : scope.label,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({required this.checkedInAt, required this.busy, required this.onCheckIn});

  final DateTime? checkedInAt;
  final bool busy;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final at = checkedInAt;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: TgcgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: at == null ? TgcgColors.border : TgcgColors.success),
      ),
      child: Row(
        children: [
          Icon(
            at == null ? Icons.where_to_vote_outlined : Icons.verified_rounded,
            color: at == null ? TgcgColors.muted : TgcgColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              at == null
                  ? 'Check in when you reach your polling unit. Your GPS position is recorded.'
                  : 'Checked in today at ${at.hour.toString().padLeft(2, '0')}:'
                      '${at.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: TgcgColors.ink,
                fontWeight: at == null ? FontWeight.w600 : FontWeight.w900,
              ),
            ),
          ),
          if (at == null)
            FilledButton(
              onPressed: busy ? null : onCheckIn,
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Check in'),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Row(
                children: [
                  Icon(icon, color: TgcgColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          detail,
                          style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Sent extends StatelessWidget {
  const _Sent({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onDevice,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool onDevice;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: TgcgColors.primaryMid),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w800),
                  ),
                  Text(detail, style: const TextStyle(color: TgcgColors.muted, fontSize: 11.5)),
                ],
              ),
            ),
            if (onDevice)
              const TgcgStatusPill(
                label: 'ON THIS PHONE',
                color: TgcgColors.accentDeep,
                compact: true,
              ),
          ],
        ),
      );
}

/// Switch for sharing live location while on duty on election day.
/// Location sharing follows the project the person takes part in: on while
/// it runs, off when it ends. There is no switch.
class _ProjectDutyCard extends StatelessWidget {
  const _ProjectDutyCard();

  @override
  Widget build(BuildContext context) {
    final mode = ProjectMode.of(context);
    final tracker = DutyTracker.instance;
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final work = mode?.myWork;
        final invitation = mode == null || mode.invitations.isEmpty ? null : mode.invitations.first;
        final sharing = work != null && tracker.onDuty;
        final last = tracker.lastFix;
        final (title, detail) = switch ((work, invitation)) {
          (final TgcgProject work?, _) => (
              sharing ? 'Sharing your location' : 'Starting to share your location',
              '${work.name} until ${hourMinute(work.endsAt)}'
                  '${last == null ? '' : ' · last fix ±${last.accuracyMeters.round()} m'}',
            ),
          (null, final TgcgProject invitation?) => (
              'You are asked to take part in ${invitation.name}',
              'From ${formatMoment(invitation.startsAt)} to ${formatMoment(invitation.endsAt)}',
            ),
          _ => ('No project now', 'Your location is not shared.'),
        };
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          decoration: BoxDecoration(
            color: sharing ? TgcgColors.primary : TgcgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sharing ? TgcgColors.primary : TgcgColors.border),
          ),
          child: Row(
            children: [
              Icon(
                sharing ? Icons.share_location_rounded : Icons.location_disabled_outlined,
                color: sharing ? TgcgColors.accentBright : TgcgColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: sharing ? Colors.white : TgcgColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: sharing ? const Color(0xFFC9D4F0) : TgcgColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (work == null && invitation != null)
                FilledButton(
                  onPressed: () => answerInvitation(context, invitation),
                  child: const Text('Answer'),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _hhmm(DateTime? value) => value == null
    ? '--:--'
    : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

/// Switch for sound alerts: while on duty the phone listens for danger, also
/// with the screen locked, and raises an incident when it hears one.
class _SoundAlertsCard extends StatelessWidget {
  const _SoundAlertsCard({required this.alerts});

  final SoundAlerts alerts;

  @override
  Widget build(BuildContext context) {
    final tracker = DutyTracker.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([alerts, tracker]),
      builder: (context, _) {
        final on = alerts.on;
        final last = alerts.lastSent;
        final detail = switch (alerts.state) {
          SoundAlertsState.off when !tracker.onDuty => 'Works while you are on duty',
          SoundAlertsState.off => 'Gunshots, screaming, a loud crowd, breaking glass',
          SoundAlertsState.starting => 'Starting…',
          _ => alerts.problem ??
              (last == null
                  ? 'Listening, also with the screen locked'
                  : 'Last alert ${_hhmm(last.at.toLocal())}: ${last.kind.label}'),
        };
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          decoration: BoxDecoration(
            color: on ? TgcgColors.primary : TgcgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? TgcgColors.primary : TgcgColors.border),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.hearing_rounded : Icons.hearing_disabled_outlined,
                color: on ? TgcgColors.accentBright : TgcgColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      on ? 'Sound alerts on' : 'Sound alerts',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: on ? Colors.white : TgcgColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: on ? const Color(0xFFC9D4F0) : TgcgColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                onChanged: on || tracker.onDuty ? (value) => _toggle(context, value) : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggle(BuildContext context, bool value) async {
    if (!value) {
      await alerts.switchOff();
      return;
    }
    if (!await alerts.switchOn() && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sound alerts need the microphone. Allow it for TGCG and try again.'),
        ),
      );
    }
  }
}
