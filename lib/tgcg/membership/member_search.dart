import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show failureMessage, formatDay, formatMoment;
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../api/member_repository.dart' show disabilityText;
import '../api/reference_repository.dart' show RegistrationPlace;
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'members_exco_page.dart' show ageOn, formatCount, levelLabel, standingChips;

/// The status choices: (label, show, verification status, membership state).
const memberStatusFilters = <(String, String?, String?, String?)>[
  ('Any status', null, null, null),
  ('Exco', 'withRole', null, null),
  ('Ordinary members', 'withoutRole', null, null),
  ('Fully verified', 'fullyVerified', null, null),
  ('Not fully verified', 'notFullyVerified', null, null),
  ('Awaiting review', null, 'pendingReview', null),
  ('Not checked yet', null, 'unverified', null),
  ('Suspended', null, null, 'suspended'),
  ('Never signed in', 'neverSignedIn', null, null),
];

String channelLabel(String channel) => switch (channel) {
  'self' => 'Joined in the app',
  'assisted' => 'By a coordinator',
  'ussd' => 'By USSD',
  'import' => "From a chapter's list",
  'referred' => 'By another member',
  _ => 'Other',
};

String placeOf(GeographicScope scope) =>
    [?scope.pollingUnitName, ?scope.wardName, ?scope.lgaName, ?scope.stateName].join(', ');

/// "LGA Women Leader · Kaduna North LGA".
String postLabel(MemberPost post) {
  final level = post.areaLevel;
  final where = post.areaName.isEmpty
      ? ''
      : level == null || level == GeographyLevel.country
      ? post.areaName
      : '${post.areaName} ${levelLabel(level)}';
  return where.isEmpty ? post.roleName : '${post.roleName} · $where';
}

Color _standingColor(String verification, bool complete, String membershipState) {
  if (membershipState != 'active') return TgcgColors.danger;
  return switch (verification) {
    'verified' => complete ? TgcgColors.success : TgcgColors.info,
    'pendingReview' => TgcgColors.warning,
    'rejected' => TgcgColors.danger,
    _ => TgcgColors.muted,
  };
}

/// The member's initials on a disc coloured by their standing.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 44,
    this.photo,
  });

  final String name;
  final Color color;
  final double size;
  final Uint8List? photo;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: .13),
      border: Border.all(color: color.withValues(alpha: .45), width: 1.5),
      image: photo == null ? null : DecorationImage(image: MemoryImage(photo!), fit: BoxFit.cover),
    ),
    alignment: Alignment.center,
    child: photo == null
        ? Text(
            _initials,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: size * .34),
          )
        : null,
  );
}

/// Find members anywhere in Nigeria: by name, membership number, phone,
/// position or place, narrowed by state, LGA, position and status. Each
/// result shows the person's posts and where they stand; tapping opens their
/// profile.
class MemberSearch extends StatefulWidget {
  const MemberSearch({
    super.key,
    this.initialQuery = '',
    this.autofocus = false,
    this.alwaysShowResults = false,
    this.onActiveChanged,
  });

  final String initialQuery;
  final bool autofocus;

  /// Show results (everyone) before anything is typed or chosen.
  final bool alwaysShowResults;

  /// Told when a search starts or is cleared.
  final ValueChanged<bool>? onActiveChanged;

  @override
  State<MemberSearch> createState() => _MemberSearchState();
}

class _MemberSearchState extends State<MemberSearch> {
  late final _text = TextEditingController(text: widget.initialQuery);
  RegistrationPlace? _state;
  RegistrationPlace? _lga;
  (String, String)? _role;
  int _status = 0;
  bool _newest = false;

  Future<List<RegistrationPlace>>? _states;
  Future<List<RegistrationPlace>>? _lgas;
  Future<List<(String, String, int)>>? _roles;

  final _members = <StaffMember>[];
  int _count = 0;
  bool _more = false;
  bool _loading = false;
  Object? _error;
  Timer? _debounce;
  bool _wasActive = false;

  bool get _active =>
      widget.alwaysShowResults ||
      _text.text.trim().isNotEmpty ||
      _state != null ||
      _role != null ||
      _status != 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = TgcgBackend.of(context);
    if (backend != null && _states == null) {
      _states = backend.reference.registrationPlaces();
      _roles = backend.members
          .analysis(AreaRef.nigeria)
          .then((analysis) => analysis.exco.roles, onError: (_) => <(String, String, int)>[]);
      if (_active) unawaited(_load());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    final active = _active;
    if (active != _wasActive) {
      _wasActive = active;
      widget.onActiveChanged?.call(active);
    }
    setState(() {});
    if (active) {
      unawaited(_load());
    } else {
      _members.clear();
    }
  }

