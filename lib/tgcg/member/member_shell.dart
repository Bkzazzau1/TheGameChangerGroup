import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../access/access_widgets.dart';
import '../access/my_access_page.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../api/member_repository.dart';
import '../location/directions.dart';
import '../media/device_media.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'member_registration_page.dart'
    show ScanPvc, TakeSelfie, readScanOnServer, scanPvcWithDevice, takeSelfieWithDevice;
import 'membership_card_view.dart';
import 'selfie_check.dart';

/// The member app: membership card, polling unit, announcements, volunteering
/// and the member's own appointments.
class MemberShell extends StatefulWidget {
  const MemberShell({
    super.key,
    this.launch = launchDirections,
    this.scanPvc = scanPvcWithDevice,
    this.takeSelfie = takeSelfieWithDevice,
    this.checkSelfie = checkSelfieOnDevice,
  });

  /// Opens the maps app (replaced in tests).
  final LaunchDirections launch;

  /// Reads a photo of the voter card: an updated one for a polling unit
  /// change, or one left out when joining (replaced in tests).
  final ScanPvc scanPvc;

  /// Takes and checks a selfie left out when joining (replaced in tests).
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int _tab = 0;
  late MemberRepository _members;
  Future<(MemberCard, Uint8List?)>? _card;
  Future<MyPollingUnit>? _unit;
  Future<List<MemberAnnouncement>>? _news;
  Future<List<VolunteerOffer>>? _volunteering;

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

  void _refresh() {
    setState(_reloadAll);
    // An appointment may have started meanwhile: the operations app opens then.
    refreshOwnAccess(context);
  }

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
          0 => _CardTab(
              card: _card!,
              onChanged: _refresh,
              scanPvc: widget.scanPvc,
              takeSelfie: widget.takeSelfie,
              checkSelfie: widget.checkSelfie,
            ),
          1 => _UnitTab(unit: _unit!, launch: widget.launch, scanPvc: widget.scanPvc),
          2 => _NewsTab(news: _news!),
          3 => _VolunteerTab(
              offers: _volunteering!,
              onChanged: () => setState(() {
                _volunteering = _members.volunteering();
              }),
            ),
          _ => const MyAccessPage(showHeader: false),
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
          NavigationDestination(icon: Icon(Icons.assignment_ind_outlined), label: 'Roles'),
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
  const _CardTab({
    required this.card,
    required this.onChanged,
    required this.scanPvc,
    required this.takeSelfie,
    required this.checkSelfie,
  });
  final Future<(MemberCard, Uint8List?)> card;
  final VoidCallback onChanged;
  final ScanPvc scanPvc;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: card,
        builder: (data) {
          final (card, photo) = data;
          final waitingRole = TgcgSession.of(context).waitingRole;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (waitingRole != null) ...[
                _WaitingRoleNote(role: waitingRole),
                const SizedBox(height: 14),
              ],
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
                    _Detail(
                      'Occupation',
                      card.occupation.isEmpty ? 'Not added' : card.occupation,
                      action: TextButton(
                        onPressed: () => _editOccupation(context, card),
                        child: Text(card.occupation.isEmpty ? 'Add' : 'Change'),
                      ),
                    ),
                    _Detail(
                      'Membership',
                      switch (card.membershipState) {
                        'suspended' => 'Suspended',
                        'deactivated' => 'Ended',
                        _ => 'Active',
                      },
                    ),
                    if (card.identityChecked) _Detail('ID check', 'Done'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TgcgSectionCard(
                title: 'My photos',
                child: Column(
                  children: [
                    _Detail(
                      'Photo of you',
                      card.hasPhoto ? 'Added' : 'Not added',
                      action: _photoAction(card, card.hasPhoto, () => _addSelfie(context)),
                    ),
                    _Detail(
                      'Photo of your PVC',
                      card.hasCardPhoto ? 'Added' : 'Not added',
                      action: _photoAction(card, card.hasCardPhoto, () => _addCardPhoto(context)),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );

  /// Adds a missing photo, or changes one until the identity is checked;
  /// after that a coordinator changes it.
  Widget? _photoAction(MemberCard card, bool added, VoidCallback onPressed) {
    if (added && card.identityChecked) return null;
    return TextButton(onPressed: onPressed, child: Text(added ? 'Change' : 'Add'));
  }

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
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.fieldError('email') ?? error.message)));
    }
  }

