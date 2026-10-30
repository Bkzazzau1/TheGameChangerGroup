import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/access_repository.dart';
import '../api/backend.dart';
import '../api/member_repository.dart';
import '../api/messaging_repository.dart';
import '../election/election_calendar.dart';
import '../election/election_countdown.dart';
import '../location/directions.dart';
import '../messaging/inbox_page.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// The member's dashboard: who they are, the days to the election, their
/// membership, their polling unit, the latest announcements and what is
/// waiting for them. Each part loads and fails on its own, so a problem with
/// one never hides the others.
class MemberHomePage extends StatefulWidget {
  const MemberHomePage({
    super.key,
    required this.card,
    required this.unit,
    required this.news,
    required this.volunteering,
    required this.launch,
    required this.onRefresh,
    required this.onOpenCard,
    required this.onOpenUnit,
    required this.onOpenUpdates,
    required this.onOpenVolunteering,
    required this.onOpenInvite,
    required this.onOpenRoles,
    this.bottomPadding = 96,
    this.clock = DateTime.now,
  });

  final Future<(MemberCard, Uint8List?)> card;
  final Future<MyPollingUnit> unit;
  final Future<List<MemberAnnouncement>> news;
  final Future<List<VolunteerOffer>> volunteering;
  final LaunchDirections launch;
  final VoidCallback onRefresh;
  final VoidCallback onOpenCard;
  final VoidCallback onOpenUnit;
  final VoidCallback onOpenUpdates;
  final VoidCallback onOpenVolunteering;
  final VoidCallback onOpenInvite;
  final VoidCallback onOpenRoles;
  final double bottomPadding;

  /// The time now (replaced in tests).
  final DateTime Function() clock;

  @override
  State<MemberHomePage> createState() => _MemberHomePageState();
}

class _MemberHomePageState extends State<MemberHomePage> {
  Future<List<Appointment>>? _appointments;
  Future<List<InboxMessage>>? _inbox;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appointments ??= _loadAppointments();
    _inbox ??= _loadInbox();
  }

  Future<List<Appointment>> _loadAppointments() async {
    final services = TgcgBackend.of(context);
    if (services == null) return const [];
    return services.access.myAppointments();
  }

  Future<List<InboxMessage>> _loadInbox() async {
    final services = TgcgBackend.of(context);
    if (services == null) return const [];
    return services.messaging.inbox();
  }

  Future<void> _refresh() async {
    widget.onRefresh();
    setState(() {
      _appointments = _loadAppointments();
      _inbox = _loadInbox();
    });
    // The spinner stays until the membership is back; failures show in place.
    await widget.card.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final greeting = _Greeting(
      card: widget.card,
      name: session.operatorName,
      number: session.membershipNumber ?? session.accessId,
      hour: lagosHour(widget.clock()),
    );
    final countdown = ElectionCountdown(clock: widget.clock);
    final membership = _MembershipCard(
      card: widget.card,
      onOpenCard: widget.onOpenCard,
      onRetry: widget.onRefresh,
    );
    final attention = _ForYourAttention(
      waitingRole: session.waitingRole,
      card: widget.card,
      appointments: _appointments!,
      inbox: _inbox!,
      onOpenCard: widget.onOpenCard,
      onOpenRoles: widget.onOpenRoles,
    );
    final unit = _UnitCard(
      unit: widget.unit,
      launch: widget.launch,
      onOpenUnit: widget.onOpenUnit,
      onRetry: widget.onRefresh,
    );
    final news = _LatestNews(
      news: widget.news,
      onOpenUpdates: widget.onOpenUpdates,
      onRetry: widget.onRefresh,
    );
    final shortcuts = _Shortcuts(
      volunteering: widget.volunteering,
      onOpenVolunteering: widget.onOpenVolunteering,
      onOpenInvite: widget.onOpenInvite,
    );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: tgcgPagePadding(
                constraints.maxWidth,
                maxWidth: 1120,
                top: TgcgSpacing.lg,
                bottom: widget.bottomPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _spaced([greeting, countdown, membership, attention]),
                    ),
                  ),
                  const SizedBox(width: TgcgSpacing.lg),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _spaced([unit, news, shortcuts]),
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: tgcgPagePadding(constraints.maxWidth, bottom: widget.bottomPadding),
            children: _spaced([greeting, countdown, attention, membership, unit, news, shortcuts]),
          );
        },
      ),
    );
  }

  /// A gap below each part. "For your attention" keeps its own, since it may
  /// have nothing to show.
  List<Widget> _spaced(List<Widget> parts) => [
    for (final part in parts)
      part is _ForYourAttention
          ? part
          : Padding(padding: const EdgeInsets.only(bottom: 14), child: part),
  ];
}

