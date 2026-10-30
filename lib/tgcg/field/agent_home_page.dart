import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show formatMoment;
import '../api/backend.dart';
import '../api/projects_repository.dart';
import '../domain/permissions.dart';
import '../election/election_countdown.dart';
import '../location/gps_prompt.dart';
import '../location/gps_service.dart';
import '../member/member_shell.dart';
import '../member/wallet_page.dart';
import '../membership/member_review_page.dart';
import '../projects/project_mode.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../sound/sound_alerts.dart';
import '../sync/server_records.dart';
import '../sync/sync_controller.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

/// An agent's home on the phone: an operations dashboard. Who and where they
/// are (from their server account), check-in, the two urgent jobs, what is
/// still on the phone, on-duty location sharing, and what they have sent.
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

    final sync = TgcgSync.of(context);
    final syncBlocked = sync?.problem != null;

    final identity = _AgentCard(
      name: session.operatorName,
      accessId: me,
      role: session.roleTitle,
      scope: session.scope,
    );
    final checkIn = _CheckInCard(
      checkedInAt: checkedInToday ? last : null,
      busy: _checkingIn,
      onCheckIn: _checkIn,
    );
    final canReport = session.modules.contains(TgcgModule.fieldMonitoring);
    final canSubmit = session.modules.contains(TgcgModule.resultCapture);
    final urgent = _UrgentActions(
      onReport: canReport ? () => widget.onOpenModule(TgcgModule.fieldMonitoring) : null,
      onSubmit: canSubmit ? () => widget.onOpenModule(TgcgModule.resultCapture) : null,
    );
    final duty = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ProjectDutyCard(),
        if (alerts.supported) ...[
          const SizedBox(height: 10),
          _SoundAlertsCard(alerts: alerts),
        ],
      ],
    );
    const countdown = ElectionCountdown(size: ElectionCountdownSize.compact);
    final sent = _SentList(
      rows: [
        for (final item in submissions.take(3))
          _Sent(
            icon: Icons.ballot_outlined,
            title: 'Result ${item.pollingUnitScope.pollingUnitId ?? ''}',
            detail: _sentDetail(item.status.name, item.submittedAt),
            upload: results.uploadState(item.id),
            refusal: results.uploadStatus(item.id),
            syncBlocked: syncBlocked,
          ),
        for (final item in incidents.take(3))
          _Sent(
            icon: Icons.warning_amber_rounded,
            title: item.title,
            detail: _sentDetail(item.status.name, item.reportedAt),
            upload: field.uploadState(item.id),
            refusal: field.uploadStatus(item.id),
            syncBlocked: syncBlocked,
          ),
        for (final item in reports.take(3))
          _Sent(
            icon: Icons.feed_outlined,
            title: item.category,
            detail: _sentDetail(item.status.name, item.reportedAt),
            upload: field.uploadState(item.id),
            refusal: field.uploadStatus(item.id),
            syncBlocked: syncBlocked,
          ),
      ],
    );
    final tools = TgcgRowGroup(
      children: [
        if (session.modules.contains(TgcgModule.meetingRoom))
          TgcgActionRow(
            icon: Icons.call_rounded,
            title: 'Meetings',
            detail: 'Calls from your coordinators',
            onTap: () => widget.onOpenModule(TgcgModule.meetingRoom),
          ),
        if (session.modules.contains(TgcgModule.discussionRoom))
          TgcgActionRow(
            icon: Icons.forum_outlined,
            title: 'Social Forum',
            detail: 'Posts and discussions',
            onTap: () => widget.onOpenModule(TgcgModule.discussionRoom),
          ),
        if (session.membershipNumber != null)
          TgcgActionRow(
            icon: Icons.badge_outlined,
            title: 'My membership card',
            detail: 'Your details and photos, and the card to download',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyMembershipCardPage()),
            ),
          ),
        if (session.membershipNumber != null)
          TgcgActionRow(
            icon: Icons.account_balance_wallet_outlined,
            title: 'My wallet',
            detail: 'Payments from TGCG, and the account they go to',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyWalletPage()),
            ),
          ),
        if (session.can(TgcgCapability.verifyMemberIdentity))
          TgcgActionRow(
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
      ],
    );
    final hasTools = session.modules.contains(TgcgModule.meetingRoom) ||
        session.modules.contains(TgcgModule.discussionRoom) ||
        session.membershipNumber != null ||
        session.can(TgcgCapability.verifyMemberIdentity);

    const gap = SizedBox(height: 12);
    final operations = <Widget>[identity, gap, checkIn, gap, urgent, gap];
    final standing = <Widget>[if (sync != null) const SyncStatusCard(), duty, gap];
    final records = <Widget>[
      const TgcgSectionHeading(title: 'What you have sent'),
      sent,
      if (hasTools) ...[
        const SizedBox(height: 18),
        const TgcgSectionHeading(title: 'More'),
        tools,
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return SingleChildScrollView(
            padding: tgcgPagePadding(constraints.maxWidth, maxWidth: 1120, top: TgcgSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [...operations, ...standing],
                  ),
                ),
                const SizedBox(width: TgcgSpacing.lg),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [countdown, const SizedBox(height: 18), ...records],
                  ),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: tgcgPagePadding(constraints.maxWidth),
          children: [
            ...operations,
            ...standing,
            countdown,
            const SizedBox(height: 18),
            ...records,
          ],
        );
      },
    );
  }

  /// "Under review · 16 Jan 09:40": the record's state, as the app knows it.
  String _sentDetail(String status, DateTime at) {
    final words = status.replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match[0]!.toLowerCase()}');
    final state = words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
    return '$state · ${formatMoment(at.toLocal())}';
  }
}

