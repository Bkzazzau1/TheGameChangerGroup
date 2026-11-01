import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show failureMessage, formatDay, formatMoment, promptText;
import '../api/api_client.dart' show ApiException;
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../api/member_repository.dart' show disabilityText;
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'member_search.dart' show MemberAvatar, channelLabel, standingColor;
import 'members_exco_page.dart' show ageOn, levelLabel, standingChips;

/// Everything on record about a member that this account may see, with their
/// photos large enough to judge by. A member awaiting review can be approved
/// or rejected here, by whoever the server lets decide them: the buttons only
/// appear once it has said so, and it checks again on every decision.
///
/// [reviewAny] also offers the decision on a member not awaiting review, for
/// Member Review. [onChanged] runs after a decision, so the list behind this
/// view can show it.
Future<void> showMemberDetails(
  BuildContext context,
  String number, {
  bool reviewAny = false,
  VoidCallback? onChanged,
}) => showDialog<void>(
  context: context,
  builder: (_) => _MemberProfile(number: number, reviewAny: reviewAny, onChanged: onChanged),
);

class _MemberProfile extends StatefulWidget {
  const _MemberProfile({required this.number, required this.reviewAny, this.onChanged});

  final String number;
  final bool reviewAny;
  final VoidCallback? onChanged;

  @override
  State<_MemberProfile> createState() => _MemberProfileState();
}

class _MemberProfileState extends State<_MemberProfile> {
  late MemberAdminRepository _members;
  bool _started = false;

  StaffMember? _member;
  Object? _failure;

  /// Null until the server says this account may decide this member.
  MemberVerification? _verification;

