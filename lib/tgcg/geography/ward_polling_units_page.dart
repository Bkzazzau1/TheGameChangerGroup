import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../api/reference_repository.dart';
import '../domain/permissions.dart';
import '../membership/polling_unit_members_page.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// Who may find members in their areas, as on the server (`MEMBER_READERS`).
const memberReaders = [
  TgcgCapability.manageMembership,
  TgcgCapability.registerMembers,
  TgcgCapability.accreditAgents,
  TgcgCapability.manageAgentAssignments,
  TgcgCapability.verifyMemberIdentity,
  TgcgCapability.suspendMembers,
  TgcgCapability.viewMemberSensitiveData,
];

bool canFindMembers(TgcgSessionController session) => session.canAny(memberReaders);

/// INEC names are upper case; show them in title case.
String titleCaseName(String name) => name
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Opens a ward's polling units, with the members registered at each for
/// those who may find members there.
Future<void> openWardPollingUnits(
  BuildContext context, {
  required String code,
  required String name,
}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WardPollingUnitsPage(code: code, name: name)),
    );

class WardPollingUnitsPage extends StatefulWidget {
  const WardPollingUnitsPage({super.key, required this.code, required this.name});

  /// INEC ward code, e.g. 18-23-05.
  final String code;
  final String name;

  @override
  State<WardPollingUnitsPage> createState() => _WardPollingUnitsPageState();
}

class _WardPollingUnitsPageState extends State<WardPollingUnitsPage> {
  Future<(List<ServerPollingUnit>, MemberCounts?)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<ServerPollingUnit>, MemberCounts?)> _load() async {
    final backend = TgcgBackend.of(context);
    if (backend == null) return (const <ServerPollingUnit>[], null);
    final counts = canFindMembers(TgcgSession.of(context, listen: false))
        ? backend.members
              .counts(level: GeographyLevel.ward, code: widget.code, by: GeographyLevel.pollingUnit)
              // A ward outside the account's area has no numbers to show.
              .then<MemberCounts?>((value) => value, onError: (Object _) => null)
        : Future<MemberCounts?>.value();
    final units = await backend.reference.pollingUnitsWithin(
      GeographicScope(level: GeographyLevel.ward, country: 'Nigeria', wardId: widget.code),
    );
    return (units, await counts);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(title: Text('${titleCaseName(widget.name)} ward')),
    body: FutureBuilder<(List<ServerPollingUnit>, MemberCounts?)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: TgcgEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load polling units',
              message: error is ApiException ? error.message : '$error',
              action: TextButton(
                onPressed: () => setState(() => _data = _load()),
                child: const Text('Try again'),
              ),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final (units, counts) = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              '${widget.code} • ${units.length} polling unit${units.length == 1 ? '' : 's'}'
              '${counts == null ? '' : ' • ${_members(counts.total)}'}',
              style: const TextStyle(color: TgcgColors.muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Material(
              color: TgcgColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: TgcgColors.border),
              ),
              child: Column(
                children: [
                  for (final (index, unit) in units.indexed) ...[
                    if (index > 0) const Divider(height: 1, color: TgcgColors.border),
                    ListTile(
                      title: Text(
                        titleCaseName(unit.name),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${unit.code}'
                        '${unit.registeredVoters == null ? '' : ' • ${unit.registeredVoters} voters'}',
                        style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted),
                      ),
                      trailing: counts == null
                          ? null
                          : Text(
                              _members(counts[unit.code]),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: TgcgColors.primary,
                              ),
                            ),
                      onTap: counts == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    PollingUnitMembersPage(code: unit.code, name: unit.name),
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

String _members(int count) => '$count member${count == 1 ? '' : 's'}';
