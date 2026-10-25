import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../access/access_widgets.dart';
import '../account/change_pin_dialog.dart';
import '../access/my_access_page.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../api/member_repository.dart';
import '../api/wallet_repository.dart';
import '../askme/ask_me_chat.dart';
import '../discussion/discussion_room_page.dart';
import '../location/directions.dart';
import '../messaging/inbox_page.dart';
import '../media/device_media.dart';
import '../media/save_download.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'member_registration_page.dart'
    show ScanPvc, TakeSelfie, readScanOnServer, scanPvcWithDevice, takeSelfieWithDevice;
import 'disability_picker.dart';
import 'membership_card_view.dart';
import 'referral.dart';
import 'pvc_scan_page.dart';
import 'registered_members_page.dart';
import 'selfie_check.dart';
import 'wallet_page.dart';

/// The member app: membership card, polling unit, announcements, the Social
/// Forum, volunteering and the member's own appointments, with Ask Me on
/// every tab.
class MemberShell extends StatefulWidget {
  const MemberShell({
    super.key,
    this.launch = launchDirections,
    this.scanPvc = scanPvcWithDevice,
    this.takeSelfie = takeSelfieWithDevice,
    this.checkSelfie = checkSelfieOnDevice,
    this.saveCard = saveDownload,
  });

  /// Opens the maps app (replaced in tests).
  final LaunchDirections launch;

  /// Hands the downloaded card to the member (replaced in tests).
  final SaveDownload saveCard;

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
    final card = await _members.own.card();
    Uint8List? photo;
    if (card.hasPhoto) {
      try {
        photo = await _members.own.photo();
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
            // Shrinks rather than overflow beside the buttons on a narrow phone.
            Flexible(
              child: Text(
                'TGCG Member',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
          const InboxButton(),
          const RegisterMembersButton(),
          IconButton(
            tooltip: 'Change PIN',
            onPressed: () => showChangePin(context),
            icon: const Icon(Icons.password_rounded),
          ),
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
              saveCard: widget.saveCard,
            ),
          1 => _UnitTab(unit: _unit!, launch: widget.launch, scanPvc: widget.scanPvc),
          2 => _NewsTab(news: _news!),
          3 => const DiscussionRoomPage(bottomPadding: _belowAskMe),
          4 => _VolunteerTab(
              offers: _volunteering!,
              onChanged: () => setState(() {
                _volunteering = _members.volunteering();
              }),
            ),
          _ => const MyAccessPage(showHeader: false, bottomPadding: _belowAskMe),
        },
      ),
      // Ask Me, from every tab.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ask-me',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AskMePage()),
        ),
        icon: const Icon(Icons.record_voice_over_outlined),
        label: const Text('Ask Me'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Card'),
          NavigationDestination(icon: Icon(Icons.how_to_vote_outlined), label: 'My unit'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), label: 'News'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Social'),
          NavigationDestination(icon: Icon(Icons.volunteer_activism_outlined), label: 'Volunteer'),
          NavigationDestination(icon: Icon(Icons.assignment_ind_outlined), label: 'Roles'),
        ],
      ),
    );
  }
}

/// The member's card, details and photos, as in the member app's Card tab,
/// for members who use another app: agents, executives and coordinators.
class MyMembershipCardPage extends StatefulWidget {
  const MyMembershipCardPage({
    super.key,
    this.scanPvc = scanPvcWithDevice,
    this.takeSelfie = takeSelfieWithDevice,
    this.checkSelfie = checkSelfieOnDevice,
    this.saveCard = saveDownload,
  });

  final ScanPvc scanPvc;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;
  final SaveDownload saveCard;

  @override
  State<MyMembershipCardPage> createState() => _MyMembershipCardPageState();
}