  /// The review could not be loaded, for a reason other than being refused.
  Object? _reviewFailure;
  Future<Uint8List>? _selfie;
  Future<Uint8List>? _card;
  bool _busy = false;
  String? _done;
  Object? _problem;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _members = TgcgBackend.of(context)!.members;
    unawaited(_loadMember());
    final session = TgcgSession.maybeOf(context);
    if (session?.can(TgcgCapability.verifyMemberIdentity) ?? false) {
      unawaited(_loadReview());
    }
  }

  Future<void> _loadMember() async {
    try {
      final member = await _members.member(widget.number);
      if (mounted) setState(() => _member = member);
    } catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _loadReview() async {
    try {
      final verification = await _members.verification(widget.number);
      if (!mounted) return;
      setState(() {
        _verification = verification;
        _reviewFailure = null;
      });
    } on ApiException catch (error) {
      // Refused: this account does not decide this member, so it offers nothing.
      if (mounted && error.statusCode != 403 && error.statusCode != 404) {
        setState(() => _reviewFailure = error);
      }
    } catch (error) {
      if (mounted) setState(() => _reviewFailure = error);
    }
  }

  /// The selfie: for those who see personal details, and for whoever decides.
  Future<Uint8List>? _selfieOf(StaffMember member) {
    final available = member.sensitiveVisible
        ? member.photoUrl != null
        : _verification != null && !member.gaps.contains('selfie');
    return available ? _selfie ??= _members.photo(member.membershipNumber) : null;
  }

  /// The voter card shows the whole VIN: only for whoever decides.
  Future<Uint8List>? _cardOf(StaffMember member) {
    final available = _verification != null && !member.gaps.contains('cardPhoto');
    return available ? _card ??= _members.cardPhoto(member.membershipNumber) : null;
  }

  bool _deciding(StaffMember member) =>
      _verification != null && (widget.reviewAny || member.verificationStatus == 'pendingReview');

  Future<void> _run(Future<MemberVerification> Function() action, String done) async {
    setState(() {
      _busy = true;
      _done = null;
      _problem = null;
    });
    try {
      final verification = await action();
      widget.onChanged?.call();
      // The decision stands even if reading the member again fails.
      final member = await _members
          .member(widget.number)
          .then<StaffMember?>((member) => member, onError: (_) => null);
      if (!mounted) return;
      setState(() {
        _verification = verification;
        _member = member ?? _member;
        _done = done;
      });
    } catch (error) {
      if (mounted) setState(() => _problem = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(StaffMember member) async {
    final notes = await promptText(
      context,
      title: "Approve ${member.displayName}'s identity?",
      message:
          'Record what you checked yourself, for example that you compared the PVC with '
          'the person in front of you. Do not write the VIN or phone number here.',
      label: 'What you checked and how',
      action: 'Approve',
      required: true,
    );
    if (notes == null) return;
    await _run(
      () => _members.approveIdentity(member.membershipNumber, notes),
      'Identity approved.',
    );
  }

  Future<void> _reject(StaffMember member) async {
    final reason = await promptText(
      context,
      title: "Reject ${member.displayName}'s identity?",
      message:
          'Any appointments they hold stop at once, and they cannot be appointed until '
          'their identity is confirmed.',
      label: 'Why it could not be confirmed',
      action: 'Reject',
      required: true,
      destructive: true,
    );
    if (reason == null) return;
    await _run(
      () => _members.rejectIdentity(member.membershipNumber, reason),
      'Identity rejected.',
    );
  }

  /// Who this is and where they stand: the first thing to read.
  Widget _heading(StaffMember member) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(member.displayName, style: TgcgType.title),
      const SizedBox(height: 2),
      SelectableText(member.membershipNumber, style: TgcgType.support),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: standingChips(
          verificationStatus: member.verificationStatus,
          verifiedHow: member.verifiedHow,
          gaps: member.gaps,
          signedIn: member.signedIn,
          membershipState: member.membershipState,
        ),
      ),
    ],
  );

  Widget _record(StaffMember member) {
    final verification = _verification;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_reviewFailure case final problem?) ...[
          const SizedBox(height: 12),
          TgcgNotice(
            icon: Icons.cloud_off_outlined,
            color: TgcgColors.warning,
            action: TextButton(onPressed: _loadReview, child: const Text('Try again')),
            child: Text('The review could not be loaded: ${failureMessage(problem)}'),
          ),
        ],
        if (verification != null && _deciding(member)) ...[
          const SizedBox(height: 14),
          _ReviewPanel(
            verification: verification,
            onRunChecks: _busy
                ? null
                : () =>
                      _run(() => _members.runChecks(member.membershipNumber), 'Checks run again.'),
          ),
        ],
        _Sections(member: member),
      ],
    );
  }

  Widget _photos(StaffMember member, {required bool wide}) {
    final color = standingColor(
      member.verificationStatus,
      member.gaps.isEmpty,
      member.membershipState,
    );
    final selfie = _selfieOf(member);
    final card = _cardOf(member);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Picture(
          key: const ValueKey('member-photo'),
          picture: selfie,
          label: selfie != null
              ? 'Photo'
              : member.sensitiveVisible || member.gaps.contains('selfie')
              ? 'No photo on record'
              : 'Photo hidden for your role',
          aspectRatio: wide ? 4 / 5 : 1,
          empty: MemberAvatar(name: member.displayName, color: color, size: 112),
        ),
        if (card != null) ...[
          const SizedBox(height: 12),
          _Picture(
            key: const ValueKey('member-card-photo'),
            picture: card,
            label: 'Voter card',
            aspectRatio: 1.6,
            // All of it, to the edges: this is what the decision rests on.
            fit: BoxFit.contain,
            empty: const Icon(Icons.badge_outlined, size: 48, color: TgcgColors.primary),
          ),
        ],
      ],
    );
  }

  Widget _content(BuildContext context, {required bool wide}) {
    final member = _member;
    if (_failure case final failure?) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failureMessage(failure), style: const TextStyle(color: TgcgColors.danger)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      );
    }
    if (member == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    final deciding = _deciding(member);
    final status = member.verificationStatus;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TgcgSpacing.lg - 4),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 300, child: _photos(member, wide: true)),
                      const SizedBox(width: TgcgSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_heading(member), _record(member)],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heading(member),
                      const SizedBox(height: 14),
                      _photos(member, wide: false),
                      _record(member),
                    ],
                  ),
          ),
        ),
        // Always in reach, however long the record is.
        DecoratedBox(
          decoration: const BoxDecoration(
            color: TgcgColors.surface,
            border: Border(top: BorderSide(color: TgcgColors.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_done case final done?) ...[
                  TgcgNotice(
                    icon: Icons.check_circle_rounded,
                    color: TgcgColors.success,
                    child: Text(done),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_problem case final problem?) ...[
                  TgcgNotice(
                    icon: Icons.error_outline_rounded,
                    color: TgcgColors.danger,
                    child: Text(failureMessage(problem)),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                    if (deciding && status != 'rejected')
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _reject(member),
                        style: OutlinedButton.styleFrom(foregroundColor: TgcgColors.danger),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Reject'),
                      ),
                    if (deciding && status != 'verified')
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _approve(member),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Approve'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) {
      return Dialog.fullscreen(
        backgroundColor: TgcgColors.surface,
        child: SafeArea(child: _content(context, wide: false)),
      );
    }
    return Dialog(
      backgroundColor: TgcgColors.surface,
      insetPadding: const EdgeInsets.all(TgcgSpacing.lg),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.lg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: _content(context, wide: width >= 860),
      ),
    );
  }
}

/// A picture to judge by: tap it to see it full screen and zoom in.
class _Picture extends StatelessWidget {
  const _Picture({
    super.key,
    required this.picture,
    required this.label,
    required this.aspectRatio,
    required this.empty,
    this.fit = BoxFit.cover,
  });

  final Future<Uint8List>? picture;
  final String label;
  final double aspectRatio;
  final BoxFit fit;

  /// In its place when there is no picture.
  final Widget empty;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: picture,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      final waiting = picture != null && !snapshot.hasData && !snapshot.hasError;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(TgcgRadius.md),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: bytes == null
                  ? ColoredBox(
                      color: TgcgColors.primarySoft,
                      child: Center(
                        child: waiting
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : snapshot.hasError
                            ? const Icon(
                                Icons.no_photography_outlined,
                                size: 48,
                                color: TgcgColors.muted,
                              )
                            : empty,
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: TgcgColors.primarySoft),
                        Image.memory(
                          bytes,
                          fit: fit,
                          semanticLabel: label,
                          errorBuilder: (context, _, _) => const ColoredBox(
                            color: TgcgColors.primarySoft,
                            child: Icon(
                              Icons.no_photography_outlined,
                              size: 48,
                              color: TgcgColors.muted,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(onTap: () => _showFull(context, bytes, label)),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(snapshot.hasError ? '$label could not be loaded' : label, style: TgcgType.caption),
        ],
      );
    },
  );
}

Future<void> _showFull(BuildContext context, Uint8List bytes, String label) => showDialog<void>(
  context: context,
  barrierColor: Colors.black,
  builder: (context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(bytes, fit: BoxFit.contain, semanticLabel: label),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton.filledTonal(
              tooltip: 'Close photo',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
      ],
    ),
  ),
);

