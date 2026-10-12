import 'package:flutter/material.dart';

import '../api/access_repository.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/reference_repository.dart';
import '../geography/geography_registry.dart';
import '../geography/lga_wards.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// 11 Oct 2026
String formatDay(DateTime value) => '${value.day} ${_months[value.month - 1]} ${value.year}';

/// 11 Oct 2026, 14:05
String formatMoment(DateTime value) =>
    '${formatDay(value)}, ${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// An area as people say it; national areas read "Nigeria (nationwide)".
String areaLabel(GeographicScope scope) =>
    scope.level == GeographyLevel.country ? 'Nigeria (nationwide)' : scope.label;

/// The message to show for a failed call.
String failureMessage(Object error) => switch (error) {
  ApiException(isOffline: true) =>
    'The server cannot be reached. Changes to roles and access need a connection.',
  ApiException(:final message) => message,
  _ => 'Something went wrong. Try again.',
};

void showFailure(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(failureMessage(error)), backgroundColor: TgcgColors.danger),
  );
}

void showDone(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Asks for a line of text (a reason, notes). Null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String action = 'Confirm',
  String? message,
  bool required = false,
  bool destructive = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPrompt(
    title: title,
    label: label,
    action: action,
    message: message,
    required: required,
    destructive: destructive,
  ),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.action,
    required this.required,
    required this.destructive,
    this.message,
  });

  final String title;
  final String label;
  final String action;
  final String? message;
  final bool required;
  final bool destructive;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = !widget.required || _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!, style: const TextStyle(color: TgcgColors.muted, height: 1.4)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.required ? widget.label : '${widget.label} (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: TgcgColors.danger)
              : null,
          onPressed: ready ? () => Navigator.pop(context, _controller.text.trim()) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Asks to confirm an action. True when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirm',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 420, child: Text(message, style: const TextStyle(height: 1.4))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: TgcgColors.danger) : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Small chips naming each area.
class AreaChips extends StatelessWidget {
  const AreaChips(this.areas, {super.key});

  final List<GeographicScope> areas;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final area in areas)
        Chip(
          avatar: const Icon(Icons.place_outlined, size: 16, color: TgcgColors.primaryMid),
          label: Text(areaLabel(area), style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
    ],
  );
}

/// Shown on server-only pages in offline presentation mode.
class ConnectToServerNotice extends StatelessWidget {
  const ConnectToServerNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: TgcgEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Connect to the TGCG server',
        message: message,
      ),
    ),
  );
}

/// A permission's label from the server's registry (the code if unknown).
String permissionLabel(String code, Map<String, PermissionInfo> registry) =>
    registry[code]?.label ?? code;

/// The server's permission registry, loaded once per session.
class PermissionRegistry {
  PermissionRegistry._();

  static Future<Map<String, PermissionInfo>>? _loaded;
  static ApiClient? _client;

  static Future<Map<String, PermissionInfo>> of(BuildContext context) {
    final services = TgcgBackend.of(context)!;
    if (_loaded == null || !identical(_client, services.client)) {
      _client = services.client;
      _loaded = services.access.permissions().then(
        (items) => {for (final item in items) item.code: item},
      );
      _loaded!.catchError((Object _) {
        _loaded = null;
        return <String, PermissionInfo>{};
      });
    }
    return _loaded!;
  }
}

/// Pick one area at one of [levels]. The codes match the server's.
Future<GeographicScope?> pickArea(BuildContext context, {required List<GeographyLevel> levels}) =>
    showDialog<GeographicScope>(
      context: context,
      builder: (_) => AreaPickerDialog(levels: levels),
    );

class AreaPickerDialog extends StatefulWidget {
  const AreaPickerDialog({super.key, required this.levels});

  final List<GeographyLevel> levels;

  @override
  State<AreaPickerDialog> createState() => _AreaPickerDialogState();
}

class _AreaPickerDialogState extends State<AreaPickerDialog> {
  late GeographyLevel level = widget.levels.first;
  CanonicalZone? zone;
  CanonicalState? state;
  CanonicalSenatorialDistrict? district;
  CanonicalLga? lga;
  WardInfo? ward;
  ServerPollingUnit? unit;
  Future<LgaWards>? wards;
  Future<List<ServerPollingUnit>>? units;