class _MyMembershipCardPageState extends State<MyMembershipCardPage> {
  Future<(MemberCard, Uint8List?)>? _card;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _card ??= _load();
  }

  Future<(MemberCard, Uint8List?)> _load() async {
    final members = TgcgBackend.of(context)!.member.own;
    final card = await members.card();
    Uint8List? photo;
    if (card.hasPhoto) {
      try {
        photo = await members.photo();
      } on ApiException {
        // The card still shows without the photo.
      }
    }
    return (card, photo);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: TgcgColors.canvas,
        appBar: AppBar(title: const Text('Membership card')),
        body: SafeArea(
          child: _CardTab(
            card: _card!,
            onChanged: () => setState(() {
              _card = _load();
            }),
            scanPvc: widget.scanPvc,
            takeSelfie: widget.takeSelfie,
            checkSelfie: widget.checkSelfie,
            saveCard: widget.saveCard,
          ),
        ),
      );
}

/// Completing the registration of a member the signed-in person registered:
/// the name, phone number and place they gave, the member's details, a photo
/// and the PVC scan, until the member's identity is checked.
class RegisteredMemberPage extends StatefulWidget {
  const RegisteredMemberPage({
    super.key,
    required this.membershipNumber,
    this.scanPvc = scanPvcWithDevice,
    this.takeSelfie = takeSelfieWithDevice,
    this.checkSelfie = checkSelfieOnDevice,
  });

  final String membershipNumber;
  final ScanPvc scanPvc;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;

  @override
  State<RegisteredMemberPage> createState() => _RegisteredMemberPageState();
}

class _RegisteredMemberPageState extends State<RegisteredMemberPage> {
  late MemberRepository _members;
  late MemberProfile _profile;
  Future<(RegisteredMemberDetails, Uint8List?)>? _details;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_details != null) return;
    _members = TgcgBackend.of(context)!.member;
    _profile = _members.registered(widget.membershipNumber);
    _details = _load();
  }

  Future<(RegisteredMemberDetails, Uint8List?)> _load() async {
    final details = await _members.registeredDetails(widget.membershipNumber);
    Uint8List? photo;
    if (details.card.hasPhoto) {
      try {
        photo = await _profile.photo();
      } on ApiException {
        // The details still show without the photo.
      }
    }
    return (details, photo);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: TgcgColors.canvas,
        appBar: AppBar(title: const Text('Complete registration')),
        body: SafeArea(
          child: _RegisteredCard(
            details: _details!,
            members: _members,
            profile: _profile,
            onChanged: () => setState(() {
              _details = _load();
            }),
            scanPvc: widget.scanPvc,
            takeSelfie: widget.takeSelfie,
            checkSelfie: widget.checkSelfie,
          ),
        ),
      );
}

class _RegisteredCard extends StatelessWidget {
  const _RegisteredCard({
    required this.details,
    required this.members,
    required this.profile,
    required this.onChanged,
    required this.scanPvc,
    required this.takeSelfie,
    required this.checkSelfie,
  });