  void _typed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _changed);
  }

  void _clear() {
    _debounce?.cancel();
    _text.clear();
    _state = null;
    _lga = null;
    _lgas = null;
    _role = null;
    _status = 0;
    _changed();
  }

  AreaRef? get _area => _lga != null
      ? AreaRef(GeographyLevel.lga, _lga!.code, _lga!.name)
      : _state != null
      ? AreaRef(GeographyLevel.state, _state!.code, _state!.name)
      : null;

  Future<void> _load({bool more = false}) async {
    final backend = TgcgBackend.of(context);
    if (backend == null) return;
    final (_, show, verification, standing) = memberStatusFilters[_status];
    final asked = '${_text.text}|${_area?.code}|${_role?.$1}|$_status|$_newest';
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _members.clear();
    });
    try {
      final page = await backend.members.members(
        query: _text.text,
        area: _area,
        role: _role?.$1,
        show: show,
        verificationStatus: verification,
        membershipState: standing,
        ordering: _newest ? '-created_at' : 'full_name',
        offset: more ? _members.length : 0,
      );
      final now = '${_text.text}|${_area?.code}|${_role?.$1}|$_status|$_newest';
      if (!mounted || now != asked) return; // a newer search is on its way
      setState(() {
        if (!more) _members.clear();
        _members.addAll(page.items);
        _count = page.count;
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _state != null || _role != null || _status != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TgcgColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: TgcgColors.border),
            boxShadow: const [
              BoxShadow(color: Color(0x0A0A2463), blurRadius: 18, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('member-search-field'),
                controller: _text,
                autofocus: widget.autofocus,
                onChanged: _typed,
                onSubmitted: (_) => _changed(),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: TgcgColors.surfaceSoft,
                  hintText: 'Search name, membership number, phone, position or place',
                  prefixIcon: const Icon(Icons.search_rounded, color: TgcgColors.primaryMid),
                  suffixIcon: _text.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear the search',
                          onPressed: () {
                            _text.clear();
                            _changed();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _PlaceMenu(
                    key: const ValueKey('filter-state'),
                    icon: Icons.map_outlined,
                    label: _state?.name ?? 'All states',
                    places: _states,
                    selected: _state?.code,
                    anyLabel: 'All states',
                    onSelected: (place) {
                      _state = place;
                      _lga = null;
                      _lgas = place == null
                          ? null
                          : TgcgBackend.of(
                              context,
                            )!.reference.registrationPlaces(state: place.code);
                      _changed();
                    },
                  ),
                  if (_state != null)
                    _PlaceMenu(
                      key: const ValueKey('filter-lga'),
                      icon: Icons.location_city_outlined,
                      label: _lga?.name ?? 'All LGAs',
                      places: _lgas,
                      selected: _lga?.code,
                      anyLabel: 'All LGAs',
                      onSelected: (place) {
                        _lga = place;
                        _changed();
                      },
                    ),
                  _RoleMenu(
                    roles: _roles,
                    selected: _role,
                    onSelected: (role) {
                      _role = role;
                      _changed();
                    },
                  ),
                  _ChoiceMenu(
                    key: const ValueKey('filter-status'),
                    icon: Icons.verified_user_outlined,
                    label: memberStatusFilters[_status].$1,
                    active: _status != 0,
                    options: [for (final option in memberStatusFilters) option.$1],
                    onSelected: (index) {
                      _status = index;
                      _changed();
                    },
                  ),
                  if (filtered || _text.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                      label: const Text('Clear all'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_active) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _loading && _members.isEmpty
                      ? 'Searching...'
                      : '${formatCount(_count)} ${_count == 1 ? 'member' : 'members'}',
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('A to Z')),
                  ButtonSegment(value: true, label: Text('Newest')),
                ],
                selected: {_newest},
                showSelectedIcon: false,
                onSelectionChanged: (selected) {
                  _newest = selected.single;
                  unawaited(_load());
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                failureMessage(_error!),
                style: const TextStyle(color: TgcgColors.danger),
              ),
            ),
          if (!_loading && _error == null && _members.isEmpty)
            TgcgEmptyState(
              icon: Icons.person_search_outlined,
              title: 'No members match',
              message: filtered
                  ? 'Try fewer words, or clear a filter.'
                  : 'Try fewer words, or another spelling.',
              action: filtered
                  ? OutlinedButton(onPressed: _clear, child: const Text('Clear all'))
                  : null,
            ),
          _ResultGrid(members: _members),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_more && !_loading)
            Center(
              child: TextButton(onPressed: () => _load(more: true), child: const Text('Show more')),
            ),
        ],
      ],
    );
  }
}

