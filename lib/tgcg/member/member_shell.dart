import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_repository.dart';
import '../location/directions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_card_view.dart';

/// The member app: membership card, polling unit, announcements and volunteering.
class MemberShell extends StatefulWidget {
  const MemberShell({super.key, this.launch = launchDirections});

  /// Opens the maps app (replaced in tests).
  final LaunchDirections launch;

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int _tab = 0;
  late MemberRepository _members;
  Future<(MemberCard, Uint8List?)>? _card;
  Future<MyPollingUnit>? _unit;
  Future<List<MemberAnnouncement>>? _news;
  Future<List<VolunteerApplication>>? _volunteering;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_card != null) return;
    _members = TgcgBackend.of(context)!.member;
    _reloadAll();
  }

  void _reloadAll() {
    _card = _loadCard();
    _unit = _members.pollingUnit();
    _news = _members.announcements();
    _volunteering = _members.volunteering();
  }

  Future<(MemberCard, Uint8List?)> _loadCard() async {
    final card = await _members.card();
    Uint8List? photo;
    if (card.hasPhoto) {
      try {
        photo = await _members.photo();
      } on ApiException {
        // The card still shows without the photo.
      }
    }
    return (card, photo);
  }

  void _refresh() => setState(_reloadAll);

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          children: [
            TgcgLogo(size: 30),
            SizedBox(width: 10),
            Text('TGCG Member', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
          IconButton(
            tooltip: 'Sign out',
            onPressed: session.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (_tab) {
          0 => _CardTab(card: _card!, onEmailChanged: _refresh),
          1 => _UnitTab(unit: _unit!, launch: widget.launch),
          2 => _NewsTab(news: _news!),
          _ => _VolunteerTab(
              applications: _volunteering!,
              card: _card!,
              onApplied: () => setState(() {
                _volunteering = _members.volunteering();
              }),
            ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Card'),
          NavigationDestination(icon: Icon(Icons.how_to_vote_outlined), label: 'My unit'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), label: 'News'),
          NavigationDestination(icon: Icon(Icons.volunteer_activism_outlined), label: 'Volunteer'),
        ],
      ),
    );
  }
}

/// Shows a loading spinner, an error with a hint, or the loaded data.
class _Loaded<T> extends StatelessWidget {
  const _Loaded({required this.future, required this.builder});
  final Future<T> future;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TgcgEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load this page',
                  message: error is ApiException
                      ? error.message
                      : 'Check your connection, then tap refresh at the top.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return builder(snapshot.data as T);
        },
      );
}

class _CardTab extends StatelessWidget {
  const _CardTab({required this.card, required this.onEmailChanged});
  final Future<(MemberCard, Uint8List?)> card;
  final VoidCallback onEmailChanged;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: card,
        builder: (data) {
          final (card, photo) = data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: MembershipCardView(card: card, photo: photo)),
              const SizedBox(height: 18),
              TgcgSectionCard(
                title: 'My details',
                child: Column(
                  children: [
                    _Detail('Phone', card.phoneNumber),
                    _Detail(
                      'Email',
                      card.email.isEmpty ? 'Not added' : card.email,
                      action: TextButton(
                        onPressed: () => _editEmail(context, card),
                        child: Text(card.email.isEmpty ? 'Add' : 'Change'),
                      ),
                    ),
                    _Detail('PVC', card.vin ?? 'Not on record'),
                    if (card.occupation.isNotEmpty) _Detail('Occupation', card.occupation),
                    _Detail('Status', card.status.isEmpty ? '—' : _title(card.status)),
                  ],
                ),
              ),
            ],
          );
        },
      );

  Future<void> _editEmail(BuildContext context, MemberCard card) async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: 'Email address',
        label: 'Email (optional)',
        action: 'Save',
        initial: card.email,
        keyboardType: TextInputType.emailAddress,
      ),
    );
    if (email == null) return;
    try {
      await members.updateEmail(email);
      onEmailChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.fieldError('email') ?? error.message)));
    }
  }
}

class _UnitTab extends StatelessWidget {
  const _UnitTab({required this.unit, required this.launch});
  final Future<MyPollingUnit> unit;
  final LaunchDirections launch;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: unit,
        builder: (mine) {
          final unit = mine.unit;
          if (unit == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: TgcgEmptyState(
                  icon: Icons.how_to_vote_outlined,
                  title: 'No polling unit yet',
                  message: 'Your polling unit is not on record. Ask your ward coordinator to add it.',
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TgcgSectionCard(
                title: unit.name,
                subtitle: unit.area,
                trailing: TgcgStatusPill(label: unit.code, color: TgcgColors.primary, compact: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (unit.location.isNotEmpty) _Detail('Location', unit.location),
                    _Detail('TGCG members in this unit', '${mine.membersInUnit}'),
                    _Detail('TGCG members in this ward', '${mine.membersInWard}'),
                    const SizedBox(height: 12),
                    UnitDirectionsView(directions: unit.directions, launch: launch),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Vote at this polling unit on election day. Bring your PVC.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TgcgColors.muted, fontSize: 12.5),
              ),
            ],
          );
        },
      );
}