  final Future<(RegisteredMemberDetails, Uint8List?)> details;
  final MemberRepository members;
  final MemberProfile profile;
  final VoidCallback onChanged;
  final ScanPvc scanPvc;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: details,
        builder: (data) {
          final (details, photo) = data;
          final card = details.card;
          final edits = _Edits(
            profile: profile,
            onChanged: onChanged,
            takeSelfie: takeSelfie,
            checkSelfie: checkSelfie,
            forOther: true,
          );
          // Once their PVC is on record, the name and place come from it.
          final fromCard = card.hasPvc;
          final placed = details.place.level != GeographyLevel.country;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: TgcgColors.primarySoft,
                    backgroundImage: photo == null ? null : MemoryImage(photo),
                    child: photo == null
                        ? const Icon(Icons.person_outline_rounded, color: TgcgColors.primary)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.fullName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        Text(card.membershipNumber, style: const TextStyle(color: TgcgColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TgcgSectionCard(
                title: 'Their details',
                child: Column(
                  children: [
                    _Detail(
                      'Name',
                      card.fullName,
                      action: fromCard
                          ? null
                          : TextButton(
                              onPressed: () => _editName(context, card),
                              child: const Text('Change'),
                            ),
                    ),
                    _Detail(
                      'Phone',
                      localPhone(card.phoneNumber),
                      action: details.canChangePhone
                          ? TextButton(
                              onPressed: () => _editPhone(context, card),
                              child: const Text('Change'),
                            )
                          : null,
                    ),
                    _Detail(
                      'Place',
                      placed ? areaLabel(details.place) : 'Not added',
                      action: fromCard
                          ? null
                          : TextButton(
                              onPressed: () => _pickPlace(context, card),
                              child: Text(placed ? 'Change' : 'Add'),
                            ),
                    ),
                    ..._detailRows(context, card, edits),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TgcgSectionCard(
                title: 'Their photo and PVC',
                child: Column(
                  children: [
                    _Detail(
                      'Photo of them',
                      card.hasPhoto ? 'Added' : 'Not added',
                      action: edits._changeAction(
                        card,
                        card.hasPhoto,
                        () => edits._addSelfie(context),
                      ),
                    ),
                    _PvcScanRow(
                      key: ObjectKey(card),
                      card: card,
                      profile: profile,
                      scanPvc: scanPvc,
                      onChanged: onChanged,
                      forOther: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );

  Future<void> _editName(BuildContext context, MemberCard card) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: 'Name',
        label: 'Full name, as on their PVC',
        action: 'Save',
        initial: card.fullName,
      ),
    );
    if (name == null || name.isEmpty || name == card.fullName) return;
    await _correct(
      messenger,
      'full_name',
      () => members.correctRegistration(card.membershipNumber, fullName: name),
    );
  }

  /// The number is also their first password, so both change together.
  Future<void> _editPhone(BuildContext context, MemberCard card) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: 'Phone number',
        label: 'Their phone number',
        action: 'Save',
        initial: localPhone(card.phoneNumber),
        keyboardType: TextInputType.phone,
      ),
    );
    if (phone == null || phone.isEmpty) return;
    final saved = await _correct(
      messenger,
      'phone_number',
      () => members.correctRegistration(card.membershipNumber, phone: phone),
    );
    if (saved == null) return;
    final number = localPhone(saved.card.phoneNumber);
    messenger.showSnackBar(
      SnackBar(content: Text('They now sign in with $number, and $number is the password.')),
    );
  }

  Future<void> _pickPlace(BuildContext context, MemberCard card) async {
    final messenger = ScaffoldMessenger.of(context);
    final place = await pickArea(
      context,
      levels: const [
        GeographyLevel.state,
        GeographyLevel.lga,
        GeographyLevel.ward,
        GeographyLevel.pollingUnit,
      ],
    );
    if (place == null) return;
    await _correct(
      messenger,
      'scope',
      () => members.correctRegistration(card.membershipNumber, place: place),
    );
  }

  Future<RegisteredMemberDetails?> _correct(
    ScaffoldMessengerState messenger,
    String field,
    Future<RegisteredMemberDetails> Function() save,
  ) async {
    try {
      final saved = await save();
      onChanged();
      return saved;
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.fieldError(field) ?? error.message)));
      return null;
    }
  }
}