/// For a member listed as an agent or observer whose identity is not checked
/// yet: why they see the member app, and what happens next.
class WaitingRoleNote extends StatelessWidget {
  const WaitingRoleNote({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) => TgcgNotice(
    icon: Icons.hourglass_top_rounded,
    child: Text(
      'You are listed as a $role. That work starts once a coordinator has checked '
      'your identity; then tap refresh at the top. Until then, you have everything '
      'members have.',
    ),
  );
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.card,
    required this.name,
    required this.number,
    required this.hour,
  });

  final Future<(MemberCard, Uint8List?)> card;

  /// The session's, so the greeting never waits for the network.
  final String name;
  final String number;
  final int hour;

  @override
  Widget build(BuildContext context) {
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Row(
      children: [
        FutureBuilder<(MemberCard, Uint8List?)>(
          future: card,
          builder: (context, snapshot) {
            final photo = snapshot.data?.$2;
            return CircleAvatar(
              radius: 26,
              backgroundColor: TgcgColors.primary,
              foregroundImage: photo == null ? null : MemoryImage(photo),
              child: Text(
                name.isEmpty ? 'T' : name.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: TgcgColors.accentBright,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(part, style: TgcgType.support),
              Text(name, style: TgcgType.title),
              Text(number, style: TgcgType.caption.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Space kept while a part loads, so the page does not jump.
class _Loading extends StatelessWidget {
  const _Loading({this.height = 96});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(
      child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
    ),
  );
}

/// A part that could not load: says so where it would have been.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.cloud_off_outlined, color: TgcgColors.muted, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: TgcgType.support)),
      TextButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.card, required this.onOpenCard, required this.onRetry});

  final Future<(MemberCard, Uint8List?)> card;
  final VoidCallback onOpenCard;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: 'Your membership',
    child: FutureBuilder<(MemberCard, Uint8List?)>(
      future: card,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Unavailable(message: 'Your membership details could not load.', onRetry: onRetry);
        }
        final data = snapshot.data;
        if (data == null) return const _Loading(height: 72);
        final card = data.$1;
        final (standing, standingColor) = switch (card.membershipState) {
          'suspended' => ('Suspended', TgcgColors.danger),
          'deactivated' => ('Ended', TgcgColors.muted),
          _ => ('Active', TgcgColors.success),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TgcgStatusPill(
                  label: standing,
                  color: standingColor,
                  icon: Icons.verified_outlined,
                ),
                TgcgStatusPill(
                  label: card.identityChecked ? 'Identity checked' : 'Identity not checked yet',
                  color: card.identityChecked ? TgcgColors.success : TgcgColors.muted,
                  icon: card.identityChecked
                      ? Icons.how_to_reg_rounded
                      : Icons.person_outline_rounded,
                ),
                TgcgStatusPill(
                  label: card.hasPvc ? 'PVC on record' : 'No PVC on record',
                  color: card.hasPvc ? TgcgColors.primary : TgcgColors.muted,
                  icon: Icons.credit_card_rounded,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Member since ${card.memberSince.year}', style: TgcgType.caption),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpenCard,
              icon: const Icon(Icons.badge_outlined),
              label: const Text('View membership card'),
            ),
          ],
        );
      },
    ),
  );
}

/// What is waiting for the member, from their own records. Nothing shows when
/// nothing is waiting.
class _ForYourAttention extends StatefulWidget {
  const _ForYourAttention({
    required this.waitingRole,
    required this.card,
    required this.appointments,
    required this.inbox,
    required this.onOpenCard,
    required this.onOpenRoles,
  });

  final String? waitingRole;
  final Future<(MemberCard, Uint8List?)> card;
  final Future<List<Appointment>> appointments;
  final Future<List<InboxMessage>> inbox;
  final VoidCallback onOpenCard;
  final VoidCallback onOpenRoles;

  @override
  State<_ForYourAttention> createState() => _ForYourAttentionState();
}

class _ForYourAttentionState extends State<_ForYourAttention> {
  late Future<List<Object?>> _loaded = _load();

  /// Each may fail on its own: what did arrive still shows.
  Future<List<Object?>> _load() => Future.wait<Object?>([
    widget.card.then<Object?>((value) => value, onError: (_) => null),
    widget.appointments.then<Object?>((value) => value, onError: (_) => null),
    widget.inbox.then<Object?>((value) => value, onError: (_) => null),
  ]);