  Future<void> _editOccupation(BuildContext context, MemberCard card) async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    final occupation = await showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: 'Occupation',
        label: 'What you do for a living',
        action: 'Save',
        initial: card.occupation,
      ),
    );
    if (occupation == null) return;
    try {
      await members.updateOccupation(occupation);
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.fieldError('occupation') ?? error.message)),
      );
    }
  }

  /// A selfie through the phone's face check. If the check finds a problem,
  /// the member may take it again or keep it: a coordinator reviews it anyway.
  Future<void> _addSelfie(BuildContext context) async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    try {
      while (true) {
        final file = await takeSelfie();
        if (file == null) return;
        final problem = (await _checked(file)).problem;
        if (!context.mounted) return;
        if (problem != null) {
          final again = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Check your photo'),
              content: Text(problem),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Use this photo'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Take again'),
                ),
              ],
            ),
          );
          if (again == null) return;
          if (again) continue;
        }
        final name = file.name.isEmpty ? 'selfie.jpg' : file.name;
        await members.addPhoto((bytes: await file.readAsBytes(), name: name));
        onChanged();
        messenger.showSnackBar(const SnackBar(content: Text('Your photo was saved.')));
        return;
      }
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.fieldError('photo') ?? error.message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeDeviceError(error))));
    }
  }

  /// The phone's face check. If the check itself breaks, the photo goes
  /// through, as when joining.
  Future<SelfieCheck> _checked(XFile file) async {
    try {
      return await checkSelfie(file);
    } catch (_) {
      return const SelfieCheck.notAvailable();
    }
  }

  Future<void> _addCardPhoto(BuildContext context) async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Take a photo of the card'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null) return;
    try {
      final scan = await scanPvc(camera: camera);
      if (scan == null) return;
      await members.addCardPhoto(scan.photo);
      onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Your card photo was saved.')));
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.fieldError('pvc_image') ?? error.message)),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeDeviceError(error))));
    }
  }
}

class _UnitTab extends StatelessWidget {
  const _UnitTab({required this.unit, required this.launch, required this.scanPvc});
  final Future<MyPollingUnit> unit;
  final LaunchDirections launch;
  final ScanPvc scanPvc;

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
              const SizedBox(height: 16),
              _PollingUnitChanges(scanPvc: scanPvc),
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

/// Volunteering for party work. It is not a route to becoming an agent:
/// coordinators accredit agents separately.
class _VolunteerTab extends StatelessWidget {
  const _VolunteerTab({required this.offers, required this.onChanged});
  final Future<List<VolunteerOffer>> offers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: offers,
        builder: (items) {
          final open = items.where((offer) => offer.isOpen).firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TgcgSectionCard(
                title: 'Volunteer for party work',
                subtitle: 'Tell your coordinators how you can help. They will contact you.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (open == null)
                      FilledButton.icon(
                        onPressed: () => _offer(context),
                        icon: const Icon(Icons.volunteer_activism_rounded),
                        label: const Text('Offer to help'),
                      )
                    else
                      const Text(
                        'Your offer is with your coordinators. Withdraw it below to send a '
                        'different one.',
                        style: TextStyle(color: TgcgColors.muted),
                      ),
                  ],
                ),
              ),
              for (final item in items) ...[
                const SizedBox(height: 12),
                _OfferTile(
                  offer: item,
                  onWithdraw: item.isOpen ? () => _withdraw(context, item) : null,
                ),
              ],
            ],
          );
        },
      );

  Future<void> _offer(BuildContext context) async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    final offer = await showDialog<(List<String>, String)>(
      context: context,
      builder: (_) => const _OfferDialog(),
    );
    if (offer == null) return;
    try {
      await members.volunteer(interests: offer.$1, message: offer.$2);
      messenger.showSnackBar(
        const SnackBar(content: Text('Thank you. Your coordinators will contact you.')),
      );
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.fieldError('interests') ?? error.message)));
    }
  }

  Future<void> _withdraw(BuildContext context, VolunteerOffer offer) async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await members.withdrawVolunteering(offer.id);
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, this.onWithdraw});
  final VolunteerOffer offer;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (offer.status) {
      'pending' => ('WITH COORDINATORS', TgcgColors.warning),
      'accepted' => ('ACCEPTED', TgcgColors.success),
      'declined' => ('DECLINED', TgcgColors.danger),
      _ => ('WITHDRAWN', TgcgColors.muted),
    };
    return TgcgSectionCard(
      title: 'Your offer',
      subtitle: 'Sent ${_date(offer.createdAt)}',
      trailing: TgcgStatusPill(label: label, color: color, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final interest in offer.interests)
                Chip(
                  label: Text(volunteerInterests[interest] ?? interest),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (offer.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(offer.message),
          ],
          if (offer.decisionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              offer.decisionReason,
              style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
            ),
          ],
          if (onWithdraw != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onWithdraw, child: const Text('Withdraw')),
            ),
        ],
      ),
    );
  }
}

/// Choose the kinds of party work to offer, with an optional message.
class _OfferDialog extends StatefulWidget {
  const _OfferDialog();

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final _chosen = <String>{};
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('How can you help?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in volunteerInterests.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _chosen.contains(entry.key),
                      onSelected: (on) => setState(
                        () => on ? _chosen.add(entry.key) : _chosen.remove(entry.key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _message,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Message to your coordinator (optional)',
                  hintText: 'e.g. I have a car and am free on weekends.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.pop(context, (
                      [for (final key in volunteerInterests.keys) if (_chosen.contains(key)) key],
                      _message.text.trim(),
                    )),
            child: const Text('Send'),
          ),
        ],
      );
}