/// A filter that looks like a chip and opens a menu.
class _MenuChip extends StatelessWidget {
  const _MenuChip({required this.icon, required this.label, required this.active});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? TgcgColors.primary : TgcgColors.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
      decoration: BoxDecoration(
        color: active ? TgcgColors.primarySoft : TgcgColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? TgcgColors.primaryMid : TgcgColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
          Icon(Icons.arrow_drop_down_rounded, color: color),
        ],
      ),
    );
  }
}

class _PlaceMenu extends StatelessWidget {
  const _PlaceMenu({
    super.key,
    required this.icon,
    required this.label,
    required this.places,
    required this.selected,
    required this.anyLabel,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final Future<List<RegistrationPlace>>? places;
  final String? selected;
  final String anyLabel;
  final ValueChanged<RegistrationPlace?> onSelected;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<RegistrationPlace>>(
    future: places,
    builder: (context, snapshot) {
      final list = snapshot.data ?? const <RegistrationPlace>[];
      return PopupMenuButton<String>(
        tooltip: anyLabel,
        enabled: list.isNotEmpty,
        onSelected: (code) => onSelected(list.where((place) => place.code == code).firstOrNull),
        itemBuilder: (_) => [
          PopupMenuItem(value: '', child: Text(anyLabel)),
          for (final place in list)
            CheckedPopupMenuItem(
              value: place.code,
              checked: place.code == selected,
              child: Text(place.name),
            ),
        ],
        child: _MenuChip(icon: icon, label: label, active: selected != null),
      );
    },
  );
}

class _RoleMenu extends StatelessWidget {
  const _RoleMenu({required this.roles, required this.selected, required this.onSelected});

  final Future<List<(String, String, int)>>? roles;
  final (String, String)? selected;
  final ValueChanged<(String, String)?> onSelected;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<(String, String, int)>>(
    future: roles,
    builder: (context, snapshot) {
      final list = snapshot.data ?? const <(String, String, int)>[];
      if (list.isEmpty) return const SizedBox.shrink();
      return PopupMenuButton<String>(
        key: const ValueKey('filter-position'),
        tooltip: 'Any position',
        onSelected: (code) {
          final role = list.where((role) => role.$1 == code).firstOrNull;
          onSelected(role == null ? null : (role.$1, role.$2));
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('Any position')),
          for (final (code, name, count) in list)
            CheckedPopupMenuItem(
              value: code,
              checked: code == selected?.$1,
              child: Text('$name ($count)'),
            ),
        ],
        child: _MenuChip(
          icon: Icons.account_tree_outlined,
          label: selected?.$2 ?? 'Any position',
          active: selected != null,
        ),
      );
    },
  );
}

class _ChoiceMenu extends StatelessWidget {
  const _ChoiceMenu({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool active;
  final List<String> options;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: options.first,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final (index, option) in options.indexed)
        CheckedPopupMenuItem(value: index, checked: option == label, child: Text(option)),
    ],
    child: _MenuChip(icon: icon, label: label, active: active),
  );
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.members});

  final List<StaffMember> members;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1100
          ? 3
          : constraints.maxWidth >= 680
          ? 2
          : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final member in members)
            SizedBox(
              width: width,
              child: MemberCard(member: member),
            ),
        ],
      );
    },
  );
}