/// Shows a loading spinner, an error with a hint, or the loaded data.
/// Room at the bottom of each tab's list, so its last item scrolls clear of
/// the Ask Me button.
const _belowAskMe = 96.0;
const _tabPadding = EdgeInsets.fromLTRB(16, 16, 16, _belowAskMe);

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
    required this.saveCard,
  });
  final Future<(MemberCard, Uint8List?)> card;
  final VoidCallback onChanged;
  final ScanPvc scanPvc;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;
  final SaveDownload saveCard;

  @override
  Widget build(BuildContext context) => _Loaded(
        future: card,
        builder: (data) {
          final (card, photo) = data;
          final waitingRole = TgcgSession.of(context).waitingRole;
          final edits = _Edits(
            profile: TgcgBackend.of(context)!.member.own,
            onChanged: onChanged,
            takeSelfie: takeSelfie,
            checkSelfie: checkSelfie,
          );
          return ListView(
            padding: _tabPadding,
            children: [
              if (waitingRole != null) ...[
                _WaitingRoleNote(role: waitingRole),
                const SizedBox(height: 14),
              ],
              Center(child: MembershipCardView(card: card, photo: photo)),
              const SizedBox(height: 12),
              _CardDownload(card: card, save: saveCard),
              const SizedBox(height: 18),
              const _WalletRow(),
              const ReferralCard(),
              TgcgSectionCard(
                title: 'My details',
                child: Column(
                  children: [
                    _Detail('Phone', card.phoneNumber),
                    ..._detailRows(context, card, edits),
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
                title: 'My photo and PVC',
                child: Column(
                  children: [
                    _Detail(
                      'Photo of you',
                      card.hasPhoto ? 'Added' : 'Not added',
                      action: edits._changeAction(
                        card,
                        card.hasPhoto,
                        () => edits._addSelfie(context),
                      ),
                    ),
                    // A new card means a fresh look at the scan, e.g. after one applied.
                    _PvcScanRow(
                      key: ObjectKey(card),
                      card: card,
                      profile: edits.profile,
                      scanPvc: scanPvc,
                      onChanged: onChanged,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
}

/// The details a member adds or changes after joining, as rows with their
/// buttons: the member's own, or those of someone they registered.
List<Widget> _detailRows(BuildContext context, MemberCard card, _Edits edits) => [
      _Detail(
        'Email',
        card.email.isEmpty ? 'Not added' : card.email,
        action: TextButton(
          onPressed: () => edits._editEmail(context, card),
          child: Text(card.email.isEmpty ? 'Add' : 'Change'),
        ),
      ),
      _Detail(
        'WhatsApp',
        card.whatsappNumber.isEmpty ? 'Same as phone' : card.whatsappNumber,
        action: TextButton(
          onPressed: () => edits._editWhatsapp(context, card),
          child: const Text('Change'),
        ),
      ),
      _Detail('PVC', card.vin ?? 'Not on record'),
      _Detail(
        'Gender',
        switch (card.gender) {
          'male' => 'Male',
          'female' => 'Female',
          _ => 'Not added',
        },
        action: edits._changeAction(
          card,
          card.gender.isNotEmpty,
          () => edits._pickGender(context, card),
        ),
      ),
      _Detail(
        'Date of birth',
        card.dateOfBirth == null ? 'Not added' : _date(card.dateOfBirth!),
        action: edits._changeAction(
          card,
          card.dateOfBirth != null,
          () => edits._pickBirthday(context, card),
        ),
      ),
      _Detail(
        'Occupation',
        card.occupation.isEmpty ? 'Not added' : card.occupation,
        action: TextButton(
          onPressed: () => edits._editOccupation(context, card),
          child: Text(card.occupation.isEmpty ? 'Add' : 'Change'),
        ),
      ),
      _Detail(
        'Disability',
        card.disabilities.isEmpty
            ? 'None given'
            : disabilityText(card.disabilities, card.disabilityOther),
        action: TextButton(
          onPressed: () => edits._pickDisabilities(context, card),
          child: Text(card.disabilities.isEmpty ? 'Add' : 'Change'),
        ),
      ),
    ];

/// The edits on a member's details, through [profile]: the member's own, or
/// those of a member the signed-in person registered ([forOther], which
/// words them for someone else).
class _Edits {
  const _Edits({
    required this.profile,
    required this.onChanged,
    required this.takeSelfie,
    required this.checkSelfie,
    this.forOther = false,
  });

  final MemberProfile profile;
  final VoidCallback onChanged;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;
  final bool forOther;

  /// [yours] for the member's own details; [theirs] for someone they registered.
  String _say(String yours, String theirs) => forOther ? theirs : yours;

  /// For the photos, gender and date of birth: add one that is missing, or
  /// change it until the identity is checked; after that a coordinator does.
  Widget? _changeAction(MemberCard card, bool added, VoidCallback onPressed) {
    if (added && card.identityChecked) return null;
    return TextButton(onPressed: onPressed, child: Text(added ? 'Change' : 'Add'));
  }

  Future<void> _pickGender(BuildContext context, MemberCard card) async {
    final members = profile;
    final messenger = ScaffoldMessenger.of(context);
    final gender = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_say('Gender, as on your PVC', 'Gender, as on their PVC')),
        children: [
          for (final (value, label) in const [('male', 'Male'), ('female', 'Female')])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text(label, style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
    if (gender == null || gender == card.gender) return;
    try {
      await members.updateGender(gender);
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.fieldError('gender') ?? error.message)));
    }
  }

  Future<void> _pickBirthday(BuildContext context, MemberCard card) async {
    final members = profile;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: card.dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 110),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      helpText: _say('Date of birth, as on your PVC', 'Date of birth, as on their PVC'),
    );
    if (picked == null || picked == card.dateOfBirth) return;
    try {
      await members.updateDateOfBirth(picked);
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.fieldError('date_of_birth') ?? error.message)),
      );
    }
  }

  /// The member's own, to give, change or take back at any time.
  Future<void> _pickDisabilities(BuildContext context, MemberCard card) async {
    final members = profile;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showDialog<(List<String>, String)>(
      context: context,
      builder: (_) => DisabilityDialog(kinds: card.disabilities, other: card.disabilityOther),
    );
    if (picked == null) return;
    final (kinds, other) = picked;
    try {
      await members.updateDisabilities(kinds, other);
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.fieldError('disability_other') ?? error.fieldError('disabilities') ?? error.message,
          ),
        ),
      );
    }
  }

  Future<void> _editEmail(BuildContext context, MemberCard card) async {
    final members = profile;
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

  Future<void> _editWhatsapp(BuildContext context, MemberCard card) async {
    final members = profile;
    final messenger = ScaffoldMessenger.of(context);
    final number = await showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: 'WhatsApp number',
        label: _say(
          'Leave empty if it is your phone number',
          'Leave empty if it is their phone number',
        ),
        action: 'Save',
        initial: card.whatsappNumber,
        keyboardType: TextInputType.phone,
      ),
    );
    if (number == null) return;
    try {
      await members.updateWhatsappNumber(number);
      onChanged();
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.fieldError('whatsapp_number') ?? error.message)),
      );
    }
  }

  Future<void> _editOccupation(BuildContext context, MemberCard card) async {
    final members = profile;
    final messenger = ScaffoldMessenger.of(context);
    final occupation = await showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: 'Occupation',
        label: _say('What you do for a living', 'What they do for a living'),
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
    final members = profile;
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
              title: Text(_say('Check your photo', 'Check the photo')),
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
        messenger.showSnackBar(
          SnackBar(content: Text(_say('Your photo was saved.', 'The photo was saved.'))),
        );
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

}