  bool get _needsState => const {
    GeographyLevel.state,
    GeographyLevel.senatorialDistrict,
    GeographyLevel.lga,
    GeographyLevel.ward,
    GeographyLevel.pollingUnit,
  }.contains(level);

  bool get _needsLga =>
      const {GeographyLevel.lga, GeographyLevel.ward, GeographyLevel.pollingUnit}.contains(level);

  GeographicScope? get _choice {
    switch (level) {
      case GeographyLevel.country:
        return GeographicScope.nigeria;
      case GeographyLevel.geopoliticalZone:
        return zone?.scope;
      case GeographyLevel.state:
        return state?.scope;
      case GeographyLevel.senatorialDistrict:
        return district?.scope;
      case GeographyLevel.lga:
        return lga?.scope;
      case GeographyLevel.ward:
        final lga = this.lga, ward = this.ward;
        if (lga == null || ward == null) return null;
        return _wardScope(lga, ward);
      case GeographyLevel.pollingUnit:
        final lga = this.lga, ward = this.ward, unit = this.unit;
        if (lga == null || ward == null || unit == null) return null;
        final parent = _wardScope(lga, ward);
        return GeographicScope(
          level: GeographyLevel.pollingUnit,
          country: parent.country,
          zoneId: parent.zoneId,
          zoneName: parent.zoneName,
          stateId: parent.stateId,
          stateName: parent.stateName,
          senatorialDistrictId: parent.senatorialDistrictId,
          senatorialDistrictName: parent.senatorialDistrictName,
          lgaId: parent.lgaId,
          lgaName: parent.lgaName,
          wardId: parent.wardId,
          wardName: parent.wardName,
          pollingUnitId: unit.code,
          pollingUnitName: unit.name,
        );
    }
  }

  GeographicScope _wardScope(CanonicalLga lga, WardInfo ward) {
    final base = lga.scope;
    return GeographicScope(
      level: GeographyLevel.ward,
      country: base.country,
      zoneId: base.zoneId,
      zoneName: base.zoneName,
      stateId: base.stateId,
      stateName: base.stateName,
      senatorialDistrictId: base.senatorialDistrictId,
      senatorialDistrictName: base.senatorialDistrictName,
      lgaId: base.lgaId,
      lgaName: base.lgaName,
      wardId: ward.code,
      wardName: ward.name,
    );
  }

  void _setLevel(GeographyLevel value) => setState(() {
    level = value;
    unit = null;
    units = null;
  });

  void _setState(CanonicalState? value) => setState(() {
    state = value;
    district = null;
    lga = null;
    ward = null;
    unit = null;
    wards = null;
    units = null;
  });

  void _setLga(CanonicalLga? value) => setState(() {
    lga = value;
    ward = null;
    unit = null;
    units = null;
    wards = value == null ? null : LgaWards.load(value.id);
  });

  void _setWard(WardInfo? value, BuildContext context) => setState(() {
    ward = value;
    unit = null;
    final services = TgcgBackend.of(context);
    units = value == null || services == null || level != GeographyLevel.pollingUnit
        ? null
        : services.reference.pollingUnitsWithin(_wardScope(lga!, value));
  });