  @override
  void didUpdateWidget(_ForYourAttention old) {
    super.didUpdateWidget(old);
    if (old.card != widget.card ||
        old.appointments != widget.appointments ||
        old.inbox != widget.inbox) {
      _loaded = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Object?>>(
    future: _loaded,
    builder: (context, snapshot) {
      final waitingRole = widget.waitingRole;
      final values = snapshot.data;
      final missing = (values?[0] as (MemberCard, Uint8List?)?)?.$1.cardMissing ?? const <String>[];
      final undecided = [
        for (final item in (values?[1] as List<Appointment>?) ?? const <Appointment>[])
          if (item.acceptedAt == null && item.isCurrent) item,
      ];
      final messages = (values?[2] as List<InboxMessage>?) ?? const <InboxMessage>[];
      final rows = [
        if (undecided.isNotEmpty)
          TgcgActionRow(
            icon: Icons.assignment_ind_outlined,
            color: TgcgColors.accentDeep,
            title: undecided.length == 1
                ? 'You are appointed ${undecided.single.roleName}'
                : 'You have ${undecided.length} appointments to answer',
            detail: 'Accept or decline it in Roles and access',
            onTap: widget.onOpenRoles,
          ),
        if (missing.isNotEmpty)
          TgcgActionRow(
            icon: Icons.badge_outlined,
            color: TgcgColors.accentDeep,
            title: 'Complete your membership card',
            detail: 'Add ${missing.map((need) => cardNeeds[need] ?? need).join(', ')}',
            onTap: widget.onOpenCard,
          ),
        if (messages.isNotEmpty)
          TgcgActionRow(
            icon: Icons.mail_outline_rounded,
            title: messages.first.title.isEmpty ? 'Latest message' : messages.first.title,
            detail: messages.first.body,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const InboxPage())),
          ),
      ];
      if (waitingRole == null && rows.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (waitingRole != null) WaitingRoleNote(role: waitingRole),
            if (waitingRole != null && rows.isNotEmpty) const SizedBox(height: 10),
            if (rows.isNotEmpty) TgcgRowGroup(children: rows),
          ],
        ),
      );
    },
  );
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.launch,
    required this.onOpenUnit,
    required this.onRetry,
  });

  final Future<MyPollingUnit> unit;
  final LaunchDirections launch;
  final VoidCallback onOpenUnit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: 'Your polling unit',
    trailing: TextButton(onPressed: onOpenUnit, child: const Text('Details')),
    trailingBeside: true,
    child: FutureBuilder<MyPollingUnit>(
      future: unit,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Unavailable(message: 'Your polling unit could not load.', onRetry: onRetry);
        }
        final mine = snapshot.data;
        if (mine == null) return const _Loading(height: 72);
        final unit = mine.unit;
        if (unit == null) {
          return const Text(
            'Your polling unit is not on record. Ask your ward coordinator to add it.',
            style: TgcgType.support,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(unit.name, style: TgcgType.bodyStrong),
            const SizedBox(height: 2),
            Text(unit.area, style: TgcgType.support),
            const SizedBox(height: 2),
            Text('Code ${unit.code}', style: TgcgType.caption),
            const SizedBox(height: 12),
            UnitDirectionsView(directions: unit.directions, launch: launch),
          ],
        );
      },
    ),
  );
}

class _LatestNews extends StatelessWidget {
  const _LatestNews({required this.news, required this.onOpenUpdates, required this.onRetry});

  final Future<List<MemberAnnouncement>> news;
  final VoidCallback onOpenUpdates;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: 'Latest announcements',
    trailing: TextButton(onPressed: onOpenUpdates, child: const Text('See all')),
    trailingBeside: true,
    child: FutureBuilder<List<MemberAnnouncement>>(
      future: news,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Unavailable(message: 'Announcements could not load.', onRetry: onRetry);
        }
        final items = snapshot.data;
        if (items == null) return const _Loading(height: 56);
        if (items.isEmpty) {
          return const Text(
            'Announcements for your area will appear here.',
            style: TgcgType.support,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, item) in items.take(2).indexed) ...[
              if (index > 0) const Divider(height: 20),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TgcgType.bodyStrong,
              ),
              const SizedBox(height: 2),
              Text(
                item.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TgcgType.support,
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({
    required this.volunteering,
    required this.onOpenVolunteering,
    required this.onOpenInvite,
  });

  final Future<List<VolunteerOffer>> volunteering;
  final VoidCallback onOpenVolunteering;
  final VoidCallback onOpenInvite;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<VolunteerOffer>>(
    future: volunteering,
    builder: (context, snapshot) {
      final offers = snapshot.data ?? const <VolunteerOffer>[];
      final open = offers.any((offer) => offer.isOpen);
      return TgcgRowGroup(
        children: [
          TgcgActionRow(
            icon: Icons.volunteer_activism_outlined,
            title: 'Volunteer',
            detail: open
                ? 'Your offer is with your coordinators'
                : 'Tell your coordinators how you can help',
            onTap: onOpenVolunteering,
          ),
          TgcgActionRow(
            icon: Icons.group_add_outlined,
            title: 'Invite with your code',
            detail: 'Share your referral code and link',
            onTap: onOpenInvite,
          ),
        ],
      );
    },
  );
}
