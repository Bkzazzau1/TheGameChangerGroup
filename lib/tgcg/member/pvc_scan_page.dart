import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_repository.dart';
import '../api/reference_repository.dart';
import '../ui/tgcg_design.dart';
import 'member_registration_page.dart' show PvcScan, cleanVin, isVin;

/// The member checks the details read off their PVC before they replace the
/// ones typed when joining: at once, or after a coordinator's second check
/// once the identity is checked. Returns how the scan went.
class PvcScanPage extends StatefulWidget {
  const PvcScanPage({super.key, required this.scan, required this.card});

  final PvcScan scan;
  final MemberCard card;

  @override
  State<PvcScanPage> createState() => _PvcScanPageState();
}

class _PvcScanPageState extends State<PvcScanPage> {
  static const _fields = {'full_name', 'vin', 'delim', 'gender', 'date_of_birth', 'occupation'};

  // What the card showed, or else the member's own detail (the VIN is only
  // ever shown masked, so it comes from the card or is typed).
  late final _name = TextEditingController(text: widget.scan.fullName ?? widget.card.fullName);
  late final _vin = TextEditingController(text: widget.scan.vin ?? '');
  late final _delim = TextEditingController(
    text: widget.scan.delim ?? widget.card.pollingUnit?.code ?? '',
  );
  late final _occupation = TextEditingController(
    text: widget.scan.occupation ?? widget.card.occupation,
  );
  late String? _gender =
      widget.scan.gender ?? (widget.card.gender.isEmpty ? null : widget.card.gender);
  late DateTime? _dateOfBirth = widget.scan.dateOfBirth ?? widget.card.dateOfBirth;
  DelimUnit? _unit;
  bool _busy = false;
  bool _started = false;
  Map<String, String> _errors = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _lookUp();
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _vin, _delim, _occupation]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _lookUp() async {
    final delim = _delim.text.trim();
    if (delim.isEmpty) return;
    final reference = TgcgBackend.of(context)!.reference;
    setState(() {
      _busy = true;
      _errors.remove('delim');
    });
    try {
      final unit = await reference.pollingUnitForDelim(delim);
      if (!mounted) return;
      setState(() {
        _unit = unit;
        _delim.text = unit.code;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _unit = null;
          _errors['delim'] = error.fieldError('delim') ?? error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 110);
    final lastDate = DateTime(now.year - 16, now.month, now.day);
    final birthday = DateUtils.dateOnly(_dateOfBirth ?? DateTime(now.year - 30));
    final initialDate = birthday.isBefore(firstDate)
        ? firstDate
        : birthday.isAfter(lastDate)
            ? lastDate
            : birthday;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Date of birth, as on your PVC',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _send() async {
    final delim = _delim.text.trim();
    setState(() {
      _errors = {
        if (_name.text.trim().isEmpty) 'full_name': 'Enter your full name, as on the PVC.',
        if (!isVin(_vin.text)) 'vin': 'A VIN has 19 letters and digits.',
        if (delim.isEmpty) 'delim': 'Enter the polling unit code from your PVC.',
      };
    });
    if (_unit == null && delim.isNotEmpty) await _lookUp();
    if (!mounted || _errors.isNotEmpty || _unit == null) return;
    final members = TgcgBackend.of(context)!.member;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final result = await members.sendPvcScan(
        PvcScanDetails(
          photo: widget.scan.photo,
          fullName: _name.text.trim(),
          vin: cleanVin(_vin.text),
          delim: _unit!.code,
          gender: _gender,
          dateOfBirth: _dateOfBirth,
          occupation: _occupation.text.trim(),
        ),
      );
      navigator.pop(result);
    } on ApiException catch (error) {
      if (mounted) {
        final errors = {for (final entry in error.fieldErrors.entries) entry.key: entry.value.first};
        setState(() {
          _errors = {
            for (final entry in errors.entries)
              if (_fields.contains(entry.key)) entry.key: entry.value,
            if (!errors.keys.any(_fields.contains))
              'general': errors.isEmpty ? error.message : errors.values.first,
          };
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your PVC')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(widget.scan.photo.bytes, height: 180, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              const Text(
                'Check each detail against your card. They replace the details you typed '
                'when you joined. A card is scanned only once.',
                style: TextStyle(color: TgcgColors.muted, height: 1.4),
              ),
              if (widget.card.identityChecked) ...[
                const SizedBox(height: 8),
                const Text(
                  'Your identity has been checked, so a coordinator compares these with your '
                  'card before they change.',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                ),
              ],
              if (_errors['general'] case final general?) ...[
                const SizedBox(height: 12),
                Text(general, style: const TextStyle(color: TgcgColors.danger)),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Full name, as on the PVC',
                  errorText: _errors['full_name'],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _vin,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'VIN (Voter Identification Number)',
                  errorText: _errors['vin'],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _delim,
                onSubmitted: (_) => _lookUp(),
                onChanged: (_) => setState(() => _unit = null),
                decoration: InputDecoration(
                  labelText: 'Polling unit code (marked CODE on the PVC)',
                  errorText: _errors['delim'],
                  suffixIcon: IconButton(
                    tooltip: 'Find polling unit',
                    onPressed: _busy ? null : _lookUp,
                    icon: const Icon(Icons.search_rounded),
                  ),
                ),
              ),
              if (_unit case final unit?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Your polling unit: ${unit.label}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(height: 14),
              const Text('Gender', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'male', label: Text('Male')),
                  ButtonSegment(value: 'female', label: Text('Female')),
                ],
                selected: {?_gender},
                onSelectionChanged: (value) => setState(() => _gender = value.firstOrNull),
              ),
              if (_errors['gender'] case final error?)
                Text(error, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickBirthday,
                icon: const Icon(Icons.cake_outlined),
                label: Text(
                  _dateOfBirth == null
                      ? 'Date of birth'
                      : 'Born ${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
                ),
              ),
              if (_errors['date_of_birth'] case final error?)
                Text(error, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _occupation,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Occupation',
                  errorText: _errors['occupation'],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Use these details'),
              ),
            ],
          ),
        ),
      );
}