/// The agent, and the place they answer for.
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
  Widget build(BuildContext context) {
    final atUnit = scope.level == GeographyLevel.pollingUnit;
    final area = [
      if ((scope.wardName ?? scope.wardId) case final ward?) ward,
      if ((scope.lgaName ?? scope.lgaId) case final lga?) lga,
      if ((scope.stateName ?? scope.stateId) case final state?) state,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TgcgRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TgcgColors.primaryDark, TgcgColors.primary],
        ),
        border: Border.all(color: TgcgColors.accent.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TgcgLogo(size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$accessId · $role',
                      style: const TextStyle(color: TgcgColors.onNavyMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: TgcgColors.accent.withValues(alpha: .35)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.place_outlined, color: TgcgColors.accentBright, size: 19),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      atUnit ? scope.pollingUnitName ?? scope.pollingUnitId ?? '' : scope.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (atUnit && area.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        area,
                        style: const TextStyle(color: TgcgColors.onNavyMuted, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({required this.checkedInAt, required this.busy, required this.onCheckIn});

  final DateTime? checkedInAt;
  final bool busy;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final at = checkedInAt;
    if (at != null) {
      return TgcgNotice(
        icon: Icons.verified_rounded,
        color: TgcgColors.success,
        child: Text(
          'Checked in today at ${_hhmm(at)}',
          style: TgcgType.bodyStrong,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.surface,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              TgcgIconBadge(icon: Icons.where_to_vote_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Check in when you reach your polling unit. Your GPS position is recorded.',
                  style: TgcgType.body,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : onCheckIn,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.my_location_rounded),
            label: const Text('Check in'),
          ),
        ],
      ),
    );
  }
}

/// The two jobs that cannot wait, side by side on all but the narrowest
/// phones. Each shows only for an agent the server allows it.
class _UrgentActions extends StatelessWidget {
  const _UrgentActions({required this.onReport, required this.onSubmit});

  final VoidCallback? onReport;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (onReport != null)
        _UrgentAction(
          icon: Icons.report_problem_outlined,
          title: 'Report an incident',
          detail: 'Anything wrong at your unit',
          color: TgcgColors.danger,
          onTap: onReport!,
        ),
      if (onSubmit != null)
        _UrgentAction(
          icon: Icons.ballot_outlined,
          title: 'Submit the result',
          detail: 'From the signed sheet',
          color: TgcgColors.primary,
          onTap: onSubmit!,
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (actions.length == 1 || constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, action) in actions.indexed) ...[
                if (index > 0) const SizedBox(height: 10),
                action,
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: actions[0]),
              const SizedBox(width: 10),
              Expanded(child: actions[1]),
            ],
          ),
        );
      },
    );
  }
}

class _UrgentAction extends StatelessWidget {
  const _UrgentAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .85),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// What the agent has sent, or the plain note that nothing has been yet.
class _SentList extends StatelessWidget {
  const _SentList({required this.rows});

  final List<_Sent> rows;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: rows.isEmpty
            ? const Text(
                'Nothing yet. Incidents, reports and results you send appear here.',
                style: TgcgType.support,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0) const Divider(height: 18),
                    row,
                  ],
                ],
              ),
      );
}

/// One record: what it is, its state, and where it stands on its way to the
/// server, as the outbox says. Nothing is shown as uploaded before the server
/// has confirmed it.
class _Sent extends StatelessWidget {
  const _Sent({
    required this.icon,
    required this.title,
    required this.detail,
    required this.upload,
    required this.refusal,
    required this.syncBlocked,
  });

  final IconData icon;
  final String title;
  final String detail;
  final RecordUpload? upload;

  /// The server's reason, for a record it refused.
  final String? refusal;

  /// Uploads are stopped for now (offline, or the server is busy).
  final bool syncBlocked;

  @override
  Widget build(BuildContext context) {
    final state = switch (upload) {
      RecordUpload.waiting => syncBlocked
          ? ('Saved on phone', TgcgColors.accentDeep)
          : ('Waiting to upload', TgcgColors.accentDeep),
      RecordUpload.uploading => ('Uploading', TgcgColors.info),
      RecordUpload.uploaded => ('Uploaded', TgcgColors.success),
      RecordUpload.refused => ('Not accepted', TgcgColors.danger),
      null => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 21, color: TgcgColors.primaryMid),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TgcgType.bodyStrong,
              ),
              const SizedBox(height: 2),
              Text(detail, style: TgcgType.caption),
              if (upload == RecordUpload.refused && refusal != null) ...[
                const SizedBox(height: 2),
                Text(refusal!, style: TgcgType.caption.copyWith(color: TgcgColors.danger)),
              ],
              if (state != null) ...[
                const SizedBox(height: 6),
                TgcgStatusPill(label: state.$1, color: state.$2, compact: true),
              ],
            ],
          ),
        ),
      ],
    );
  }
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
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: sharing ? TgcgColors.primary : TgcgColors.surface,
            borderRadius: BorderRadius.circular(TgcgRadius.md),
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
                      style: TgcgType.bodyStrong.copyWith(
                        color: sharing ? Colors.white : TgcgColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TgcgType.caption.copyWith(
                        color: sharing ? TgcgColors.onNavyMuted : TgcgColors.muted,
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
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: on ? TgcgColors.primary : TgcgColors.surface,
            borderRadius: BorderRadius.circular(TgcgRadius.md),
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
                      style: TgcgType.bodyStrong.copyWith(
                        color: on ? Colors.white : TgcgColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TgcgType.caption.copyWith(
                        color: on ? TgcgColors.onNavyMuted : TgcgColors.muted,
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
