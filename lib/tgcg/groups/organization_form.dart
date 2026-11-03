import 'package:flutter/material.dart';

import '../api/support_groups_repository.dart';
import '../geography/geography_registry.dart';
import '../ui/tgcg_design.dart';

/// The states, by name, with the server's codes.
final _states = [...GeographyRegistry.prototypeSeed().states]
  ..sort((a, b) => a.name.compareTo(b.name));

/// What has been typed into the organization's part of the form.
class OrganizationDraft {
  final name = TextEditingController();
  final email = TextEditingController();
  String coverage = 'national';
  String? region;
  String? state;

  /// Up to three other leaders, as on the paper form.
  final officials = [
    for (var i = 0; i < 3; i++)
      (
        name: TextEditingController(),
        position: TextEditingController(),
        phone: TextEditingController(),
      ),
  ];

  OrganizationDetails get details => OrganizationDetails(
    name: name.text,
    coverage: coverage,
    region: region ?? '',
    state: state ?? '',
    email: email.text,
    officials: [
      for (final official in officials)
        GroupOfficial(
          name: official.name.text,
          position: official.position.text,
          phone: official.phone.text,
        ),
    ],
  );

  /// What is missing, keyed as the server keys it, before anything is sent.
  Map<String, String> check() => {
    if (name.text.trim().length < 3) 'organization_name': "Enter the organization's name.",
    if (coverage == 'regional' && region == null)
      'organization_zone': 'Choose the region it covers.',
    if (coverage == 'state' && state == null) 'organization_state': 'Choose the state it covers.',
    if (officials.any(
      (official) =>
          official.name.text.trim().isEmpty &&
          (official.position.text.trim().isNotEmpty || official.phone.text.trim().isNotEmpty),
    ))
      'organization_officials': 'Give the name of each leader listed.',
  };

  void dispose() {
    name.dispose();
    email.dispose();
    for (final official in officials) {
      official.name.dispose();
      official.position.dispose();
      official.phone.dispose();
    }
  }
}

/// The organization's part of the registration form: its name, what it
/// covers, its email and up to three other leaders.
class OrganizationFields extends StatefulWidget {
  const OrganizationFields({
    super.key,
    required this.draft,
    this.errors = const {},
    this.onChanged,
  });

  final OrganizationDraft draft;

  /// Errors by field, from the server or [OrganizationDraft.check].
  final Map<String, String> errors;
  final VoidCallback? onChanged;

  @override
  State<OrganizationFields> createState() => _OrganizationFieldsState();
}

class _OrganizationFieldsState extends State<OrganizationFields> {
  OrganizationDraft get _draft => widget.draft;

  void _changed(VoidCallback change) {
    setState(change);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _draft.name,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => widget.onChanged?.call(),
        decoration: InputDecoration(
          labelText: 'Name of the organization',
          errorText: widget.errors['organization_name'],
        ),
      ),
      const SizedBox(height: 16),
      const Text('Area it covers', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: [
          for (final (code, label) in groupCoverages)
            ButtonSegment(value: code, label: Text(label)),
        ],
        selected: {_draft.coverage},
        onSelectionChanged: (value) => _changed(() => _draft.coverage = value.first),
      ),
      if (widget.errors['organization_coverage'] case final error?) _FieldError(error),
      if (_draft.coverage == 'regional') ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _draft.region,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Region',
            errorText: widget.errors['organization_zone'],
          ),
          items: [
            for (final (code, name) in groupRegions)
              DropdownMenuItem(value: code, child: Text(name)),
          ],
          onChanged: (value) => _changed(() => _draft.region = value),
        ),
      ],
      if (_draft.coverage == 'state') ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _draft.state,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'State',
            errorText: widget.errors['organization_state'],
          ),
          items: [
            for (final state in _states) DropdownMenuItem(value: state.id, child: Text(state.name)),
          ],
          onChanged: (value) => _changed(() => _draft.state = value),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _draft.email,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: "Organization's email (optional)",
          errorText: widget.errors['organization_email'],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Other leaders of the organization (optional)',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      const Text('Up to three, with their position and phone number.', style: TgcgType.caption),
      for (final (index, official) in _draft.officials.indexed) ...[
        const SizedBox(height: 12),
        Text('Leader ${index + 1}', style: TgcgType.label),
        const SizedBox(height: 6),
        TextField(
          controller: official.name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name', isDense: true),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: official.position,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Position', isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: official.phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone', isDense: true),
              ),
            ),
          ],
        ),
      ],
      if (widget.errors['organization_officials'] case final error?) _FieldError(error),
    ],
  );
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(message, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
  );
}