class _NewsTab extends StatelessWidget {
  const _NewsTab({required this.news});
  final Future<List<MemberAnnouncement>> news;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: news,
        builder: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: TgcgEmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'No announcements yet',
                  message: 'Announcements for your area will appear here.',
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final date = item.publishedAt;
              return TgcgSectionCard(
                title: item.title,
                subtitle: [
                  if (item.author.isNotEmpty) item.author,
                  if (date != null) _date(date),
                ].join(' · '),
                child: Text(item.body, style: const TextStyle(height: 1.4)),
              );
            },
          );
        },
      );
}

class _VolunteerTab extends StatelessWidget {
  const _VolunteerTab({required this.applications, required this.card, required this.onApplied});
  final Future<List<VolunteerApplication>> applications;
  final Future<(MemberCard, Uint8List?)> card;
  final VoidCallback onApplied;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: card,
        builder: (data) => _Loaded(
          future: applications,
          builder: (items) => _build(context, data.$1, items),
        ),
      );

  Widget _build(BuildContext context, MemberCard card, List<VolunteerApplication> items) {
          final open = items.any((a) => a.status == 'pending' || a.status == 'accepted');
          final canApply = !open && card.agentId == null && card.pollingUnit != null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TgcgSectionCard(
                title: 'Serve as a polling unit agent',
                subtitle: 'Agents watch the vote at their own polling unit on election day '
                    'and report results and incidents through the TGCG app.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (card.agentId != null)
                      Text(
                        'You are accredited as agent ${card.agentId}.',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: TgcgColors.success),
                      )
                    else if (card.pollingUnit == null)
                      const Text(
                        'Your polling unit must be on record before you can volunteer.',
                        style: TextStyle(color: TgcgColors.muted),
                      )
                    else if (open)
                      const Text(
                        'Your application is with your coordinators.',
                        style: TextStyle(color: TgcgColors.muted),
                      ),
                    if (canApply)
                      FilledButton.icon(
                        onPressed: () => _apply(context),
                        icon: const Icon(Icons.volunteer_activism_rounded),
                        label: const Text('Volunteer as an agent'),
                      ),
                  ],
                ),
              ),
              for (final item in items) ...[
                const SizedBox(height: 12),
                _ApplicationTile(application: item),
              ],
            ],
          );
  }

  Future<void> _apply(BuildContext context) async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPrompt(
        title: 'Volunteer as an agent',
        label: 'Message to your coordinator (optional)',
        hint: 'e.g. I am free all day and have a smartphone.',
        action: 'Send',
        maxLines: 3,
        maxLength: 500,
      ),
    );
    if (message == null) return;
    try {
      await members.volunteer(message: message);
      messenger.showSnackBar(const SnackBar(content: Text('Thank you. Your coordinators will review it.')));
      onApplied();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({required this.application});
  final VolunteerApplication application;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (application.status) {
      'pending' => ('WITH COORDINATORS', TgcgColors.warning),
      'accepted' => ('ACCEPTED', TgcgColors.success),
      'declined' => ('DECLINED', TgcgColors.danger),
      _ => ('WITHDRAWN', TgcgColors.muted),
    };
    return TgcgSectionCard(
      title: 'Agent application',
      subtitle: 'Sent ${_date(application.createdAt)}',
      trailing: TgcgStatusPill(label: label, color: color, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (application.message.isNotEmpty) Text(application.message),
          if (application.decisionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              application.decisionReason,
              style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
            ),
          ],
          if (application.agentId != null) ...[
            const SizedBox(height: 6),
            Text('Agent ID: ${application.agentId}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

/// A dialog with one text field. Returns the trimmed text, or null if cancelled.
/// It owns its controller, so the field outlives the dialog's closing animation.
class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.action,
    this.initial = '',
    this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
  });

  final String title;
  final String label;
  final String action;
  final String initial;
  final String? hint;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: Text(widget.action),
          ),
        ],
      );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, {this.action});
  final String label;
  final String value;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5)),
            ),
            Expanded(
              flex: 3,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ?action,
          ],
        ),
      );
}

String _title(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _date(DateTime value) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