/// One member in search results: who, where, their posts and their standing.
class MemberCard extends StatelessWidget {
  const MemberCard({super.key, required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final place = placeOf(member.scope);
    final color = _standingColor(
      member.verificationStatus,
      member.gaps.isEmpty,
      member.membershipState,
    );
    return Material(
      color: TgcgColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('member-${member.membershipNumber}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => showMemberDetails(context, member.membershipNumber, member: member),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TgcgColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(name: member.displayName, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [member.membershipNumber, ?member.phoneNumber].join(' · '),
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 11.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined, size: 14, color: TgcgColors.muted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              place,
                              style: const TextStyle(color: TgcgColors.muted, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (member.posts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final post in member.posts) _PostChip(post: post)],
                      ),
                    ],
                    const SizedBox(height: 8),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostChip extends StatelessWidget {
  const _PostChip({required this.post});

  final MemberPost post;

  @override
  Widget build(BuildContext context) {
    final active = post.state == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? TgcgColors.primarySoft : TgcgColors.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        active ? postLabel(post) : '${postLabel(post)} (${post.state})',
        style: TextStyle(
          color: active ? TgcgColors.primary : TgcgColors.accentDeep,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// --- one member's profile -----------------------------------------------------------

/// Everything on record about a member that this account may see.
Future<void> showMemberDetails(BuildContext context, String number, {StaffMember? member}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MemberProfile(number: number),
    );

class _MemberProfile extends StatefulWidget {
  const _MemberProfile({required this.number});

  final String number;

  @override
  State<_MemberProfile> createState() => _MemberProfileState();
}

class _MemberProfileState extends State<_MemberProfile> {
  Future<StaffMember>? _member;
  Future<Uint8List>? _photo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = TgcgBackend.of(context)!;
    _member ??= backend.members.member(widget.number);
  }

  Future<Uint8List>? _photoOf(StaffMember member) {
    if (!member.sensitiveVisible || member.photoUrl == null) return null;
    return _photo ??= TgcgBackend.of(context)!.members.photo(member.membershipNumber);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: FutureBuilder<StaffMember>(
        future: _member,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                failureMessage(snapshot.error!),
                style: const TextStyle(color: TgcgColors.danger),
              ),
            );
          }
          final member = snapshot.data;
          if (member == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: LinearProgressIndicator(minHeight: 2),
            );
          }
          return _ProfileBody(member: member, photo: _photoOf(member));
        },
      ),
    ),
  );
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.member, required this.photo});

  final StaffMember member;
  final Future<Uint8List>? photo;

  @override
  Widget build(BuildContext context) {
    final age = ageOn(member.dateOfBirth, DateTime.now());
    final color = _standingColor(
      member.verificationStatus,
      member.gaps.isEmpty,
      member.membershipState,
    );
    final scope = member.scope;
    String place(String? name, String? code) => [
      if (name != null && name.isNotEmpty) name,
      if (code != null && code.isNotEmpty && code != name) code,
    ].join(' · ');
    String assigned(String? name, String? code) {
      final value = place(name, code);
      return value.isEmpty ? 'Not assigned' : value;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FutureBuilder<Uint8List>(
                future: photo,
                builder: (context, snapshot) => MemberAvatar(
                  name: member.displayName,
                  color: color,
                  size: 64,
                  photo: snapshot.data,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SelectableText(
                      member.membershipNumber,
                      style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ),
        ],
      ),
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
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: TgcgColors.primaryMid,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: .9,
          ),
        ),
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
          final labelWidget = Text(
            label,
            style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
          );
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

// --- the search page and the top-bar entry -------------------------------------------

/// Member search on its own page, from the top bar.
class MemberSearchPage extends StatelessWidget {
  const MemberSearchPage({super.key, this.query = ''});

  final String query;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(title: const Text('Find members')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [MemberSearch(initialQuery: query, autofocus: true, alwaysShowResults: true)],
    ),
  );
}

/// The top bar's member search, for those who see Members & Exco: a search
/// field on wide screens, a button on phones.
class MemberSearchButton extends StatelessWidget {
  const MemberSearchButton({super.key, this.wide = false});

  final bool wide;

  void _open(BuildContext context, [String query = '']) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => MemberSearchPage(query: query)));

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (!session.isServerSession || !session.modules.contains(TgcgModule.membershipNetwork)) {
      return const SizedBox.shrink();
    }
    if (!wide) {
      return IconButton(
        tooltip: 'Find members',
        onPressed: () => _open(context),
        icon: const Icon(Icons.person_search_outlined),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: 280,
        height: 40,
        child: TextField(
          key: const ValueKey('top-member-search'),
          textInputAction: TextInputAction.search,
          onSubmitted: (text) => _open(context, text),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: TgcgColors.surfaceSoft,
            hintText: 'Find members',
            prefixIcon: const Icon(Icons.person_search_outlined, size: 19),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: TgcgColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: TgcgColors.border),
            ),
          ),
        ),
      ),
    );
  }
}