/// A dialog with one text field. Returns the trimmed text, or null if cancelled.
/// It owns its controller, so the field outlives the dialog's closing animation.
class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.action,
    this.initial = '',
    this.keyboardType,
  });

  final String title;
  final String label;
  final String action;
  final String initial;
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
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(labelText: widget.label),
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

/// For a member listed as an agent or observer whose identity is not checked
/// yet: why they see the member app, and what happens next.
class _WaitingRoleNote extends StatelessWidget {
  const _WaitingRoleNote({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TgcgColors.primarySoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.hourglass_top_rounded, color: TgcgColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You are listed as a $role. That work starts once a coordinator has checked '
                'your identity; then tap refresh at the top. Until then, you have everything '
                'members have.',
                style: const TextStyle(height: 1.4),
              ),
            ),
          ],
        ),
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

String _date(DateTime value) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}


/// After an INEC transfer: ask for the registered polling unit to change, and
/// follow the request. A coordinator checks the updated card first.
class _PollingUnitChanges extends StatefulWidget {
  const _PollingUnitChanges({required this.scanPvc});

  final ScanPvc scanPvc;

  @override
  State<_PollingUnitChanges> createState() => _PollingUnitChangesState();
}

class _PollingUnitChangesState extends State<_PollingUnitChanges> {
  Future<List<PollingUnitChange>>? _changes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _changes ??= TgcgBackend.of(context)!.client.myPollingUnitChanges();
  }

  void _reload() =>
      setState(() {
        _changes = TgcgBackend.of(context)!.client.myPollingUnitChanges();
      });

  Future<void> _ask() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeRequestDialog(scanPvc: widget.scanPvc),
    );
    if (sent == true) _reload();
  }

  Future<void> _withdraw(PollingUnitChange change) async {
    try {
      await TgcgBackend.of(context)!.client.withdrawPollingUnitChange(change.id);
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Moved to another polling unit?',
        subtitle: 'After an INEC transfer, send your updated voter card. A coordinator checks it '
            'before your polling unit changes.',
        child: FutureBuilder<List<PollingUnitChange>>(
          future: _changes,
          builder: (context, snapshot) {
            final changes = snapshot.data ?? const <PollingUnitChange>[];
            final pending = changes.where((change) => change.isPending).firstOrNull;
            final last = changes.isEmpty ? null : changes.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending != null) ...[
                  Text(
                    'Waiting for review: move to ${pending.toPollingUnit} '
                    '${pending.toPollingUnitName}.',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _withdraw(pending),
                      child: const Text('Withdraw request'),
                    ),
                  ),
                ] else ...[
                  if (last != null && last.status != 'withdrawn')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        last.status == 'approved'
                            ? 'Your last request was approved.'
                            : 'Your last request was not accepted: ${last.decisionReason}',
                        style: const TextStyle(color: TgcgColors.muted),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _ask,
                    icon: const Icon(Icons.move_down_rounded),
                    label: const Text('Ask to change my polling unit'),
                  ),
                ],
              ],
            );
          },
        ),
      );
}

class _ChangeRequestDialog extends StatefulWidget {
  const _ChangeRequestDialog({required this.scanPvc});

  final ScanPvc scanPvc;

  @override
  State<_ChangeRequestDialog> createState() => _ChangeRequestDialogState();
}

class _ChangeRequestDialogState extends State<_ChangeRequestDialog> {
  final _delim = TextEditingController();
  final _reason = TextEditingController();
  Uint8List? _card;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _delim.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _scan({required bool camera}) async {
    final members = TgcgBackend.of(context)!.member;
    var scan = await widget.scanPvc(camera: camera);
    if (scan == null || !mounted) return;
    setState(() => _card = scan!.photo.bytes);
    if (!scan.textRead) {
      // A browser cannot read the card: the server reads the photo, and if it
      // cannot, the member types the code.
      (scan, _) = await readScanOnServer(scan, members.readPvcText);
      if (!mounted) return;
    }
    final code = scan.delim;
    if (code != null && code.isNotEmpty) setState(() => _delim.text = code);
  }

  Future<void> _send() async {
    final card = _card;
    if (card == null || _delim.text.trim().isEmpty) {
      setState(() => _error = 'Scan your updated card and check the code on it.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await TgcgBackend.of(context)!.client.requestPollingUnitChange(
            delim: _delim.text,
            cardImage: card,
            reason: _reason.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = failureMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Change my polling unit'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Scan the voter card INEC gave you after the transfer. Your appointments do '
                  'not change.',
                  style: TextStyle(color: TgcgColors.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (_card != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_card!, height: 140, fit: BoxFit.cover),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _sending ? null : () => _scan(camera: true),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(_card == null ? 'Scan card' : 'Scan again'),
                    ),
                    TextButton.icon(
                      onPressed: _sending ? null : () => _scan(camera: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('From gallery'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _delim,
                  decoration: const InputDecoration(
                    labelText: 'Polling unit code (marked CODE on the card)',
                    hintText: '18-23-01-001',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    labelText: 'Anything to add (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _sending ? null : _send, child: const Text('Send')),
        ],
      );
}