  @override
  Widget build(BuildContext context) {
    final registry = MembershipOperations.of(context).geography;
    final states = [...registry.states]..sort((a, b) => a.name.compareTo(b.name));
    final choice = _choice;
    return AlertDialog(
      title: const Text('Choose an area'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.levels.length > 1)
                _Picker<GeographyLevel>(
                  label: 'Level',
                  value: level,
                  items: widget.levels,
                  text: geographyLevelLabel,
                  onChanged: (value) {
                    if (value != null) _setLevel(value);
                  },
                ),
              if (level == GeographyLevel.geopoliticalZone)
                _Picker<CanonicalZone>(
                  label: 'Zone',
                  value: zone,
                  items: registry.zones,
                  text: (item) => item.name,
                  onChanged: (value) => setState(() => zone = value),
                ),
              if (_needsState)
                _Picker<CanonicalState>(
                  label: 'State',
                  value: state,
                  items: states,
                  text: (item) => item.name,
                  onChanged: _setState,
                ),
              if (level == GeographyLevel.senatorialDistrict && state != null)
                _Picker<CanonicalSenatorialDistrict>(
                  label: 'Senatorial district',
                  value: district,
                  items: registry.districtsForState(state!.id),
                  text: (item) => item.name,
                  onChanged: (value) => setState(() => district = value),
                ),
              if (_needsLga && state != null)
                _Picker<CanonicalLga>(
                  label: 'LGA',
                  value: lga,
                  items: registry.lgasForState(state!.id),
                  text: (item) => item.name,
                  onChanged: _setLga,
                ),
              if ((level == GeographyLevel.ward || level == GeographyLevel.pollingUnit) &&
                  wards != null)
                FutureBuilder<LgaWards>(
                  future: wards,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const _PickerNote('The wards of this LGA are not available.');
                    }
                    final data = snapshot.data;
                    if (data == null) return const LinearProgressIndicator();
                    return _Picker<WardInfo>(
                      label: 'Ward',
                      value: ward,
                      items: data.wards,
                      text: (item) => item.name,
                      onChanged: (value) => _setWard(value, context),
                    );
                  },
                ),
              if (level == GeographyLevel.pollingUnit && units != null)
                FutureBuilder<List<ServerPollingUnit>>(
                  future: units,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _PickerNote(failureMessage(snapshot.error!));
                    }
                    final data = snapshot.data;
                    if (data == null) return const LinearProgressIndicator();
                    return _Picker<ServerPollingUnit>(
                      label: 'Polling unit',
                      value: unit,
                      items: data,
                      text: (item) => '${item.code} ${item.name}',
                      onChanged: (value) => setState(() => unit = value),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: choice == null ? null : () => Navigator.pop(context, choice),
          child: const Text('Choose'),
        ),
      ],
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.items,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T item) text;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item,
            child: Text(text(item), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

class _PickerNote extends StatelessWidget {
  const _PickerNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: const TextStyle(color: TgcgColors.muted)),
  );
}

/// A coloured pill for an appointment's state.
TgcgStatusPill appointmentStatePill(AppointmentState state) => TgcgStatusPill(
  label: appointmentStateLabel(state),
  compact: true,
  color: switch (state) {
    AppointmentState.active => TgcgColors.success,
    AppointmentState.scheduled => TgcgColors.info,
    AppointmentState.suspended => TgcgColors.warning,
    AppointmentState.expired => TgcgColors.muted,
    AppointmentState.declined || AppointmentState.resigned => TgcgColors.muted,
    AppointmentState.revoked => TgcgColors.danger,
  },
);

/// Reloads what the server grants the signed-in user (after a change that
/// may affect their own access). A member whose appointments now give
/// operational access moves to the operations app, and back when they no
/// longer do.
Future<void> refreshOwnAccess(BuildContext context) async {
  final services = TgcgBackend.of(context);
  final session = TgcgSession.of(context, listen: false);
  if (services == null || !session.isServerSession) return;
  try {
    final user = await services.auth.me();
    if (user.usesMemberApp && !session.isMember) {
      session.signInMember(
        fullName: user.fullName,
        membershipNumber: user.membershipNumber ?? user.accessId,
        waitingRole: user.roleAwaitingVerification,
      );
    } else if (!user.usesMemberApp && (session.isMember || session.role != user.role)) {
      session.signInFromServer(
        role: user.role,
        fullName: user.fullName,
        accessId: user.accessId,
        scope: user.workingScope,
        capabilities: user.capabilities,
        grants: user.access,
        supervises: user.supervises,
        membershipNumber: user.membershipNumber ?? (user.isMember ? user.accessId : null),
      );
    } else {
      session.updateAccess(
        capabilities: user.capabilities,
        grants: user.access,
        supervises: user.supervises,
        scope: user.workingScope,
      );
    }
  } on ApiException {
    // Offline: the next sign-in or refresh picks it up.
  }
}