/// What the system could and could not check, for the person deciding.
class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({required this.verification, required this.onRunChecks});

  final MemberVerification verification;
  final VoidCallback? onRunChecks;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
    decoration: BoxDecoration(
      color: TgcgColors.surfaceSoft,
      borderRadius: BorderRadius.circular(TgcgRadius.md),
      border: Border.all(color: TgcgColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Identity checks', style: TgcgType.section),
        if (verification.reviewedBy != null)
          Text('Last decision by ${verification.reviewedBy}', style: TgcgType.caption)
        else if (verification.verifiedAutomatically)
          const Text('Verified automatically', style: TgcgType.caption),
        const SizedBox(height: 8),
        for (final check in verification.checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (check.result) {
                    'passed' => Icons.check_circle_rounded,
                    'failed' => Icons.cancel_rounded,
                    'pending' => Icons.hourglass_top_rounded,
                    _ => Icons.help_outline_rounded,
                  },
                  size: 20,
                  color: switch (check.result) {
                    'passed' => TgcgColors.success,
                    'failed' => TgcgColors.danger,
                    'pending' => TgcgColors.warning,
                    _ => TgcgColors.muted,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(checkLabel(check.kind), style: TgcgType.label),
                      Text(check.detail, style: TgcgType.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const Text(
          'Checks marked as not available were not performed: no authoritative INEC source, '
          'liveness detection or trusted reference photo is connected. Confirm those in person.',
          style: TgcgType.caption,
        ),
        if (verification.hasFailedCheck)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'A failed check must be resolved (for example by adding the PVC) before the '
              'identity can be confirmed.',
              style: TgcgType.caption.copyWith(color: TgcgColors.danger),
            ),
          ),
        TextButton(onPressed: onRunChecks, child: const Text('Run checks again')),
      ],
    ),
  );
}