/// Downloads the card as a PDF (front and back) once nothing is missing;
/// until then, says what to add first.
class _CardDownload extends StatefulWidget {
  const _CardDownload({required this.card, required this.save});

  final MemberCard card;
  final SaveDownload save;

  @override
  State<_CardDownload> createState() => _CardDownloadState();
}

class _CardDownloadState extends State<_CardDownload> {
  var _busy = false;

  Future<void> _download() async {
    final members = TgcgBackend.of(context)!.member;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final pdf = await members.cardPdf();
      final name = '${widget.card.membershipNumber}-card.pdf';
      final saved = await widget.save(pdf, name, 'application/pdf');
      if (saved != null) messenger.showSnackBar(SnackBar(content: Text('Saved in $saved')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('The card could not be saved: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing = widget.card.cardMissing;
    return Column(
      children: [
        FilledButton.icon(
          onPressed: missing.isEmpty && !_busy ? _download : null,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download_rounded),
          label: const Text('Download card (PDF)'),
        ),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'First add ${missing.map((need) => cardNeeds[need] ?? need).join(', ')}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
            ),
          ),
      ],
    );
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
            padding: _tabPadding,
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
            padding: _tabPadding,
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
            padding: _tabPadding,
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

/// The member's one PVC scan: the card's details replace the ones they typed
/// when joining. A card scanned or uploaded when joining is on record already.
/// Through [profile], the person who registered a member scans theirs.
class _PvcScanRow extends StatefulWidget {
  const _PvcScanRow({
    super.key,
    required this.card,
    required this.profile,
    required this.scanPvc,
    required this.onChanged,
    this.forOther = false,
  });

  final MemberCard card;
  final MemberProfile profile;
  final ScanPvc scanPvc;
  final VoidCallback onChanged;
  final bool forOther;

  @override
  State<_PvcScanRow> createState() => _PvcScanRowState();
}

class _PvcScanRowState extends State<_PvcScanRow> {
  late MemberRepository _members;
  Future<PvcScanState>? _state;

  String get _label => widget.forOther ? 'Their PVC' : 'Your PVC';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _members = TgcgBackend.of(context)!.member;
    _state ??= widget.profile.pvcScan();
  }

  void _reload() => setState(() {
        _state = widget.profile.pvcScan();
      });

  Future<void> _scan() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
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
      var scan = await widget.scanPvc(camera: camera);
      if (scan == null || !mounted) return;
      if (!scan.textRead) {
        // A browser cannot read the card: the server reads the photo.
        final (read, problem) = await readScanOnServer(scan, _members.readPvcText);
        scan = read;
        if (problem != null) messenger.showSnackBar(SnackBar(content: Text(problem)));
      }
      final checked = scan;
      final result = await navigator.push<PvcScanResult>(
        MaterialPageRoute(
          builder: (_) => PvcScanPage(
            scan: checked,
            card: widget.card,
            profile: widget.profile,
            forOther: widget.forOther,
          ),
        ),
      );
      if (result == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.isPending
                ? 'Sent. A coordinator will check the new details against your card.'
                : widget.forOther
                    ? 'Their details now match their PVC.'
                    : 'Your details now match your PVC.',
          ),
        ),
      );
      widget.onChanged();
      if (mounted) _reload();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeDeviceError(error))));
    }
  }

  Future<void> _withdraw(PvcScanResult latest) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.profile.withdrawPvcScan(latest.id);
      if (mounted) _reload();
      messenger.showSnackBar(const SnackBar(content: Text('Scan taken back. You can scan again.')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PvcScanState>(
        future: _state,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final latest = state?.latest;
          if (state == null) {
            return _Detail(_label, snapshot.hasError ? 'Could not load' : '…');
          }
          if (latest != null && latest.isPending) {
            return _Detail(
              _label,
              'Waiting for a coordinator',
              action: TextButton(onPressed: () => _withdraw(latest), child: const Text('Withdraw')),
            );
          }
          if (state.canScan) {
            return _Detail(
              _label,
              latest?.status == 'rejected'
                  ? 'Not accepted: ${latest!.decisionReason}'
                  : 'Not scanned',
              action: TextButton(onPressed: _scan, child: const Text('Scan')),
            );
          }
          return _Detail(_label, 'On record');
        },
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

/// The wallet's balance, opening the wallet. Nothing shows when the server
/// has no wallet to give.
class _WalletRow extends StatefulWidget {
  const _WalletRow();

  @override
  State<_WalletRow> createState() => _WalletRowState();
}

class _WalletRowState extends State<_WalletRow> {
  Future<MemberWallet>? _wallet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wallet ??= TgcgBackend.of(context)?.wallets.myWallet();
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MyWalletPage()),
    );
    if (!mounted) return;
    setState(() {
      _wallet = TgcgBackend.of(context)?.wallets.myWallet();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MemberWallet>(
        future: _wallet,
        builder: (context, snapshot) {
          final wallet = snapshot.data;
          if (wallet == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TgcgSectionCard(
              title: 'My wallet',
              trailing: TextButton(onPressed: _open, child: const Text('Open')),
              child: _Detail(
                'Balance',
                wallet.hasWallet ? formatNaira(wallet.balance) : 'Not open yet',
              ),
            ),
          );
        },
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