/// The member's record, section by section.
class _Sections extends StatelessWidget {
  const _Sections({required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final age = ageOn(member.dateOfBirth, DateTime.now());
    final scope = member.scope;
    String place(String? name, String? code) => [
      if (name != null && name.isNotEmpty) name,
      if (code != null && code.isNotEmpty && code != name) code,
    ].join(' · ');
    String assigned(String? name, String? code) {
      final value = place(name, code);
      return value.isEmpty ? 'Not assigned' : value;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: 'Positions',
          children: member.posts.isEmpty
              ? [const _Line('None', 'An ordinary member')]
              : [
                  for (final post in member.posts)
                    _Line(
                      post.roleName,
                      [
                        if (post.areaName.isNotEmpty)
                          post.areaLevel == null || post.areaLevel == GeographyLevel.country
                              ? post.areaName
                              : '${post.areaName} ${levelLabel(post.areaLevel!)}',
                        if (post.state != 'active') post.state,
                      ].join(' · '),
                    ),
                ],
        ),
        _Section(
          title: 'Contact',
          children: [
            _Line(
              'Phone',
              member.sensitiveVisible
                  ? member.phoneNumber ?? 'Not provided'
                  : 'Hidden for your role',
              selectable: member.sensitiveVisible,
            ),
            if (member.sensitiveVisible && (member.whatsappNumber ?? '').isNotEmpty)
              _Line('WhatsApp', member.whatsappNumber!, selectable: true),
            if (member.sensitiveVisible && (member.email ?? '').isNotEmpty)
              _Line('Email', member.email!, selectable: true),
          ],
        ),
        _Section(
          title: 'Registration',
          children: [
            if (member.createdAt != null) _Line('Joined', formatDay(member.createdAt!)),
            if (member.updatedAt != null) _Line('Last updated', formatMoment(member.updatedAt!)),
            _Line('How they joined', channelLabel(member.registrationChannel)),
            _Line('Membership', switch (member.membershipState) {
              'suspended' => 'Suspended',
              'deactivated' => 'Deactivated',
              _ => 'Active',
            }),
          ],
        ),
        _Section(
          title: 'Registered location',
          children: [
            if (scope.zoneId != null) _Line('Zone', place(scope.zoneName, scope.zoneId)),
            _Line('State', assigned(scope.stateName, scope.stateId)),
            if (scope.senatorialDistrictId != null)
              _Line('District', place(scope.senatorialDistrictName, scope.senatorialDistrictId)),
            _Line('LGA', assigned(scope.lgaName, scope.lgaId)),
            _Line('Ward', assigned(scope.wardName, scope.wardId)),
            _Line('Polling unit', assigned(scope.pollingUnitName, scope.pollingUnitId)),
            if (member.pollingUnitFromList) _Line('Unit selection', 'Chosen from the list'),
          ],
        ),
        _Section(
          title: 'Identity & profile',
          children: [
            _Line('Identity', verificationLabel(member.verificationStatus)),
            if (member.verifiedAt != null) _Line('Verified on', formatMoment(member.verifiedAt!)),
            _Line(
              'Voter card',
              member.hasPvc
                  ? member.sensitiveVisible && member.vin != null
                        ? 'VIN ${member.vin}'
                        : 'VIN on record'
                  : 'No VIN',
            ),
            if (member.gender.isNotEmpty)
              _Line('Gender', member.gender == 'female' ? 'Woman' : 'Man'),
            if (member.sensitiveVisible && member.dateOfBirth != null)
              _Line(
                'Born',
                '${formatDay(member.dateOfBirth!)}${age == null ? '' : ' ($age years)'}',
              ),
            if (member.occupation.isNotEmpty) _Line('Occupation', member.occupation),
          ],
        ),
        if (member.sensitiveVisible && member.disabilities.isNotEmpty)
          _Section(
            title: 'Accessibility',
            children: [
              _Line('Disability', disabilityText(member.disabilities, member.disabilityOther)),
            ],
          ),
        _Section(
          title: 'App',
          children: [
            _Line('App account', member.hasAppAccount ? 'Linked' : 'None'),
            _Line(
              'Signed in',
              member.lastSignIn != null
                  ? 'Last on ${formatMoment(member.lastSignIn!)}'
                  : member.hasAppAccount
                  ? 'Never'
                  : 'No app account',
            ),
            _Line('Phone confirmed', member.phoneVerified ? 'Yes' : 'No'),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: TgcgType.eyebrow),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.selectable = false});

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    const valueStyle = TextStyle(color: TgcgColors.ink, fontSize: 13, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(label, style: TgcgType.support);
          final valueWidget = selectable
              ? SelectableText(value, style: valueStyle)
              : Text(value, style: valueStyle);
          if (constraints.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 2), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: labelWidget),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
